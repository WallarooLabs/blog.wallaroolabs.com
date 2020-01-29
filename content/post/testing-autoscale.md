+++
title = "How We Test the Stateful Autoscaling of Our Stream Processing System"
date = 2018-03-22T00:00:00-05:00
draft = false
author = "nisanharamati"
description = "Repeatability is key in testing, and even more so in complex systems tests where many moving pieces come together. Dive into this post for an overview of how we instrument and automate the testing of Wallaroo's autoscale features."
tags = [
    "testing",
]
categories = [
    "testing",
]
+++

This post discusses how we use end-to-end testing techniques to test Wallaroo's [autoscaling features](http://www.wallaroolabs.com/technology/autoscaling).

## Background

Autoscaling in Wallaroo enables adding or removing work capacity from an application that performs partitioned work. In other words, it allows users to change the number of workers that are concurrently handling a parallelized state computation. To understand what this means, we will cover some basic Wallaroo terminology. If you're already familiar with these terms, feel free to skip ahead to the next section.

>__**Computation (Stateless)**__
>Code that transforms input data to output data (optionally omitting the output if it is being filtered).
>
>__**Parallel Computation**__
>A stateless computation that can be executed in parallel on multiple workers.
>
>__**State**__
>The result of data stored and updated over the course of time
>
>__**State Computation**__
>Code that takes an input data and a state object, and operates on the input and state (possibly updating the state), and optionally produces output data.
>
>__**Source**__
>An input point for data from a external systems into the application.
>
>__**Sink**__
>An output point for data from the application to external systems.
>
>__**Partitioned State Computation**__
>Wallaroo supports parallel execution of state computations by way of state partitioning. The state is broken up into distinct parts, and Wallaroo manages access to each part so that they can be accessed in parallel. To do this, a partition function is used to determine which state part a computation on a particular datum should be applied to. Once the part is determined, the data is routed to that state part, and the State Computation takes pair (data and state part) to execute the computation logic.
>
>__**State Partition**__
>An individual part of a partitioned state computation's state object.

With autoscaling, Wallaroo allows users to grow and shrink the application cluster, which results in the application rebalancing the distribution of state partitions between the available workers. In a grow event, existing workers migrate some of their state partitions over to the joining workers. In a shrink event, departing workers migrate _all_ of their state partitions to the remaining workers. In both cases, Wallaroo handles the changes to data routing and connection topology under the hood, so that a user only has to add workers, or issue a `shrink` command.

The animation below shows how Wallaroo grows an application with a partitioned state computation from 1 to 2 workers: after a worker joins the application cluster, the partitioned state is redistributed so that each of the workers has an (approximately) equal load.

![grow gif](/images/post/testing-autoscale/grow-to-fit.gif)

