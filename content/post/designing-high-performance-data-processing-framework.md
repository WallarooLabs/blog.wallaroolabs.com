+++
title = "How We Built Wallaroo to Process Millions of Messages/Sec with Microsecond Latencies"
draft = false
date = 2018-02-27T00:00:00Z
tags = [
    "performance"
]
categories = [
    "Exploring Wallaroo Interals"
]
description = "How we approached designing Wallaroo with performance in mind and some principles that could be useful when building your own performance-sensitive software systems."
author = "jmumm"
+++

When designing [Wallaroo](https://github.com/WallarooLabs/wallaroo)&mdash;a high-throughput, low-latency data processing framework written in the [Pony](https://github.com/ponylang/ponyc) programming language&mdash;we were concerned with designing for performance from the very beginning, with our initial goal being to achieve sub-millisecond latency tails with high throughputs. One of our guiding principles was that the Wallaroo framework should add as little overhead as possible. This would mean lower latencies, and lower latencies would allow for higher throughputs with the same set of resources (see Peter Lawry’s [blog post](https://vanilla-java.github.io/2016/07/23/Why-dont-I-get-the-throughput-I-benchmarked.html) for more on this idea). 

In this post, I’m going to talk about how we approached designing Wallaroo with performance in mind, and introduce some principles that could be useful when building your own software systems. I’ll also discuss how we we went about isolating different variables by building a very simple version of Wallaroo that we could performance test one small change at a time.

Our initial development of Wallaroo took place in four stages. First, we created a Python prototype along with a set of auxiliary tools that we planned to use throughout Wallaroo development. 

Second, we built a simple Pony prototype to get fast feedback on the performance characteristics of our initial architectural ideas. We used this prototype to quickly identify performance bottlenecks and develop a more informed strategy for designing a Pony system with performance in mind. 

Third, we built a simple version of our system we called "Wallaroo Jr." in order to isolate the performance impact of a series of very small changes. 

Finally, we rebuilt Wallaroo from scratch using the knowledge we had gained from the second and third stages. In what follows, I’m going to focus mostly on those second and third stages, discussing our guiding principles and the lessons we learned along the way.

## Python Prototype and Auxiliary Tools

In the first stage of initial development, we created a small Python prototype that allowed us to receive incoming messages over TCP, perform some computations on that data, and emit outputs and basic metrics over TCP to external systems. We chose Python so we could quickly get something working end to end. This allowed us to build a number of auxiliary tools for sending and receiving data, processing and displaying metrics, and running black box tests. 

We focused on getting the auxiliary tools in place first for a number of reasons. First, once we actually got to work on our Pony prototype, we wanted to be able to test that it was working correctly with a test harness we had already validated. We also wanted insight into the prototype’s performance characteristics from as early as possible in the development process. And we knew that these tools would develop in concert with Wallaroo itself, which was important because providing a user metrics monitoring system and an effective test harness were among our core goals for the Wallaroo ecosystem.

## Initial Pony Prototype 

Once we had our auxiliary tools in place, we moved to stage two: building our initial Pony prototype. As this was our first major Pony project, we still had a lot to learn. Our goal at that point was to build something we could plug into our auxiliary tools that would pass our suite of black box tests and emit simple metrics. By the time our Pony prototype was passing black box tests, our performance wasn’t much better than we’d seen with the Python prototype, despite the fact that Pony compiles to native code and Python is interpreted. We still had a lot of work to do, but at least we had a functioning prototype in place.

We had theories about how to speed things up, but our plan was to approach performance improvements systematically. We didn’t want to spend time optimizing code with minimal impact on performance. For example, code in the hot path should take priority since that’s what’s being exercised most frequently. We also didn’t want to take for granted that our assumptions about which factors had the most impact were correct. We needed a way to validate these assumptions before we actually got to work updating code. 

Our primary performance goal was to reduce Wallaroo overhead in the hot path. This would allow us to reduce latency and, as a result, increase throughput (see Peter Lawry’s [blog post](https://vanilla-java.github.io/2016/07/23/Why-dont-I-get-the-throughput-I-benchmarked.html) for a discussion of some of the ways reducing latency can lead to higher throughput). But in order to reduce overhead, we needed to know where that overhead was coming from. The first thing we did was to use [Instruments](https://developer.apple.com/library/content/documentation/DeveloperTools/Conceptual/InstrumentsUserGuide/index.html) on OSX to determine where the application was spending most of its time. At that point, most of the time was spent running some inefficient code in the Pony standard library. And we were exercising this code for every message processed in our test scenarios. 

So we dug in and improved the standard library. After these fixes, Instruments indicated that most of our time was spent in Pony GC. We hypothesized that this had to do with sending more cross actor messages than were necessary and our naive approach to sharing immutable data across actors. But whatever the explanation, Instruments was no longer providing good returns since it was no longer revealing particular features of our code that were dominating the runtime. For example, if you are allocating too much in general, a profiler like Instruments is not going to help you easily pinpoint where it's happening. We needed to broaden our approach.

## Wallaroo Jr.

At this point, we had to decide how to best continue our investigation. Since our hypothesized performance slowdowns were based on properties of the code that were spread evenly across the hot path, Instruments was no longer particularly helpful in drilling down further. We decided that the shortest path to answering our questions was to build an app we called “Wallaroo Jr.” in very small steps, performance testing each addition. Our guiding idea was that when it comes to performance, assumptions about what is “obviously” benign are not always correct. We wanted to put these assumptions to the test.

What exactly was Wallaroo Jr.? At first it was the simplest thing we could plug into our data sender and receiver tools. Our data sender allowed us to send data read from a text file to Wallaroo over TCP, and our data receiver allowed us to receive outputs from Wallaroo over TCP. We sent in a sequence of increasing integers via the sender, which the first iteration of Wallaroo Jr. immediately forwarded to the receiver. We recorded a timestamp for each integer at both the sender and receiver, and used a simple script to calculate latency and throughput based on these values. 

With this first step, we discovered our first performance issue: the Pony actor responsible for managing TCP connections wasn’t playing nice with the scheduler in our most common scenario. In particular, we weren’t regulating how much data we were processing at the TCP actor before yielding to other actors. Once we updated that strategy, we were seeing performance well above our initial goals. This was good, since if we were going to reach our initial goals with a fully featured Wallaroo, then we’d better have been able to exceed it with such a simple passthrough app.

### A Note About Wallaroo Internals

In order to understand some of our other performance improvements, you’ll need to know a bit more about Wallaroo internals. A Wallaroo application consists of one or more data processing “pipelines”, where a pipeline begins from a data ingesting “source”, runs through some number of “steps” encapsulating user-defined computations, and optionally terminates in a “sink” that is responsible for sending outputs to an external system. 

These concepts map to actor types in internal Wallaroo code (though Wallaroo users don’t need to concern themselves with these actors directly). Wallaroo uses what we call `Step` actors to serve as both atomic transaction boundaries and units of parallelism to encapsulate data processing code supplied by the user. When data first reaches Wallaroo, it is handled by a `Source` actor. When it’s ready to be sent to an external system, it’s handled by a `Sink` actor. Wallaroo Jr. now had a very simple version of a `Source` and a `Sink` (the minimum necessary for our simple metrics calculations). The next thing to do was to add in an analogue of the `Step`. 

### Reducing Allocations

When we had built the Pony prototype, we used a `Message` class to encapsulate message data and metadata that was processed by a series of `Steps`. This makes conceptual sense when you think about passing messages down a chain of processing steps. But Wallaroo Jr. revealed a number of serious performance problems with this approach. 

We knew there would be a performance impact from allocating a new `Message` at every `Step`, but we hadn’t yet tested how significant that impact would be. We tried breaking the `Message` fields out into parameters passed into Wallaroo Jr.’s `Step`’s `process` [behavior](https://tutorial.ponylang.org/types/actors.html). Our tests revealed that this simple change created a surprisingly large performance speedup. We discovered something similar with primitive boxing when passing messages between actors (you can read the [Pony Performance Cheatsheet](https://www.ponylang.org/reference/pony-performance-cheatsheet) for more information on [allocations](https://www.ponylang.org/reference/pony-performance-cheatsheet/#avoid-allocations) and [primitive boxing](https://www.ponylang.org/reference/pony-performance-cheatsheet/#boxing-machine-words) in Pony).

### Further Improvements

Although we knew that allocations and primitive boxing would have associated performance costs, we underestimated how significant they were in the context of sending messages across actors in the hot path. Now that we’d found these examples via our step-by-step development of Wallaroo Jr., we started to think about other aspects of our hot path code that could lead to unnecessary allocations or boxing. This quickly led us to even more performance improvements. 

Now that we had a better idea of the costs involved with unnecessary cross actor messages, we started digging into other strategies for reducing them.  For example, we compared the difference between sending a message across 3 `Step` actors encapsulating 3 distinct computations, and sending it through one `Step` actor that ran all 3 computations in sequence. The results showed that we could further lower overhead by coalescing sequences of computations into single actors whenever function composition allowed, and that it was worth trying to do this whenever we could.

With every small change to Wallaroo Jr., we measured the performance impact, even when it didn’t seem like there would be one worth mentioning. We knew that various decisions would have some performance impact, but this approach showed that we didn’t always know how significant the impact of any given decision would be. 

## After Wallaroo Jr.

We took the lessons we’d learned from Wallaroo Jr. as well as from the initial Pony prototype, and entered our fourth phase of initial development: building Wallaroo again from scratch, this time with a much greater understanding of how to achieve our goals. We were seeing performance numbers well above our initial targets. 

Of course, there was plenty more to do. We needed to add support for scaling out, and we needed to think about OS tuning tailor-made for the client demos that we were working on. When all of these changes were taken into account, we were seeing throughputs in the millions per second with sub-millisecond latency tails. 

These benchmarks were for an application we called “Market Spread”, which ingested two streams of external data. One stream consisted of recent stock price information that was used to update in-memory state. The other consisted of orders that needed to be checked against the most recent stock price information. When certain conditions were met, we sent outputs to an external system informing it that an order should be rejected. We were seeing throughputs of 1.5 million/sec for each pipeline (3 million/sec in total) with 50th percentile latencies of 66 microseconds, 99th percentile latencies of 260 microseconds, and 99.99th percentile latencies of 1 millisecond.

It’s important to note that these numbers refer to the Wallaroo Pony system.  Applications built using the Python or Go APIs have their own distinct performance characteristics (which are beyond the scope of this post), but they are both bounded by the characteristics of the underlying Pony system.

## Conclusion

Wallaroo has moved beyond the simple prototype phase. But it became one of our guiding principles that we performance test any change to the hot path, no matter how “obvious” it might be that it would have minimal impact. And we’ve still been known to build a Jr.-style app from time to time when testing performance assumptions that would be much more difficult to evaluate in the context of a complex codebase. 

You might find it helpful in some scenarios to do something similar: build a simple system that looks like the software you are trying to design in order to help isolate the performance impact of different changes. If you plan to do this, make sure to test the smallest changes possible. The real causes of performance hits are not always what you’d expect.

Let’s recap some of the principles that allowed us to develop Wallaroo with performance in mind. The first principle was not to take anything for granted. You’re going to get hit by unexpected problems. Furthermore, you might know something’s an issue but not know how significant it really is. This is where validation is crucial. You don’t want to spend a lot of time on a performance optimization with little actual impact (possibly creating a more complex codebase in the process). On the other hand, you shouldn’t rule out the possibility that performance hits might be coming from unexpected places. 

One strategy you can follow is to create small examples to isolate variables. Small Jr-style test apps also cut down on noise, making it easier to use tools like Instruments and [Flame Graphs](http://www.brendangregg.com/flamegraphs.html) to discover bottlenecks and sites of potential improvement.  Of course, if you discover performance improvements in a Jr-style app, you need to retest performance once you integrate them into your “real app” since they aren’t always guaranteed to carry over.

Even if you’re making your test changes directly to the codebase itself, it’s often a good idea to make small changes and performance test each one if you’re changing code in the hot path. That’s where otherwise small performance hits can add up quickly.

If you're interested in learning more about performance strategies for building software written in Pony, check out the [Pony Performance Cheatsheet](https://www.ponylang.org/reference/pony-performance-cheatsheet). And if you’re interested in learning more about Wallaroo, contributing to our open source codebase, or just providing feedback, check out the following links:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)
 
