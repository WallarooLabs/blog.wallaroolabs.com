+++
title = "Wallaroo: We’ve heard your feedback, here’s what’s coming"
date = 2018-05-03T14:42:42-04:00
draft = false
author = "seantallen"
description = "What's coming over the next few months with Wallaroo? A lot of features that you've asked for!"
tags = [
    "Wallaroo",
    "Resilience",
    "Python",
    "Go",
    "Integration",
    "Partitioning",
    "State"
]
categories = [
    "Hello Wallaroo"
]
+++
Its been over a year since I wrote the first blog post [introducing Wallaroo to the world](/2017/03/hello-wallaroo/). We’ve covered a lot of ground since then; from introducing the [Python API](/2018/02/idiomatic-python-stream-processing-in-wallaroo/) that is our primary product, to [releasing all our code under an open core model](/2017/09/open-sourcing-wallaroo/). I’m not writing to you today to look back, but instead, forward. I want to talk about what’s coming in Wallaroo over the next few months, but first a bit about how we got here.

We’ve been hard at work on Wallaroo, and also hard at work getting feedback from developers who are interested in Wallaroo. That process has been critical to helping us understand what the community is asking for, and we've prioritized all the features discussed in this post due to that feedback. This community engagement is critical to us, so if you're interested in Wallaroo, please reach out to us so we can learn about your use case and get your input at [hello@wallaroolabs.com](mailto:hello@wallaroolabs.com).