If you would like a more in-depth review of how autoscale works, check out the [Introducing Wallaroo's autoscaling feature](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/) post we published in the fall, or the [Autoscaling Feature Section on WallarooLabs.com](http://www.wallaroolabs.com/technology/autoscaling).

The rest of this post will discuss _how_ we test autoscaling.

## A Feature is Only Good if it Works, Right?

We're pretty big on the whole testing thing at Wallaroo Labs. We like to make sure things work correctly in both dev and real environments. We also like to make sure they work well in unideal environments, fraught with network errors, process crashes, and severe resource constraints, because they can teach us a lot about the kind of behaviour we might see from Wallaroo when it's taken to the absolute limit.


![skydiving_cat](/images/post/testing-autoscale/skydiving-cat.gif)
<small>source: http://thesochillnetwork.tumblr.com/post/52221628376/and-then-this-happened</small>

Wallaroo is a complex system:

- it is made up of multiple independent processes, called Workers
- the workers typically run on many machines (in production environments), or may run alongside other workers on the same machine (e.g. in simple test environments)
- workers are connected to one another with separate channels for data and control, each of which uses its own TCP connection
- in addition to the distributed nature of Wallaroo itself, a complete application requires additional ancillary components, like data sources and sinks, to produce any output


![full system](/images/post/testing-autoscale/full-system.png)

Testing this sort of system [is challenging](https://queue.acm.org/detail.cfm?id=2800697), and testing a feature like autoscaling, which requires an entire system to be in place, isn't simple. You may call this an [integration test](https://blog.kentcdodds.com/write-tests-not-too-many-mostly-integration-5e8c7fff591c), or an [end-to-end test](https://medium.freecodecamp.org/why-end-to-end-testing-is-important-for-your-team-cb7eb0ec1504), but in either case, this is the sort of feature that needs a fully running system, with input, output, verification, and most importantly, _control instrumentation_, in order to test effectively and _repeatably_.

## On The Need for Repeatability

1. Start a distributed system with N workers
2. Get it to the desired state for the start of the test
3. Introduce a test event
4. Observe and validate the outcome
5. Repeat... Repeat... Repeat... Repeat!


![snowboard loop](/images/post/testing-autoscale/snowboard-loop.gif)
<small>source: http://popkey.co/m/67wkm-redbull-extreme-snowboard-snow+board</small>

Testing a distributed system is a laborious process, and it only gets worse the deeper you dive into the kind of autoscale tests we want to run. Growing from 1 worker to 2, or shrinking from 2 to 1 may be manageable as a manual test. Shrinking from 10 to 7 after several grow and shrink events with lots of state lying around everywhere takes more effort to set up, and then getting the timing of the various events right can be difficult.

What's worse, though, is that the more complex the test, the less likely it is that a manual run is even recreating the same conditions during the test! Is the timing right? Did we get the commands exactly the same? Is the input sent in at the right time, at the correct rate, and is it stopped at the same time in each test iteration?

If a test fails, and we can't reproduce that failure as near as possible to the original failure, then figuring out the cause becomes that much more difficult. So it is an important aspect for a testing system that errors can be easily and reliably reproduced. And the same idea applies once the fix is implemented—how can we trust that the fix solved the problem if we couldn't reliably reproduce the error in the first place? And besides, we want to run these tests in CI!

So we need some automation.

Luckily, we already have an integration testing framework for Wallaroo, which supports both standard [blackbox integration tests](http://softwaretestingfundamentals.com/black-box-testing/), as well as scripted [correctness tests](http://softwaretestingfundamentals.com/acceptance-testing/) for scenarios like [state recovery](https://blog.wallaroolabs.com/2017/10/measuring-correctness-of-state-in-a-distributed-system/), log-rotation, and autoscaling.

In order to make the tests repeatable, however, we also need to control for the non-determinism that arises from the distributed nature of Wallaroo.

We use several techniques to ensure a repeatable state in tests:

1. The test is controlled by a single-threaded, central process.
2. Sources, Sinks, and Metrics receivers are controlled by the central control process.
3. Input is static and always the same in every iteration of the test.
3. The commands for the individual Wallaroo workers are generated by the test framework, and ensure that the workers are always started with the same configuration parameters.
4. Test flow control is handled by the central control process. This ensures that, although the system under test may be heavily concurrent, the flow control is single threaded, and easier to reason about.
5. Flow control is event based, rather than time based. We use Wallaroo's observability channel to get the application topology information and processing status. At each phase of the test, we wait for a desired status, bounded by a timeout. If the timeout elapses, the test fails.
    This is especially useful when tests are run in resource constrained environments, like CI, where tests that complete in seconds on your local dev environment can take minutes in the CI environment.
6. The application output is validated by the control process at the end of each test.

## Validating an Autoscale Test

In order to validate tests we need to define the success criteria. Since there are two different types of autoscale events—grow and shrink—we define success criteria for each:

__**Success Criteria for Grow**__


![grow diagram](/images/post/testing-autoscale/grow.png)

A grow event involves 1 or more workers joining the cluster. The existing workers migrate some of their load over to the new workers. We test that:

1. The same number of partitions exist before and after a grow event.
2. All workers after a grow event have partitions allocated to them (if there are more partitions than workers)&#42;.
3. The partitions located on the joining workers after a grow event were previously located on other workers (that were active before the new workers joined).
4. The cluster is processing messages at the end of the grow event.

&#42; <small>Note that the test for the balance of the partition distribution is done in a unit test, and is outside the scope of the full system test.</small>

__**Success Criteria for Shrink**__


![shrink diagram](/images/post/testing-autoscale/shrink.png)

A shrink event involves 1 or more workers leaving the cluster. The leaving workers migrate all of the load to the remaining workers. We test that:

1. The same number of partitions exist before and after a shrink event.
2. All remaining workers after a shrink event have partitions allocated to them.
3. The partitions previously located on the leaving workers are located on the remaining workers after a shrink event.
4. The cluster is processing messages at the end of the grow event.

__**Success Criteria for Both Grow and Shrink**__

In addition to these event-specific tests, we also test that:

1. No workers exit with an error at any stage of the test.
2. The output is independently verified against the input data, to ensure no errors were introduced to the in-memory state.
3. Each test phase completes within a reasonable amount of time.

Data is sent from the source at a constant rate throughout the duration of the test, so that the autoscaling features are tested under a continuous load.

## Instrumentation

Wallaroo's test instrumentation framework is written in Python and makes use of the `subprocess` module to control external processes (such as Wallaroo application workers).

- The workers' STDOUT is captured and included in error printouts, and each worker's exit status is checked at the end of the test to ensure no workers exited with errors.
- The framework is responsible for creating the command line arguments for each test worker, as well as finding and assigning free ports for each worker's control and data channels.
- sources and sinks are run as additional threads.
- Wallaroo metrics are captured in an additional thread and can be parsed and analyzed in tests where they are relevant.

Flow control is governed by state changes: after each phase of the test, the test criteria are checked, and if they're all met the test will move forward to the next phase, or else if they are not met within a timeout period, the test will fail.

### Repetitions

While in many cases you may only be interested in testing that the autoscale behaviour _works_, we are specifically interested to test that _it works continuously throughout the application's lifetime_. This means that it's not enough to test, for example, that the cluster can grow by 1 worker. We want to also test that it can do so multiple times in a row.

The same idea applies to more complex test sequences, such as grow by 1, shrink by 4, grow by 4, shrink by 2, and so on, which can then be repeated in multiple cycles.
These tests have already flushed out bugs in routing and partition balancing that only show up on the 3rd, 4th, and 10th iterations of some test sequences and wouldn't arise earlier in the test.

Being able to define repetitions independently of the sequence also allows us to express tests more concisely, which turns out to be pretty handy!

### The Test Harness

With the technical details covered, let's talk about the test harness itself.

The way an autoscale test is defined is by the types and sizes of the operations we wish to execute. For example, in a test that grows by 2 and then shrinks by 2, we can say that we want to effect the sequence of changes +2 and -2 on the cluster topology. To repeat this sequence 4 times, we can define the number of cycles to be 4.
So far so good.

But there's a catch, isn't there?
Yes. There is.

While we can run any number of grow events starting with an application cluster size of 1 worker, the same isn't true for shrink events. We can't shrink a cluster to less than 1 worker, because then we'd have no workers left, and there would be no more application to test (although in practice, the cluster will refuse to shrink below 1 worker). We can solve the disappearing-cluster problem by defining the initial number of workers in the test such that there is always at least 1 worker remaining, but that's an easy vector for user errors. So instead, the test harness computes the initial cluster size based on the sequence of operations and the number of cycles. A test definition may still override the value for an initial cluster size, in which case the test harness will first validate that the cluster will not dip below 1 worker at any point during the test before proceeding to run the test. This is useful when we want to test the same sequence of operations on very large topologies (testing the extremes can be so informative!).

An autoscale test sequence takes three parameters:

1. base command - this is the command that is used to generate the command for each worker.
    For example, to run the partitioned [Python Alphabet application](https://github.com/WallarooLabs/wallaroo/tree/0.4.1/examples/python/alphabet_partitioned) example, we would use `machida --application-module alphabet_partitioned` as the base command
2. operations - the sequence of autoscale operations to execute, defined as positive and negative integers. This may be either a single integer or a list of integers
3. cycles - the number of times to repeat the sequence of operations
4. initial size - the size of the cluster at the start of the test

```python
def test_autoscale_python_shrink_by_1_grow_by_many():
    autoscale_sequence('machida --application-module alphabet', ops=[-1,4], cycles=5)
```

We then use [pytest](https://docs.pytest.org/en/latest/) to run the set of autoscale tests.

### The Test Matrix

The basic autoscale operations are:

- grow by 1
- grow by many (e.g. >1)
- shrink by 1
- shrink by many (e.g. > 1)

Since we want to test that _any sequence_ of autoscale operations is valid, at the very least, we have to test every possible pairing of the basic operations. We use a 4x4 matrix to generate the 16 tests that cover each possible pair.
We still need more tests, however, because of Wallaroo's multiple APIs. So we also duplicate each of the tests for each API, resulting in a 4x4x2 matrix of tests (soon to become 4x4x3 once the Go API gets official autoscale support).
In all, we currently run 32 separate autoscale tests for Wallaroo's Python and Pony APIs.

## Upcoming Tests

In addition to the tests described above, we keep working on improving our system's testing capabilities. Over the next few weeks we plan on adding:

- Adding source and sink addition/removal to the set of basic operations a test may define
- [fault injection](https://en.wikipedia.org/wiki/Fault_injection): network errors
- fault injection: process crash/recovery with inlined real-time state verification
- Go API tests
- [Generative testing](https://en.wikipedia.org/wiki/QuickCheck): a long running process that generates new sequences of operations (or test cases) with increasing complexity until it either finds a bug or exhausts a maximum complexity limit. Once a bug is found, the test program attempts to narrow down the trigger to the smallest possible change in parameters, which helps developers identify the cause and address it.

## Bugs Found

As with all new features, bugs are expected. Here is a sampling of the bugs we have found (and fixed) so far:

- topology routing update errors ([#2018](https://github.com/WallarooLabs/wallaroo/pull/2018))
- errors in the partition rebalancing algorithm ([#2027](https://github.com/WallarooLabs/wallaroo/pull/2027))
- Correctly remove boundaries of departing workers ([#2073](https://github.com/WallarooLabs/wallaroo/pull/2073))
- a shrunk worker failing to exit after completing migration of its data off to the remaining workers

## Conclusion

Wallaroo allows users to easily create fast, resilient, and scale-agnostic applications, but under the hood it is still a complex distributed system. We have abstracted most of that complexity behind the API, so that developers can worry about their product, rather than building and managing a distributed system. But when we test Wallaroo, we need to make sure that our tests treat it as what it is: a complex distributed system. To do this, we make use of existing tools and disciplines, and supplement that with additional tools of our own when necessary.

The full system tests required to test the autoscale feature made use of our existing integration test instrumentation framework, along with an additional layer on top of it to manage the different autoscale phases and their validation. We found this harness to be tremendously useful in finding bugs and in building confidence in their resolution, since the repeatability of the tests means that the same conditions are present in each run of a particular test.

In addition to making it easy to define (and expand) the suite of tests that we run, the autoscale testing harness also serves as the basis for our next testing project: [generative testing](https://en.wikipedia.org/wiki/QuickCheck). Look out for a future post on the topic!
