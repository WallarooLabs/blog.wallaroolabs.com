+++
title = "Open Sourcing Wallaroo"
date = 2017-09-27T12:00:00-04:00
draft = false
author = "seantallen"
description = "In which we announce the opening up of our codebase."
tags = [
    "wallaroo",
    "open source",
    "announcement"
]
categories = [
    "Hello Wallaroo"
]
+++
I'm very excited to announce the first open source, public release of our ultrafast and elastic data processing engine, Wallaroo. In this post, I'm going to give you an overview of what Wallaroo is, where we are taking it, where it is now and how you can start using it.

## What is Wallaroo?

Wallaroo is an ultrafast and elastic data processing engine that rapidly takes you from prototype to production by making the infrastructure virtually disappear.  We’ve designed it to handle demanding high-throughput, low-latency tasks where the accuracy of results is essential. Wallaroo takes care of mechanics of scaling, resilience, state management, and message delivery. We've designed Wallaroo to make it easy to scale applications with no code changes, and allow programmers to focus on business logic. If you are interested in learning more about Wallaroo, I suggest you start with our introductory blog post ["Hello Wallaroo!" blog post][hello wallaroo post] that we released back in March. 

I've done a [15-minute video of our engineering presentation][scale independence with wallaroo] that has helped people understand what Wallaroo is. If you watch it, you will get:

- An overview of the problem we are solving with our Scale-Independent API
- A short intro to the Python API
- A demonstration of our Autoscale functionality (for stateful applications)
- To see the power of Scale-Independent APIs in action

If you want to dive in right now, head over to [our website and get started][website community section]. Otherwise, keep reading. We have plenty more to share.

## What's the vision?

Writing data processing tools is hard. Too hard. We require too much of our engineers. The tools we can use to quickly build code on our laptops don't work well in a production environment. And our production tools aren't ideal for fast, quick iteration. Wallaroo aims to change this equation.

When we set out to build Wallaroo, we wanted to improve the state of the art for event-by-event data processing by providing better per-worker throughput, dramatically lower latencies, simpler state management, and an easier operational experience. That's where our vision started. Over the course of time, we've evolved our vision.

While talking to potential clients and working with partners, we've realized that the operational and development burdens of simultaneously supporting both a high-speed, event-by-event data processing system and a higher-latency long-running job system are too high. Asking clients to install an event-by-event system next to a long-running job system was asking them to take on too much overhead. Wallaroo has to be able to do both. If we want to meet our goal of vastly simplifying building and maintaining data processing systems, we need to provide a system that supports both event-by-event and long-running workloads. As we go forward building Wallaroo, we do so with an expanded vision.

As our CEO Vid Jain puts it:

> Wallaroo should provide game-changing simplicity - data scientists and developers need to be able to go from laptop to production at any scale without changing code. Wallaroo should speed time-to-market and significantly lowers costs for applications such as capturing and transforming real-time data, performing long-running analysis and any machine learning application.

And that's what we are looking at every day. Our engineers are always asking themselves, does this feature:

- Make it easier to scale an application? 
- Push the burden of scaling a distributed application from the developer to the framework?
- Improve performance?
- Increase a developer's productivity?
- Reduce time-to-market?

Part of that means that we want to allow developers to use the languages they are used to. The big data landscape is dominated by projects that require you to use the JVM. The JVM is an impressive piece of technology, but it's not for everyone.  To that end, we are launching with a Python API, followed by C++ and Go bindings in the near future. We think that data scientists shouldn't have to rewrite the application they developed in Python to get it into production. The same would apply to C++ and Go; everyone deserves great tools. We're here to provide them to more folks.

So, that's what we are building. But, what's the state of Wallaroo now and where is it going in the immediate future?
 
## What's the current state?

Wallaroo has a solid core in place that can be immediately useful for some production workflows now. We do [extensive testing][codemesh16 how did i get here] of Wallaroo that we continue to expand on and improve. Through both internal testing usage and via customer proof of concept engagements, Wallaroo has already processed billions of messages in a single day.

With our open source release you get:

- A Python 2.7 API for building linear data processing applications
- [Documentation][documentation website] to get you started
- Integrated state-management 
- Process failure recovery
- Ability to take your application from running on one process to many without changing code
- Metrics UI

Wallaroo has been used to build a variety of applications including:

- High-volume position keeping system (using our C++ API, slated for GA in the near future) 
- Python video transcription and analysis system using TensorFlow and NLP 

