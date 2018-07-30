Wallaroo is designed to help you build stateful event processing services that scale easily and elastically. State is partitioned across workers in the system and migrates when workers join or leave the cluster; Wallaroo routes messages to the correct worker by extracting a key from the message's content. Our initial implementation of Wallaroo was designed so that all of the keys that would be used by the system were known when defining the application. There was no way to add new keys on the fly. This limitation still enabled a large number of use cases, but it had limits.

Recently we added the ability to add new keys to the system on the fly. We call this feature "dynamic keys" and it expands Wallaroo's applicability to a wider number of use cases, as well as enabling new application architectures that were not possible with the old system. In this blog post I'll describe what the change looks like from the user's perspective and talk about some of the technical details around the implementation.

## The Basics of Dynamic Keys

Wallaroo divides state into entities that are spread across workers. Part of designing a Wallaroo application is determining how to partition your application state. For example, if you were counting how many times you saw a word in a document, you might want to design your application so that each word was represented by a separate partition. In our old system this wouldn't have worked very well because the partitions were fixed; as a workaround, our word counting application partitioned state by the first letter of the word so that the counts for "aardvark" and "apple" were stored together in the same state entity. The keys were the letters "a" through "z", which were known ahead of time and included in the definition of the application.

With dynamic keys Wallaroo can add a new state entity to the system as soon as it receives a message with that key. So now the first time the word count application receives "apple" it will create a new entity to represent the number of times it has seen "apple", and all subsequent "apple" messages will be routed to that state entity to increase its count. New words can flow into the system at any time.

### What Is a Key?

Keys must be strings in the Python API or byte slices in the Go API. When a message needs to be routed, Wallaroo applies the partition function to the message. The partition function returns the key based on whatever criteria the application designer has chosen.

### How Are Keys Placed In The Cluster?

Keys are placed on a worker using a technique called "consistent hashing". Imagine the numbers 0 through 2^128-1 being placed in a line. Then, a hash function is applied to the names of all the workers in the cluster. The worker with the lowest hashed name value "claims" all of the values in the from its hashed name value up to one less than the number of the next lowest worker. This continues on. Finally, the worker with the highest hashed name value claims all of the highest remaining values, as well as the value from 0 to one less than the value of the lowest worker's hashed name value. When a key needs to be assigned to a worker, the same hash function is applied to the key and the key is assigned to the worker that "claims" that value.

When a new worker is added to the cluster its name is hashed and it claims the numbers from that number through to the next highest hashed worker name. This region had previously belonged to the worker whose hashed name was smaller, so all of the keys associated with that worker are moved over to the new worker. When a worker leaves the cluster, the claims are recalculated and keys are again moved around.

This system has several useful properties. First of all, when a new worker is added the keys only need to be moved from one existing worker to the new worker, so this reduces the amount of overall movement. Second, as long as a worker knows the names of the workers in the cluster it will be able to figure out which worker it should send a message to; there is no need to coordinate a global routing table.

## Applications

In some instances the application developer knows the set of keys that will be used by the application. For example, an application that monitors stock trades on the NYSE will only need to deal with about 3000 symbols, so if state is partitioned by symbol then it is fairly trivial to load all of these symbols from a file every morning.

On the other hand, other applications may want to partition state according to a group whose membership evolves over time. For example, a system that is responsible for sending transactional emails to members of an online clothing retailer will need to be able to handle messages about new users who did not exist when the system started running.

As a business evolves the applications that underpin it must be able to grow as well. Dynamic keys make it easier to grow because they allow an application to use a potentially unlimited number of keys. And the larger the set of keys used by the application, the more workers the application will be able to take advantage of.

## What's Changed in the APIs

The changes to the API are:

1. All keys must be strings. Prior to this the Python API allowed any object that supported an equality check to be a key, and the Go API required that all keys be `uint64`s.
2. It is no longer necessary to pass a list of keys when setting up a stateful computation.
  * In the Python API the list of keys is now an optional argument to `to_state_partition`
  * In the Go API `ToStatePartition` and `ToStatePartitionMulti` no longer take a key slice argument, and `ToStatePartitionWithKeys` and `ToStatePartitionMultiWithKeys` have been added if you still want to provide a key slice.

We still give you a way of providing a list of keys because there is a small performance penalty for adding keys dynamically. If you know all the keys ahead of time then you can avoid this penalty by providing the list. Even if you provide a list of keys your application can still dynamically handle new keys, the list is only there to tell it which keys to set up ahead of time.

To see the API in action, take a look at the [Word Count With Dynamic Keys](https://github.com/WallarooLabs/wallaroo/tree/0.5.0/examples/python/word_count_with_dynamic_keys) example. If you compare it to the original [Word Count](https://github.com/WallarooLabs/wallaroo/tree/0.5.0/examples/python/word_count) example you'll notice that we no longer pass a list of keys to `to_state_partition`. The state objects that keep track of word counts are now objects that store a single word and its count, rather than a dictionary that stores all of the words that start with a particular letter. This architecture is easier to understand because words are a natural key for this application.

## We Want To Make You Awesome

We want Wallaroo to be a tool that makes your job easier, and we think that adding support for dynamic keys does that. We'd love to hear your feedback on this or any other feature of our system. Please feel free to reach out to us in our IRC channel or our mailing list.

Wallaroo is open source and you can start using it right now by going to our GitHub repository. You'll find information, example application, and source code there.
