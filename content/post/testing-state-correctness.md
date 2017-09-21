---
description: "Introducing the error detection problem and how we approach it when testing Wallaroo's state correctness in the face of failure."
title: "Measuring Correctness of State in a Distributed System"
date: 2017-10-05T00:00:00Z
author: nisanharamati
slug: testing-state-correctness
draft: false
categories:
  - testing
tags:
  - testing
  - chaos engineering
  - fault injection
  - error detection
  - exactly-once
  - crash recovery
  - resilience
  - streaming
  - big data
  - serverless
  - distributed systems
  - clustering
  - large scale computing
  - data engineering
---

## Introduction

Distributed systems are hard. The larger the number of machines in a system, the higher the probability that at any given time, one or more of those machines is experiencing some sort of failure. And then there are the many possible types of failure: programming errors, inefficient patterns, caching errors, data corruption, storage failure, network failure, machine failure, data centre failure, timing errors... And the list goes on and on. It is no surprise then that a lot of distributed systems programming boils down to defensive strategies against failures. A better approach is to be proactive and design systems to _withstand_ a large number of errors, and use algorithms and protocols that are designed to be _resilient_ in the face of failures.

One of the problems we face when trying to _test_ a distributed system is, perhaps unsurprisingly, also hard: proving that the system is _correct in the presence of failure_. This is hard for many reasons, but the two that affect us the most are:

1. Errors may be difficult to measure (e.g. internal state, clock skew in an asynchronous system, etc.)
2. Errors may happen in areas of limited observability (e.g. loss and delay in an asynchronous network where only loss is considered an error)

There is overlap between the two, but the main distinction is that in the first case even if we had a global view of the entire system we may still fail to measure some of these errors unless they propagate and manifest as another error elsewhere in the system, by which time it may be very difficult, if not impossible, to trace back to the original error. In the second case, errors beyond the limit of observation, we often run into limits in terms of cost or physics that lead to uncertainty in our knowledge about the state of the system at a specific point in time.

