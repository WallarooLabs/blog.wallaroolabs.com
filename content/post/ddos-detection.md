+++
title = "DDoS Attack Detection with Wallaroo: A Real-time Time Series Analysis Example"
draft = true
date = 2017-11-30T00:00:00Z
tags = [
    "windowing",
    "partitioning",
    "python",
    "example",
]
categories = [
    "Example"
]
description = "Building a DDoS attack detector using timeseries analysis in real time with Wallaroo."
author = "nisanharamati"
+++


This post will go through a real-world use case for Wallaroo, our distributed data processing framework for building high-performance streaming data applications. We will construct a streaming DDoS attack detector, which consumes a stream of request logs from a large group of servers and uses statistical anomaly detection to alert us when a server is under attack.

If you're new to Wallaroo and are interested in learning more about it before diving into today's example, you can check our [Go Python, Go! Stream Processing for Python][go python] post, where we introduce the Wallaroo Python API.

The code for the example in this post can be found on [GitHub][ddos-detection], and can be run with the [current version of Wallaroo (0.2.2)](https://github.com/WallarooLabs/wallaroo/tree/0.2.2).

## When Your Service Layer is Under Attack

In addition to the benefits you get in terms of reach when running an application over the Internet, you are also exposed to a variety of threats. One of these threats—a distributed denial of service attack—is what we will handle in this example.

According to [Cloudflare][cloudflare what is ddos],

> [a] distributed denial-of-service (DDoS) attack is a malicious attempt to disrupt normal traffic of a targeted server, service or network by overwhelming the target or its surrounding infrastructure with a flood of Internet traffic.

The attack utilizes the fact that responding to each request takes up a fraction of your system's finite resources. So if an attacker can generate sufficiently many requests, they can use up all of your resources, leaving none available to service legitimate requests from your users. Typically, in order to avoid being throttled, an attacker will use a large number of (probably) compromised machines to send service requests, making it hard to block them.

Responding to attacks is an art in itself, but first you must know that it's happening. Early detection is key.

## Detecting that an Attack is Underway

In order to detect an attack, we need two things:

1. a model for "good" or "normal" behaviour
2. a way to measure our services' current behaviour to compare against the "normal" one

If the difference between the measured behaviour and the normal behaviour is too large, we can mark the measured data point as anomalous. This process is called anomaly detection. In the case of the DDoS attack, if the anomalous behaviour matches an attack pattern, we will mark the server as "under attack".

Since DDoS attacks typically involve a sharp increase in traffic, we can use "healthy" traffic to derive a "normal" model on the fly, using the ongoing metrics from our servers. Once a normal model is established, we can look for a sharp increase in the number of requests and number of unique clients that a server is handling as an indicator for a potential DDoS attack.

To do this, we will compute a weighted mean and a weighted standard deviation for the requests/second and unique-clients/second values over a fixed window of metrics data for each server. Then as each new data point arrives, we will make a prediction of the final-value for the current second. If our prediction differs from the mean by more than 2 standard deviations, we will mark the server as under attack. For this illustration, we will use 1-second intervals, and a 60-second window.

The basic logic is described below:

1. Each web request produces a log entry containing a timestamp, a client IP address, the server IP address, and the resource requested.
2. While the server is healthy, we compute a weighted mean and weighted standard deviation over the last 60 seconds of data (for each of requests/second and unique-clients/second).
    We update these values whenever a full second rolls over and the window moves forward by one second.
3. For the current fragment of a second, we compute the _predicted_ metrics, using the current number of requests and unique clients measured so far, divided by the fraction of the second.
4. We subtract the mean values from the predicted ones, and compare the difference to their respective standard deviations. If either of the differences is greater than 2 multiples of the standard deviation (e.g. > 2 sigma), we call this prediction anomalous.
5. Since early data can be misleading, we also apply a minimum threshold to prevent flapping: in order to change from "healthy" to "under attack", there must be at least 20 requests the current prediction's sample.
    And likewise, in order to change from "under attack" to "healthy", there must be at least 10 requests in the current prediction's sample.
6. Whenever a server's status changes from either "healthy" to "under attack" and vice versa, we notify a consumer via a message over TCP, noting the server's address, the new status, and the time at which it changed.

## The Application in Wallaroo

![application diagram][application diagram]

Our application's input will be a stream of request events, containing a timestamp, a client IP address, a server IP address, and a resource identifier, recorded as a JSON document.

```
...
{"timestamp":1509494400.0,"client":"191.115.118.144","resource":"f06b667efd","server":"23.133.98.170"}
{"timestamp":1509494400.001,"client":"212.177.244.108","resource":"8c4af94440","server":"187.224.241.67"}
{"timestamp":1509494400.002,"client":"229.28.98.137","resource":" 594e9919a","server":"224.217.101.60"}
...
```

In this example, we will use synthetic data generated with a python script that is included along with the demo code at [ddos-detection].
The data has the following characteristics:

1. 100 servers, serving 10,000 resources.
2. 10 seconds of normal traffic, with 1,000 clients making 1,000 requests/second, distributed uniformly over all the servers.
3. 10 seconds of attack traffic, with 100,000 clients making 25,000 requests/second, with 90% of the traffic hitting only 10 servers.
4. 10 seconds of normal traffic, with 1,000 clients making 1,000 requests (in total) per second, distributed uniformly over all the servers.

To produce a similar set, run

```bash
python data_gen.py --clients 1000 --attack-clients 100000 \
  --requests 1000 --attack-requests 25000 --loaded-weight 0.9 \
  --file data.json
```

To consume this stream, we will need to decode the JSON documents with a Wallaroo `Decoder`, using the standard library's `json` module:

```python
class Decoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        return json.loads(bs)
```

As each server's status is computed independently of the others, we need a way to choose the partition for each incoming record. We could create a partition for each unique IP address, but without prior knowledge about the IPs we need to monitor, that would require a partition index list the size of 2^32 - 1 (assuming only IPv4 addresses), which will take a massive amount of memory. Instead, we will divide the IP range into _K_ even segments to be our partitions. We can then convert the string IP address in each record from the form of `A.B.C.D` to an integer, and determine the index of the segment it is in, which will become its partition identifier.

```python
class ServerPartitionFunction(object):
    def __init__(self, partitions):
        self.part_size = 2**32/partitions

    def partition(self, data):
        parts = data['server'].split('.')
        ipnum = ((int(parts[0]) << 24) + (int(parts[1]) << 16) +
                 (int(parts[2]) << 8) + int(parts[3]))
        return ipnum/self.part_size
```

The state object is where things get interesting. For each server, we need to maintain a 60 seconds long rolling window of aggregate data. This data is small enough that we could probably use a list and pay the cost of shifting it whenever we need to roll the window. But a more efficient way of doing this, especially if the data window is larger, would be to use a [circular buffer]. For brevity, the code for the circular buffer is not included in this post, but you may find in the [demo code][ddos-detection circularbuffer].

For each server, we need to keep track of a few things:

1. `address` - the server's address
2. `window` - a rolling window of per-second data aggregates for requests per second and unique clients per second
3. `requests_mean` - the weighted mean of the requests data over the window
4. `requests_stdev` - the weighted standard deviation of the requests data over the window
5. `clients_mean` - the weighted mean of the clients data over the window
6. `clients_stdev` - the weighted standard deviation of the clients data over the window
7. `current_ts` - the current partial second's timestamp
8. `current_requests` - the number of requests for the current (partial) second
9. `current_clients` - a set of unique client addresses (to produce the number of clients per second aggregate)
10. `is_attack` - the current health status of the server

```python
class SingleServerLoadStatistics(object):
    def __init__(self, address):
        self.address = address
        self.window = CircularBuffer(60)
        self.requests_mean = 0
        self.requests_stdev = 0
        self.clients_mean = 0
        self.clients_stdev = 0
        self.current_ts = 0
        self.current_requests = 0
        self.current_clients = set()
        self.is_attack = False
```

We also need to implement three pieces of logic:

1. Updating our model by advancing the window and recomputing the means and standard deviations
2. Updating the current fragment's data
3. Predicting whether the server is under attack in the current fragment and acting on that prediction

The code for computing the weighted mean and standard deviation can be found in the [demo code][ddos-detection stats].

Since our application is event driven, it is possible for the time difference between two metrics for the same server to be larger than 1 second. So we need to be careful about filling in any gaps when we advance the window.

If this is the first time we advance the window, then we can insert the new record right away, and set the means to the value in the new record (since the mean of a single value is itself).

```python
def update_model(self, timestamp):
    if not self.window:
        self.window.append((self.current_ts, self.current_requests,
                            len(self.current_clients)))
        self.requests_mean = self.current_requests
        self.clients_mean = len(self.current_clients)
```

In all other cases, we have to be careful about backfilling two gaps: the one between the last timestamp in the window and the timestamp of the second we're about to add to the window:

```python
    else:
        last_ts = self.window[-1][0]
        for ts in range(last_ts, self.current_ts):
            self.window.append((ts, 0, 0))
        self.window.append((self.current_ts, self.current_requests,
                            len(self.current_clients)))
```

And the gap between the timestamp of the second being added to the window and the timestamp of the new partial second:

```python
        last_ts = self.window[-1][0]
        for ts in range(last_ts, timestamp):
            self.window.append((ts, 0, 0))
```

Once the window has been updated, we can update the weighted means and standard deviations, but only if the server is not currently under attack:

```python
        if not self.is_attack:
            self.requests_mean, self.requests_stdev = (
                weighted_mu_sigma(map(lambda x: x[2], self.window),
                                  range(1, len(self.window) + 1)))
            self.clients_mean, self.clients_stdev = (
                weighted_mu_sigma(map(lambda x: x[1], self.window),
                                  range(1, len(self.window) + 1)))
```

And finally, reset the values for the current fragment:

```python
    self.current_ts = timestamp
    self.current_requests = 0
    self.current_clients = set()
```

Updating the current fragment's aggregates is straightforward.

```python
def update_fragment(self, data):
    self.current_requests += 1
    self.current_clients.add(data['client'])
```

When predicting the attack status, we should take some care in handling the minimum thresholds to avoid flapping in the 4 possible transitions

1. healthy --> healthy
2. healthy --> under_attack
3. under_attack --> healthy
4. under_attack --> under_attack

```python
def predict_from_fragment(self, timestamp):
    ts_frac = timestamp % 1
    if ts_frac > 0 and self.current_requests > 10:
        # Predict the final values of the current fragment
        exp_cli = len(self.current_clients)/ts_frac
        exp_req = self.current_requests/ts_frac

        # is it >2sigma from the mean?
        is_attack = False
        if (exp_cli - self.clients_mean) > (2 * self.clients_stdev):
            is_attack = True
        elif (exp_req - self.requests_mean) > (2 * self.requests_stdev):
            is_attack = True

        if is_attack:
            if self.is_attack:
                # under_attack -> under_attack
                return None
            else:
                if self.current_requests > 20:
                    # healthy -> under_attack
                    self.is_attack = True
                    return (self.address, timestamp, True)
        else:
            if self.is_attack:
                # under_attack -> healthy
                self.is_attack = False
                return (self.address, timestamp, False)
            else:
                # healthy -> healthy
                return None
```

The `SingleServerStats` maintains the state and predicts the status for a single server, but our partitions are for IP range segments, and not unique IP addresses. So we need to have a state object per partition, which will route the updates within a partition to the correct server. This is the [state object][wallaroo state] that Wallaroo maintains for resilience purposes.

```python
class PartitionStatsBuilder(object):
    def build(self):
        return PartitionLoadStatistics()


class PartitionLoadStatistics(object):
    def __init__(self):
        self.servers = {}

    def update(self, data):
        return (self.servers.setdefault(data['server'],
                                        SingleServerLoadStatistics(
                                            data['server']))
                .update(data))
```

The computation, `ProcessLogEntry`, interacts directly with the `PartitionLoadStatistics` state object by passing the incoming data to the state's `update` method.

```python
class ProcessLogEntry(object):
    def name(self):
        return "Process web log entry"

    def compute(self, data, state):
        status = state.update(data)
        return (status, True)
```

We also need to encode the output data for a TCP consumer

```python
class Encoder(object):
    def encode(self, data):
        # data is a tuple of (server_name, timestamp, is_under_attack)
        if data[2]:
            # under attack
            return ("Server {} is under ATTACK! (Status changed at {})\n"
                    .format(data[0], data[1]))
        else:
            # no longer under attack
            return ("Server {} is no longer under attack. "
                    "(Status changed at {})\n"
                    .format(data[0], data[1]))
```

And finally, perform the imports and set up the application and its pipeline so Wallaroo can run it all:

```python
import json
import pickle
import struct

import wallaroo

from circular_buffer import CircularBuffer
from stats import weighted_mu_sigma


def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    partitions = 10000
    server_partitions = range(partitions)

    ab = wallaroo.ApplicationBuilder("DDoS Attack Detector")
    ab.new_pipeline("ddos detection",
                    wallaroo.TCPSourceConfig(in_host, in_port, Decoder()))
    ab.to_state_partition_u64(ProcessLogEntry(), PartitionStatsBuilder(),
                          "process log entry",
                          ServerPartitionFunction(partitions),
                          server_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
    return ab.build()
```

## Running the Application

To run the application, we will use netcat for our TCP receiver, and a custom sender that's included in the [demo code][ddos-detection] which will send server metrics in batches of 1000, and attempt to keep the timing roughly in line with the time deltas of the input records by sleeping between batches.

The following steps will run the application:

1. Set up Wallaroo for your OS following [these instructions][setup instructions]
2. Check out the [Wallaroo Blog Examples GitHub repository][wallaroo blog examples] and navigate to the ddos-detection example directory

    ```bash
    git clone https://github.com/WallarooLabs/wallaroo_blog_examples.git
    cd wallaroo_blog_examples/ddos-detection
    ```

3. Start the included listener in its own terminal so you can view the output

    ```bash
    python receiver.py --host 127.0.0.1:7002
    ```

4. Start two Wallaroo workers
    in two separate terminals:
    1. Initializer:

        ```bash
        export PYTHONPATH="$PYTHONPATH:.:$HOME/wallaroo-tutorial/wallaroo/machida"
        export PATH="$PATH:$HOME/wallaroo-tutorial/wallaroo/machida/build"
        machida --application-module ddos_detector --in 127.0.0.1:7010 --out 127.0.0.1:7002 \
          --control 127.0.0.1:12500 --data 127.0.0.1:12501 --name initializer --cluster-initializer \
          --worker-count 2 --metrics 127.0.0.1:5001 --ponythreads 1 --ponypinasio --ponynoblock
        ```

    2. 2nd Worker:

        ```bash
        export PYTHONPATH="$PYTHONPATH:.:$HOME/wallaroo-tutorial/wallaroo/machida"
        export PATH="$PATH:$HOME/wallaroo-tutorial/wallaroo/machida/build"
        machida --application-module ddos_detector --in 127.0.0.1:7010  --out 127.0.0.1:7003 \
          --control 127.0.0.1:12500  --name worker --metrics 127.0.0.1:5001 --ponythreads 1 \
          --ponypinasio --ponynoblock
        ```

4. Start the sender:

    ```bash
    python sender.py --host 127.0.0.1:7010 --file data.json --batch 1000
    ```

And your output should look like:

![demo gif][demo gif]

## Next Steps

This example builds on the concepts introduced in [Non-native event-driven windowing in Wallaroo][windowing in wallaroo]. It adds partitioning, parallelization, and the application of statistical analysis to perform a simplified anomaly detection.

However, as this example is designed for illustration purposes, it is not without limitations: the thresholds used for preempting false-positives aren't adaptive, and may not work well with certain loads; the anomaly detection algorithm itself is very simplistic in its assumptions, and may falsely flag legitimate increases in traffic as malicious; likewise, it may fail to detect malicious traffic that isn't large enough relative to the legitimate traffic; the partitioning logic assumes server IPs are uniformly distributed across the entire IPv4 range, while in reality most of the servers you're interested in monitoring have addresses in a much smaller range. In the production use case, we would use more sophisticated algorithms to address these limitations.

If you wish to see the full code, it is available on [GitHub][ddos-detection]. If you have any technical questions that this post didn't answer, or if you have any suggestions, please get in touch via [our mailing list][mailing list] or [our IRC channel][irc channel].

Keep an eye out for future posts about example use cases, the philosophy behind Wallaroo, and how we go about making sure Wallaroo handles your data safely even in the event of crashes.



[circular buffer]: https://en.wikipedia.org/wiki/Circular_buffer
[wallaroo blog examples]: https://github.com/WallarooLabs/wallaroo_blog_examples
[ddos-detection]: https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/ddos-detection
[ddos-detection stats]: https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/ddos-detection/stats.py
[ddos-detection circularbuffer]: https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/ddos-detection/circular_buffer.py
[windowing in wallaroo]: /2017/11/non-native-event-driven-windowing-in-wallaroo
[go python]: /2017/10/go-python-go-stream-processing-for-python/
[cloudflare what is ddos]: https://www.cloudflare.com/learning/ddos/what-is-a-ddos-attack/
[nist]: http://www.itl.nist.gov/div898/software/dataplot/refman2/ch2/weightsd.pdf
[weighted mean]: https://en.wikipedia.org/wiki/Weighted_arithmetic_mean
[setup instructions]: https://docs.wallaroolabs.com/book/getting-started/setup.html
[mailing list]: https://groups.io/g/wallaroo
[irc channel]: https://webchat.freenode.net/?channels=#wallaroo
[wallaroo state]: https://docs.wallaroolabs.com/book/core-concepts/state.html


[this site cannot be reached]: /images/post/ddos-detection/this_site_cannot_be_reached.png
[application diagram]: /images/post/ddos-detection/application_diagram.png
[demo gif]: /images/post/ddos-detection/demo.gif
