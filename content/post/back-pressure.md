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

This is the first of a pair of Wallaroo Labs articles about
overload.  Here's a sketch of the series.

1. Part one presents a brief overview of queueing networks and what
   the term overload means for a queueing network, followed by
   an outline of some common techniques that computer systems use to
   mitigate the effects of overload.
2. Part two discusses the details of how Wallaroo uses one of those
   techniques, back-pressure, to manage overload conditions.

Part two planned for April 3rd, 2018. TODOTODOTODOTODOTODOTODO

## Introduction: An overview to queueing networks

Most of the details of the mathematics of queueing theory aren't needed
for in this article or for the follow-up article.
However, a very small introduction to
queueing theory will help put us all on the same page.

Here's a diagram of a very simple queueing system.

![A Single Service Center](/images/post/back-pressure/1-svc-center.png)

This basic model has been used for modeling lots of systems,
including:

* Waiting at the deli counter or at the post office
* Phone calls in telephone exchanges
* Street and expressway traffic congestion
* Computer systems, especially for capacity planning purposes

In the case of a deli counter or the post office, you might know (or
assume) that deli/postal service requires 60 seconds per customer, on
average.  If customers arrive at a rate of `X` people per minute, then
how long will the queue time typically be, you wonder?  Or, perhaps
you want to predict how many people will usually waiting in the queue.

Mathematicians have worked for roughly 100 years to define scenarios &
models for many
different kinds of arrival rate schemes, service time schemes, and queue
size limits.
It's surprising how powerful a tool this single queue+service model
is.  Furthermore, when the model's simplicity is found lacking,
mathematicians started putting multiple service centers
into networks to solve bigger problems.  Here's a multi-service center
network model:

![A Network of Queues](/images/post/back-pressure/network-of-queues.png)

Here is a network model for the edit-compile-execute cycle of software
development:

![A Network Model for Software Development](/images/post/back-pressure/dev-cycle-network.png)

I'm intentionally not discussing any of the many methods that are used
to predict
answers to questions like, "How long will the queue be?" or "How long
will I wait?"  Instead, I wish to highlight one of the fundamental
assumptions that most of those methods require: steady state.

The assumption of steady state might instead be called "flow balance
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

Let's use an informal definition for the word overload.

> When a finite size service queue becomes full, or when a service
> queue's size continues to grow without stopping, then the service is
> overloaded.

The cause of overload boils down to a simple equation.
Note that it is the opposite of the definition of steady state.

> Arrival Rate > Departure Rate

If this simple equation is true for short periods of time, then a
system is not necessarily overloaded.  Is your local post office
overloaded if the arrival rate exceeds the departure rate for a 1
minute time period?  Usually, no.  However, what if 200 customers
arrived in that one minute?

