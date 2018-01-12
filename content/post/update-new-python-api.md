+++
title = "How to update your Python applications to the new API"
slug = "update-new-python-api"
draft = false
date = 2017-11-09T00:00:00Z
tags = [
    "wallaroo",
    "python",
    "howto"
]
categories = [
    "API"
]
description = "Guide to updating to the new API version"
author = "amosca"
+++

In version 0.4.0, we relased some breaking changes to the Python API. Whilst these have been seen as improvements to the API resulting in smaller applications with less boiler-plate code, it means you will have to update the code for your applications. We created this blog entry to help guide you through the process. We'll be using word count as an example, but you should be able to follow along with your own code.

## What's changed

A few things are now different (we hope you'll agree that this is better):

* We use a lot less "helper" classes, and replaced them with decorators
* You no longer need to create StateBuilder classes
* Header decoding is much simpler

## Update your decoders

Let's proceed in the standard order of what a pipeline would look like. So first, we want to update our decoders to the new API. The new format uses the `@wallaroo.decoder` decorator. So instead of creating a `Decoder` class that implements certain methods, we define a `decode` function (this can have any name), and wrap it with the decorator. We also drop the `header_length()` and `payload_length()` methods, and instead pass a `header_length` and `length_ftm` arguments to the decorator. So
```
class Decoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        return bs.decode("utf-8")
```
becomes
```
@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(bs):
    return bs.decode("utf-8")
```

Much prettier, right? That's what we were going for: a simplified API that removes a lot of boilerplate code!

Then, you will need to update your pipeline creation to use the new function instead of the old class:
```
ab.new_pipeline("Split and Count",
								wallaroo.TCPSourceConfig(in_host, in_port, Decoder()))
```
becomes
```
ab.new_pipeline("Split and Count",
								wallaroo.TCPSourceConfig(in_host, in_port, decoder))
```

## Remove StateBuilders

You know those StateBuilder classes we made you create to that wallaroo could instantiate a new State for you on each partition? They're gone. Instead, when you create the pipeline, you directly pass your state class as an argument to the pipeline creation calls. For example:

```
ab.to_state_partition(CountWord(), WordTotalsBuilder(), "word totals",
		WordPartitionFunction(), word_partitions)
```

becomes

```
ab.to_state_partition(count_word, WordTotals, "word totals",
		partition, word_partitions)
```

## State classes stay the same

Your state class does not change. We didn't see any improvements from being able to take *anything* as state. Hooray!

## Update your partition functions (if you have them)

Instead of having to create a partition function object, you can simply declare a function (with any name), and wrapper with the `@wallaroo.partition` decorator. So

```
class WordPartitionFunction(object):
    def partition(self, data):
        if data[0] >= 'a' and data[0] <= 'z':
          return data[0]
        else:
          return "!"
```

becomes

```
@wallaroo.partition
def partition(data):
    if data[0] >= 'a' or data[0] <= 'z':
        return data[0]
    else:
        return "!"
```

You will also have to update your `to_state_partition` call to use the new wrapped function (see the previous section).

## Update your computations

This is the biggest of the changes. First of all, a computation is no longer a class. We use a few wrappers to distinguish different computations:

* `computation`: a stateless computation
* `computation_multi`: a stateless computation that outputs multiple messages at once
* `state_computation`: a computation that uses state
* `state_computation_multi`: a state computation that outputs multiple messages at once

You will have to pick the right one to match your type of computation. However, the changes you will have to make after that are all similar to each other. 
```
class CountWord(object):
    def name(self):
        return "Count Word"

    def compute(self, word, word_totals):
        word_totals.update(word)
        return (word_totals.get_count(word), True)
```
becomes
```
@wallaroo.state_computation(name="Count Word")
def count_word(word, word_totals):
    word_totals.update(word)
    return (word_totals.get_count(word), True)
```

Notice that the `name()` method is gone completely. Instead, we pass the name of the computation as an argument to the decorator. Also, the name of the function that computes the results can be anything. The only thing that remains to be done is to update the pipeline creation, but replacing all references to the computation class (`CountWord`) to the wrapped function (`count_word`).

## Update your encoders

The very last thing left to do, is to update your sink encoders. As you might have guessed by now, there is a `@wallaroo.decoder` decorator, and we need to wrap our `decode` function in this. So
```
class Encoder(object):
    def encode(self, data):
        return data.word + " => " + str(data.count) + "\n"
```
becomes
```
@wallaroo.encoder
def encoder(data):
    return data.word + " => " + str(data.count) + "\n"
```

Then we update our pipeline calls and we are done:

```
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
```
becomes
```
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
```


We hope you didn't find the upgrade process too cumbersome, and that the benefits from having a simpler, more pythonic API is going to make using wallaroo even more easy and fun!