I’m going to take a short detour to cover what Wallaroo is for those for whom this post is their first introduction to Wallaroo. Everyone else, feel free to skip the next section and jump directly to [“Dynamic Partitioning”](#dynamic-partitioning).

## What is Wallaroo

Wallaroo is a modern framework for streaming data applications that react to real-time events.
Writing stateful streaming applications in Wallaroo is as easy as writing a Python script. Wallaroo [manages state for the application programmer](/2017/10/how-wallaroo-scales-distributed-state/) allowing for Wallaroo applications to be run across any number of workers without having to make any code changes.

We currently support [Python](/2018/02/idiomatic-python-stream-processing-in-wallaroo/) and [Go](/2018/01/go-go-go-stream-processing-for-go/) as end-user languages. 

You can learn more about Wallaroo on [our website](http://www.wallaroolabs.com/).

## Dynamic Partitioning

One of the key features of Wallaroo is management of in-memory state. Our Wallaroo API allows programmers to delegate the management of their application state to Wallaroo. In return, they can scale their application horizontally without having to make any code changes.

To do this, the application programmer has to partition their state in a way that is meaningful to their application. For example, in an app that tracks the state of various stocks on the New York Stock Exchange, the application programmer would partition based on stock symbols such as `IBM` or `GM`. Wallaroo can then distribute these symbols across an arbitrary number of Wallaroo processes. You can learn more about this in [“How Wallaroo scales distributed state”](/2017/10/how-wallaroo-scales-distributed-state/). Wallaroo's current state scaling implementation works quite well, except for one current limitation: the application programmer has to set up all partitions ahead of time. In our previous case, this would mean that we need to know all the symbols on the New York Stock Exchange ahead of time. Given how rarely new stocks are listed on the NYSE, that isn’t an insurmountable problem. It becomes much more difficult if you are working with a more dynamic data set like you would find when implementing Word Count.

When counting words, we can’t reasonably know every single word that we might see, so defining them all ahead of time is very difficult. One way to address this is [what we do in our Wallaroo word count example](https://github.com/WallarooLabs/wallaroo/blob/0.4.1/examples/python/word_count/word_count.py#L25). Instead of 1 state object per word, we do 1 state object per letter of the alphabet and [each state object manages a dictionary](https://github.com/WallarooLabs/wallaroo/blob/0.4.1/examples/python/word_count/word_count.py#L59) that contains a mapping of words (all of which start with the same letter) to the number of times we’ve seen that word. It’s similar to Apache Storm’s [Fields grouping](http://nrecursions.blogspot.com/2016/09/understanding-fields-grouping-in-apache.html). There are differences, but you end up with about the same level of control.

There are some problems with this approach. 

- We can only scale up to the number of partitions established
- If we want to scale beyond the number of partitions, we will have to change our partitioning scheme and some logic
- Our state objects don’t accurately reflect how we think about our domain. 

In the end, what we want is to have Wallaroo manage state objects that match our domain. In the case of word count, that means our state objects should be words and their counts, not maps of words to counts.

Dynamic partitioning will allow Wallaroo applications to be written in such a fashion. Our state object to be:

```python
 class WordCount(object):
    def __init__(self, word, count):
        self.word = word
        self.count = count
```

and if we haven’t seen a word before, Wallaroo will create a new one, and we will route the incoming message to it.

Dynamic partitioning will be a massive boon to Wallaroo users. We’re excited to get it into folks' hands and see what awesome things they do with it.

## Resilience

We’ve designed Wallaroo to be resilient against failures. Resilient against failures means that if your application experiences a failure, such as a process crash, that you should be able to rectify the fault and then continue processing and end up with the same results you would have gotten had no failures occurred.

We take resilience seriously. We invest a lot of time testing Wallaroo resilience. If you are interested in learning more about our testing approach, you can learn more [here](/2017/10/measuring-correctness-of-state-in-a-distributed-system/), [here](/2018/03/how-we-test-the-stateful-autoscaling-of-our-stream-processing-system/), and [here](https://www.youtube.com/watch?v=6MsPDtpe2tg&index=3&list=PLWbHc_FXPo2hGJHXhpgqDU-P4BArpCdh6).

There are 2 limitations to our current resilience strategy that we will be addressing over the next few months. 

Our failure recovery protocols are only able to handle a single failure at a time. Being limited to handling single failure at a time means if your Wallaroo cluster has experienced a failure and is currently recovering and experiences another failure, it will not be able to recover. 

Additionally, Wallaroo currently makes application state resilient by using a write-ahead log that is written to a filesystem available on the same node where a Wallaroo worker is running. If the log is written to the local filesystem, Wallaroo won’t be able to survive the loss of the machine. To alleviate it this, we currently suggest that operators place the file on a persistent block storage device such as [Amazon Elastic Block Store](https://aws.amazon.com/ebs/). EBS is a workable solution, but not everyone is comfortable with it.

To address these concerns, we are adding the replication of state within a Wallaroo cluster. Each Wallaroo state object will be replicated within the cluster. So long as at least one replica exists within the cluster, Wallaroo will be able to continue processing. 

## Bring your own integrations

Data enters Wallaroo from external systems via an abstraction we call a “source.” Data exits Wallaroo and is sent to other systems via “sinks.” Currently, Wallaroo ships with sources and sinks for TCP and Kafka. You can add your own sources and sinks but, you have to code it in [Pony](https://www.ponylang.org/). 

Not being able to implement sources or sinks in Python or Go, the language you are implementing your Wallaroo application in, is a drawback.

Our “Bring your own integrations” project, when completed, will allow you to write Wallaroo integrations in any language and have your source/sink communicate with Wallaroo over an established protocol. 

The completion of BYOI means, for example, if you want to Wallaroo receive data from RabbitMQ, that you’ll be able to add a RabbitMQ source and write it in pure Python (or Go, if that’s your language of choice). You will not have to learn a new unfamiliar language to add your own sources and sinks.

## and more

In addition to our 3 big ticket items above, we have plenty more going on over here at Wallaroo Labs including:

- An improved installation and deployment process
- Vagrant support for getting a development environment set up quickly
- Windows via Vagrant and Docker as supported development environments

## Give Wallaroo a Try

We hope that this post has piqued your interest in Wallaroo! Stay tuned for additional posts. In future weeks, we’ll be digging into more technical details of how the various new Wallaroo features work. In the meantime, how about giving Wallaroo a try?

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