We're looking to work with commercial partners and the open source community to grow the product in line with our vision. We've come a long way from where we started eighteen months ago, and we know there's plenty more to do; software is never done. The problems Wallaroo aims to solve will continue to grow and change. So what are we planning on doing with Wallaroo over the next few months?

## What's coming in the immediate future?

Knowing that we have a solid foundation in place, we have some items we are looking to address by the end of the year:

- Improve the installation process
- Support long-running and Micro-batch workloads
- Add language bindings, including Go and Python 3
- Make [Autoscaling][autoscaling] and [Exactly-once message processing][exactly-once] generally available
- Handle increasingly esoteric failure scenarios

If you are interested in more details, check out our [roadmap][roadmap].

## Licensing

Wallaroo is an open source project. All of the source code is available to you. However, not all of the Wallaroo source code is available under an "open source" license. 

Most of the Wallaroo code base is available under the [Apache License, version 2][apache 2 license]. Parts of Wallaroo are licensed under the [Wallaroo Community License Agreement][wallaroo community license]. The [Wallaroo Community License][wallaroo community license] is based on [Apache version 2][apache 2 license]. However, you should read it for yourself. Here we provide a summary of the main points of the [Wallaroo Community License Agreement][wallaroo community license].

- You can **run** all Wallaroo code in a non-production environment without restriction.
- You can **run** all Wallaroo code in a production environment for free on up to 3 servers or 24 CPUs.
- If you want to **run** Wallaroo Enterprise version features in production above 3 servers or 24 CPUs, you have to obtain a license.
- You can **modify** and **redistribute** any Wallaroo code
- Anyone who uses your **modified** or **redistributed** code is bound by the same license and needs to obtain a Wallaroo Enterprise license to run on more than 3 servers or 24 CPUs in a production environment. 

Please [contact us][contact us email] if you have any questions about licensing or Wallaroo Enterprise.

## Give Wallaroo a try

We're excited to start working with our friends in the open source community and new commercial partners. 

If you are interested in getting started with Wallaroo, head over to [our website and get started][website community section]. If you would like a demo or to talk about how Wallaroo can help your business, please get in touch by emailing [hello@wallaroolabs.com][contact us email].

There's lots more coming from us. Expect posts from us on:

- Testing Wallaroo for correctness
- A look inside our Python engine
- How exactly-once message processing works in Wallaroo
- Scale-independent computing

See you soon!

## Additional Wallaroo related content

In case you want more... right now...

- [Hello Wallaroo!][hello wallaroo post]

An introduction to Wallaroo.

- [What's the "Secret Sauce"][secret sauce post]

A look inside Wallaroo's excellent performance

- [Wallaroo Labs][wallaroo labs website]

The company behind Wallaroo.

- [Documentation][documentation website]

Wallaroo documentation.

- QCon NY 2016: [How did I get here? Building Confidence in a Distributed Stream Processor][qcon16 how did i get here]
- CodeMesh 2016:[How did I get here? Building Confidence in a Distributed Stream Processor][codemesh16 how did i get here]

Our VP of Engineering Sean T. Allen talks about one of the techniques we use to test Wallaroo.

- [Wallaroo Labs Twitter][twitter]

[apache 2 license]: https://www.apache.org/licenses/LICENSE-2.0
[autoscaling]: https://www.wallaroolabs.com/technology/autoscaling
[codemesh16 how did i get here]: https://www.youtube.com/watch?v=6MsPDtpe2tg
[contact us email]: mailto:hello@wallaroolabs.com
[documentation website]: http://docs.wallaroolabs.com
[exactly-once]: https://www.wallaroolabs.com/technology/exactly-once
[hello wallaroo post]: https://blog.wallaroolabs.com/2017/03/hello-wallaroo/
[qcon16 how did i get here]: https://www.infoq.com/presentations/trust-distributed-systems
[scale independence with wallaroo]: https://vimeo.com/234753585
[secret sauce post]: https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/
[roadmap]: https://github.com/WallarooLabs/wallaroo/blob/master/ROADMAP.md
[twitter]: https://www.twitter.com/wallaroolabs
[wallaroo community license]: https://github.com/WallarooLabs/wallaroo/blob/master/LICENSE.md
[wallaroo labs website]: https://www.wallaroolabs.com
[website community section]: https://www.wallaroolabs.com/community
