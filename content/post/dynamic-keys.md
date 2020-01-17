+++
title = "Dynamic Keys"
date = 2018-08-02T7:00:00-04:00
draft = true
author = "aturley"
description = "A look at how Wallaroo applications can now support new keys"
tags = [
    "python",
    "golang",
    "announcement",
    "api"
]
categories = [
    "Exploring Wallaroo Internals"
]
+++

Wallaroo is designed to help you build stateful event processing services that scale easily and elastically. State is partitioned across workers in the system and migrates when workers join or leave the cluster. Wallaroo routes messages to the correct worker by extracting a key from the message's content. Our initial implementation of Wallaroo was designed so that all of the keys that would be used by the system were known when defining the application. There was no way to add new keys on the fly. This still enabled a large number of use cases but unfortunately it had limits.

Recently we added the ability for the system to add new keys as needed. We call this feature "dynamic keys" and it expands Wallaroo's applicability to a wider number of use cases, as well as enabling new application architectures that were not possible with the old system. In this blog post, I'll talk about some of the technical details around the implementation.

## Messages, Keys, and Wallaroo

Wallaroo is a framework for creating applications that process messages; Wallaroo takes care of state management and scaling so that the application programmer can focus on the business logic. The state of a Wallaroo application is stored in state objects that are associated with keys. When a message is being processed, Wallaroo applies a user-defined function to the message to extract a key, and that key is used to determine the state object where the message should be sent. The destination state object may be on the same worker, or it may be on a different worker. Wallaroo manages this so that the application programmer doesn’t have to worry about the details of message routing.

## The Basics of Dynamic Keys

Part of designing a Wallaroo application is determining how to partition your application state. For example, if you were counting how many times you saw a word in a document, you might want to design your application so that each word was represented by a separate partition. In our old system this wouldn't have worked very well because the partitions were fixed. As a workaround, our word counting application partitioned state by the first letter of the word so that the counts for "aardvark" and "apple" were stored together in the same state object. The keys were the letters "a" through "z", which were known ahead of time and included in the definition of the application.

With dynamic keys, Wallaroo can add a new state object to the system as soon as it receives a message with the corresponding key. So now the first time the word count application receives "apple" it will create a new state object to represent the number of times it has seen "apple", and all subsequent "apple" messages will be routed to that state state object to increase its count. New words can flow into the system at any time.

The only limit to the number of state objects is the amount of memory in your system. Fortunately, Wallaroo is designed to let you easily create scalable systems, so if you need more memory you can add more workers to your cluster.

## Applications

In some instances the application developer knows the set of keys that will be used by the application. For example, an application that monitors stock trades on the NYSE will only need to deal with about 3000 symbols, so if state is partitioned by symbol then it is fairly trivial to load all of these symbols from a file every morning.

On the other hand, other applications may want to partition state according to a group whose membership evolves over time. For example, a system that is responsible for sending transactional emails to members of an online clothing retailer will need to be able to handle messages about new users who did not exist when the system started running.

As a business evolves, the applications that underpin it must be able to grow as well. Dynamic keys make it easier to grow because they allow an application to use a potentially unlimited number of keys. And the larger the set of keys used by the application, the more workers the application will be able to take advantage of.

To see dynamic keys in action, take a look at the [word count with dynamic keys](https://github.com/WallarooLabs/wallaroo/tree/0.5.0/examples/python/word_count_with_dynamic_keys) example. You can compare it to the version of [word count that doesn’t use dynamic keys](https://github.com/WallarooLabs/wallaroo/tree/0.5.0/examples/python/word_count). The important things to notice are that the dynamic keys version doesn’t create a list of keys in the application setup, and the partition function returns the entire word as the key instead of just the first letter of the word. Every word is treated as a separate key, and a new state object is created each time a new word is encountered.

### What Is a Key?

Keys must be strings in the Python API or byte slices in the Go API. When a message needs to be routed, Wallaroo applies the partition function to the message. The partition function returns the key based on whatever criteria the application designer has chosen.

### How Are Keys Placed In The Cluster?

Each worker is assigned an equally sized subinterval of the hash interval. Any keys that hash to a value in a worker's subinterval are handled by that worker.

![A key is placed on the worker that claims the interval in which the hash of the key falls.](/images/post/dynamic-keys/dynamic-key-placement.png)

## We Want To Make You Awesome

We want Wallaroo to be a tool that makes your job easier, and we think that adding support for dynamic keys does that. If you have a use case and you’d like to see how it might work using dynamic keys, please feel free to reach out to us in our [IRC channel](https://webchat.freenode.net/?channels=#wallaroo) or our [mailing list](https://groups.io/g/wallaroo).

Wallaroo is open source and you can start using it right now by going to our [GitHub repository](https://github.com/WallarooLabs/wallaroo). You'll find information, example applications, and source code there.