Modern distributed systems employ a mixed approach of [formal verification](http://lamport.azurewebsites.net/tla/formal-methods-amazon.pdf), integration testing, [property based testing](http://blog.jessitron.com/2013/04/property-based-testing-what-is-it.html), safety and consistency testing using histories (such as [Jepsen](http://jepsen.io/)), [fault injection testing](http://www.cs.colostate.edu/~bieman/Pubs/issre96preprint.pdf), [lineage-driven fault injection](https://people.eecs.berkeley.edu/~palvaro/molly.pdf), and [chaos engineering](http://principlesofchaos.org/). Which method is used often depends on the specific system and the properties that are important to it.

In this blog we wanted to share with you what we've learnt and approaches we have taken with our own distributed system, Wallaroo. There's a lot here that is very general, and we also want feedback from you (the reader) and the larger community to help us improve Wallaroo.

## Testing Wallaroo

To find out more about Wallaroo, our ultrafast and elastic data processing engine for distributed applications, please check out our previous posts [Open Sourcing Wallaro](/2017/09/open-sourcing-wallaroo/), [Hello Wallaroo](/2017/03/hello-wallaroo/) and [What's the Secret Sauce](/2017/06/whats-the-secret-sauce/), or follow us on our [mailing list](https://groups.io/g/wallaroo).
The rest of this post will focus on a specific scenario, crash-recovery, to work through some of the approaches we tried when testing Wallaroo's in-memory state, and the pattern that we settled on for ensuring that Wallaroo's state remains correct in the face of failure events.

When we set out to build Wallaroo, we wanted to use a [Test-Driven-Development](https://en.wikipedia.org/wiki/Test-driven_development) approach. However, as we already noted, distributed systems testing can be really hard.

> What sets distributed systems engineering apart is the probability of failure and, worse, the probability of partial failure.  
>[Notes on Distributed Systems for Young Bloods (Jeff Hodges)](https://www.somethingsimilar.com/2013/01/14/notes-on-distributed-systems-for-young-bloods)

> Distributed systems can be especially difficult to program, for a variety of reasons. They can be difficult to design, difficult to manage, and, above all, difficult to test.  
> [Testing a Distributed System (Philip Maddox)](http://queue.acm.org/detail.cfm?id=2800697)

In the first few months, as we were building prototypes of the system and the testing apparatus, it was already apparent that in addition to unit tests and integration tests, we would need some sort of black box correctness testing that can cover both prototypes and the final product. This meant that such testing would have to rely on real input data, real output data, along with a history of the events that the system experienced in order to determine whether the system is behaving correctly or not. This is similar to the approach [Jepsen](https://github.com/jepsen-io/jepsen#design-overview) uses for distributed databases.

If you're interested in an overview of some of our earlier testing efforts, you can watch Sean T. Allen, our VP of Engineering, present on it in [CodeMesh 2016](https://www.youtube.com/watch?v=6MsPDtpe2tg).

## Testing Crash-Recovery

One of our major concerns with Wallaroo has been finding faults affecting the processing and delivery characteristics of the system. We want to be able to prove that Wallaroo's output is correct after any number of network or process failures and their respective recovery events. To do this, we turned to [fault-injection testing](https://en.wikipedia.org/wiki/Fault_injection), [chaos engineering](https://github.com/dastergon/awesome-chaos-engineering), and [lineage-driven
testing](https://people.eecs.berkeley.edu/~palvaro/molly.pdf).

One of the difficult problems in running such a test is failure detection: we want to _prove_ that such faults _definitely did not occur_.

> The power of a binary hypothesis test is the probability that the test correctly rejects the null hypothesis  
> [Statistical Power (Wikipedia)](https://en.wikipedia.org/wiki/Statistical_power)

So if we run a test, one of the most important questions to ask is how plausible is it that a fault did occur, but went undetected? In other words, it's not enough to inject failures, we also need to ensure that _we can detect errors when they occur!_

## State Invariant

> In computer science, an invariant is a condition that can be relied upon to be true during [the] execution of a program.  
> [Invariant (Wikipedia)](https://en.wikipedia.org/wiki/Invariant_(computer_science))

One of the great things about Wallaroo is that it [handles state management for you](https://docs.wallaroolabs.com/book/core-concepts/working-with-state.html). This includes state persistence and, consequently, state recovery after failure. Updates to any particular state in Wallaroo are [sequentially consistent](https://en.wikipedia.org/wiki/Sequential_consistency), so that processing of state updates is guaranteed to be _repeatable_. i.e. whether during the first execution, or
during recovery from a process crash or a network failure, the state will undergo _exactly the same updates in exactly the same order_, and arrive at _exactly the same state_ as it would if no failure event had occurred. In order to detect a violation of this property, we need to show that a different order of updates has been executed. If we imagine the evolution of a state and its updates as a sequence of pairs of update operations and the resulting state at the end of the update,

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(op<sub>0</sub>, state<sub>0</sub>) &rarr; (op<sub>1</sub>, state<sub>1</sub>) &rarr; (op<sub>2</sub>, state<sub>2</sub>) &rarr; ... &rarr; (op<sub>n</sub>, state<sub>n</sub>)

then we can express a violation of sequential consistency of the state as

1. a _removal_ of a pair from the sequence of pairs that already happened

    &nbsp;&nbsp;&nbsp;&nbsp;... &rarr; (op<sub>5</sub>, state<sub>5</sub>) &rarr; (op<sub>7</sub>, <span style="color:blue">invalid state</span>)&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">loss</span>

2. an _insertion_ of a pair that hasn't yet happened _before_ one that already has (e.g. _reordering_ or _corruption_)

	  &nbsp;&nbsp;&nbsp;&nbsp;... &rarr; (op<sub>5</sub>, state<sub>5</sub>) &rarr; (op<sub>4</sub>, <span style="color:blue">invalid state</span>)&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">reordering</span>

	  &nbsp;&nbsp;&nbsp;&nbsp;... &rarr; (op<sub>5</sub>, state<sub>5</sub>) &rarr; (<span style="color:blue">invalid op</span>, <span style="color:blue">invalid state</span>)&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">corruption</span>

3. a duplication of the same operation more than once

	  &nbsp;&nbsp;&nbsp;&nbsp;... &rarr; (op<sub>5</sub>, state<sub>5</sub>) &rarr; (op<su>5</su>, <span style="color:blue">invalid state</span>)&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">duplication</span>

In other words, _loss_, _reordering_, _corruption_, and _duplication_ are the _indicators_ we will use to determine if the sequential consistency of the state has been violated. If we can detect that any of these events have happened, then the sequential consistency invariant has been violated, and the test should fail.

Since messaging related errors surface as state invariant violations, it is enough to show that no state invariant violations have occurred in order to also rule out any messaging errors.

## Proving the State Invariant

In order to show that a run has not experienced _loss_, _reordering_, _corruption_, or _duplication_, we have to satisfy two requirements:

1. We need a way to introduce faults in a controlled fashion during a run, and
2. We need a way to detect the four possible violations to the invariant, using the output of the application

We'll start with the easier of the two: introducing faults.

## Fault Injection


[Fault injection](https://en.wikipedia.org/wiki/Fault_injection) is the practice of introducing faults into an application in order to exercise code paths that don't get tested in normal executions. There are a variety of approaches to fault injection, ranging from compiler-fault-injection, to input fuzzing, to process and system level error injection. With Wallaroo, we are interested in fault injection that works well with black box testing, and so we concentrate on process-level event injection, such as network failures and process crashes; the former allows us to build and test mechanisms for dealing with various forms of network errors, and the latter allows us to exercise a complete process recovery in various scenarios.

## Spike: Network Fault Injection

Wallaroo has a network fault-injector named Spike, which can introduce both random and deterministic network failure events; these allow us to test the reconnection protocol and the behaviour of the remaining workers in the cluster while another worker is unreachable.
Since Spike is a compile-time configuration, production builds of Wallaroo do not contain the Spike code paths.

## Process Crash

To simulate a process crash, we use the POSIX SIGKILL signal to abruptly terminate a running Wallaroo worker process. This allows us to exercise recovery from a crashed process, test how the remaining workers in the application cluster behave while a worker is down, and test the coordination involved in bringing up a replacement worker, reloading its state from both log files and other live workers in the cluster, and finally validate that the system's output _is still correct_.

## Detecting Invariant Violation

Detecting invariant violation can be approached from two directions: macro (batch) or micro (streaming). We can test the output as a whole, once the test run has completed, or we can test each message in the output stream for validity—both in isolation and with respect to its predecessors.

## The Macro (Batch Testing) Approach: an A/B Test

We started with the macro approach. It is easier to set up and run, and relatively simple to perform.

In this approach, we compare the output sets from application runs with and without a crash-recovery event, and if they match (and if the applications' outputs are sensitive to invariant violations), then we say that no violations occurred during the recovery.
This approach, however, suffers from several limitations:

* Outputs may not be directly comparable, and require additional processing, which may introduce its own errors (e.g. if the output is an unordered map, we would have to compare the two outputs a key at a time)
* Larger runs, with larger input and output sets, may take much longer to validate than they take to run. This presents a real problem when performing stress tests under heavy loads, as we would run into processing capacity limits when validating the results, and tests would take too long.
* Not all applications will experience a change in their output as a result of an invariant violation!
* There is no guarantee that no errors occurred and went undetected in the reference run.

The last two points are critical. If we cannot trust that an application's output will change if an invariant under test is violated, then the test resolution isn't good enough for our needs. And if the assumption that the reference run is error-free is unreliable, then we can't use a comparison with the reference run's output to conclude that the run under test produced an error-free output.

We need a test that can _guarantee_ that if any of the four possible violations to the invariant occur, it will show up in the output.

## The Micro Approach: A Streaming Test

An alternative to the batch test is a streaming test, where the output is validated in real time, as it is produced, message-by-message. Since Wallaroo is itself a stream processing engine, this approach lends itself to doing longer, heavier runs than the batch testing approach would allow for. If we can validate the output in real-time, we would not run into processing capacity limits during the validation phase of the test. This approach does, however, impose its own set of restrictions: it must be able to detect errors in _real time_ and, in order for this to work, the output must reflect any violations of the invariant under test.

Recall the state invariant violations being tested:

1. no _loss_ of updates
2. no _reordering_ of updates
3. no _corruption_ of updates or states
4. no _duplication_ of an update

In other words, we are testing that the state and its updates are _sequentially consistent_. And in order to test this on a stream, we need a way to tell, whenever a new output message arrives, whether it is the _right message at that time_.

That is, we want to be able to say, based on the last event, _X<sub>n</sub>_, what the subsequent event, _X<sub>n+1</sub>_ ought to be:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_X<sub>n+1</sub>_ = _F(X<sub>n</sub>)_

And then, on the first occurrence where

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_X<sub>n+1</sub>_ ≠ _F(X<sub>n</sub>)_

we can say that the test has failed.

It is important to be explicit here: this kind of test requires a deterministic output. We must be able to _know_, based on the last output message, what the next output message _ought to be_.

Once a test runs to completion without failing, we say that the test has passed.

To do this in Wallaroo, we need to build an application whose output would include a trace of the invariant violations, whose output will change—in a detectable manner—if state updates are _lost_, _reordered_, _corrupted_, or _duplicated_, and whose output can be tested using the sequential relationship defined above.

## Testing _Order_

In order to detect _reordering_, we need to know about the correct order. One way to achieve this is to use a priori knowledge about the input data's order. If we know that the input data follows a certain order and that the application preserves this order under normal conditions, then we can look for outputs that violate this order preservation as proof that the _ordering property_ has been violated.

For example, if the input data is the subset of natural numbers

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 2, 3, 4_

and the application only applies an _identity_ operation, then any output that _is not_ the set of natural numbers from _1_ to _n_, in ascending order, is an indication of an _ordering_ violation.

e.g. the ordered output

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 2, 3, 4_

is valid, but

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 3, 2, 4_&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">_reordering_</span>

is not, because it doesn't follow the same order as the sequence of natural numbers.
This is a pretty good start: we can write a basic streaming application that can act as a detector for _reordering_.

## Loss, Duplication, and Corruption

It turns out that the set of natural numbers lets us detect _lost updates_ and _duplicate updates_ as well. If an update is lost along the way between the input and the output, the output will no longer be the sequence of natural numbers. It will have gaps:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 3, 4, 5_&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">_loss_</span>

If an update is duplicated, we will see an entry appear more than once:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 2, 3, 2_&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">_duplication_</span>

And if an update or a state are corrupted, this will show as an entry _that couldn't possibly be produced by the application_:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_1, 2, 3, D_&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">_corruption_</span>

The same test will detect all three of these errors: _is the output a monotonically increasing sequence of integers from 1 to n, with an increment size of 1_?

Specifically, we can test this by applying the following rules to the _i-th_ output message, _K<sub>i</sub>_:

1. _K<sub>1</sub>_ = _1_
2. _K<sub>i</sub>_ = _i_. That is, the _i_-th value in the output sequence is equal to _i_.  
    <sub>Note that we use 1-based indexing.</sub>
3. There are _n_ total values in the output.

So we can use the set of natural numbers from 1 to n as an input, with an application whose output is reducible to the _identity_ operation, in order to test all four possible violations to the state invariant. That's pretty sweet!

But there's one thing still missing for this test to be effective: _state recovery_.

Since the identity application's output doesn't rely on any internal state, this test wouldn't reveal any errors in the recovery of stateful applications.

For example, if our application maintained the sum of all the numbers it has processed as its state, but only output the identity of its input, a failed recovery could go like so:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;_before failure_  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;input: _K<sub>5</sub>_ = _5_ &rarr; _State{ sum: 15 }; Output { 5 }_  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<< _failure_ >>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<< _recovery_ >> &rarr; _State{ sum: 0 }_  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;input: _K<sub>6</sub>_ = _6_ &rarr; _State{ sum: 6 }; Output { 6 }_  

In this case, even though recovery resulted in the application being able to resume processing, its state was incorrect (initialized back to _0_, instead of the last state before failure, _{ sum: 15 }_), but the output doesn't show it, and the test above would pass, despite the failure to correctly recover the state.

## Sequence Window: Adding State to the Natural Sequence

We want to keep the properties of the sequence test above so that it can be used as a streaming detector for the four violations to the state invariant, but we also want the test to detect errors in recovery. In order to do this, we can keep a memory—or a window—of the sequence, as the state, and instead of sending the identity of the current value as the output, we send out the latest window, after it has been updated with the latest value. To do this, we use a Wallaroo [StateComputation](https://docs.wallaroolabs.com/book/core-concepts/working-with-state.html#state-computations) that maintains a ring buffer of length _4_ (this size is somewhat arbitrary, but we find that _4_ is both long enough to "see what happened" and short enough to allow for quick skimming of an output set). The window is initialized with zeroes, and as new values arrive from the source, the oldest value is ejected, and the new value pushes the rest down.

This can be visualized as a fixed-size window that moves from left to right across the set of natural numbers, one position at a time. The underscored values represent the state, as the current window, _W<sub>k</sub>_, after the _k_-th event is processed:

![Sequence State Updates](/images/post/building-an-error-detector/sequence-state.png)

We can apply a similar test as before to the _i_-th value in the output set:

1. _W<sub>1</sub>_ = [0, 0, 0, 1]
2. The _i_-th window is  
	  [max(0, _i_-3), max(0, _i_-2), max(0, _i_-1), _i_]
3. There are _n_ total windows.

Now, if a process has crashed and recovered, and for some, reason it recovered a different state than the one it had immediately before crashing, it would fail condition 2.

For example, if the process was restarted, but the state was not recovered and took on the initial state of

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 0]

we may see a message such as

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 10]

Since the test operates on the assumption that the input is the sequence of natural numbers, we can determine that [0, 0, 0, 10] is not a valid output and say that the test has failed.

## Using Sequence Window Tests in Practice

To use the Sequence Window test setup in a Wallaroo crash-recovery test, we wrote a partitioned application that keeps a sequence window on ordered values partitioned with a modulo operator. Each partition is placed on a different worker, and we can crash individual workers or inject network faults between any pair of workers.

The logical test is adjusted for partitioned windows:

1. The incoming data is partitioned modulo _M_.
2. Each partition sends its data to a separate sink.
3. At a sink<sub>i</sub>, where _i_ is the _i_-th partition based on the modulo operation (_v_ % _M_ = _i_),
    1. The first window is [0, 0, 0, _i_]
    2. The _j_-th window is  
      [max(0, (_j_-3)*_M_+_i_), max(0, (_j_-2)*_M_+_i_), max(0, (_j_-1)*_M_+_i_), max(0, _j_*_M_+_i_)]


Across all sinks, at the end of the run:

1. There are n total windows
2. The highest value of all the windows is _n_
3. The highest value in each sink is either _n_, or _n_-_M_ + _i_.

For example, if we use two partitions, so that _M_ = 2, and send in the values {1, 2, 3, 4, 5, 6}, the following output would be valid:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 2]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Sink<sub>0</sub>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 2, 4]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 2, 4, 6]  

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 1]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Sink<sub>1</sub>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 1, 3]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 1, 3, 5]  

The following output, however, would fail the test:

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 2]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Sink<sub>0</sub>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 2, 4]  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 2, 4, 6]  

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 1]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Sink<sub>1</sub>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 3]&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span style="color:red">_loss_</span>  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 3, 5]  

