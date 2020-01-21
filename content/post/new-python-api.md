+++
title= "Idiomatic Python Stream Processing in Wallaroo"
date = 2018-02-01T12:00:00-04:00
draft = true
author = "aturley"
description = "Wallaroo’s New Python API makes writing distributed stream processing applications more Pythonic."
tags = [
    "python",
    "api",
    "announcement"
]
categories = [
    "announcement"
]
+++

We have been working on Wallaroo, our scale-independent event processing system, for a little over two years. When we open sourced it in September of 2017 we included an API for writing applications using a Python API. This blog post tells the story of what we learned from the feedback we received about the original API and how we applied that feedback to make improvements that have led to our new API.

Three months ago I wrote [a blog post](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) about the first iteration of our Python API. At the end of that post I wrote, "Our API is new, and we are looking at ways to improve it. We have a lot of ideas of our own, but if you have any ideas, we would love to hear from you." We got some feedback on various channels, including [Hacker News](https://news.ycombinator.com/item?id=15457343) and direct communications with folks who were interested in Wallaroo. One theme that emerged from these conversations was that folks felt that the API didn’t use Python in an idiomatic way (a quality that Python users often refer to as “Pythonic”). And internally we had felt that there were things that we could improve in the API.

We took the feedback and began to think about what kinds of things made the existing API unpythonic. Then we mocked up some of our ideas and tried them out by reimplementing some of our example programs to see how they felt. Finally, we worked on solving some unexpected problems that arose from the changes. The end result is a new Wallaroo Python API that is much more concise and Pythonic than the original. We’ve gotten some great early feedback, and we think it represents a notable improvement over the original API.

## What Was Wrong with the Original Python API

Wallaroo makes heavy use of Pony classes, and the original Python API closely mirrored this because doing so allowed us to reason more easily about how the pieces of the API would fit together with the underlying Pony objects that made Wallaroo work. Unfortunately, that meant that the API didn’t feel natural to Python programmers.

One comment was that the API was verbose. It required the user to create lots of classes, many of which had one method for doing something and another method for returning a name. In other words, many of these classes were really just functions with names. People thought that it was silly to have to define an entire class just to get a function. And they were right.

Another comment was that there were places where a developer would have to write the same code every time they implemented something, even though for the most part the code was the same. For example, in decoders the user had to provide methods that:

1. return the number of bytes that would represent the header for a message
2. take an array of bytes and return the actual size of the message
3. take the message bytes and return the object represented by the message

Here’s what a decoder used to look like:

```pony
class Decoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        return bs.decode("utf-8")
```

The only part of the decoder that really needs to have any logic is the part that takes bytes and returns a message; the first item can be described by an integer and the second one can be described by a string that is passed as an argument to `struct.unpack(...)` to tell it how to turn the incoming bytes into a number. With these changes, a decoder now looks like this:
```python
@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(bs):
    return bs.decode("utf-8")
```

## Why We Created a New API

Before we had even published the blog post about the original Python API, we had discussed ideas for things that we could do to improve the API. One of the ideas that we had considered was using decorators to cut down on the number of classes and thus reduce the amount of code that needed to be written. When we asked for feedback, several people suggested using decorators to improve the API, so we felt that our earlier idea had been validated. We went ahead and designed a new decorator-based API.

## The New Python API

### A Motivating Example

We will start with the canonical streaming data processing application, Word Count. A stream of input text is analyzed and the total number of times each word has been seen is reported. [The example](https://github.com/WallarooLabs/wallaroo/blob/release/examples/python/word_count/word_count.py) in it's entirety is in our [GitHub repository](https://github.com/WallarooLabs/wallaroo/tree/release).

We will make the following assumptions:

* Incoming messages will come from a TCP connection and be sent to
  another TCP connection.
* Words are sent to the system in messages that can contain zero or
  more words.
* Incoming messages consist of a string.
* Outgoing messages consist of a word and the number of times that
  word has been seen in the event stream.

![Word Count Diagram](/images/post/python-api/word-count-diagram.png)

In our example, we will also split the state (the number of times each word has been seen) into 26 partitions, where each partition handles words that start with different letters. For example "acorn" and "among" would go to the "a" partition, while "bacon" would go to the "b" partition.

This application will process messages as they arrive. This contrasts with some other streaming data processing systems that are designed around processing messages in micro-batches. This results in lower latencies because message processing is not delayed.

### Wallaroo's Core Abstractions

In order to understand the Python API, it is important to understand Wallaroo's core abstractions:

* State -- Accumulated result of data stored over the course of time.
* Computation -- Code that transforms an input to an
  output.
* State Computation -- Code that takes an input and a state
  entity, operates on that input and state
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

We’ll cover these abstractions in more detail as we proceed.

### Application Setup

Wallaroo calls the `application_setup` function to create a data structure that represents the application.

```
def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    word_partitions = list(string.ascii_lowercase)
    word_partitions.append("!")

    ab = wallaroo.ApplicationBuilder("Word Count Application")
    ab.new_pipeline("Split and Count",
                    wallaroo.TCPSourceConfig(in_host, in_port, decoder))
    ab.to_parallel(split)
    ab.to_state_partition(count_word, WordTotals, "word totals",
        partition, word_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
    return ab.build()
```

This code creates an application with the topology that was described earlier. It represents one pipeline that consists of a stateless computation called `Split` that splits a string of words into individual words and a state computation called `CountWord` that updates the state of the application and creates outgoing messages that represent the word count. The objects and functions used here will be described more in the following sections.

#### State Partitions and State Entities

In this example, the state is the number of times each word has been seen. The easiest way to do this would be with a dictionary where the key is a word, and the value associated with that key is the number of times that word has been seen in the event stream.

Wallaroo lets you divide state partitions into pieces called state entities. State entities are pieces of state partitions that are uniquely identified by a key of some sort. State can be partitioned by any number of keys. The only restriction is that the state entities must be completely isolated from each other so that they can be accessed and updated independently.

When a message is sent, Wallaroo applies a partition function to the message to determine which state partition to send it to. Different state entities may live on different workers, and an entity may move from one worker to another when workers are added or removed from the cluster. This makes it easy to scale the application up and down as the number of workers in the cluster increases and decreases.

This example represents the state as a dictionary that is wrapped in an object that knows how to update it and has a method that returns an outgoing message object representing a given word's count.

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

`partition` is a partition function that takes a string and returns the first character if the first character is a lowercase letter, or a `"!"` if it is not. The `@wallaroo.partition` decorator must be used to indicate that the function is a partition function.

```python
@wallaroo.partition
def partition(data):
    if data[0] >= 'a' or data[0] <= 'z':
        return data[0]
    else:
        return "!"
```

#### Incoming Messages and the Decoder

The `decoder` contains the logic for interpreting incoming bytes from a TCP stream into an object that represents the message within the application. In this example, incoming messages are represented as strings.

```python
@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(bs):
    return bs.decode("utf-8")
```

The `@wallaroo.decoder` decorator must be used to indicate that this is a decoder. The `header_length` argument specifies the number of bytes that will be used for the message length. The `length_fmt` argument specifies the way the length bytes are structured using the same format that is used by the `struct` module. In this case, `">I"` means that the length will be a big-endian 32-bit integer.

#### Stateless Computation

`split` is a stateless computation. It takes a string and splits it into a list of strings where each string in the list represents a word.

```
"why hello world" -> Split -> ["why", "hello", "world"]
```

Here's what the `split` computation looks like:

```python
@wallaroo.computation_multi(name="split into words")
def split(data):
    punctuation = " !\"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"

    words = []

    for line in data.split("\n"):
        clean_line = line.lower().strip(punctuation)
        for word in clean_line.split(' '):
            clean_word = word.strip(punctuation)
            words.append(clean_word)

    return words
```

The `split` computation returns a list of individual words that the Wallaroo framework sends along as messages to the next step in the pipeline. Wallaroo takes care of making sure that each message gets delivered to the correct partition. Your application does not need to know how the data is partitioned or which machine holds that partition. The `@wallaroo.computation_multi(...)` decorator must be used to indicate that this is a computation that returns multiple outgoing messages. The `name` argument specifies the name of the computation that will be used by Wallaroo when reporting information about the application.

#### State Computation

`count_word` is a state computation; it uses an incoming message and a state entity to update the word count for the new word and returns a message for Wallaroo to send on its behalf. The second value, in the returned tuple, indicates to Wallaroo that the state entity should be persisted because it has been updated.

```python
@wallaroo.state_computation(name="Count Word")
def count_word(word, word_totals):
    word_totals.update(word)
    return (word_totals.get_count(word), True)
```

The `@wallaroo.state_computation(...)` decorator must be used to indicate that this is a state computation. As with the computation above, the `name` argument specifies the name that Wallaroo will use when reporting information about the application.

#### Outgoing Messages and the Encoder

In our example, the outgoing message is represented within the application as an object that stores the word and the count of the number of times that word has been seen in the event stream.

```
class WordCount(object):
    def __init__(self, word, count):
        self.word = word
        self.count = count
```

The `encoder` contains the logic for transforming this object into a list of bytes that will then be sent on the outgoing TCP connection. In the example, outgoing messages are strings of `WORD => COUNT\n` where `WORD` is the word being counted and `COUNT` is the count.

```python
@wallaroo.encoder
def encoder(data):
    return data.word + " => " + str(data.count) + "\n"
```

The `@wallaroo.encoder` decorator must be used to indicate that this function is an encoder.

This example uses a TCP sink, but Wallaroo also supports Kafka sinks. Other types of sinks will be added in the future.

## A Scalable Event Processing Application

This application can run on one worker and can scale horizontally by adding more and more workers. Wallaroo's flexibility makes it easy to adapt to whatever partitioning strategy your application requires. Take a look at our documentation for [information about how to run a Wallaroo cluster](https://docs.wallaroolabs.com/book/running-wallaroo/running-wallaroo.html#multi-worker-setup).

## Check It Out

If you're interested in running this application yourself, take a look at the [Wallaroo documentation](https://docs.wallaroolabs.com) and the [word count example application](https://github.com/WallarooLabs/wallaroo/tree/release/examples/python/word_count) that we've built. You'll find instructions on setting up Wallaroo and running applications. And take a look at our [community page](https://www.wallaroolabs.com/community) to sign up for our mailing list or join our IRC channel to ask any question you may have.

This API represents what we think is an improvement over our original Python API. Applications written using the new API are more compact and readable than they were before, and they feel more Pythonic. While we're very happy with this improvement, we know that there are always ways to make things even better, so if you have suggestions for improvements we would love to hear from you. Please get in touch with us on [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).


## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
