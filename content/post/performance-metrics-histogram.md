+++
title = "Latency Histograms and Percentile Distributions In Wallaroo Performance Metrics"
date = 2018-02-20T07:00:00-05:00
draft = false
author = "nisanharamati"
description = "How we implemented Wallaroo's low overhead performance counters and the philosophy behind the choices we made."
tags = [
    "performance",
    "metrics",
    "monitoring"
]
categories = [
    "Observability"
]
+++


#### How We Implemented Wallaroo's Low Overhead Performance Counters, and the Philosophy Behind Our Choices

This post is based on an internal white paper from May 2016 and follows the basic paper format. The white paper's original purpose was to make a case to move away from discrete percentile measurement and use performance histogram measurements instead.

## Abstract

We describe two methods for computing a percentile distribution: a sorted value list, and a fixed-bin histogram approach. The two strategies are analysed for cost and their ability to answer the pertinent question of whether the target of having at least a certain fraction of the population below a specific value is met. e.g. Whether 99% of events are processed in less than 1ms, and whether 99.9% of events are processed in less than 10ms.

It is shown that while a histogram approach loses resolution (i.e., it may not be able to provide the latency value at an arbitrary percentile point), it is far more efficient, and that the cost of only being able to provide the fractions of the population with values _below a predetermined set of values_ is a sensible choice in the context of addressing the question of meeting a performance SLA target.
## Terms and Definitions

__**Latency**__  
The time elapsed between the start_time and end_time of some event.

__**Histogram**__  
A division of a dimension of values into bins defined over continuous ranges, and the associated size of the population whose values fall in each bin.  
For example, for a dimension of numbers with values between 1 and 100, a histogram with the bins 1-50 and 51-100, and the population {1,2,3,95}, the histogram would show  
&nbsp;&nbsp;&nbsp;&nbsp;bin 1-50:&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;3 members  
&nbsp;&nbsp;&nbsp;&nbsp;bin 51-100:&nbsp;&nbsp;&nbsp;&nbsp;1 members

__**Percentile**__  
The value below which a given percentage of observations in a group of observations fall.  
For example, the 75th percentile of {1,2,3,4} is 3.  
Likewise, the 75th percentile of {1,4,3,1} is 3.  
That is, percentiles are applied to _value-ordered populations_.

__**SLA**__  
Service Level Agreement.  
e.g. "99% of events will be processed in less than 1ms."

__**Worker**__  
A Wallaroo worker process. Part of a Wallaroo application cluster.

__**Pipeline**__  
A Wallaroo application pipeline. Part of a Wallaroo application topology. A pipeline consists of computations (stateless or stateful), partitions, sources, and (optionally) sinks.

__**Step**__  
A step is a logical unit in a Wallaroo pipeline which is a part of a larger topology. Any individual component of a pipeline is a step for the purposes of monitoring.

__**Boundary**__  
A part Wallaroo's internal topology representation that is responsible for networking between separate workers. Ingress and egress boundaries make natural points on which to measure worker throughput.

__**Source**__  
The first step in any Wallaroo pipeline, which is responsible for receiving incoming data from an external system such as a TCP sender, Kafka, etc.

__**Sink**__  
The last step in a Wallaroo pipeline which emits output, which is responsible for sending outgoing data from Wallaroo to an external system, such as a TCP receiver, Kafka, etc.

__**Metrics Receiver**__  
A instance on each Wallaroo worker that is responsible for collecting and processing metrics produced on the worker. The same instance is also responsible for emitting the aggregate collection to an external monitoring system.

## Problem Statement

We would like to provide our clients with an SLA stating that 99% of the events we process have an end-to-end latency of less than 1ms, and 99.9% have an end-to-end latency of less than 10ms.
We wish to be able to expose this information for an arbitrary, continuous time range. Our current monitoring system shows the data for a sliding 5-minute window, which is updated once per second.
In addition, we would also like to see how well our application is performing overall so we can identify areas that might need improvement as well as areas where the application is already competitive and may be worth highlighting to potential customers.

To summarize: what we are trying to achieve is the ability to tell whether 99% or more of the events processed in a given time period have a latency below 1ms, and whether 99.9% or more of the events processed in a given time period have a latency below 10ms. In addition, we need to be able to efficiently recompute this every second.

## Approaches