since the output [0, 0, 0, 3] fails condition (2). In this case, we can infer that something happened to the state of the Odds partition after our application processed the value _k<sub>1</sub>_ = _1_ and before it processed the value _k<sub>3</sub>_ = _3_.

## And Does it Work?

You might be wondering whether this is all there is to a crash-recovery test. The setup seems really simple. Surely this can't be all there is to it, can it?  
In a way, this really is all there is to it. Simple is good.  
The sequence window application itself isn't the test, it is the error detector. And its simplicity means that tests that use it can also be simple in most cases.

For example, one of our simplest tests, where we test the failure of one worker in a two-worker cluster, using a modulo 2 partitioning, can be summarised as

1. start a data receiver (ongoing for the duration of the test)
2. start worker<sub>1</sub>
3. start worker<sub>2</sub>
4. start sending data (ongoing for the duration of the test)
5. crash worker<sub>2</sub>
6. restart worker<sub>2</sub>  
   << worker<sub>2</sub> recovers from log >>  
   << worker<sub>2</sub> receives replay from worker<sub>1</sub> >>  
   << worker<sub>2</sub> resumes processing new data >>  
10. wait until data sender sends all of the data
11. validate final output values

We still need to _execute_ the test. We need to orchestrate running the application workers, inject the failures, and inspect the outputs. We also need to ensure that the timing of events is correct in the tests, and that we covered all of the possible orderings of events; how we do that is a topic for another post.

