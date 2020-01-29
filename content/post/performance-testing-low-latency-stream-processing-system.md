+++
title= "Performance testing a low-latency stream processing system"
date = 2018-03-08T12:00:00-04:00
draft = false
author = "dipin"
description = "How we performance test Wallaroo, our high-performance, low-latency stream processing system."
tags = [
    "performance",
    "testing"
]
categories = [
    "testing",
]
+++

At [Wallaroo Labs](http://www.wallaroolabs.com/) we've been working on our stream processing engine, [Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release) for just under two years now. We've designed Wallaroo to be able to handle millions of messages a second on a single server with low microsecond latencies. We recently explained how we [increased performance of Wallaroo](https://blog.wallaroolabs.com/2018/02/how-we-built-wallaroo-to-process-millions-of-messages/sec-with-microsecond-latencies/) and how we [collect metrics without impacting performance](https://blog.wallaroolabs.com/2018/02/building-low-overhead-metrics-collection-for-high-performance-systems/). This blog post focuses on how we do our performance testing to help us achieve [Wallaroo's goals](https://github.com/wallaroolabs/wallaroo#what-is-wallaroo).

## Importance of Performance Testing and Considerations Involved

It is important to understand the performance characteristics of any high-performance system. Without this understanding, it is impossible to determine resource requirements, to be able to do a thorough cost/benefit analysis, or to compare one solution to another. Understanding performance is also important from a sales perspective. Everyone wants to be able to work faster and quicker while spending less money and using less resources. You can't sell a system without understanding its performance characteristics.

In order to be able to be able to determine performance of a system, we need to ensure that our test environment is set up correctly to minimize interference between the system being tested and the operating system it is being run on. In addition, we need to set up a test that will appropriately exercise it in a meaningful way. Lastly, we need to define our SLAs and collect the relevant metrics to be able to compare different performance tests to each other to determine how the performance of the system is changing as it evolves to add functionality to identify performance gains or regressions.

## Testing Environment

### Hardware and Environment

For Wallaroo, we chose to run our performance tests in AWS for ease of provisioning and ability to allow for multiple performance tests to be running in parallel using [Terraform](https://www.terraform.io/) and [Ansible](https://www.ansible.com/). We rely on the AWS c4.8xlarge instance type for the underlying hardware because it allows us to [control CPU C-States and P-States](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/processor_state_control.html) to ensure maximum performance and consistent CPU speed without CPU power management functionality interfering with our tests. We disable hyperthread cores on the CPUs to minimize hardware CPU pipeline contention for our performance test workload. We have the Linux kernel run the CPU cores at maximum frequency and we disable turbo boost to minimize jitter. Lastly, we also rely on AWS placement groups to ensure minimal network impact from noisy neighbors.

### Software Environment

At the Linux operating system level, we disable use of swap, assign interrupts to specific CPU cores, and disable transparent huge pages. In order to ensure Linux processes do not interfere with Wallaroo, we rely on a number of Linux utilities and tweaks. We enable process isolation using cgroups/cpusets (via [cset](http://manpages.ubuntu.com/manpages/trusty/man1/cset.1.html)). This helps us to ensure that all system processes only run on CPU 0 in our testing environment while Wallaroo can run on all the other CPU cores.

We run Wallaroo itself to ensure maximum performance. We use cset to run all processes in a cpuset where system processes are not allowed to run and [numactl](http://man7.org/linux/man-pages/man8/numactl.8.html) to pin processes to specific CPU cores to avoid contention between the different Wallaroo workers and the other related components (data senders and data receivers). We rely on [chrt](http://man7.org/linux/man-pages/man1/chrt.1.html) to run processes at a realtime priority to minimize Linux scheduler preemption.

## Wallaroo Performance Testing Environment

### Senders, Receivers, Metrics

In order to performance test Wallaroo, we need a number of supporting applications that are part of our ecosystem. The `sender` is used to send data into Wallaroo. The `receiver` receives data output from Wallaroo. The `Metrics UI` receives metrics from Wallaroo. More details about how we collect metrics from Wallaroo while minimizing overhead can be found at our [recent blog post](https://blog.wallaroolabs.com/2018/02/building-low-overhead-metrics-collection-for-high-performance-systems/) about the topic.

### Wallaroo Application

The Wallaroo application that we use for performance testing is called [Market Spread](https://blog.wallaroolabs.com/2017/12/stateful-multi-stream-processing-in-python-with-wallaroo/#market-spread-our-two-pipeline-example-application). Market Spread is a relatively simple application that keeps track of recent data about stock prices (“market data”) and checks streaming orders against that market state in order to detect anomalies and, if necessary, sends out alerts to an external system indicating that an order should be rejected. This simple application uses a number of Wallaroo features such as state split across many partitions, multiple sources/streams of input, one stream of output, and it is composed to two pipelines. These qualities combine to allow us to test a multitude of scenarios across one or more workers while exercising the core of Wallaroo as a framework while keeping the business logic simple enough to ensure that we can identify bottlenecks in Wallaroo itself.

## Running a Performance Test

Running a performance test for Wallaroo is a mostly manual process at the moment. The process is as follows:

* Create and configure testing cluster in AWS (using terraform/ansible)
* Log into the cluster and compile the various applications involved in testing (market-spread, sender, receiver, etc)
* Start Metrics UI
* Start receiver
* Start market-spread
* Start senders
* Monitor the run and capture relevant details
* Shut down everything
* Destroy the testing cluster

We record all the details of the run including all commands used, git hashes involved, and any other pertinent details for tracking. If anything is considered out of the ordinary, it is highlighted so it can be further investigated if necessary. An example of a performance test run document can be found [here](https://docs.google.com/document/d/1PsTK3b5mCBIUJI8nJdQV5iJQk1uHPAENTI2PuagJjgY/edit).

### The relevant details

As part of the "Monitor the run and capture relevant details" step of running a performance test, we focus on the following metrics and details:

* throughput of the stream processing in Wallaroo (monitored using the Metrics UI)
* latency of the stream processing in Wallaroo (monitored using the Metrics UI)
* memory usage of Wallaroo (monitored using [htop](https://hisham.hm/htop/))
* CPU usage of Wallarooo (monitored using [htop](https://hisham.hm/htop/))
* network bottlenecks/buffers (monitored using [netstat](http://man7.org/linux/man-pages/man8/netstat.8.html))

We have found these details to be the most relevant to the performance of Wallaroo and changes to these metrics alert us to regressions so we can investigate further. We're either able to identify the regressions and fix them or understand that the performance impact is a necessary by product of new features introduced. In both cases, we make sure we understand what the root cause is so we can take the appropriate action.

## Next steps

The above is a summary of how we currently performance test Wallaroo. We still have a long way to go before we have our ideal performance testing mechanism. We are working to improve things by implementing the following:

* Improved automation (specifically around the running of the tests)
* Metrics/logs capture for analysis
* Easier methods by which to analyze, visualize, and compare multiple runs

## Conclusion

We hope this blog post about how we performance test Wallaroo has been informative. For more details on some of the performance gains we've managed with our performance testing process, take a look at our recent blog post on [how we built Wallaroo to process millions of messages/sec with microsecond latencies](https://blog.wallaroolabs.com/2018/02/how-we-built-wallaroo-to-process-millions-of-messages/sec-with-microsecond-latencies/). While some of the specifics may not apply to other systems, every system should be able to benefit from the techniques involved to isolate and minimize impact of the operating environment from the application being tested along with the details of optimizing the CPU resources by controlling CPU C-States and P-States.
