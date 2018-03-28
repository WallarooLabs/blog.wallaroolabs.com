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
    "back-pressure",
    "overload"
]
+++

## Series Introduction: Overload and how Wallaroo mitigates overload

This is the first of a pair of Wallaroo Labs blog articles.  Here's a
sketch of the series.

1. Give a brief overview of queueing networks and what "overload" means
   for a queueing network.
2. Outline some common techniques that computer systems use to
   mitigate the effects of overload.
3. Discuss in detail how Wallaroo uses one of those techniques to
   manage overload: back-pressure.

This article will cover points #1 and #2.  The next article, planned
for April 3rd, will tackle point #3 in more detail.

## Introduction: An overview to queueing networks

Queueing theory is about 100 years old.  It's a fascinating topic, one
that has been applied to computer systems since the 1960s.  The
Wikipedia article https://en.wikipedia.org/wiki/Queueing_theory is a
good place to start for diving into the mathematical models of
queueing networks.  A dive into math isn't needed for in this article
or for the follow-up article.  But a very small introduction to
queueing theory will help put us all on the same page.

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

Mathematicians have worked for roughly 100 years to define scenarios &
models for many
different kinds of arrival rate schemes, service time schemes, and queue
size limits, then applying those schemes to this very simple model.
It's surprising how powerful a tool this single queue+service model
is.  When the model's simplicity is no longer sufficient,
mathematicians and analysts started putting multiple service centers
into networks, like this one:

![A Network of Queues](/images/post/back-pressure/network-of-queues.png)

Here is a network model for the edit-compile-execute cycle of software
development:

![A Network Model for Software Development](/images/post/back-pressure/dev-cycle-network.png)

I'm intentionally not discussing any of the many methods that are used
to predict
answers to questions like, "How long will the queue be?" or "How long
will I wait?"  Instead, I wish to highlight one of the fundamental
assumptions that most of those methods require: steady state.

The assumption of "steady state" might instead be called "flow balance
assumption" or "stability", depending on the book or paper that you're
reading.  A network queue model in steady state  has an arrival rate less
than or equal to the departure rate.  If a system is not in steady
state, then one (or more!) queues in the model's network start growing
without limit.

What does a steady state assumption mean for your system?  From a
theoretical point of view, a violation of steady state means that the
model loses its predictive power: the model cannot tell you how the
system will behave.  From a practical point of view, an overloaded
system has queue sizes that grow without stopping.

We do not yet have computers with truly infinite memory. Until that
day, let's look at how to design systems that try to remain in steady
state.

## Overload: How to define it and how to mitigate its effects

Let's use an informal definition for "overload".

> When a finite size service queue becomes full, or when a service
> queue's size continues to grow without stopping, then the service is
> overloaded.

The cause of overload boils down to a simple equation.
Note that it is the opposite of the definition of steady state.

> Arrival Rate > Departure Rate

If this simple equation is true for "short periods of time", then a
system is not necessarily overloaded.  Is your local Post Office
overloaded if the arrival rate exceeds the departure rate for a 1
minute time period?  Usually, no.  However, what if 200 customers
arrived in that one minute?

My local Post Office is not big enough to "store" 200 customers in
its queue, regardless of how quickly those customers arrived.
If my Post Office's line fills the lobby and runs out of
the door, then I call that Post Office "overloaded".  (And I call
myself lucky not to be waiting in that line.)

Let's look at some methods for mitigating overload conditions.  We'll
see that the methods available depend on changing the conditions of
the steady state equation or increasing system's storage space.

### Solution 1: Add more queue space

If an service's buffer gets full, then we simply add more space.  Most
modern operating systems will do this for you, via the wonderful magic
of virtual memory.

We know that computer systems do not have infinite storage
space.  If the `Arrival Rate > Departure Rate` equation is true for
long enough, any single machine will run out of space.  The same
statement holds true for a multi-machine system.  
If we add more space without changing the balance of steady state
equation, then we are simply delaying when the consequences of full
queues will strike us.

### Solution 2: Increase the Departure Rate

Two common strategies to increase `Departure Rate` are
increasing service throughput or decreasing service latency.
Strategies are commonly used to implement them are "horizontal scaling"
and "load shedding", respectively.

#### Solution 2a: horizontal scaling (a.k.a. "make your cluster bigger")

Sometimes, it is possible to add more space (RAM, NVRAM, disk, etc.)
or CPU capacity to a single machine, but it isn't common.
It's usually far easier to add additional machines.  Or add virtual
machines (VMs).  Or add containers.  "Horizontal scaling" is the usual
name for this technique.

Service providers like Azure, Google, Amazon, and many others have
APIs that include "Add More, Just Click Here!".  (But perhaps not with
that exact name.)  
Adding
more capacity to the system is fantastic for the future, but the extra
capacity cannot help your overloaded system *right now*.

* Adding extra capacity may be impossible or difficult
* Adding extra capacity may be expensive
* You may wait a long time before extra capacity is available
* Overhead of adding extra capacity may *reduce* capacity of
  existing system during the transition time.

Aside: You're probably also adding storage space to the system by making
your cluster bigger.

#### Solution 2b: Load shedding

"Load shedding" is another way to increase the `Departure Rate` side of our
service equation.  Load shedding implementations can include:

* Do not compute the requested value, but instead send an immediate
  reply to the client ... usually a reply that also signals that the
  system is overloaded.  (Whether clients actually act upon the overload
  signal is a worthwhile question to ask.)
