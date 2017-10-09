# Scalable Event Processing in Python

Python has been under-supported in the big data and streaming world,
in spite of the fact that it is widely used in may other areas such as
data science and machine learning. Consequently, many organizations
end up in a situation where they either have to translate systems that
were originally written in Python in a JVM language, or rely on
systems that involve interprocess communication and lots of data
serialization between the JVM and a Python interpreter. The first of
these is error prone and often impossible due to a lack of similar
libraries; the second is slow and sometimes difficult to reason
about.

Building and operating large-scale distributed data applications is
hard, and if you start from scratch you have to address many
infrastructure plumbing issues. You need to figure out how workers
will communicate, what kinds of data they need to pass between each
other, how data will get to the right place, how to handle dropped
messages, how to recover from errors, how to redistribute data when
the system scales up and down. Once you make all these decisions, you
need to actually build the system and hope that you get everything
right.

To promote Python as a language on-par or even better than Java for
most data applications means allowing people who are familiar with
Python to quickly and easily build industrial-grade data processing
applications using only Python and the libraries that they are already
familiar with, and being able to scale them easily and operate them at
low-cost.

In this post we want to delve into Wallaroo, our open-source, highly
elastic processing engine for big data, fast data and machine learning
applications in Python, and other languages like GoLang and C++.

## Wallaroo -- Simplicity, Speed, and Scale

Wallaroo is a framework for building event driven distributed data
processing applications. It provides a simple model for building fast
systems that scale almost infinitely.

### Simplicity

It takes care of the scale-aware pieces of
the system, the state management, and the message delivery guarantees
that developers would have to think about if they were creating their
own system from scratch. Its philosophy is that the framework should
take care of the hard parts of distributed event processing so that
the application developers can spend their time focused on solving the
problems that are important to their business.

### Speed

Wallaroo provides true stream processing, not microbatching. Each
message that enters the system is processed immediately. This means
that message processing latencies (the time from when a message is
received to when it is finished processing) are very low when compared
to microbatching systems that send batches of messages through the
system at intervals. When milliseconds count, you want a system that
produces results as quickly as possible.

Wallaroo applications store their own state, which can be accessed and
updated in response to incoming messages. Messages are routed to the
worker that stores the state that is required to process a
message. This design discourages the use of external data stores and
caches in favor of local state, which means that message processing
doesn't require communication with other services over a network.

### Scale

Wallaroo applications are able to scale almost infinitely. They are
able to do this because Wallaroo stores application state in small
pieces that workers can read and updated without coordinating with
other workers. Since there is no coordination, it doesn't matter
whether two pieces of state exist on the same worker or on separate
workers on different computers. When more computers are added to a
system to scale it up, those pieces of state can be easily moved from
one computer to another and their new location will have no impact on
the speed of the system. And because the Wallaroo framework is
responsible for delivering messages, the application developer doesn't
have to worry about keeping track of where the pieces of state are
located. Scaling is transparent to the application developer.

## The Python API

### Wallaroo's Core Abstractions

In order to understand the Python API, it is important to understand
Wallaroo's core abstractions:
* State -- Accumulated result of data stored over the course of time.
* Computation -- Code that transforms an input of some type In to an
  output of some type Out (or optionally None if the input should be
  filtered out).
* State Computation -- Code that takes an input type In and a state
  object of some type State, operates on that input and state
  (possibly making state updates), and optionally producing an output
  of some type Out.
* Source -- Input point for data from external systems into an application.
* Sink -- Output point from an application to external systems.
* Decoder -- Code that transforms a stream of bytes from an external
  system into a series of application input types.
* Encoder -- Code that transforms an application output type into
  bytes for sending to an external system.
* Pipeline -- A sequence of computations and/or state computations
  originating from a source and optionally terminating in a sink.
* Application -- A collection of pipelines.

These abstractions will be described more later.

### A Motivating Example

The cannonical streaming data processing application is word count, in
which a stream of input text is analyzed and the total number of times
each word has been seen is reported. This description is broad enough
to allow developers to make different design tradeoffs in their
implementations.

For this example we will make the following assumptions:
* Incoming messages will come from a TCP connection and be sent to
  another TCP connection.
* Words are sent to the system in messages that can contain zero or
  more words.
* Incoming messages consist of a string of bytes that start with a
  32-bit big-endian integer that indicates the number of remaining
  bytes in the payload.
* Outgoing messages consist of a word and the number of times that
  word has been seen in the event stream.

For example the following string would represent a message:

```
"\x00\x00\x00\x2cMy solitude is cheered by that elegant hope."
```

The first four bytes are the length, and the remainder represents the
words to add to the count.

```
// INSERT GRAPHIC OF THIS OR SOMETHING

incoming message
|
| bytes
v
Decode
|
| string
v
Split (stateless)
| | |
| | | string
v v v
CountWord (stateful)
|
| WordCount
v
Encode
|
| bytes
v
outgoing mesage
```

In our example we will also split the state (the number of times each
word has been seen) into 26 partitions, where each partition handles
words that start with different letters. For example "acorn" and
"among" would go to the "a" partition, while "bacon" would go to the
"b" partition.

### Application Setup

Wallaroo calls the `application_setup` function to create a data
structure that represents the application.

