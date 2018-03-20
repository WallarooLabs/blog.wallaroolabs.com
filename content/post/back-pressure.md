+++
title = "Overload, Back-Pressure, Pony, and Wallaroo: a savory stew"
date = 2018-03-20T06:30:12-06:00
draft = false
author = "slfritchie"
description = "TODO A savory stew of overload, backpressure, the Pony Runtime, and Wallaroo"
tags = [
    "back-pressure",
    "overload",
    "pony",
    "wallaroo"
]
categories = [
    "TODO"
]
+++

# Introduction: What is overload?

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
typically a fixed, static amount.)  However, 

3. "Steady state".  This might be called "flow balance assumption" or
"stability", depending on the book or paper that you're reading.  The
steady state assumption is that the arrival rate is less than or equal
to the departure rate.  If a system is not in steady state, then one
(or more!) queues in the model's network starts growing and are never
empty (after a sufficiently long period of time).

What do these three assumptions mean for your system?

1. Infinite queue length: Your computer does not have infinite memory.

2. & 3. Finite queue length & steady state: When/If the queue limit is
violated, the model cannot tell you much (or anything) about the
system's behavior.

# Overload

Let's use an informal definition for "overload".

> When a finite size service queue becomes full, or when any service
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
methods available depend on changing the arrival rate or changing the
queuing space.

## Solution 1: Add more queue space to a single machine

If an application's buffer gets full, just add more space.  Most
modern operating systems will do this for you, via the wonderful magic
of virtual memory.

We also know that computer systems do not have infinite storage
space.  If the `Arrival Rate > Departure Rate` equation is true for
long enough, any single machine will run out of space.

## Solution 2: Add more capacity to the system

What's the difference between this solution and solution #1?
Complexity.

a. Add more more queue space (RAM, NVRAM, disk, etc.)
   * Typically by adding more machines to a distributed system
   * In some cases, adding a new storage device is feasible, e.g.,
     adding a new Elastic Block Store (EBS) device to an Amazon cloud
     virtual machine.
b. Add more computing capacity (CPU, GPU, network I/O processors,
   etc.) to the system.
   * Increasing computing capacity will increase the Departure Rate of
     the system (we hope!).
   * If you add entire new machines (or virtual machines or
     containers), then you are probably also adding more queue space.

Quickly adding more computing resources to a single machine is not
common.  Most standalone computers cannot easily add a new CPU or a
new disk drive while it is running.

For cloud computing systems such as Amazon Web Services (AWS), Google
Compute Engine (GCE), Azure Compute, and many others, adding capacity
is indeed feasible.  They have APIs that include (some type of) "Add
More".  For a fewservices, it's that easy.  For many others, it is not
that easy.

Adding more capacity to the system can help in the future, but the
extra capacity cannot help your overloaded system *right now*.

* Adding extra capacity may be impossible or difficult
* Adding extra capacity may be expensive
* Time latency before extra capacity is available
* Overhead of adding extra capacity may *reduce* capacity of
  existing system before and/or during the transition time.

Even if your computing service provide can add services quickly, your
application may not be designed to use the new capacity immediately.
So you can still have an overloaded system.  Bummer.

## Solution 3: Load shedding

This is another method of changing the `Arrival Rate > Departure Rate`
equation: we "shed" load (or "drop" or "ignore" or "degrade service")
to increase the `Departure Rate` side of the equation.  These
strategies include:

* Drop the request/query/packet.  Literally, do nothing.
* Choose an alternatve computation that requires less time.
  * If the service is text search, then only search 10% of the text corpus
    instead of the full 100%.
  * If the service calculates square roots with 25 digits of
    precision, then reduce the precision to 5 digits instead.

## Solution 4: Back-Pressure

----
----

Scraps

The "queue" in this abstract model is some place, real or imaginary,
where things wait before getting actual service from the system.  In
computer systems, the model's queue usually has a linked list or array
or some other data structure to manage the items in the physical
queue in the computer's memory.  

