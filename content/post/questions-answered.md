+++
title= "Your Wallaroo Questions Answered"
date = 2018-03-15T12:00:00-04:00
draft = false
author = "cblake"
description = "Top Questions from Developers and Hacker News Community about Wallaroo."
tags = [
  "python"
]
categories = [
]
+++
Wallaroo Labs has received a lot of great feedback from developers on Hacker News and other communities.

Below are some answers to questions that repeatedly come up in conversations about Wallaroo.

Thank you! Please keep reading our engineering posts, commenting, and asking questions!

## Why did you write Wallaroo in Pony?

When we looked at the tools available to build Wallaroo and the use cases we wanted to handle, there were a few paths available to us.

We wanted high-throughput and very low-latency processing, so Erlang was going to be a problem. If we wanted to write a runtime from scratch, we could go with C/C++ or maybe Rust. Our other option was to take the plunge with Pony and leverage its runtime.

Writing a lock-free, high-performance runtime for safely accessing data and running multiple threads is no small task, so leveraging the Pony runtime has been a massive win for us. There’s no doubt it was the right choice.

If we didn't use the Pony runtime and had written our own from scratch, we wouldn’t have made progress so quickly. It’s not always easy to figure how much time you didn’t waste, but – if you forced us to put a number on it – we estimate that using the Pony runtime saved us a good 18 months of hard work.

For a more in-depth overview, check out our post: [“Why We Used Pony to Write Wallaroo.”](https://blog.wallaroolabs.com/2017/10/why-we-used-pony-to-write-wallaroo/)

## What types of tasks are well-suited for Wallaroo?

Wallaroo is built for applications that process data on an event-by-event basis, operate at high-throughput, and demand low-latency.

Additionally, we offer native Python support, so you don't need to run on top of Java/JVM. This makes Wallaroo a great choice to vs. other stream processing frameworks that run on the JVM like Apache Storm, Spark, or Flink.

Wallaroo can handle any use case that a stream processing system can handle, covering a variety of use cases within a range of industries and verticals including medical cybersecurity, infrastructure monitoring, programmatic advertising, location services, and manufacturing.  [o1]

## Is Wallaroo used in production?

We are working with several clients on applications including use cases in infrastructure monitoring, cybersecurity, and streaming workflows.

Currently, none of these Wallaroo installations are in production, but we expect several of them to be live by spring of 2018.

We’ll keep you posted on our progress.
## How does Wallaroo compare to other stream processing frameworks?

Wallaroo was built to handle the ever-increasing demands of data-driven applications. On an event-by-event basis (not micro-batching), we’ve seen sustained, end-to-end latency as low as two microseconds. .

We know that you have many stream processing frameworks to choose from, so you want to know what makes Wallaroo special. Here are the areas in which Wallaroo excels.

### Stateful Applications
Wallaroo has a built-in resilient in-memory resilient state; you don't need to roll your own or use a secondary system to keep state.

### Python and Golang are first-class citizens.
Wallaroo lets you program natively in Python and Golang, using your favorite tools and libraries.  Wallaroo is perfect for organizations that don’t want to deal with the complexity of JVM-based solutions.

### High-performance
Wallaroo was conceived while working on consulting projects for a large bank’s electronic trading systems.  High-throughput and low-latency were the core goals of Wallaroo – goals that we have achieved wonderfully.

### Scalability
Using Wallaroo's scale-independent API, you can write code once and deploy on any infrastructure at any scale.

If any of these benefits pique your interest, Wallaroo is an excellent choice for you.

## How do you ingest data with Wallaroo? What sources and sinks are supported?

Wallaroo currently supports TCP and Kafka sources and sinks. We have plans to roll out additional source and sink support soon, prioritized by user and client needs. That’s in addition to an API that allows developers to build their own in Python and Golang, which you can also expect to see in the near future.

## How is Wallaroo licensed?

Wallaroo is an open source project, so all of the source code is available to you. It is available under the Apache License, version 2. Parts of earlier versions of Wallaroo were released under a more restrictive Wallaroo Community License, but now these pieces are under the Apache License as well.

## How does Wallaroo measure latency?

In Wallaroo, we measure the time it takes to process every message within the system.

Much [thought](https://blog.wallaroolabs.com/2018/02/building-low-overhead-metrics-collection-for-high-performance-systems/) went into how we go about capturing detailed latency statistics while minimizing the impact on the system's performance.

The Wallaroo UI shows the latency of message processing for the last five minutes.  The UI reports latency in the following percentiles: 50%, 95%, 99%, 99.9% and 99.99%.  These latency numbers are visible overall for a pipeline, as well as broken down to works and computations, the individual components of the pipeline.

We believe that by providing meaningful metrics via the Wallaroo UI and allowing developers to identify specific bottlenecks in computations or other parts of our system, they will be able to make quick iterations in their development cycle.

## What are Wallaroo’s current limitations and how are you planning on addressing them?

The current state of Wallaroo provides a great set of features and functionality that target a wide variety of use cases.  That being said, Wallaroo is a work in progress, and we expect there to always be open issues as we move the state of the art forward.

The most current and up-to-date- information on the limitations of Wallaroo are located [here](https://github.com/WallarooLabs/wallaroo/blob/master/LIMITATIONS.md).

We prioritize issues and new feature requests according to the needs of our clients and most active users. If there is something that you would like to see addressed, please speak up. You can [open an issue](https://github.com/WallarooLabs/wallaroo/issues) or ping us on [IRC](https://webchat.freenode.net/?channels=#wallaroo).
## What windowing strategies does Wallaroo support?

Wallaroo currently supports event-driven windowing, in which the boundaries of each window are determined outside of Wallaroo and triggered by any event. Wallaroo is told when a window ends, and work is run on the aggregate state and started over.

A detailed example of event-driven windowing in Wallaroo is available [here](https://blog.wallaroolabs.com/2017/11/non-native-event-driven-windowing-in-wallaroo/).

We will be rolling out support for additional windowing use cases as needed to support our clients.
## Where did the name Wallaroo come from?

Picking the correct name is important, and a whole lot of fun!

When we began building our high-performance stream processing framework, we called the project Buffy, an ode to "Buffy the Vampire Slayer." The idea was that we could call the framework Buffy and name its various components after other characters from the show.  Some of those references, such as Giles and Spike, live on in our code.

As our company progressed, we considered the idea of open-sourcing our software, and decided to take the opportunity to come up with a better name.

Internally, we started to toss around lots of new ideas. Many names were suggested only to be batted down.  Warp? Nope, too generic. Arkwright? Too obscure. We tried the names of scientists, such as Heisenberg, but decided that associating our framework and its accurate results with his “uncertainty principle” might have been a poor marketing decision.

After all of that, we tried animal names. Of those chosen, "Wallaroo" quickly became a frontrunner.  It was one of the top five names that we came up with internally, and our CEO, Vid Jain, made it official when he made the final selection.

We’re quite happy with the name, but we’re particularly proud of the logo. The Wallaroo platform is perfectly represented by the unassuming animal outfitted with boxing gloves.

Simple, powerful, and ready for a fight!

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
