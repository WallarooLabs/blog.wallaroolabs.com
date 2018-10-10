+++
title = "Building low-overhead metrics collection for high-performance systems"
date = 2018-02-20T07:20:00-05:00
draft = false
author = "jonbrwn"
description = "Design decisions that allowed us to capture metrics in Wallaroo with a low-overhead."
tags = [
    "metrics",
    "performance",
]
categories = [
    "Exploring Wallaroo Internals"
]
+++

Metrics play an integral part in providing confidence in a high-performance software system. Whether you’re dealing with a data processing framework or a web server, metrics provide insight into whether your system is performing as expected. A direct impact of capturing metrics is the performance cost to the system being measured.

When we first started development on [Wallaroo](https://github.com/WallarooLabs/Wallaroo), our high-throughput, low-latency, and elastic data processing framework, we were aiming to meet growing demand in the data processing landscape. Companies are relying on more and more data all while expecting to process that data as quickly as possible for, among other things, faster, better decision making, and cost reduction. Because of this, we set out to develop Wallaroo with three core principles in mind:

1. High-Throughput
2. Low-Latency
3. Lower the infrastructure costs/needs compared to existing solutions.

Proving to our users that we were delivering on these principles was an essential part of the early development cycle of Wallaroo. How could we prove we were delivering on these principles? We needed to capture metrics. Metrics are an excellent way to spot bottlenecks in any system. Providing meaningful metrics to our users would mean they could make quicker iterations in their development cycle by being able to spot specific bottlenecks in various locations of our system. An added benefit that came from capturing these metrics was that it also sped up the Wallaroo development cycle as we were able to use them as guidelines to [measure the “cost” of every feature](https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/#measure-the-cost-of-every-feature).

In the end, what came of our metrics capturing process became a web UI that provides Wallaroo users introspection for various parts of the applications they develop. Here's what the result looks like:

![application dashboard page](/images/post/performance-metrics-overview/application-dashboard-page.png)

In this post, I'll cover some of the design decisions we made regarding our metrics capturing system to maintain the high performance our system was promising.

## Metrics Aren't Free

Adding introspection via metrics to your system inherently adds an overhead. However, the impact of that overhead is determined by how you capture metrics and what information you choose to capture. Not only is there a ton of information to capture, but there are also many different ways to capture it. The biggest problem you face while determining how you capture metrics is maintaining a low overhead. A computationally heavy metrics capturing system could mean lower throughput, higher latencies, and costlier infrastructure, all things you want to avoid. When approaching this type of problem, you need to determine how much information you need to capture to provide meaningful details via your metrics while minimizing the performance impact on your system.

## Information We Want to Convey with our Metrics

A Wallaroo application broken down to its simplest form is composed of the following components:

- **Computations:** code that transforms an input of some type to an output of some type. In Wallaroo, there are stateless computations and what we call “state computations” that operate on in-memory state.
- **Pipelines:** a sequence of computations and/or state computations originating from a source and optionally terminating in a sink.

These components can be on one or more Wallaroo **workers** (process). By capturing metrics for these components, we give Wallaroo users a granular look into various parts of the applications they develop.

The information we want to convey to our users with the metrics we capture is the following:

  - the throughput of a specific component in Wallaroo for a given period.
  - the percentile of latencies that fell under a specific time in Wallaroo for a given period.

Our metrics capturing needs to be flexible enough to give us accurate statistics over different periods of time. Knowing what information the metrics of your system needs to convey will end up playing a major factor in how you determine to capture metrics.

## Using Histograms for our Metrics Capturing

There are many ways to capture metrics, each with its own positives and negatives. Out of the options we looked at, histograms were the most appealing because they could provide the statistics we wanted to convey while also maintaining a low overhead. For a low-level look into this decision, Nisan wrote a dedicated blog post  ["Latency Histograms and Percentile Distributions In Wallaroo Performance Metrics"](https://blog.wallaroolabs.com/2018/02/latency-histograms-and-percentile-distributions-in-wallaroo-performance-metrics/). I’ll cover this design choice on a higher level.

To best describe how we came about in choosing histograms as the metrics capturing data structure in Wallaroo, I will focus on one of Wallaroo's components: state computations.

These were the metric statistics we wanted to provide:

![computation page](/images/post/performance-metrics-overview/computation-detailed-metrics-page.png)

As mentioned above, Wallaroo allows for both stateless computations and computations that operate on state. To maintain high-throughput and low-latency, we leverage some of the design principles behind [Pony](https://github.com/ponylang/ponyc), an object-oriented, actor-model, capabilities-secure, high-performance programming language. To maintain high performance at scale, concurrency and parallelism are needed for our state computations to avoid acting as a bottleneck in our pipelines. Sean talked a bit about this design principle in detail in the [Avoid Coordination](https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/#avoid-coordination) section of our ["What's the Secret Sauce?"](https://blog.wallaroolabs.com/2017/06/whats-the-secret-sauce/) blog post.

Here’s an example of state partitioning in Wallaroo:

For a [Word Count](https://docs.wallaroolabs.com/book/python/word-count.html) application, we partition our word count state into distinct state entities based on the letters of the alphabet. We ultimately set up 27 state entities in total, one for each letter plus one called "!" which will handle any "word" that doesn't start with a letter. By partitioning, we remove the potential bottleneck of a single data structure to maintain the state of the count of all of our words.

Each state entity is managed by a Step, an actor which is responsible for running the state computation and routing output messages downstream, amongst other things. Using Steps allow us to avoid coordination in updating state, but we also need to avoid coordination in our metrics capturing system. To get a full picture of how a state computation is performing, the metrics provided by each Step needs to be able to be stitched together. Here's a diagram to best illustrate the type of aggregation we require across Steps:

![aggregated steps diagram](/images/post/performance-metrics-overview/steps-diagram.png)

A [Sorted Values List](https://blog.wallaroolabs.com/2018/02/latency-histograms-and-percentile-distributions-in-wallaroo-performance-metrics#using-a-sorted-values-list) would give us the granularity we need to do the aggregations required but would have a much higher performance impact than we want. Another option would be to store specific statistics (mean/median/average) per Step, but the need for aggregation would render these statistics entirely useless if we want an accurate depiction of the computation multiple Steps represent. [Theo Schlossnagle](https://twitter.com/postwait) wrote a great blog post explaining why bad math like an average of averages provides useless metrics: ["The Problem with Math: Why Your Monitoring Solution is Wrong"](https://www.circonus.com/2015/02/problem-math/). Existing industry research shows that histograms are excellent solutions for gathering meaningful metrics: ["How NOT to Measure Latency"](https://www.youtube.com/watch?v=lJ8ydIuPFeU) by [Gil Tene](https://twitter.com/giltene) and ["The Uphill Battle for Visibility"](https://www.circonus.com/2016/07/uphill-battle-visibility/) by [Theo Schlossnagle](https://twitter.com/postwait) are two great examples. We recognized that histograms would work well for us due to the following:

- low cost of both time and space compared to other metric capturing techniques
- histograms can be easily aggregated, necessary when not all metrics are stored in a single data structure
- Allows us to answer: is the 99th percentile latency below this time value?

## Minimizing the Metrics Capturing Overhead

We know what metrics information we need to capture, and we know how we want to capture it. The next step is to determine how much of this workload is required to be handled by Wallaroo. We need to aggregate histograms to get a complete picture of components but is it worth the resource cost to process this online in Wallaroo or any other high-performance system? The answer is generally no. An external system could take these histograms and perform the aggregations needed without impinging on the resources required by Wallaroo. This means freeing up CPU and memory resources that we'd be using if Wallaroo were also responsible for the aggregation of its metrics. Since metrics would have to be offloaded from Wallaroo in some fashion eventually, we decided to do this as early as possible.

### Push vs. Poll

When deciding how to offload the metrics information from Wallaroo to an external system, we have two options: push or poll. We ended up making the metrics system push-based for several reasons. Using Steps as an example here, if we were polling each for its metrics, we'd be wasting CPU resources if a Step had not completed any work. If we have 300 Steps and only 50 are handling the workload, polling and sending empty stats for the remaining 250 could turn our outgoing connection to the external metrics processing system into a bottleneck. By pushing only from Steps which are completing work, we save on CPU resources and minimize the potential of the metrics receiver bottlenecking from an overload of incoming data.

## Wallaroo’s Metrics in Action

In the end, it was a combination of several design choices that allowed us to capture the metrics we wanted without greatly impacting the performance of Wallaroo. Maintaining our high-throughput and low-latency principles while capturing metrics was not the most straightforward task, but we’re happy with what we’ve been able to achieve so far.

As we saw above, we ultimately ended up developing a Metrics UI to assist developers using Wallaroo. Feel free to spin up a Wallaroo application and our Metrics UI to get a feel of how we handle metrics for all of the components that compose a Wallaroo application.

In a future post, I’ll dive into how we use the metrics we receive from Wallaroo to come up with the information displayed above.

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!