```
def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    word_partitions = list(string.ascii_lowercase)
    word_partitions.append("!")

    ab = wallaroo.ApplicationBuilder("Word Count Application")
    ab.new_pipeline("Split and Count",
                    wallaroo.TCPSourceConfig(in_host, in_port, Decoder()))
    ab.to_parallel(Split)
    ab.to_state_partition(CountWord(), WordTotalsBuilder(), "word totals",
        WordPartitionFunction(), word_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
    return ab.build()
```

This code creates an application with the topology that was described
earlier. It represents one pipeline that consists of a stateless
computation called `Split` that splits a string of words into
individual words and a stateful computation called `CountWord` that
updates the state of the application and creates outgoing messages
that represent the word count. The classes used here will be described
more in the following sections.

#### State and State Partitions

In this example, the state is the number of times each word has been
seen. The easiest way to do this would be with a dictionary where the
key is a word, and the value associated with that key is the number of
times that word has been seen in the event stream.

Wallaroo lets you divide state into pieces called state
partitions. State partitions are pieces of state that are uniquely
identified by a key of some sort. A state can be divided into any
number of partitions. The only restriction is that these partitions
must be independent of each other in terms of how they will be
accessed, because only one state partition can be accessed at a time.

State partitions are accessed inside state computations. When a
message is sent, Wallaroo applies a partition function to the message
to determine which state partition to send it to. Different state
partitions may live on different workers, and a partition may move
from one worker to another when workers are added or removed from the
cluster.

This example represents the state as a dictionary that is wrapped in
an object that knows how to update it and has a method that returns an
outgoing message object representing a given word's count.

```python
class WordTotals(object):
    def __init__(self):
        self.word_totals = {}

    def update(self, word):
        if self.word_totals.has_key(word):
            self.word_totals[word] = self.word_totals[word] + 1
        else:
            self.word_totals[word] = 1

    def get_count(self, word):
        return WordCount(word, self.word_totals[word])
```

There also needs to be a class that can build these state partition
objects. In this example, the class is `WordTotalsBuilder`.

```python
class WordTotalsBuilder(object):
    def build(self):
        return WordTotals()
```

`WordPartitionFunction` is a partition function takes a string and
returns the first character if the first character is a lowercase
letter, or a `"!"` if it is not.

```python
class WordPartitionFunction(object):
    def partition(self, data):
        if data[0] >= 'a' or data[0] <= 'z':
          return data[0]
        else:
          return "!"
```

#### Incoming Messages and the Decoder

The `Decoder` contains the logic for interpreting incoming bytes from
a TCP stream into an object that represents the message within the
application. In this example, incoming messages are represented as
strings.

```python
class Decoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        return bs.decode("utf-8")
```

#### Stateless Computation

`Split` is a stateless computation. It takes a string and splits it into
a list of strings where each string in the list represents a word.

```
"why hello world" -> Split -> ["why", "hello", "world"]
```

Here's what the `Split` computation looks like:

```python
class Split(object):
    def name(self):
        return "split into words"

    def compute_multi(self, data):
        punctuation = " !\"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"

        words = []

        for line in data.split("\n"):
            clean_line = line.lower().strip(punctuation)
            for word in clean_line.split(' '):
                clean_word = word.strip(punctuation)
                words.append(clean_word)

        return words
```

The `Split` computation doesn't actually send messages itself, it
returns a list of messages that the Wallaroo framework will send on
it's behalf. If the incoming message was `why hello world` then `why`
and `world` would be send to the "w" partition, and `hello` would be
send to the "h" partition. The `Split` computation does not need to be
aware of how data is partitioned, nor does it need to be aware of
which machines hold these partitions; the Wallaroo framework takes
care of all of that.

#### Stateful Computation

`CountWord` is a stateful computation; it uses an incoming message and
a state to update the word count for the new word and return a message
for Wallaroo to send on it's behalf.

```python
class CountWord():
    def name(self):
        return "Count Word"

    def compute(self, word, word_totals):
        word_totals.update(word)
        return (word_totals.get_count(word), True)
```

#### Outgoing Messages and the Encoder

In our example, the outgoing message is represented within the
application as an object that stores the word and the count of the
number of times that word has been seen in the event stream.

```
class WordCount(object):
    def __init__(self, word, count):
        self.word = word
        self.count = count
```

The `Encoder` contains the logic for transforming this object into a
list of bytes that will then be sent on the outgoing TCP
connection. In the example outgoing messages are strings of `WORD =>
COUNT\n` where `WORD` is the word being counted and `COUNT` is the
count.

```python
class Encoder(object):
    def encode(self, data):
        return data.word + " => " + str(data.count) + "\n"
```

## A Scalable Event Processing Application

This application can run on one worker and can scale horizontally by
adding more and more workers. Since each partition lives on a worker
and there are only 26 partitions, this application can't scale much
beyond 26 workers. However, an application with more partitions would
be able to take advantage of more workers.

## Running the Application

If you're interested in running this application yourself, take a look at the
the [Wallaroo documentation](https://docs.wallaroolabs.com) and the
[example applications](https://github.com/WallarooLabs/wallaroo/tree/release/examples/python) that
we've built. You'll find instructions on setting up Wallaroo and running applications. And take a look at
our [community page](https://www.wallaroolabs.com/community) to sign
up for our mailing list or join our IRC channel to ask any question you may have.

## Check It Out

We built Wallaroo to help people create applications without getting
bogged down in the hard parts of distributed systems. We hope you'll
take a look at
our [github repository](https://github.com/wallaroolabs/wallaroo) and
get to know Wallaroo to see if it can help you with the problems
you're trying to solve. And we hope to hear back from you about the
great things you've done with it.
