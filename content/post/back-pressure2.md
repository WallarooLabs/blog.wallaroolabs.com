+++
title = "TODO Part 2"
date = 2018-03-27T06:30:12-06:00
draft = false
author = "slfritchie"
description = "TODO"
tags = [
    "back-pressure",
    "overload",
    "workload management",
    "pony",
    "wallaroo"
]
categories = [
    "TODO"
]
+++

## TODO: Break here for end of first article / start of second article?

## Wallaroo's Back-Pressure Mechanisms

Wallaroo uses end-to-end back-pressure to limit queue sizes of all
actors within the system.  This section describes how it back-pressure
is implemented by Wallaroo today and how it will change in a
near-future release.

### Where Does the Term Back-Pressure Come From?

Originally, the term "back-pressure" refers to the resistance to
forward flow of gas or liquid in a confined space, e.g., air duct or
pipe.  The gas (or liquid) experiences friction along the sides of the
duct (or pipe).  It is easy to create an experiment to experience
different amounts of back-pressure in a gas.  Using your lungs and
mouth, try to blow as much air (as quickly as possible!) through the
following tubes:

* A small cocktail straw
* A regular drink straw, e.g., from the soda fountain at McDonalds
* The cardboard tube from a roll of paper towels or toilet paper
* A hallway in your favorite school, office building, or your
  house/apartment.
  * I.e., the hallway is a very large-sized tube for this experiment

### TCP's Back-Pressure Mechanism: Sliding Window Flow Control

This isn't the time & place to describe TCP's sliding window flow
control in detail.  However, a picture is worth at least a thousand
words in this case.  Let's take a look.

First, let's make some assumptions and statements about a hypothetical
TCP connection.  (This is a partial list, in order to simplify the
example.)

* The sender application is Wallaroo.
* Wallaroo is attempting to send 50,000 bytes of data to the receiver
  as quickly as possible.
* The sender can only send as many bytes as specified by the
  receiver's advertise window.
* The receiver app is some TCP data sink that stores Wallaroo's
  computation output in 1,000 byte chunks.
* The receiver's disk drive is very old and slow.  To write a single
  single 1,000 byte block can cause the writing application to pause
  for several seconds.

Shown below in Figure 25.7 by Prof. Douglas Comer of Purdue
University, we assume
that a TCP connection is already established between a sender and
receiver.  This diagram tracks one of the two "advertise windows" of
the sliding window protocol for the connection.  We look at one
direction only, but the a separate sliding window is used for data
sent in the other direction.

From the receiver's point of view:

* The advertise window starts at 2,500 bytes.
* Packets start arriving from the sender.  However, the receiver app
  has been put to sleep by the kernel and cannot read any data.
* The app wakes up, reads 2,000 bytes from the TCP connection, writes
  the data to disk, then goes to sleep while waiting for disk I/O to finish.
* The app wakes up, reads 1,000 bytes from the TCP connection, writes
  the data to disk, then goes to sleep while waiting for disk I/O to finish.

Dr. Comer's diagram of this sequence of network events looks like this:

