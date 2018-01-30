+++
title= "Why we wrote our Kafka Client in Pony"
date = 2018-01-30T12:00:00-04:00
draft = false
author = "dipin"
description = "Why we wrote our Kafka Client in Pony instead of relying on the existing C Kafka Client and creating bindings for it. We talk about the pros/cons of our decision and how far we've come including some preliminary performance numbers."
tags = [
    "wallaroo",
    "kafka",
    "pony"
]
categories = [
    "Kafka Client"
]
+++
At [Wallaroo Labs](http://www.wallaroolabs.com/) we've been working on our stream processing engine, [Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release) for just under two years now. We recently introduced our [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/) to complement our [Python API](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) and to make Wallaroo available to a wider range of programmers. Over the last few months we've been working to allow programmers to easily use Kafka as both a sink and a source for data processing applications regardless of the language they’re working in. This blog post shares the story of why we ended up writing our own Kafka client from scratch in Pony instead of wrapping the existing librdkafka C client in order to achieve this goal.

## Wallaroo and Kafka
### Wallaroo's and Kafka's and tough choices

With Wallaroo, [our goal](https://github.com/wallaroolabs/wallaroo#what-is-wallaroo) has been to make it as easy to build fast, [scale-independent](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/) applications for processing data. Wallaroo is written in a language called [Pony](https://www.ponylang.org/discover/#what-is-pony). In order to enable development flexibility we provide APIs to create applications using [Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) or [Go](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/). Whatever your favorite language is, Wallaroo enables you to focus on your business logic, not your infrastructure. Out of the box, Wallaroo already supports two types of sources and sinks: TCP and Kafka, with more planned. To achieve the best possible performance, Wallaroo sources and sinks are written in Pony. In addition, we are actively working on other approaches to give Wallaroo developers the ability to write sources and sinks in other languages like Python and Golang, which we will cover in future posts.

We knew from day one that [Kafka](https://kafka.apache.org/) support was going to be critical. Kafka, developed originally at [LinkedIn](https://engineering.linkedin.com/27/project-kafka-distributed-publish-subscribe-messaging-system-reaches-v06), is a critical component of modern big data architectures that lets you publish and subscribe to streams of records in a fault tolerant way. It replaces a more traditional message queue system and allows for processing of these streams of records in realtime as they occur. Internally, Kafka stores data in logs that are split into partitions to allow for parallelism. It distributes these partitions across a number of replicas allowing for fault tolerance and redundancy. You can learn more about Kafka on their excellent [introduction page](https://kafka.apache.org/intro). Kafka is written in Java and has clients available in a variety of languages in addition to the official Java client.

We knew going in that we couldn't rely on the official Java client available for Kafka. As mentioned, Wallaroo is written in Pony, and Pony does not run in the JVM. What Pony does give us are some impressive [qualities](https://blog.wallaroolabs.com/2017/10/why-we-used-pony-to-write-wallaroo/) that are critical to achieving our goals such as [easy](https://www.ponylang.org/discover/#pony-is-memory-safe), [reliable](https://www.ponylang.org/discover/#deadlock-free) and [low-overhead](https://www.ponylang.org/discover/#native-code) concurrency with [data safety](https://www.ponylang.org/discover/#data-race-free). While Pony has an excellent C foreign function interface, embedding the JVM wasn't a practical option due to the overhead involved. That left us with two choices, use the existing C client ([librdkafka](https://github.com/edenhill/librdkafka)) via FFI or write our own client from scratch in Pony. We chose to write our own from scratch and the rest of this blog post is about why we created the [Pony Kafka client](https://github.com/WallarooLabs/pony-kafka) and its current state.

### Costs... Benefits... Tradeoffs...

We left off the story at having a choice between using librdkafka from Pony via FFI or writing a Kafka client from scratch. The are a lot of positives about librdkafka. It is [feature rich](https://github.com/edenhill/librdkafka#overview), [high performance](https://github.com/edenhill/librdkafka/blob/master/INTRODUCTION.md#performance), battle tested, well maintained, officially supported by Confluent, the backbone of a number of Kafka clients in [other languages](https://github.com/edenhill/librdkafka#language-bindings) and used for mission critical data processing applications. Using it would have given us an amazing Kafka client relatively quickly with low maintenance overhead, albeit with the risk of high costs to enhance the client if we ever needed to ourselves.

There are, however, a couple of architectural concerns between how librdkafka and Pony work. Pony is based on the [actor model](https://en.wikipedia.org/wiki/Actor_model) of [concurrency](https://www.ponylang.org/discover/#every-actor-is-single-threaded) and asynchronous message passing and processing is a fundamental part of the language and its runtime. While librdkafka internally uses multiple threads to fetch and send data to Kafka brokers asynchronously, its interface with [applications is synchronous](https://github.com/edenhill/librdkafka/blob/master/INTRODUCTION.md#threads-and-callbacks) and requires regular polling. The other concern was the aforementioned threads internal to librdkafka, since both Pony and librdkafka have their own internal thread pools there was concern that they would end up thrashing CPU resources to the detriment of both.

Writing our own Kafka client from scratch presented some challenges that we needed to address. The code would be new and not battle tested and it would take significantly longer to implement a fraction of the features already available in librdkafka. Additionally, the maintenance costs for our implementation would be much higher than with librdkafka, although adding in new features could be easier. On the other hand, we would be able to work with Pony - Wallaroo's native language - while making effective use of the language’s features and runtime to have a truly asynchronous Kafka client. Performance would be, in theory, comparable to librdkafka due to Pony’s focus on being a high performance language and compiling down to machine code. We would also get all the data safety and easy concurrency features of Pony to allow us to iterate on the code faster. Lastly, we would avoid the risks related to the potential thread pool contention between Pony and librdkafka.

We still weren't sure which route to take so we decided to do a proof of concept using librdkafka to get a feel for using it via [Pony’s FFI](https://tutorial.ponylang.org/c-ffi/). Unfortunately, we didn't get very far; not due in any way to librdkafka's API or Pony's FFI. We simply kept running into the pain of trying to marshall all of the C objects to Pony along with the impedance mismatch of having to poll librdkafka regularly. In all honesty, it *felt wrong*.

So, we started exploring the Kafka protocol in more detail and decided that it was straightforward enough that we could have a proof of concept Pony Kafka client working relatively quickly, so we built that. The PoC  barely worked, but it worked, and was relatively painless to build at about 1 week of effort. After that experience, we took a good look at how long we thought creating a more fully featured Kafka client in Pony would take (doubled that estimate) and compared that option with the alternative of using librdkafka via the FFI. We evaluated both options in the context of [Wallaroo's goals](https://github.com/wallaroolabs/wallaroo#what-is-wallaroo) and realized that the polling required to use librdkafka would eventually become a performance bottleneck. Additionally, we knew the thread pool contention would eventually rear its ugly head at the most inopportune time (because isn't that always when things go wrong?). We decided to bite the bullet, realizing that we were wading into the deep end, and decided that for us, the long term payoff was worth the strategic investment to write a Kafka client from scratch in Pony.

### Results... good, bad, and ugly

Today, we’ve spent about 12 weeks of implementation effort and we have a fully asynchronous standalone Kafka client written in Pony - which we couldn't have done without relying on the excellent C and Java clients for inspiration. Based on a rough back of the envelope estimate, we probably have about 30% - 35% API coverage as compared to the Java client with a core consumer/producer API working for Kafka 0.8 - 0.10.2. The biggest things we’re missing are the high level/group consumer, security (via SSL/SASL), and the new features added since Kafka 0.11.0 such as message format version 2 and the exactly once semantics built around the new format. Then there are the “nice to have” items such as metrics, testing, documentation and dynamic configuration changes. Implementing the rest of the API and some of the “nice to have” items (not including testing and documentation) is probably another 4 weeks - 8 weeks or so of effort. Testing and documentation will take longer and will likely be ongoing due to the nature of the work.

When it comes to performance, the Pony Kafka client has lived up to our expectations thanks to compiling down to native code and Pony’s [zero copy message passing](https://dl.acm.org/citation.cfm?doid=3152284.3133896). Looking at the [unscientific results](https://github.com/WallarooLabs/pony-kafka/issues/30#issuecomment-360353969) of running our [performance application](https://github.com/WallarooLabs/pony-kafka/tree/master/examples/performance) that is similar to [librdkafka’s performance application](https://github.com/edenhill/librdkafka/blob/master/examples/rdkafka_performance.c) shows how things turned out. Pony Kafka sends data to Kafka about 5% - 10% slower than librdkafka but reads data from Kafka about 75% slower than librdkafka. Pony Kafka is at the moment mostly unoptimized, so we have the ability to squeeze out further performance gains and achieve parity with the C client. Some of these gains would be performance tuning of hot code paths, others would be based on enhancements to Pony and/or its standard library or under the hood changes to the client to allow for things like multiple connections to a single broker. This would enable us to split the workload across multiple actors (and threads as a result) to avoid CPU bottlenecking or more intelligent data structures/algorithms for internal logic to keep everything synchronization free between connections.

Wallaroo uses Kafka just as any other application would. The way Wallaroo sources and sinks work is that they abstract away the details from the Wallaroo application developer. All that is required is to use the KafkaSource or KafkaSink in Wallaroo and give the appropriate command line arguments that are required (similar to how the TCPSource and TCPSink require the host and port). Wallaroo performance when using the Pony Kafka client hasn’t been measured yet.

All in all, we've learned a lot during this process, not only about Kafka but also Pony, which has led us to improving Pony along the way. We still have a huge amount of work left to do but overall, we're happy with the decision we made.

Pony Kafka today has the following features:

* Basic/low level Consumer API
* Producer API with batching and rate limiting
* Wallaroo has integrated it via its KafkaSource and KafkaSink
* Support for the Kafka protocol from version 0.8 - 0.10.2 and compatibility with brokers and both the C and java clients (based on our limited testing)
* Support for message formats V0 and V1
* Compression support
* Throttling/backpressure to slow down producers if needed
* Message delivery reports
* Logging and error handling
* Partial support for leader failover (the logic is mostly implemented and needs testing/hardening)
* A relatively minimal amount of testing
* Performance comparable to librdkafka in some cases ([details here](https://github.com/WallarooLabs/pony-kafka/issues/30#issuecomment-360353969))

The following features are what Pony Kafka doesn't have yet: (but we plan on adding in the near future)

* Full test suite ([GH #27](https://github.com/WallarooLabs/pony-kafka/issues/27))
* Full support for leader failover handling ([GH #47](https://github.com/WallarooLabs/pony-kafka/issues/47) and [GH #12](https://github.com/WallarooLabs/pony-kafka/issues/12))
* Message Format V2 (introduced in Kafka 0.11.0) ([GH #13](https://github.com/WallarooLabs/pony-kafka/issues/13))
* Idempotence/transactions/exactly once semantics ([GH #14](https://github.com/WallarooLabs/pony-kafka/issues/14) and [GH #15](https://github.com/WallarooLabs/pony-kafka/issues/15))
* Statistics/metrics ([GH #18](https://github.com/WallarooLabs/pony-kafka/issues/18))
* Message interceptors ([GH #46](https://github.com/WallarooLabs/pony-kafka/issues/46))
* Security (SSL/SASL/etc) ([GH #16](https://github.com/WallarooLabs/pony-kafka/issues/16) and [GH #17](https://github.com/WallarooLabs/pony-kafka/issues/17))
* Dynamic configuration changes ([GH #7](https://github.com/WallarooLabs/pony-kafka/issues/7))
* High level/group consumer and offset management ([GH #20](https://github.com/WallarooLabs/pony-kafka/issues/20))
* Better logging and error handling ([GH #23](https://github.com/WallarooLabs/pony-kafka/issues/23) and [GH 19](https://github.com/WallarooLabs/pony-kafka/issues/19))
* Comprehensive documentation ([GH #26](https://github.com/WallarooLabs/pony-kafka/issues/26) and [GH #45](https://github.com/WallarooLabs/pony-kafka/issues/45))


We're going to continue our work to make Pony Kafka into a high quality client that maintains feature parity with existing mainline clients. Wallaroo is already using the client and we even have some [example applications](https://github.com/WallarooLabs/wallaroo/tree/master/examples) that you can try out that use Kafka. Or you can play with one of the [Pony Kafka example applications](https://github.com/WallarooLabs/pony-kafka/tree/master/examples) instead.

Our Pony Kafka client is new and so is its integration with Wallaroo, so we are actively looking for ways to improve both. We would love to hear from you if you have any ideas, want to help with our implementation or share your experience with trying out Pony Kafka and/or Wallaroo. Please don’t hesitate to get in touch with us through [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo). We also have a short (30 seconds) [survey](https://wallaroolabs.typeform.com/to/PkC7iT?source=blog) that will help us learn more about the people who are interested in using the Pony Kafka client with Wallaroo, so if that's you then I'd encourage you to go fill it out.

We built Wallaroo and the Pony Kafka client to help people create applications without getting bogged down in the hard parts of distributed systems. We hope you'll take a look at our [GitHub repository](https://github.com/wallaroolabs/wallaroo) and get to know Wallaroo to see if it can help you with the problems you're trying to solve. And we hope to hear back from you about the great things you've done with it.