## Using A Sorted Values List

Using Sorted Values List, the following method is used for each metric category:

In each Wallaroo worker:

1. As events cross thresholds of interest, a metric is produced and sent to a metrics collector.
2. The metrics collector keeps each event metric, and periodically sends the collection to an external monitoring system and starts a new collection.

In the external monitoring system:

1. We store all data as a list of events, L. L is sorted by time.
2. We then select a window, W, from L, such that W contains all events whose time is within the last 5 minutes  
    `{W: e ∀ e ∊ L | e.time > now()-'5 minutes'}`
3. To select the values in the 99% and 99.9% positions, we need to sort W. We call the sorted list W'.
4. We then select the 99% and 99.9% positions in the sorted list W', by taking its length and multiplying it by 0.99 and 0.999 respectively, then rounding the fraction up to the nearest integer. We use those integers as the indexes for the events whose latencies are the 99%- and 99.9%-percentiles. 

### Cost Analysis

- We have to store every single event in L.
    - We have to send every single event to the monitoring hub so it can store it in L.  
        __**Space cost: O(|L|)**__
- We have to index L by time. 
    - We can assume events arrive in order of completion, so L is naturally sorted.  
      __**Time cost: 0**__
- We have to select the window W from L.  
    __**Space cost: O(|W|)**__  
    __**Time cost: O(log(|W|))**__  
- We have to sort W in order of latency values.
    - Assuming best case performance of quicksort of O(nlogn)  
        __**Time cost: O(|W|log(|W|))**__  

__**Total time cost: O(|W|log(|W|)) + O(log|W|)**__  
__**Total space cost: O(|L|) + O(|W|)**__

An additional issue with this approach is that percentiles cannot be added or averaged. So if we wanted to reduce the work done in the monitoring system by computing percentiles locally on each worker, we would not be able to generate system-wide metrics from these percentiles. This forces us to collect and eventually send out a metric for each lifecycle phase of each event that is processed by Wallaroo. The amount of traffic this generates is proproptional to the amount of data Wallaroo is processing.

## Using a Histogram

Using a histogram, the following method is used: 

In each Wallaroo worker:

1. As events cross thresholds of interest, a metric is produced and sent to a Metrics Receiver actor on the worker.
2. At the Metrics Receiver, the individual metrics are recorded into a histogram for the appropriate step, boundary, or pipeline. The individual metric is then discarded (since it is the histogram that we are interested in).
3. Once a metrics collection period elapses, the collection of histograms for that period is sent out to an external monitoring system.

In the external monitoring system:

1. The histograms for each metric category are stored in a list L, sorted by time.
2. The list for each metric category is stored in a hashtable H, keyed by the category.
  Note that this relationship is invertible and depends on how we prefer to query things.
3. To get the latency histogram of a metric category in a time window W, we choose all the histograms for the category and perform a bin-wise addition (since the bin ranges are identical across the histograms, this is safe). The result is the bin-wise sum of the histograms in the window, which is another histogram of the same type. We call this histogram S.
    ![fig 1: performance metrics histogram](/images/post/performance-metrics-histogram/fig01_performance_metrics_histogram.png)

6. We transform the histogram S into a cumulative histogram S', where each bin now includes the weight of all of the bins to the left of it (in addition to its own weight). 
    ![fig 2: performance metrics cumulative histogram](/images/post/performance-metrics-histogram/fig02_performance_metrics_cumulative_histogram.png)

7. We normalize the cumulative histogram to create a cumulative distribution D.
    ![fig 3: performance metrics cumulative distribution](/images/post/performance-metrics-histogram/fig03_performance_metrics_cumulative_distribution.png)

8. To answer whether the 99th- and 99.9th-percentile latencies are below our target, we simply compare the value in the appropriate bins to the target value. In the illustrated example, the fraction below 10ms is 98.59%, and the fraction below 1ms is 81.25%, so it fails the SLA.

### Cost Analysis