![Figure 25.7 from "Fundamentals Of Computer Networking And Internetworking"](https://www.cs.csustan.edu/~john/classes/previous_semesters/CS3000_Communication_Networks/2015_02_Spring/Notes/CNAI_Figures/figure-25.7.jpeg)

The advertise window falls to zero twice in this example.  Wallaroo
has over 40,000 bytes of data waiting to be transmitted.  However,
when the advertise window is zero, the sender must stop transmitting
and wait for an 'ack' message with a non-zero advertise window.

How does Wallaroo know the receiver's advertise window size?  That
level of detail is not available through the POSIX network socket API!

In truth, a POSIX kernel can tell a user application when the
advertise window size (or a related value, the congestion window) is
zero.  If the socket has been configured in non-blocking I/O mode,
then a `write(2)` or `writev(2)` system call to the socket will fail
with the `errno` value of `EWOULDBLOCK`.  The `EWOULDBLOCK` condition
tells the application that the kernel was not able to send any data on
the socket immediately.

When Wallaroo's `writev(2)` call fails with `EWOULDBLOCK` status when
sending to a data sink, then we know that the sink is slow.  We don't
know why the receiving sink is slow, but we definitely know that
Wallaroo is sending data faster than the TCP sink can read it.
Wallaroo needs to spread this information to other parts of itself
... and that dissemination process is "back-pressure".

### Wallaroo is a distributed system of actors in a single OS process

Wallaroo is an application written in the Pony language.
(We have `TODO blog post XXX` that explains why we use Pony to write Wallaroo.)

Pony implements the "Actor Model" of concurrency, which means that a
Pony program is a collection of independent actor objects that perform
computations within their own private state.

TODO: Rec by Sean: this could use a diagram.
* Move up from next section?
* Steal a simpler diagram from another article?

In our example, there is an actor called a `TCPSink` that is
responsible for writing data to a TCP socket to send to one of
Wallaroo's data sinks.  When that actor experiences an `EWOULDBLOCK`
event when sending data, it is the only actor that is aware of the
sink's speed problem.  Pony does not allow global variables.  We
cannot simply use a global variable like we can do (naively!) in C,
e.g., `hey_everyone_slow_down = 1`, to cause the rest of Wallaroo to
slow down.

In an Actor Model system, actors communicate with each other by
sending messages.  Therefore, the `TCPSink` needs to send messages to
other Wallaroo actors to tell the other actors to stop work.  If all
actors in the system are told to stop, then Wallaroo as a whole can
act as if a big finger reached into the system and pressed the "PAUSE"
button.

When that metaphorical "PAUSE" button is pressed, the system no longer
creates data to send to the sink.  Wallaroo's internal queues become
frozen as producing actors stop sending messages.  When paused, the
message mailbox queues for each actor are effectively limited in
size.  Neither Wallaroo nor Pony provide strict limits on the mailbox
service queue length, but strict limits aren't necessary.  As long as
the pause happens quickly enough, we shouldn't have to worry about
uncontrollable memory use.

TODO ^^^ needs more work

### Wallaroo today: the "mute" protocol

Inside of Wallaroo today, a custom protocol is used to control the
back-pressure of stopping & starting computation in the data stream
pipeline.  We don't really want to broadcast to all
actors: many Wallaroo actors don't need to know about back-pressure or
flow control.  But we do need a scheme to help determine what
actors really do need to participate in the protocol.

The protocol is informally called the "mute protocol", based on the
name of one of the messages it uses, called `mute`.  The word "mute"
means to be silent or to cause a speaker to become silent.  That's
what we want for back-pressure: to cause sending actors "upstream" in
a Wallaroo pipeline to stop sending messages to the `TCPSink`.

As a data stream processor, the computation stages inside of Wallaroo
are arranged in a stream or pipeline.  The diagram below shows a
simplified view of a
["word count" application in Wallaroo](https://github.com/WallarooLabs/wallaroo/tree/master/examples/python/word_count)
which shows the actors directly involved with processing the input
data stream.

![Wallaroo word count example diagram](/images/post/back-pressure/wallaroo1.png)

When the `TCPSink` actor becomes aware of back-pressure on the TCP
socket (via the `EWOULDBLOCK` error status when trying to send data),
then `TCPSink` sends `mute` messages up the chain all the way back
to the `TCPSource` actor.

When the `mute` message reaches the `TCPSource` actor, then reading
from the source TCP socket will stop.  Now, the same TCP flow control
scenario that told us that the data sink is slow can be used by
Wallaroo to force the sender of the source TCP socket to stop sending.
If the sender sends enough data, then the TCP advertise window will
drop to zero, which will force the sender to stop sending.

Now we have all three pieces of back-pressure in place:

* From a slow sink TCP socket to Wallaroo's `TCPSink` actor, via TCP's
  advertise window reduced to zero.
* Backward along the stream processing chain from `TCPSink` to
  `TCPSource`, using the custom `mute` protocol within Wallaroo
* From Wallaroo's `TCPSource` actor to the source's TCP socket, also
  via TCP's advertise window reduced to zero.
  
![Wallaroo word count example diagram plus mute and unmute messages](/images/post/back-pressure/wallaroo2.png)

This mute/unmute messaging protocol between Wallaroo actors is
software much like any other.  Software tends to have bugs.  It would
be good to rip out the artisanal, hand-crafted mute/unmute protocol
and rely on a back-pressure system that applies to all Pony programs
at the runtime level.  That general back-pressure system is described
next.

### Wallaroo tomorrow: plans to use Pony's built-in back-pressure

A comprehensive back-pressure system was added to Pony in November
2017 by
[Sean T. Allen, VP of Engineering at Wallaroo Labs](https://www.wallaroolabs.com/about).
Look for a Wallaroo Labs blog post by Sean in the future that
describes this the back-pressure scheduler in more detail.

Pony's back-pressure system operates at the actor scheduling layer
within the Pony runtime.  Pony's actor scheduler maintains internal
status of actors that are paused due to back-pressure.  The scheduler
propagates pause & resume signals similar to the mute/unmute diagram
above.  However, in the Pony runtime's implementation, the Pony
developer usually does not write any code to get back-pressure
scheduling behavior.

In Wallaroo's case, some source code change is required to take full
advantage of the runtime's back-pressure scheduling.  The necessary
changes fall into two categories:

1. Removal of most of the existing back-pressure mechanism, with its
   `mute` and `unmute` message protocol.
2. Add small pieces of glue code to allow TCP sockets that experience
   `EWOULDBLOCK` errors when writing data to signal to the runtime
   that the socket's owner actor should initiate back-pressure
   propagation.

I have already made many of the above code changes, but I haven't
tested them yet.  If you are a frequent reader of the Wallaroo blog,
then you know that we devote a lot of time and effort to correctness
testing.

Testing-wise, I've first done a lot of preparation work to permit Wallaroo
to control the kernel's TCP buffer sizes.  If you don't know how
much data is required to sent to a TCP socket before back-pressure
signals start, then it's very difficult to create reliable, repeatable
tests to confirm that the back-pressure system works correctly.  This
argument goes for both the current back-pressure `mute` protocol and
the new Pony runtime's back-pressure scheduling features.

We at Wallaroo Labs aren't completely sure that the Pony runtime's
back-pressure scheduler will actually work as Wallaroo needs it.
Here's a partial list of open questions:

* We hope that the runtime's back-pressure scheduler will sharply
  limit the amount of memory used by Wallaroo when back-pressure is
  active.  But we haven't measured Wallaroo's actual memory behavior
  yet.
* We suspect that some additional tuning parameters will be
  necessary.  For example, how many messages must exist in an actor's
  mailbox before scheduler back-pressure is triggered?
* The back-pressure scheduler may yet be buggy.  Its code is not half
  a year old yet.  More bugfixes may be needed.

These open questions drive my investment in test infrastructure: I
want to find all the bugs in Wallaroo's workload/overload management
before our customers do.  It's a fun task.  And when we find
performance changes and/or interesting bugs in this work, we'll write
about it here.  Stay tuned.

### Pointers to other back-pressure systems

* dataArtisans: [How Apache Flink™ handles backpressure](https://data-artisans.com/blog/how-flink-handles-backpressure)
* Reactive Streams initiative: [Introduction to JDK9 java.util.concurrent.Flow](http://www.reactive-streams.org)
* Henn Idan: [Reactive Streams and the Weird Case of Back Pressure](https://blog.takipi.com/reactive-streams-and-the-weird-case-of-back-pressure/)
* Zach Tellman: [Everything Will Flow](https://www.youtube.com/watch?time_continue=1&v=1bNOO3xxMc0),
  an overview of Clojure's `core.async` library.

## Give Wallaroo a Try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
