+++
title = "Non-native event-driven windowing in Wallaroo"
slug = "non-native-event-windowing"
draft = false
date = 2017-11-09T00:00:00Z
tags = [
    "wallaroo",
    "windowing",
    "partitioning"
    "python"
]
categories = [
    "Windowing"
]
description = "Creating event boundaries and processing cumulative state"
author = "amosca"
+++

Certain applications lend themselves to pure parallel computation better than others. In some cases we require to apply certain algorithms over a "window" in our data. This means that after we have completed a certain amount of processing (be it time, number of messages or some other arbitrary metric), we want to perform a special action for the data in that window. An example application of this could be producing stats for log files over a certain period of time. We may want to produce our stats in the form of a periodic summary (e.g. daily), in which case the computation in Wallaroo would have to know when it has received the last message for a particular day. We are working hard every day to support new use patterns, and this type of windowing can already be supported without any native support in Wallaroo.

This blog entry is about the aforementioned example, and how this can be implemented in the current version of Wallaroo (0.2.1).

## Types of windowing

There are a few types of windowing that can be implemented, and it is important that we clarify the distinctions. In our example we will be focusing on event-based windowing.

#### Event-based windowing

This is the most arbitrary kind of windowing. The boundaries of each window are determined outside of Wallaroo, and can be triggered by any event. This is also the simplest kind of windowing to think about: when we are told that a window ends, we run work on the aggregate state and start over.

#### Internally triggered windowing

This is very similar to event-based windowing, except that the window is triggered from within the computation. This is usually based on the internal state of the computation, and it is the responsibility of the computation itself to determine when a window has finished and when to start a new one.

#### Time-based windowing (Wall clock)

A new window is started at regular intervals using a timer. This is currently not supported in Wallaroo.

#### Time-based windowing (Event clock)

The time element is taken from information from the message rather than a timer, and windows are created accordingly. In order to implement this type of windowing, multiple windows have to be accumulated simultaneously. It is currently not possible to implement this kind of windowing easily.

## Log-file analytics application

Let's return to our log file analyzer. We will assume the goal of counting different return codes on a daily basis. This is a very basic example, but it already includes the important elements needed to create a windowed application. We will stream our logfiles line-by-line to the application, and will output one message per (day, return code) pairing. So, for instance, if we input five lines as follows

```
64.242.88.10 - - [07/Mar/2004:16:24:16 -0800] "GET /twiki/bin/view/Main/ABlogPage HTTP/1.1" 200 4924
64.242.88.10 - - [07/Mar/2004:16:29:16 -0800] "GET /twiki/bin/edit/Main/Header_checks?topicparent=Main.ConfigurationVariables HTTP/1.1" 401 12851
64.242.88.10 - - [07/Mar/2004:16:30:29 -0800] "GET /twiki/bin/attach/Main/OfficeLocations HTTP/1.1" 401 12851
64.242.88.10 - - [07/Mar/2004:16:31:48 -0800] "GET /twiki/bin/view/TWiki/WebTopicEditTemplate HTTP/1.1" 200 3732
64.242.88.10 - - [07/Mar/2004:16:32:50 -0800] "GET /twiki/bin/view/Main/WebChanges HTTP/1.1" 200 40520
```

we will expect an output as follows

```
2004-03-07 200 3
2004-03-07 401 2
```

We will also adopt a small trick. Because we are doing event-based windowing at the application level, we will introduce a "token" marker after each day, that our application will have to interpret correctly. For example

```
64.242.88.10 - - [07/Mar/2004:16:24:16 -0800] "GET /twiki/bin/view/Main/ABlogPage HTTP/1.1" 200 4924
64.242.88.10 - - [07/Mar/2004:16:29:16 -0800] "GET /twiki/bin/edit/Main/Header_checks?topicparent=Main.ConfigurationVariables HTTP/1.1" 401 12851
64.242.88.10 - - [07/Mar/2004:16:30:29 -0800] "GET /twiki/bin/attach/Main/OfficeLocations HTTP/1.1" 401 12851
END_OF_DAY
64.242.88.10 - - [08/Mar/2004:06:11:48 -0800] "GET /twiki/bin/view/TWiki/AnotherPage HTTP/1.1" 200 3732
64.242.88.10 - - [08/Mar/2004:06:12:50 -0800] "GET /twiki/bin/view/Main/YetAnotherPage HTTP/1.1" 200 40520
```

### Application Setup

The simplest possible application to do this would be composed of three elements, according to the following diagram

![High Level Logfiles Diagram](/images/post/simulate-event-windowing-wallaroo/topology.png)

A fully working version of the code from this post can be found [here](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/non-native-event-windowing/), together with instructions on how to build it and run it on some example data.

We set up our Wallaroo application as follows

```
def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    ab = wallaroo.ApplicationBuilder("Apache Log file analysis")
    ab.new_pipeline("convert",
                    wallaroo.TCPSourceConfig(in_host, in_port, Decoder()))
    ab.to_stateful(Count)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
    return ab.build()
```

