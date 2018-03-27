+++
title = "Some Common Mitigation Techniques for Overload in Queueing Networks"
date = 2018-03-26T06:30:12-06:00
draft = false
author = "slfritchie"
description = "A review of overload mitigation techniques for queuing networks and distributed systems.  Part one in a two-part series."
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

## Pre-Introduction: Overload and how Wallaroo mitigates overload

This is the first part of a two-part series of articles.  Here's a
sketch of the series.

1. Give a brief overview of queueing networks and what "overload" means
   for a queueing network.
2. Outline some common techniques that computer systems use to
   mitigate the effects of overload.
3. Discuss in detail how Wallaroo uses one of those techniques to
   manage overload: back-pressure.

This article will cover points #1 and #2.  The next article, planned
for April 3rd, will tackle point #3 in detail.

## Introduction: What is overload?

Queueing theory is about 100 years old.  It's a fascinating topic, one
that has been applied to computer systems since the 1960s.  The
Wikipedia article https://en.wikipedia.org/wiki/Queueing_theory is a
good place to start for diving into the mathematical models of
queueing networks.  A dive into math isn't needed for what I'll
discuss in this article, which is overload and back-pressure.  But a
very small introduction to queueing theory will help put us all on the
same page.

Here's a diagram of a very simple queueing system.

![A Single Service Center](/images/post/back-pressure/1-svc-center.png)

This basic model has been used for modeling lots of systems,
including:

* waiting at the deli counter or at the post office
* phone calls in telephone exchanges
* street & expressway traffic congestion
* computer systems, especially for capacity planning purposes

In the case of a deli counter or the post office, you might know (or
assume) that deli/postal service requires 60 seconds per customer, on
average.  If customers arrive at a rate of `X` people per minute, then
how long will the queue time typically be?  How many people will
usually waiting in the queue?

Mathematicians have spent decades defining scenarios & models for
different kinds of arrival rate schemes, service time schemes, and queue
size limits, then applying those schemes to this very simple model.
It's surprising how powerful a tool this single queue+service model
is.  When the model's simplicity is no longer sufficient,
mathematicians and analysts start putting multiple service centers
into networks, like this one:

![A Network of Queues](/images/post/back-pressure/network-of-queues.png)

Here is a software development network model for the
edit-compile-execute cycle.

![A Network Model for Software Development](/images/post/back-pressure/dev-cycle-network.png)

I'm skipping all of the nifty math techniques that are used to predict
answers to questions like, "How long will the queue be?" or "How long
will I wait?"  Instead, I wish to point some of the fundamental
assumptions that most of those techniques require:

1. "Infinite queue length".  This is pretty easy: the model assumes
that queues can be arbitrarily big.

2. "Finite queue length". This one is also pretty clear: the model
assumes that a queue size is limited in size.  (The queue size is also
typically a fixed, static amount.)

3. "Steady state".  This might be called "flow balance assumption" or
"stability", depending on the book or paper that you're reading.  The
steady state assumption is that the arrival rate is less than or equal
to the departure rate.  If a system is not in steady state, then one
(or more!) queues in the model's network start growing without limit.

What do these three assumptions mean for your system?

1. Infinite queue length: Sorry, your computer does not have infinite memory.

2. & 3. Finite queue length & steady state: When/If the queue limit is
violated, the model cannot tell you much (or anything) about the
system's behavior.

## Overload: Definition and Mitigation

Let's use an informal definition for "overload".

> When a finite size service queue becomes full, or when a service
> queue's size continues to grow without stopping, then the service is
> overloaded.

The cause of overload boils down to this simple equation:

> Arrival Rate > Departure Rate

If this simple equation is true for "short periods of time", then a
system is not necessarily overloaded.  Is your local Post Office
overloaded if the arrival rate exceeds the departure rate for a 1
second time period?  Usually, no ... unless 1,000 customers arrived in
that one second.  My local Post Office is not big enough to "store"
1,000 customers in its queue.

Let's look at some methods for handling overload.  We'll see that the
methods available depend on changing the queuing space, the
`Departure Rate`, and/or the `Arrival Rate`.

### Solution 1: Add more queue space

If an service's buffer gets full, just add more space.  Most
modern operating systems will do this for you, via the wonderful magic
of virtual memory.

We also know that computer systems do not have infinite storage
space.  If the `Arrival Rate > Departure Rate` equation is true for
long enough, any single machine will run out of space.  The same
statement holds true for a multi-machine system.

### Solution 2: Increase the Departure Rate

There are two significant techniques to increase the departure rate:
increase service throughput or decrease service latency.  Two
strategies are commonly used to implement them: "horizontal scaling"
and "load shedding", respectively.

#### Solution 2a: horizontal scaling (a.k.a. "make your cluster bigger")

Sometimes, it is possible to add more space (RAM, NVRAM, disk, etc.)
or CPU/GPU/network capacity to a single machine, but it isn't common.
It's usually far easier to add additional machines.  Or add virtual
machines (VMs).  Or add containers.  Or add new-technology-of-the-year.
"Horizontal scaling" is the usual name for this technique.

For cloud computing systems such as Amazon Web Services (AWS), Google
Compute Engine (GCE), Azure Compute, and many others, adding capacity
is indeed feasible.  They have APIs that include (some kind of) "Add
More, Just Click Here!".  Adding more capacity to the system is
fantastic the future, but the extra capacity cannot help your
overloaded system *right now*.