- Events are binned in a histogram with pre-determined bin value ranges
    - e.g. 0-1us, 1us-10us, 10us-100us, 100us-1ms, 1ms-10ms, 10ms-100ms, 100ms-1s, 1s-10s, >10s
    - Such a histogram is constructed for each period.  
        __**Space cost: O(|H|) for |H| bins**__  
        __**Time cost: O(|E|) for |E| events**__ (but this is essentially "free" because it's streaming data.)  
- The histograms for each period are stored in a list, L.  
    __**Space cost: O(|L|*|H|)**__  
- L is sorted by the time. The histograms arrive in order, so this is free.
- We select the window w from L.  
    __**Space cost: O(|w|*|H|)**__  
    __**Time cost: O(|w|)**__ (Note that here |w| is the _number of histograms_, whereas for percentiles |W| is the _number of events_, which is much larger.)
- We perform a bin-wise addition of the histograms. This means that we take the number of events in a bin and add them across all of the histograms in W, and do the same for each bin. This produces an aggregate histogram (which is just another histogram!).  
    __**Space cost: O(|H|)**__  
    __**Time cost: O(|w|*|H|)**__  
- We then normalize the histogram to obtain population percentage instead of size, by taking the population size associated with each bin and dividing it by the sum of the sizes of all bins to achieve the fraction of the population represented in this bin. Since we care about the fraction of the population whose value _is below a certain value_, we use the sum of the fractions of all bins whose value range is smaller than the current bin, plus the current bin's fraction.  
    __**Space cost: O(|H|)**__  
    __**Time cost: O(|H|)**__  
- We then select the bin whose maximum value is the value we wish a certain percentage of the population to be below and check whether the fraction in that bin is larger than the desired value. If it is, we're good.  
    __**Time cost: O(1)**__  

__**Total space cost: O(|L|*|H|) + O(|w|*|H|) + O(|H|) * O(|H|)**__  
__**Total time cost: O(|w|) + O(|w|*|H|) + O(|H|)**__

## Comparing the Two Approaches

The histogram approach is significantly more efficient in both space and time, and it achieves this by use of compression (a histogram is a form of compression since it loses the original data of individual events).
The efficiency difference becomes important as the total number of values grows; this is true for both network traffic and time as well as storage requirements and query times in the monitoring system.

That is, if we process 100k events per second, and show performance for 5-minute windows (e.g. 300-second windows), this would require storing data for at least 300*100,000=30,000,000 values, sorting it whenever we add data for a new second (and figuring out how to remove data from the outgoing second), and then picking two values by index, the 99th, and 99.9th percentiles. 

For the histogram approach, we store histograms (holding a bin value and a population count value for each bin—two integers per bin), which are small, and we can add them as well as subtract them. This means we can maintain a window histogram, and add the incoming period's histogram as well as subtract the outgoing period's histogram very efficiently without recomputing the sum of the entire set from all the histograms in the window.

Once updated, we can pick the bins whose maximum values are the _target 99th_ and _target 99.9th_ percentile latencies respectively, and check whether their population sizes or fractions are _greater than_ 99% and 99.9% respectively. This is a much more efficient approach than the sorted values list. However, this approach requires that we define our bins ahead of time to provide us with values of interest.

For example, if we care about the percentage of the population below 1ms, we need a bin whose maximum value is 1ms. We cannot infer what percentage is below 1ms if our two nearest bins are 0.5ms and 10ms, for example (other than the percentage must be between the percentage values of each bin).


Note that while in the sorted values list approach, we can obtain the latency of _any percentile_, in the histogram approach we instead obtain _the percentile at a predefined latency_. This means that we have the same data, and the same chart (given sufficient resolution), but _the index_ is moved from the percentile axis (in the sorted values list case) to the latency axis (in the histogram case).

## High Throughput and Metrics Saturation

An additional detractor of the sorted values list approach is scalability. The bandwidth and storage cost for the sorted values list approach grows in tandem with the load. So for each additional message processed per second, an additional metric message must be created, sent, stored, and processed. If we achieve our performance goals of 1mm msgs/sec with 99%-ile latencies below 1ms and 99.9%-ile latencies below 10ms, we would have a very difficult time maintaining the metrics monitoring infrastructure!

So we chose to use a latency histogram for each _step_, _worker_, and _pipeline_ in Wallaroo. This provides us with the ability to answer the pertinent question of whether the fraction of the population whose performance is outside of the acceptable range is too large. It also makes it trivial to calculate the fraction f of _bad performance_ metrics: 1-f.

## Options and Performance Optimizations

You might be thinking about other places where similar conclusions come up. Theo Schlossnagle's excellent posts at circonus.com are excellent examples (see [The Uphill Battle for Visibility](https://www.circonus.com/2016/07/uphill-battle-visibility/), [The Problem with Math: Why Your Monitoring Solution is Wrong](https://www.circonus.com/2015/02/problem-math/), and [Percentages Aren’t People](https://www.circonus.com/2016/06/percentages-arent-people/)). 

You may also be thinking, "Gee, this sounds a lot like an [HdrHistogram](http://hdrhistogram.github.io/HdrHistogram/)!" Have you looked into using an HdrHistogram? And indeed, we have.
But in the end, we prefer a different approach for several reasons: 

1. While HdrHistograms are amazing, they are more expensive in both time and space than a basic histogram with a small number of fixed bins.
2. While the added resolution is handy if one needs to answer arbitrary percentile questions, this isn't currently the case for Wallaroo. The current situation requires answers to very explicit questions, such as _"is the 99th percentile latency below 1ms?"_
3. There is currently no HdrHistogram implementation for Pony. (Note that this is no longer the case, as there is an excellent port by [Darach Ennis](https://github.com/darach/hdr_histogram_pony))
4. The cost or recording an event _is still too high_ for very high throughput loads.

## Powers of 2 Histogram

The binary representation of numbers offers a very useful optimization: one can obtain the nearest power of 2 that is greater than a current number by counting the leading zeros in a fixed width integer representation of that number. More importantly, nearly all modern CPUs have hardware support for this operation, which we can leverage.

For example, if the 32-bit big-endian representation of the number `100,000` is `00000000000000011000011010100000`, which has 15 leading zeros, then its nearest power of 2 which is greater or equal to it can be calculated as   
2^(32-15) = 2^17 = 131072.  
This comes in handy since we can use a single instruction to count the leading zeros of an unsigned integer.

## Implementation

To achieve the lowest possible performance measurement overhead, we chose to use the powers-of-2 histogram as the internal metrics counter in each Wallaroo worker. The way this works is by taking a nanosecond timestamp immediately before and after the points of interest (e.g. before and after a computation, or at the input and output boundaries of a worker, or at the source and sink of a pipeline). The pair of timestamps is converted into a nanosecond delta, which is then recorded in the appropriate histogram for the particular step, worker, or pipeline. The histogram is maintained over a period of 2 seconds, after which a new histogram is created and the old one is sent out to an external metrics service (such as Wallaroo's bundled [Metrics UI](https://docs.wallaroolabs.com/book/metrics/metrics-ui.html)).

We implemented the histogram using an array of 64-bit unsigned integers, initialized to 0. To record a new value, an index function is used, which returns `64 - clz(v)`, where `clz(v)` is the number of leading zeros for the number `v`. In addition, we maintain a record of the minimum and maximum values observed in each histogram, as we found those useful measurements to keep track of.
From a practical perspective, this means that our latency measurements aren't using the _natural_ units of 1us, 100us, 1ms, 100ms, and so on, but rather, they use powers of 2 of nanoseconds. In practice, this comes close enough to most points of interest, and provides us with a high resolution in Wallaroo's target performance range:


```
Index    Bin min (ns)    Bin Max (ns)    Bin Width (ns)
0        1               1               1
1        1               2               1
2        2               4               2
...
9        256             512             256
10       512             1024            512
11       1024            2048            1024
12       2048            4096            2048
...
19       262144          524288          262144
20       524288          1048576         524288
21       1048576         2097152         1048576
22       2097152         4194304         2097152
...
29       268435456       536870912       268435456
30       536870912       1073741824      536870912
31       1073741824      2147483648      1073741824
...
35       17179869184     34359738368     17179869184
```



Our powers-of-2 histogram is quite simple, and you may find the code for the implementation at https://github.com/WallarooLabs/wallaroo/blob/0.4.0/lib/wallaroo/core/metrics/histogram.pony. 

## Conclusion

Since visibility into the performance bottlenecks is a key factor when working on low-latency application, it was imperative to maintain the lowest overhead we could achieve when collecting Wallaroo's performance metrics. We found that the use of histogram counters, and the powers-of-2 histogram in particular, struck the right balance in terms of producing a good level of performance visibility without adding a lot of expensive overhead. This enables our users to fine tune their applications without adding much of an impact, so it's a win-win situation.


## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