#### Message types

We now need to determine how we will represent internally the difference between an actual log line and the boundary marker. For that we use two different classes.

```
class LogLine(object):
    def __init__(self, text):
        self.text = text


class BoundaryMessage(object):
    pass
```

#### Decoder

Our decoder needs to be able to correctly identify the `END_OF_DAY` message, and translate that into an appropriate message that will signal to the computations that they need to roll over to the next day. We will call this a `BoundaryMessage`, and all other messages will be `LogLine`s.

```
class Decoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        if bs == 'END_OF_DAY':
            return BoundaryMessage()
        else:
            return LogLine(bs)
```

#### State

Now we can create our shared state object, which will receive the state changes produced by the computation.

```
class Counter(object):
    def __init__(self):
        self.reset()

    def reset(self):
        self.current_batch = {}
        self.current_day = None

    def update(self, day, return_code):
        if self.current_day is None:
            self.current_day = day
        if self.current_day != day:
            raise
        self.current_batch[return_code] = self.current_batch.get(return_code, 0) + 1

    def get_counts(self):
        return self.current_batch
```

We must also create a factory for our state, which will be used by Wallaroo when it creates a new computation

```
class CounterBuilder(object):
    def build(self):
        return Counter()
```

#### Computation

The computation itself needs to be able to do the following things:

 - On the first `LogLine` for each window, determine which day we are counting for
 - On all `LogLine`s, accumulate the counts
 - On receipt of a `BoundaryMessage`, send all the output required as a
   `SummaryMessage`

```
class Count(object):
    def __init__(self):
        self.day_re = re.compile('\[(.*)\]')
        self.code_re = re.compile('"GET [^\s]* HTTP/[12].[01]" ([0-9]+)')

    def name(self):
        return "count status"

    def determine_return_code(self, line):
        m = self.code_re.search(line)
        if m is not None:
            return m.group(1)

    def determine_day(self, line):
        m = self.day_re.search(line)
        if m is not None:
            return m.group(1).split(':')[0]

    def compute(self, data, state):
        if isinstance(data, BoundaryMessage):
            return self.process_batch(state)
        elif isinstance(data,  LogLine):
            return_code = self.determine_return_code(data.text)
            day = self.determine_day(data.text)
            state.update(day, return_code)
            return (None, True)
        else:
            raise

    def name(self):
        return "Count return codes"

    def process_batch(self, state):
        r = state.get_counts()
        state.reset()
        return (r, True)
```

#### Encoder

On receipt of a summary message (which in our case is a `dict` of return codes and counts), we need to unpack the data inside it and create the lines of output. For simplicity, we will send a JSON-encoded version of the dictionary, which is human-readable.

```
class Encoder(object):
    def encode(self, data):
        s = json.dumps(data).encode('UTF-8')
        return struct.pack('>I{}s'.format(len(s)), len(s), s)
```

## Sending data to Wallaroo

In order to send data into Wallaroo, we must use a special sender that knows how to send the `END_OF_DAY` markers. We can create this sender by formatting our messages such that they match the working of the decoder:

* 4 bytes representing the length of the message, followed by
* a UTF-8 encoded string

Our sender will send an entire log file, followed by the special marker. This is based on the assumption that we will have one separate file per day, which will be true in many cases.

```
import sys
import socket
import struct


def send_message(conn, msg):
    conn.sendall(struct.pack('>I', len(msg)))
    conn.sendall(msg)

if __name__ == '__main__':
    wallaroo_host = sys.argv[1]
    file_to_send = sys.argv[2]
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    add = sys.argv[1].split(':')
    wallaroo_input_address = (add[0], int(add[1]))
    print 'connecting to Wallaroo on %s:%s' % wallaroo_input_address
    sock.connect(wallaroo_input_address)
    with open(file_to_send) as f:
        for line in f:
            send_message(sock, line)
    send_message(sock, "END_OF_DAY")
```

## Running our application

To run our application, we need to follow these steps:

- start a listener so we can view the output : `nc -l 7002`
- start the Wallaroo application from within its directory: `PYTHONPATH=:.:../../../machida/ ../../../machida/build/machida --application-module logfiles --in 127.0.0.1:8002 --out 127.0.0.1:7002 --metrics 127.0.0.1:5001 --control 127.0.0.1:6000 --data 127.0.0.1:6001 --worker-name worker1 --external 127.0.0.1:5050 --cluster-initializer --ponythreads=1`
- send our files to Wallaroo via our sender: `for f in day_*.log; do python sender.py 127.0.0.1:8002 $f; done`

## Next steps

There are obvious limitations to this basic example. For instance, there is no partitioning. A lot of extra functionality can be added to production-level code, but for the purpose of illustrating how to create windows, we preferred to narrow the focus and reduce distractions.

If you would like to ask us more in-depth technical questions, or if you have any suggestions, please get in touch via [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).

In this post, we have only covered a small part of windowing, and future posts will cover other types of windowing with more complex examples.
