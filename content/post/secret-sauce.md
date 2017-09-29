---
description: "A high-level look at how Wallaroo gets its excellent performance."
title: What's the "Secret Sauce"?
date: 2017-06-30T00:00:00Z
author: seantallen
slug: secret-sauce
draft: false
categories: 
  - Hello Wallaroo
tags:
  - coordination
  - performance
  - pony
  - wallaroo
---
Hi there! Welcome to the second blog post on our high-performance stream processor Wallaroo.
 
This post assumes that you are familiar with the basics of what Wallaroo is and the features that it provides. If you aren’t, you should read [“Hello Wallaroo!”](http://blog.wallaroolabs.com/2017/03/hello-wallaroo/) first.
 
People often ask us, “what’s the secret sauce?” What they mean is, “how does Wallaroo get those great performance numbers?” This post is an attempt to answer those questions. 
 
At a high level, Wallaroo’s performance comes from a combination of design choices and constant vigilance. Wallaroo uses an actor-model approach that encapsulates data, minimizes coordination, and brings state close to the computation. We test every feature for performance. We reimplement functionality when we find performance lacking.  During this post, we will touch on many of these topics and at the end, provide some additional reading you can do if you are interested in learning more.
 
## High-performance runtime
 
Let’s start with Wallaroo’s language of implementation. While it is possible to write programs that perform poorly in any programming language, some make it more difficult to write efficient programs. We wrote Wallaroo in a high-performance, actor-based language called [Pony](http://www.ponylang.org). Pony programs compile down to highly efficient native code via LLVM that can achieve performance equivalent to C. 
 
Pony comes with a runtime that provides many desirable features. It provides an actor-based programming model that makes it easy to write lockless, high-performance code. The runtime itself comes with an efficient work-stealing scheduler that is used to schedule actors in a CPU friendly fashion. By default, a program will start one scheduler thread per CPU. When combined with CPU pinning on operating systems such as Linux, this can allow for CPU cache friendly programs. Rather than a large number of threads stepping on one another to get access to a given CPU, each CPU is dedicated to a single thread. 
 
One of our goals with Wallaroo has been consistent, stable performance. Pony’s actor model implementation helps us achieve this by having no “stop-the-world” garbage collection phase, unlike the Java Virtual Machine. The JVM has a single large heap that requires all threads to be stopped to collect garbage. In the Pony runtime, each actor has its own heap that can be garbage collected by a single scheduler thread without impacting on the rest of the threads running in the process. There’s never a point in time when a Wallaroo application is doing nothing but collecting garbage. The result of this ongoing concurrent garbage collection is predictable performance. Many Wallaroo applications see a difference in latencies between the median and the 99.99% of less than 1 millisecond whereas JVM applications often measure that gap in terms of hundreds of milliseconds. 
 
In a clustered environment like Wallaroo, this consistency can become a huge source of performance gains. Imagine, if you will, two processes that feature stop-the-world garbage collection that are working together. Process A feeds data into Process B. Any time Process A experiences a garbage collection, no other processing will be done and Process B ends up starved for work. The stop-the-world pause on process A ends up acting as a stop-the-world for our cluster of machines. The same interaction can happen when process B experiences a stop-the-world event. When B is no longer able to process work, A will start to become backlogged and will either have to 1) exert backpressure to slow all producers down, or 2) queue large amounts of work that it needs to send to B thereby increasing the likelihood that it will soon experience a garbage collection event. Wallaroo never suffers from such cross worker pauses because there is never a stop-the-world garbage collection event to completely halt processing. 
 
