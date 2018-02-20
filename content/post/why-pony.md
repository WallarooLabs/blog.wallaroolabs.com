+++
title = "Why we used Pony to write Wallaroo"
date = 2017-10-26T07:30:00-04:00
draft = false
author = "seantallen"
description = "A technical dive into why we used Pony to write Wallaroo."
tags = [
    "wallaroo",
    "pony",
    "performance",
    "python",
    "coordination",
    "actor-model",
    "garbage collection"
]
categories = [
    "Hello Wallaroo"
]
+++
Hi there! Today, I want to talk to you about why we chose to write [Wallaroo](https://github.com/WallarooLabs/wallaroo), our distributed data processing framework for building high-performance streaming data applications, in [Pony](https://www.ponylang.org/discover/). It's a question that has come up with some regular frequency from our more technically minded audiences. 

I've previously touched this topic in my Wallaroo performance post [What's the secret sauce?](https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/). In this post, I'm going to dive into the topic in more detail. I promised some folks on HackerNews that I would write this post and I want to keep my promise.

In this post, I'm going to give quick overviews of both Wallaroo and Pony. While our recent [open sourcing](https://blog.wallaroolabs.com/2017/09/open-sourcing-wallaroo/) and [intro to our Python API](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) posts got good amount of traffic, I expect a large number of you aren't familiar with Wallaroo or Pony. If you are, feel free to skip the next two sections.

## What is Wallaroo?

Wallaroo is a distributed data processing framework for building high-performance streaming data applications. It's designed to handle high-throughput, low-latency workloads that can be challenging with existing tools.

Some things that we set out to achieve when building Wallaroo:

- "Effortless" scaling to handling millions of messages a second
- Low Wallaroo overhead 
- Consistent performance
- Resource efficiency

Why these? In part, it was a reaction to the types of applications we were building. We were working with one of the major US banks on improving their ability to handle data in real-time. Their existing systems had problems with all of our checklist. We aimed to solve their problems and the problems of those like them.

Wallaroo has evolved a good deal from the early vision, and we are no longer focused purely on the financial application space. Those core ideas are still us and are all still goals. I'll touch on where Wallaroo is now at the end of this post.

## What is Pony?

