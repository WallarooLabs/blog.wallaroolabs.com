+++
title= "Go Python, Go! Stream Processing for Python"
date = 2017-10-12T12:00:00-04:00
draft = false
slug = "go-python-go-stream-processing-for-python"
author = "aturley"
description = "Wallaroo’s Python API let's you write distributed stream processing applications in your favorite language, Python."
tags = [
    "wallaroo",
    "python",
    "api"
]
categories = [
    "Python API"
]
+++

We've been hard at work for 18 months on [a new processing engine called Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release) for deploying and operating big data, fast data, and machine learning applications. We designed Wallaroo to make the infrastructure virtually disappear, so you get rapid deployment and easy-to-operate applications. It provides a simple model for building fast applications that scale automatically across any number of workers.

With Wallaroo, you focus on your business algorithms, not your infrastructure, and you can use the Python libraries you’re already familiar with. Wallaroo uses an embedded Python interpreter to run your code rather than calling out to a separate Python process, which makes your application run faster. Wallaroo isn’t built on the JVM, which provides advantages that we will cover in a later blog post. And finally, [Wallaroo is open-source](https://blog.wallaroolabs.com/2017/09/open-sourcing-wallaroo/).

This blog post will show you how to use [Wallaroo's Python API](https://docs.wallaroolabs.com/book/python/api.html) to build elastic event-by-event processing applications.

## The Python API

### A Motivating Example

The canonical streaming data processing application is Word Count, in
which a stream of input text is analyzed and the total number of times
each word has been seen is reported. This description is broad enough
to allow developers to make different design tradeoffs in their
implementations. You can find
[this example](https://github.com/WallarooLabs/wallaroo/blob/release/examples/python/word_count/word_count.py) in
it's entirety in
our
[GitHub repository](https://github.com/WallarooLabs/wallaroo/tree/release).

For this example we will make the following assumptions:
* Incoming messages will come from a TCP connection and be sent to
  another TCP connection.
* Words are sent to the system in messages that can contain zero or
  more words.
* Incoming messages consist of a string.
* Outgoing messages consist of a word and the number of times that
  word has been seen in the event stream.


![Word Count Diagram](/images/post/python-api/word-count-diagram.png)

In our example we will also split the state (the number of times each
word has been seen) into 26 partitions, where each partition handles
words that start with different letters. For example "acorn" and
"among" would go to the "a" partition, while "bacon" would go to the
"b" partition.

This application will process messages as they arrive. This contrasts with some other streaming data processing systems that are designed around processing messages in micro-batches. This results in lower latencies because message processing is not delayed.

### Wallaroo's Core Abstractions

In order to understand the Python API, it is important to understand
Wallaroo's core abstractions:
* State -- Accumulated result of data stored over the course of time.
* Computation -- Code that transforms an input to an
  output.
* State Computation -- Code that takes an input and a state
  object, operates on that input and state
  (possibly making state updates), and optionally produces an output.
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
individual words and a state computation called `CountWord` that
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

When a
message is sent, Wallaroo applies a partition function to the message
to determine which state partition to send it to. Different state
partitions may live on different workers, and a partition may move
from one worker to another when workers are added or removed from the
cluster. This makes it easy to scale the application up and down as the number of workers in the cluster increases and decreases.

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

This decoder is specific to TCP sources. Wallaroo also has support for Kafka sources, and other source types will be added in the future.

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

The `Split` computation returns a list of individual words that the Wallaroo framework sends along as messages to the next step in the pipeline. Wallaroo takes care of making sure that each message gets delivered to the correct partition. Your application does not need to know how the data is partitioned or which machine holds that partition.

#### Stateful Computation

`CountWord` is a stateful computation; it uses an incoming message and
a state to update the word count for the new word and returns a message
for Wallaroo to send on its behalf.

```python
class CountWord(object):
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

This example uses a TCP sink, but Wallaroo also supports Kafka sinks. Other types of sinks will be added in the future.

## A Scalable Event Processing Application

This application can run on one worker and can scale horizontally by
adding more and more workers. Wallaroo's flexibility makes it easy to adapt to whatever partitioning strategy your application requires. Take a look at our documentation for [information about how to run a Wallaroo cluster](https://docs.wallaroolabs.com/book/core-concepts/clustering.html).

## Check It Out

If you're interested in running this application yourself, take a look at the
the [Wallaroo documentation](https://docs.wallaroolabs.com) and the
[word count example application](https://github.com/WallarooLabs/wallaroo/tree/release/examples/python/word_count) that
we've built. You'll find instructions on setting up Wallaroo and running applications. And take a look at
our [community page](https://www.wallaroolabs.com/community) to sign
up for our mailing list or join our IRC channel to ask any question you may have.

You can also watch this video to see Wallaroo in action. Our VP of Engineering walks you through the concepts that were covered in this blog post and then shows the word count application scaling by adding new workers to the cluster.

<iframe src="https://player.vimeo.com/video/234753585" width="640" height="360" frameborder="0" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>

Our API is new and we are looking at ways to improve it. We have a lot of ideas of our own, but if you have any ideas we would love to hear from you. Please don’t hesitate to get in touch with us through [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.oftc.net/?channels=wallaroo).

We built Wallaroo to help people create applications without getting
bogged down in the hard parts of distributed systems. We hope you'll
take a look at
our [GitHub repository](https://github.com/wallaroolabs/wallaroo) and
get to know Wallaroo to see if it can help you with the problems
you're trying to solve. And we hope to hear back from you about the
great things you've done with it.