Here are some of the bugs that were detected with the sequence window detector so far:

1. Recovery failed and the worker crashed when a connection was reconnected during the replay phase of the recovery process.  
    While this wasn't explicitly detected by the detector, it was encountered when running stress tests against both recovery and reconnection at the same time, using the sequence window detector application to detect any data corruption errors.
2. Deduplication code erroneously identified the outputs from a OneToMany computation (which produces multiple outputs as a result of one input) as duplicates during replay.  
    This bug resulted in certain messages being skipped during recovery from log, but not others. The data corruption errors that resulted were detected by the sequence window detector.
3. Event ID watermarks were erroneously reset to 0 after a worker recovery, instead of resuming from the previous watermark in the recovery log. If a subsequent failure event occurred before the watermark value increased above the previous highest level, then data re-sent from upstream workers would not be correctly deduplicated.  
    These data corruption errors were detected by the sequence window detector.
4. A pointer bug in a buffered writer's low-level implementation resulted in the first record written getting corrupted (but subsequent ones were fine).  
    This bug was detected by online validation during replay, since the transition from the state  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, 0]  
  to  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[0, 0, 0, \<random large number\>]  
  would always be invalid! We then verified that the error was being introduced by a bug in the buffered writer after manually decoding the resilience log file to ensure the value is already corrupt when it is saved to the log. Stepping through the program in a debugger revealed this to be the result of reading uninitialized data from a pointer in the buffered writer's implementation.

## Conclusion

As you may have guessed by now, this post isn't about the many tests we run, or about how we set up and orchestrate them; it is about a more fundamental element of our testing: _error detection_.

Error detection can be difficult, especially in complex systems—and distributed systems certainly are complex. So we wanted to make sure that we start this series with the basics.

Look forward to our future testing posts, where we discuss additional test scenarios, the limits of the sequence window detector and its generalization to non-linear topologies, and many more fun and obscure bugs!

In the meantime, why not check out the [recently open-sourced Wallaroo](/2017/09/open-sourcing-wallaroo) and its [documentation](https://docs.wallaroolabs.com/).

If you have any questions or feedback, you can find us on [our mailing list](https://groups.io/g/wallaroo) or on IRC in #wallaroo on [Freenode.net](https://webchat.freenode.net/).