* Adding extra capacity may be impossible or difficult
* Adding extra capacity may be expensive
* Waiting a long time before extra capacity is available
* Overhead of adding extra capacity may *reduce* capacity of
  existing system during the transition time.
  (Frequently, this is your service & application's problem instead of
  your data center/hosting/compute platform's problem.)

#### Solution 2b: Load shedding

This is another way to increase the `Departure Rate` side of our
service equation.  These strategies include:

* Drop the request/query/packet.  Literally, do nothing.
* Choose an alternative computation that requires less time.
  * If the service is text search, then only search 10% of the text corpus
    instead of the full 100%.
  * If the service calculates square roots with 25 digits of
    precision, then reduce the precision to 5 digits instead.
* Do not compute the requested value, but instead send an immediate
  reply to the client that signals that the system is overloaded.


### Solution 3: Decrease the Arrival Rate

It's unfortunate, but many computer systems have very little control
over a service's arrival rate.  You don't have full control over your
customers & their arrival rates.  Perhaps 1,000 customers really can
arrive in one second at your local Post Office?

#### Solution 3a: Filter out some requests

Earlier this month, on
[March 1st, 2018, GitHub experienced a denial-of-service attack](https://githubengineering.com/ddos-incident-report/).
At its peak, the attack generated 1.35 terabits/second of network
traffic at 126.9 million packets/second.  The report from GitHub's
Engineering department explains how Akamai's services were used to
reduce the `Arrival Rate` by filtering out millions of packets per
second of junk.

Akamai's technique of filtering is not a generally useful technique
for all distributed systems.  For example:

1. It only works with limited network protocols (such as HTTP over
TCP),
2. Requires specific network hardware and network architecture, and 
3. Requires significant operations staff, training, and rehearsed
procedures to operate smoothly.

#### Solution 3b: Force customers to reduce their Arrival Rate

Many decades of computer systems research has given us a lot of rate
limiting systems.  Most are based on a notion of credit or money or
tokens or ticket before a customer can be admitted to a queue.  If you
don't have the credit/money/token/ticket before arriving in the queue,
then you aren't admitted.  These systems are very effective at
reducing the `Arrival Rate`.  Perhaps your system can handle 900
operations/second, but you wish to force all users to a sum of only 7
operations/second.  Sure, admission control can do that.

One of the better-known `Arrival Rate` control mechanisms by software
developer & IT systems people is built into the TCP protocol.  The
rate limiting part is TCP's "sliding window", which permits a limited
number of network packets to be "in transit" in the network without
permanently overloading the network's capacity or the receiving
system's capacity. When the sliding
window is large, the sender is permitted to send a large number of
packets to the receiver.  When the window is zero, the sender must stop
sending.

TODO: Rec by Sean: drop this pp:
However, the credit/token/ticket subsystem itself can be modelled as a
service queue network.  And that subsystem will have its own
`Arrival Rate > Departure Rate` equation.  But if the
credit/token/ticket subsystem becomes the overloaded bottleneck in
your system, then your problem remains: overload.

#### Solution 3b variation: Reduce Arrival Rate via back-pressure

It would be fantastic to be able to enforce a reduction in the
`Arrival Rate` side of our equation for all customers.  I have
already mentioned three of ways to do it.

1. The filtering approach, e.g. Akamai's denial-of-service filtering
   service.
2. A credit/token/admission system, which (ideally!) is much more
   difficult to overload than the system that it protects.
3. Load shedding plus some kind of "I am overloaded" response.

Unfortunately, the "I am overloaded" style of load shedding doesn't
guarantee a lower `Arrival Rate`.  The customer probably does not have
to wait before trying to re-enter the service queue.  Impolite
customers can still overload the system.

There is a technique that can force customer `Arrival Rate` to slow
down: "back-pressure".  It's a technique that must be comprehensively
designed into a system to be effective.  Back-pressure is the
technique that Wallaroo uses to avoid overload.  The next section
discusses how back-pressure was designed for & implemented by
Wallaroo.

## More material on how to deal with overload

If you were to read only two items to learn more about handling
overload, my recommendations are:

1. Fred Hebert's blog, especially Fred Hebert's "Queues Don't Fix
Overload" which is linked below.  I love his illustrations with
kitchen sinks filling & draining with water.

2. I call it the "SEDA paper", but its proper title is "Adaptive
Overload Control for Busy Internet Servers" by Welsh & Culler.  It is
also linked below.  This paper from 2003 is one that I believe
everyone ought to read; its ideas will color your thoughts on software
design for many years to come.

Articles & presentations that you might find useful places to learn more.

* Wikipedia: [Back-Pressure](https://en.wikipedia.org/wiki/Back_pressure)
* Wikipedia: [TCP Flow Control](https://en.wikipedia.org/wiki/Transmission_Control_Protocol#Flow_control)
* Fred Hebert: [Queues Don't Fix Overload](https://ferd.ca/queues-don-t-fix-overload.html)
* Fred Hebert: [Handling Overload](https://ferd.ca/handling-overload.html),
  a survey of overload mitigation techniques in general & code libraries
  available in Erlang.
* Matt Welsh & David Culler. ["Adaptive Overload Control for Busy Internet Servers"](http://static.usenix.org/legacy/events/usits03/tech/welsh.html)
* Douglas Comer & Pearson Education (image credit): [Figure 25.7 from "Fundamentals Of Computer Networking And Internetworking"](https://www.cs.csustan.edu/~john/classes/previous_semesters/CS3000_Communication_Networks/2015_02_Spring/Notes/CNAI_Figures/figure-25.7.jpeg)
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