[Pony](https://www.ponylang.org/discover/) is an open source, object-oriented, actor-model, capabilities-secure, high-performance programming language. Pony’s defining characteristics are a runtime designed for high-performance actor-model programs and a novel type-system designed to support the same use-case. Pony’s two primary areas of emphasis are performance and correctness. 

Pony is open-source and features a small but vibrant community of developers. Several members of our team are active contributors to Pony. The Wallaroo Labs team has made a number of improvements to the Pony runtime and standard library. We consider the runtime to be part of Wallaroo and actively contribute back improvements that benefit both Wallaroo and the open-source Pony community at large.

If you are interested in learning more about Pony’s history, I’d suggest checking out [“An Early History of Pony”](https://www.ponylang.org/blog/2017/05/an-early-history-of-pony/) by its designer Sylvan Clebsch.

## The right tool for the job

As engineers, we bandy the phrase "the right tool for the job" around quite a lot. The rest of this post is why we found Pony to be the right tool for our job. During one of his QCon talks on Pony, Sylvan introduced Pony with what has become one of my favorite quotes:

> A programming language is just another tool. It’s not about syntax. It’s not about expressiveness. It’s not about paradigms or models. It’s about managing hard problems.

We couldn't agree more. We settled on Pony as our tool our choice because, more than any other, it helped us solve our hard problems.

## Why Pony?

When started looking at tools, we had a checklist of problems we were looking to solve and things we didn't consider issues for us. I want to highlight each and then discuss each in more detail.

- Wallaroo needed to be highly concurrent.
- We needed predictable, smooth latencies
- We were concerned about data safety, in particular, data races and data corruption
- "Batteries" were not required
- We needed an easy way to interact with other languages

### Highly concurrent

Pony represents concurrency using the [actor-model](https://en.wikipedia.org/wiki/Actor_model) of computation. If you aren't familiar with the actor-mode, you can consider it a bit like "managed threads." The actor-model was developed to make it easier to write concurrent and parallel applications.

Actors communicate via asynchronous message passing. If you are trying to build a high-performance, coordination-free system like [we were](https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/), asynchronous message passing makes modeling much more manageable.

When looking at Pony's implementation of the actor-model, we were impressed with its runtime. Knowing that it was being used for several applications inside a major bank helped with our confidence as did a tour through the code.

The Pony scheduler is quite simple with very little overhead. The scheduler features work stealing and attempts to work with modern CPU architectures to process work as efficiently as possible.

You might have heard the term "mechanical sympathy." [Mechanical sympathy](https://www.youtube.com/watch?v=MC1EKLQ2Wmg) is a term used by [Martin Thompson](https://twitter.com/mjpt777) to describe "hardware and software working together in harmony." We appreciate that Pony's runtime is written with mechanical sympathy in mind. 

### Predictable latencies

If you've written or worked with an application that runs on the JVM, you probably know that long tail latencies can be a problem. I have spent enough time looking at the latency graphs JVM based application that I can usually identify them as JVM based on the graph alone.

The standard JVM garbage collection strategy is "stop the world." That is, when the JVM needs to reclaim unused memory, it needs to pause all other processing so it can safely garbage collect. These pauses are sometimes measured in seconds. That is going to destroy your tail latencies.

We wanted consistent, flat tail latencies. We wanted Wallaroo to be a framework where you could write applications that measured their tail latencies in single digit milliseconds or even better, microseconds. To do that, we were going to need a memory management strategy that didn't feature a stop the world garbage collection phase.

Pony, while garbage collected, features per-actor heaps. That is, each actor within a Pony application has its own heap. What this means is that rather than pausing to garbage collect one large heap, Pony programs are constantly garbage collecting but, they do it in a concurrent, per-actor basis. Garbage collection gets mixed into normal processing. This might not seem like a big deal, but it is. Concurrent garbage collection leads to lower tail latencies which in turn lead to better performance for clustered applications like Wallaroo. 

One of my favorite papers is ["Trash Day: Coordinating Garbage Collection in Distributed Systems"](https://www.usenix.org/node/189882). The abstract for Trash Day has an excellent summary:

> Cloud systems such as Hadoop, Spark and Zookeeper are frequently written in Java or other garbage-collected languages. However, GC-induced pauses can have a significant impact on these workloads. Specifically, GC pauses can reduce throughput for batch workloads, and cause high tail-latencies for interactive applications.

> In this paper, we show that distributed applications suffer from each node’s language runtime system making GC-related decisions independently. We first demonstrate this problem on two widely-used systems (Apache Spark and Apache Cassandra). 

What the authors of Trash Day showed was that by having all nodes in a clustered JVM application coordinate their garbage collection pauses, they ended up with better overall performance? Why? Well, there's a bit of queueing theory in that.

Imagine a two node application. `Node 1` does work and sends it on to `Node 2`. When `Node 1` experiences a garbage collection pause, it stops producing work for `Node 2`. This often results in `Node 2` having no work to do. And the reverse is true as well when `Node 2` pauses to collect garbage, `Node 1` will experience backpressure and need to pause work. This is problematic with a small two node cluster. It gets worse and worse as we add more members to a cluster.

Pony, and by extension, Wallaroo avoids this problem by collecting garbage concurrently with normal processing. There are no garbage collection pauses. Each member of the cluster can keep its compatriots supplied with a steady stream of work. And, no member of the cluster needs to exert garbage collection related backpressure. That's pretty sweet: predictable tail latencies and improved throughput. 

### Data safety

I've been writing concurrent applications for a long time. I started back in the 90s writing threaded network servers in C++.
I was pretty green as a programmer, and I caused **a lot** of segfaults.

Over the course of time, I learned many rules that if I followed them, kept me from segfaulting my applications. This worked out great until I broke my rules. I didn't ever break them intentionally. I broke them accidentally. Tracking down where I had broken my rules was frustrating and time-consuming.

When we were looking for implementations for Wallaroo, C and C++ were both options. Personally, I love writing C. Its one of my favorite languages. It’s a powerful tool that allows you to do amazing things at a very low-level. However, it’s lack of safety can be problematic.

We wanted the performance of C/C++, and we wanted a type system that would help us not accidentally break those all important data safety rules.

The Pony language sports a novel feature called [reference capabilities](http://jtfmumm.com/blog/2016/03/06/safely-sharing-data-pony-reference-capabilities/). Reference capabilities are part of the type of an object and allow the compiler to assure that you are aren't breaking data safety.

For example, one reference capability is `iso`; `iso` tells the compiler, "there should only ever be a single pointer to this data." That is, the data is isolated. If you try to share your isolated data with another actor, and thereby another thread, without giving up your reference to it, your program won't compile.

We feel way more confident in our code with the compiler supporting us. Personally, I had an "a-ha" moment a couple of months into writing Wallaroo. I was still new to reference capabilities and often didn't understand why the compiler was complaining. I was looking at one particularly error for a good 20 minutes trying to figure out why it wouldn't compile. Finally, it dawned on me what the safety problem was and how hard it would have been to track that bug down. Personally, I wouldn't want to program concurrent software without language support. I'm good at this. I'm experienced. But I'm human. And as a human, I know I will mess this up. It's nice having the language make up for my inevitable deficiencies.

### Batteries not required

To meet our goals, we knew we were going to need to write most of Wallaroo from the ground up, so we weren't worried about Pony’s small standard library and lack of 3rd party libraries. Writing high-performance code means understanding and controlling as much of it as possible. 

### Interacting with other languages

There were a lot of reasons to use Pony, but we needed still one more. A good story for interacting with other languages. We didn't and still don't, expect everyone to start writing Wallaroo applications in Pony. We needed to support other languages.

We've built [Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/), Go, and C++ APIs via Pony's C foreign function interface. My colleague, Andrew Turley, is going to have a post coming soon that details how we have used Pony's C FFI together with Python's C API to embed a Python interpreter inside of Wallaroo. He'll be discussing how we went about doing it as well as the efficiency and resilience wins we get from that.

## Results

Would we make the same decision again? Yes. We would. 

Let's talk time to market for a moment, leveraging the Pony runtime has been a huge win for us. If we had written our own runtime that had similar performance characteristics, I'm not sure we'd be done yet. The Pony runtime fit our use case very well. There weren’t any other runtime options available that were so well suited to what we needed for Wallaroo. If we hadn’t used the Pony runtime and had written our own from scratch, we wouldn’t be as far along as we are now. If you forced me to put a number on it, my hand wave estimation would be that using the Pony runtime saved us a good 18 months of work.

On top of that, we have gotten the excellent performance we set out to achieve, and with the support of the Pony’s type system, we are far more confident when we write and refactor code.

Sure, there's been some pain along the way, but we'd do it again. 

## What's up with Wallaroo?

We released open source and source available versions of Wallaroo a month ago. If you are a Python programmer who needs to do event-by-event data processing, you should give it a spin. Everything is [available on GitHub](https://github.com/wallaroolabs/wallaroo). 

We are releasing a Go API soon as well as support for batch and micro-batch workloads, sign up for our announcement mailing list to be informed when that happens. And if you have questions, we are available to chat in our IRC channel and on our user mailing list. You can find all that and more in the [community section](http://www.wallaroolabs.com/community) of our website.

See you next time and thanks for reading!