My local post office is not big enough to "store" 200 customers in
its queue, regardless of how quickly those customers arrived.
If my post office's line fills the lobby and runs out of
the door, then I call that post office overloaded.  (And I call
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
You will probably ought to consider an alternative solution.

### Solution 2: Increase the Departure Rate

Two common strategies to increase `Departure Rate` are
increasing service throughput or decreasing service latency.
Strategies are commonly used to implement them are horizontal scaling
and load shedding, respectively.

#### Increase the Departure Rate by horizontal scaling (a.k.a. make your cluster bigger!)

Sometimes, it is possible to add more space (RAM, NVRAM, disk, etc.)
or CPU capacity to a single machine, but it isn't common.
It's usually far easier to add additional machines.  Or add virtual
machines (VMs).  Or add containers.

Service providers like Azure, Google, Amazon, and many others have
APIs that include "Add More, Just Click Here!".  (But perhaps not with
that exact name.)  Adding
more capacity to the system is fantastic for the future, but
it cannot help now.  The extra
capacity cannot help your overloaded system *right now*, because:

* Adding extra capacity probably costs more money.
* Adding extra capacity may be impossible.  For example,
  the API is easy to use, but the data center is full, which causes the API
  requests fail.
* You may wait a long time before extra capacity is available.
* Overhead of adding extra capacity may *reduce* the capacity of
  the existing system during the transition time.

To be effective, you need to plan ahead.
You have to choose some earlier time to start the
process of adding capacity, before it's too late to be helpful.
And also, be careful not to act too hastily and/or to add too much
capacity.  It's not an easy balance to find and maintain.

#### Increase the Departure Rate by load shedding

Load shedding is another way to increase the `Departure Rate` side of our
service equation.  Load shedding implementations can include:

* Do not compute the requested value, but instead send an immediate
  reply to the client ... usually a reply that also signals that the
  system is overloaded.  (Will clients actually act upon the overload
  signal and actually change their behavior? Good question.)
* Choose an alternative computation that requires less time.
  * If the service is text search, then only search 10% of the text corpus
    instead of the full 100%.
  * If the service calculates square roots with 25 digits of
    precision, then reduce the precision to 5 digits instead.
* Drop the request (or query or packet).  Do nothing more, literally, as
  quickly as possible.

### Solution 3: Decrease the Arrival Rate

It's unfortunate, but many computer systems have very little control
over a service's arrival rate.  Perhaps a flash mob of 200 customers
arrives in one minute at your local post office?
You don't have full control over your
customers and their arrival rates, but you likely still have options.

#### Decrease the Arrival Rate by filtering out some requests

Earlier this month, on
[March 1st, 2018, GitHub experienced a denial-of-service attack](https://githubengineering.com/ddos-incident-report/).
At its peak, the attack generated 1.35 terabits/second of network
traffic at 126.9 million packets/second.  The report from GitHub's
Engineering department explains how Akamai's services were used to
reduce the `Arrival Rate` by filtering out millions of packets per
second of junk.

GitHub's systems and Akamai's systems cooperated to keep GitHub's data
services usable by GitHub customers.
From GitHub's point of view, the `Arrival Rate` was reduced by Akamai's
filtering of the workload before it arrived at GitHub's servers.
From Akamai's point of view, Akamai acted as load
shedding system; until the attackers relented and stopped their
attack, `Arrival Rate` remained record-breakingingly high.

#### Decrease the Arrival Rate by back-pressure ("Hey, customers, stop!")

Many decades of computer systems research have given us a lot of rate
limiting schemes.  Most are based on an idea of fake money or credit
or tokens or a ticket that a customer must have before the customer
can be admitted to a queue.  Without the credit/money/token/ticket,
then the customer isn't permitted into the system.  Admission
control and flow control are two common names for these schemes.

I'm guessing that most of my audience knows a little bit about
the TCP protocol.
TCP includes two mechanisms for controlling `Arrival Rate`.
One is TCP's sliding window protocol, which permits a limited
number of network packets to be in transit in the network without
overloading the receiving system's capacity.
When the sliding window is non-zero, the sender is permitted to send
some bytes to the receiver, up to the window's size (in bytes).
When the sliding window is zero, the sender must stop sending.

I'll have a much more detailed example of TCP's sliding window protocol
in next week's follow-up article.  My apologies, please hold on for
part two!

#### Decrease the Arrival Rate by ... doing nothing? (Ride out the storm)

If your queue sizes are large enough, and if
`Arrival Rate > Departure Rate` is true only for a short amount of
time, then perhaps you can simply do nothing.  Instead, simply wait
for your arrival rate to drop.
Perhaps your system is busiest after suppertime, and
`Arrival Rate` naturally drops when your customers start going to sleep in the
evening.  (If your customers tend to eat and sleep at similar times!)

If you can predict your customer's peak `Arrival Rate` with 100%
accuracy, congratulations, you live in a wonderful world.
Otherwise, you probably ought to consider an alternate solution.

## Conclusion: Back-pressure forces customers to reduce their Arrival Rate

TCP's sliding window protocol is an example of a back-pressure mechanism.  When
the window is zero, the receiver is telling the sender, "I am
overloaded.  You must stop sending now.  I will tell you when you can
send more."

Wallaroo Labs has chosen back-pressure as the primary overload
mitigation technique for Wallaroo applications.  Another technique,
load shedding, is a poor fit for Wallaroo's goal of accurately
processing all data flowing through it without data loss.

Next week's follow-up to this article will
detail how Wallaroo's back-pressure mechanisms work together toward a
larger overload mitigation goal.  Thanks for reading!
I hope you'll read Part Two next week.

---

## More material on how to deal with overload

Here are some articles and presentations that you might find useful
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

<a name="refs"></a>
Here's the full list. Please explore!

* dataArtisans: [How Apache Flink™ handles backpressure](https://data-artisans.com/blog/how-flink-handles-backpressure)
* Fred Hebert: [Queues Don't Fix Overload](https://ferd.ca/queues-don-t-fix-overload.html). If you like this article, Fred's follow-up article is called is
  [Handling Overload](https://ferd.ca/handling-overload.html),
* Henn Idan: [Reactive Streams and the Weird Case of Back Pressure](https://blog.takipi.com/reactive-streams-and-the-weird-case-of-back-pressure/)
* Reactive Streams initiative: [Introduction to JDK9 java.util.concurrent.Flow](http://www.reactive-streams.org)
* Zach Tellman: [Everything Will Flow](https://www.youtube.com/watch?time_continue=1&v=1bNOO3xxMc0),
  an overview of Clojure's `core.async` library.
* Matt Welsh and David Culler: ["Adaptive Overload Control for Busy Internet Servers"](http://static.usenix.org/legacy/events/usits03/tech/welsh.html)
* Wikipedia: [Admission Control](https://en.wikipedia.org/wiki/Admission_control),
[Back-Pressure](https://en.wikipedia.org/wiki/Back_pressure),
[Queueing theory](https://en.wikipedia.org/wiki/Queueing_theory),
and
[Sliding window protocol](https://en.wikipedia.org/wiki/Sliding_window_protocol)
topics

The queue network figures in this articles are excerpts from the book
"Quantitative System Performance" by Lazowska, Jahorjan, Graham, and
Sevcik, Prentice-Hall, Inc., 1984.
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