* Choose an alternative computation that requires less time.
  * If the service is text search, then only search 10% of the text corpus
    instead of the full 100%.
  * If the service calculates square roots with 25 digits of
    precision, then reduce the precision to 5 digits instead.
* Drop the request (or query or packet).  Do nothing more, literally, as
  quickly as possible.

### Solution 3: Decrease the Arrival Rate

It's unfortunate, but many computer systems have very little control
over a service's arrival rate.  You don't have full control over your
customers & their arrival rates.  Perhaps 1,000 customers really can
arrive in one second at your local Post Office?

#### Solution 3a: Do nothing? Ride out the storm?

If your buffer sizes are large enough, and if
`Arrival Rate > Departure Rate` is true only for a short amount of
time, then perhaps you can simply do nothing and wait for your arrival
rate to drop.  Perhaps your system is busiest after suppertime, and
arrival rates drop when customers start going to sleep in the
evening.  Simply waiting for the natural decline 

#### Solution 3b: Filter out some requests

Earlier this month, on
[March 1st, 2018, GitHub experienced a denial-of-service attack](https://githubengineering.com/ddos-incident-report/).
At its peak, the attack generated 1.35 terabits/second of network
traffic at 126.9 million packets/second.  The report from GitHub's
Engineering department explains how Akamai's services were used to
reduce the `Arrival Rate` by filtering out millions of packets per
second of junk.

From GitHub's point of view, the arrival rate was reduced by filtering
the workload.  From Akamai's point of view, Akamai acted as load
shedding system.  The denial-of-service traffic arrival rate didn't
fall until the attackers gave up and stopped their network traffic.

#### Solution 3c: 

Many decades of computer systems research has given us a lot of rate
limiting schemes.  Most are based on a notion of credit or money or
tokens or a ticket before a customer can be admitted to a queue.  If a
customer doesn't have the credit/money/token/ticket before arriving in
the queue, then the customer isn't admitted to the system (or perhaps
a particular queue in the system).  "Admission control" and "flow
control" are two common names for these schemes.  (It would be nice if
they were the only two!)

Admission/flow control systems are usually very effective at
reducing the `Arrival Rate`.  Perhaps your system can handle 900
operations/second, but you wish to force all users to a sum of only 7
operations/second.  Sure, admission/flow control can do that.

I'm guessing that most of my audience knows a little something about
the TCP protocol.
TCP includes two (at least) mechanisms for controlling `Arrival Rate`.
One is TCP's "sliding window", which permits a limited
number of network packets to be "in transit" in the network without
overloading the receiving system's capacity.
When the sliding window is large, the sender is permitted to send a
large number of packets to the receiver.  When the window is zero, the
sender must stop sending.

I'll have a much more detailed example of TCP's sliding window feature
in next week's follow-up article.  My apologies, please hold on for
part two!

## Back-Pressure force customers to reduce their Arrival Rate

TCP's sliding window is a example of a back-pressure mechanism.  When
the window is zero, the receiver is telling the sender, "I am
overloaded.  You must stop sending now.  I will tell you when you can
send more."

To be most effective, back-pressure must be built into a system, from
end to end.  Wallaroo's back-pressure mechanisms will propagate a
back-pressure signal that warns of a slow sink all the way back to
Wallaroo's data sources.  Next week's follow-up to this article will
detail how those back-pressure mechanisms work.  Thanks for reading!
I hope you'll read again next week.

## More material on how to deal with overload

Here are some articles & presentations that you might find useful
places to learn more.  If you were to read only two items to learn
more about handling overload, my recommendations are:

1. Fred Hebert's blog, especially Fred Hebert's "Queues Don't Fix
Overload" which is linked below.  I love his illustrations with
kitchen sinks filling & draining with water.

2. I call it the "SEDA paper", but its proper title is "Adaptive
Overload Control for Busy Internet Servers" by Welsh & Culler.  It is
also linked below.  This paper from 2003 is one that I believe
everyone ought to read; its ideas will color your thoughts on software
design for many years to come.

* Wikipedia: [Back-Pressure](https://en.wikipedia.org/wiki/Back_pressure)
* Wikipedia: [Queueing theory](https://en.wikipedia.org/wiki/Queueing_theory)
* Fred Hebert: [Queues Don't Fix Overload](https://ferd.ca/queues-don-t-fix-overload.html)
  * If you like this article, Fred's follow-up article is called is
    [Handling Overload](https://ferd.ca/handling-overload.html),
* Matt Welsh & David Culler. ["Adaptive Overload Control for Busy Internet Servers"](http://static.usenix.org/legacy/events/usits03/tech/welsh.html)
* dataArtisans: [How Apache Flink™ handles backpressure](https://data-artisans.com/blog/how-flink-handles-backpressure)
* Reactive Streams initiative: [Introduction to JDK9 java.util.concurrent.Flow](http://www.reactive-streams.org)
* Henn Idan: [Reactive Streams and the Weird Case of Back Pressure](https://blog.takipi.com/reactive-streams-and-the-weird-case-of-back-pressure/)
* Zach Tellman: [Everything Will Flow](https://www.youtube.com/watch?time_continue=1&v=1bNOO3xxMc0),
  an overview of Clojure's `core.async` library.

The queue network figures in this articles are excerpts from the book
"Quantitative System Performance" by Lazowska, Jahorjan, Graham, and
Sevcik.
[Full text of this book is available online.](https://homes.cs.washington.edu/~lazowska/qsp/)


## Give Wallaroo a Try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