The problems that stop-the-world garbage collection can cause in a clustered environment are covered in depth in [“Trash Day: Coordinating Garbage Collection in Distributed Systems”](https://www.usenix.org/system/files/conference/hotos15/hotos15-paper-maas.pdf).
 
Wallaroo builds on top of this efficient runtime with highly optimized code.
 
## Avoid coordination
 
Coordination is a performance killer. Any time we introduce coordination into our designs we introduce a potential bottleneck. Coordination is when two or more components need to agree on something before we can make further progress. Coordination can take many forms.  Locks are an example of coordination. Multiple threads need to update some shared data so that it remains consistent. To do this, they coordinate by introducing a lock. Consensus is another form of coordination. We see “consensus as coordination” in our daily office lives. We want to make a major decision. We need to get three people together to discuss a topic. To do this, we have to find a time everyone is available and then wait. 
 
We have designed Wallaroo to avoid coordination. We avoid locks. We design so that individual components can proceed using local knowledge. How large of an impact can coordination have on performance? Let's take a look at one of our early design mistakes. In an early version of Wallaroo, we had "global" routing actors. Every message processed had to pass through one of these routers. Changing message routing was very easy. High-performance was difficult. We have since removed the global router and replaced it with many local routers. This one change in design resulted in an order of magnitude improvement in performance.
 
The performance and scalability impact of coordination can be huge.  In ["Silence is Golden"](https://www.youtube.com/watch?v=EYJnWttrC9k), Peter Bailis discusses the topic at length. If you are interested in learning more about how your systems can benefit from a coordination-avoiding design, we suggest you check it out.
 
## In-process coordination-free state
 
Want to make a streaming data application go slow? Add a bunch of calls to a remote data store. Those calls are going to end up being a bottleneck. To maximize performance, you need to keep your data and computation close to each other.
 
Imagine an application that tracks the price activity of stocks. We want to be able to update the state of each stock as fast as possible. We have at our disposal three sixteen-core computers. We want to put all forty-eight cores to work updating price information. To achieve this, we need to be able to update each stock independently. 
 
Wallaroo's state object API provides independent, parallelizable individual state “entities.”  In our application, each state object would be the data for a given stock symbol. In ["Life Beyond Distributed Transactions"](https://blog.acolyer.org/2014/11/20/life-beyond-distributed-transactions/), Pat Helland presents a means of avoiding data coordination. Wallaroo's "state objects" closely resemble the independent "entities" that Pat discusses as being key to scaling distributed data systems. The state object API makes it easy to partition state to avoid coordination among partitions.
 
## Measure the “cost” of every feature
 
In the end, Wallaroo performance comes down to careful measurement. The performance of computer applications is often surprising. Who among us hasn't made an innocent looking change and suffered a massive performance degradation? Recognizing this reality, we've adopted a simple solution. As we add features or otherwise make changes to Wallaroo, we test the impact those features have on performance.
 
We seek to keep the latency overhead of any feature as small as possible. Why keep the latency as low as possible? Lowering per-feature latency is a key to increasing throughput. Increased throughput means we can do the same amount of work with fewer resources. Not clear? Don’t worry, let’s take a look.
 
Imagine for a moment a simple Wallaroo application. It takes some input, does a computation or two, and creates some output. We're going to measure performance in "units of work." Each unit of work takes the same amount of time. If two different computations take 1 unit of work each, they take the same amount of time. Our application has a total units of work it takes to turn an input into an output. Each input takes a total of 7 units of work to complete. Of those, 4 units of work are user computations and 3 for Wallaroo overhead. Let's further imagine that our computer can do 30 units of work at any one time. Given that processing 1 message requires 7 units of work, this means at most, we can process 4 messages at a time.
 
30 / 7 ≈ 4
 
Now, let's say that we can lower our Wallaroo overhead from 3 units to 1. If we do that, it will only take 5 units of work to process a message. And with that change, we can handle 6 messages at a time. That's a 50% improvement over what we were doing before!
 
30 / 5 = 6
 
That's a simple, contrived example but the basic logic holds in the real world. The less time it takes to complete a given task, the more times we can complete that task. We take this approach every day when building Wallaroo. Watch the overhead; take fewer resources to do the work; save money.
 
## Give Wallaroo a try
 
If you are interested in giving Wallaroo a try, email us at [hello@wallaroolabs.com](mailto:hello@wallaroolabs.com). If you are interested in learning more about Wallaroo, you can [join the Wallaroo mailing list](http://eepurl.com/cnE5Cv) or [follow us on Twitter](https://twitter.com/wallaroolabs) to stay up to date on the news about Wallaroo. We have some more technically in-depth blog posts planned including:
 
- A look inside the implementation of our Python API
- Wallaroo basics including what a Wallaroo application looks like
- A deeper dive into Wallaroo performance
- Exactly-once processing 
- How we use Lineage-driven Fault Injection to test Wallaroo
 
If you would like a demo or to talk about how Wallaroo can help your business today, please get in touch by emailing [hello@wallaroolabs.com](mailto:hello@wallaroolabs.com).
