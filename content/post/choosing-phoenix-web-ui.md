+++
title = "Choosing Elixir's Phoenix to power a real-time Web UI"
date = 2018-04-12T15:00:38-04:00
draft = false
author = "jonbrwn"
description = "Why we chose Elixir's Phoenix to power Wallaroo's real-time metrics monitoring system."
tags = [
    "elixir",
    "phoenix",
    "metrics",
]
categories = [
    "Exploring Wallaroo Internals",
]
+++

Here at WallarooLabs, we've been working on [Wallaroo](https://github.com/wallaroolabs/wallaroo), our high-throughput, low-latency, and elastic data processing framework, for nearly two years now. An integral part of the development of a Wallaroo application is getting introspection to the performance characteristics of several of the components of that application.

What's a Wallaroo application? In its simplest form, a Wallaroo application accepts an incoming stream of data, processes computations on that data, and optionally outputs results of those computations. If you'd like a much deeper dive into a Wallaroo application's structure, I suggest reading our ["Hello Wallaroo!"](https://blog.wallaroolabs.com/2017/03/hello-wallaroo/) blog post.

A problem we needed to solve early on was deciding on the tooling that would power our metrics monitoring system. We needed our monitoring solution to provide real-time updates on the several steps a data message may take along the way within a Wallaroo application.

We looked at various tools for building out our metrics monitoring system but ultimately decided on using [Phoenix](http://phoenixframework.org/), a modern web framework, and by extension [Elixir](https://elixir-lang.org/), as our tooling of choice.

In this post, I'll take a deeper dive into our monitoring problem and how Phoenix and Elixir helped solve our specific issues.

## Deeper Dive into our Monitoring Problem

To provide more context around the problem we needed to solve, I want to provide a high-level overview of how a running Wallaroo application is monitored today.

Currently, a running Wallaroo application will gather throughput and latency metrics for its components and push them to what we call the Monitoring Hub. Why push instead of poll? We ended up choosing to push our metrics because it gave us [better performance](https://blog.wallaroolabs.com/2018/02/building-low-overhead-metrics-collection-for-high-performance-systems/#push-vs-poll), an important factor when building high-throughput, low-latency applications.

The Monitoring Hub is used as an intermediate step between a Wallaroo application and the Metrics UI to collect and aggregate the incoming metric messages. The Monitoring Hub then broadcasts these messages to any listening clients.

The Metrics UI uses information of connected Wallaroo applications to the Monitoring Hub to then connect to the metric channels for those applications and displays throughput and latency metric information for the various components of the running Wallaroo applications.

Here's a diagram to illustrate this setup:

![wallaroo-metrics-architecture](/images/post/choosing-phoenix-web-ui/wallaroo-metrics-architecture.png)

The biggest problem we needed to address was choosing tooling that would allow us to send and receive messages efficiently throughout our architecture. What drove us to Phoenix was its Channels abstraction.

## What are Phoenix Channels?

Phoenix Channels are based on the abstraction of sending and receiving messages in soft real-time. Senders broadcast messages about topics. Receivers subscribe to topics so that they can get those messages.[1](https://hexdocs.pm/phoenix/channels.html)

Channels are a layered system with a Transport layer, a Channel layer, and others. The [Transport](https://hexdocs.pm/phoenix/Phoenix.Socket.Transport.html) layer is an abstraction which sits between the socket and channels responsible for handling incoming and outgoing messages with clients. The [Channel](https://hexdocs.pm/phoenix/Phoenix.Channel.html) layer is responsible for communicating with the transport and for taking any action on incoming messages.

The biggest takeaway from the Channels abstraction is that Channels adhere to a specific protocol and thus senders and receivers can be anything that can implement communication via that protocol.


## Utilizing Phoenix Channels

We ended up utilizing Phoenix Channels as the communication layer between Wallaroo applications, the Monitoring Hub, and the Metrics UI. A Metrics topic exists to handle incoming metrics from running Wallaroo applications where each application has its own channel via a subtopic. These Metric channels are responsible for aggregating and storing incoming metric messages, as well as creating new topics to broadcast the aggregated metric messages.

The aggregated metric messages are broadcasted via component channels, where each component in a Wallaroo application has a channel and metrics are broadcasted down via a subtopic mapping of the component, application name, and component name. This allows for granular subscriptions to a Wallaroo application's metric channels from listening clients.

Concurrency is a huge part of how any of this can happen and thankfully Elixir handles concurrency really well considering Phoenix can handle [2 million WebSocket connections](http://phoenixframework.org/blog/the-road-to-2-million-websocket-connections).

## Flexible design of Channels

Another key benefit of Channels are the flexibility in their design. Phoenix ships with WebSocket and long-polling transport layers for channels and provides an API which can be implemented to add your own Transport layer.

WebSockets were perfect for communication between the Monitoring Hub and the Metrics UI given that it's the industry standard for real-time communication over HTTP, but provided little benefit to the communication between Wallaroo and the Monitoring Hub.

We chose to take advantage of the flexible design around the Transport layer and create a [TCP Transport](https://github.com/WallarooLabs/phoenix_tcp) for communication between Wallaroo and the Monitoring Hub. It was an added bonus for us to be able to remove the need for an HTTP server within Wallaroo just to handle the metrics messages.

Flexibility for the Serializer by Channel also provided a huge benefit for us. JSON, the default serialization option, ended up having a performance impact in Wallaroo. Switching out to a binary protocol alleviated that impact, and we were still able to use JSON for the outgoing messages for the Metrics UI.

These additional benefits provided by the flexible design of Channels allowed us to move forward quickly while still maintaining all of the functionality we expected.

## Drawback of Phoenix Channels

Although the Channels abstraction provided us a lot of benefits and allowed for quick development, we should mention a drawback we had run into. We ended up polluting how we shape our outgoing metric messages to adhere to the protocol provided by Phoenix Channels. This presented itself more obviously when we were sending messages via JSON where we needed to adhere to the following message structure:

```
{
    "topic": "metrics:my-app",
    "event": "metrics",
    "payload": {...},
    "ref": null
}
```

This means if we ever wanted to send our metrics messages to another system we'd have to do some work to get them to work for both or we'd have to support one or the other at a given time.
This is not the worst problem to have but one we know we'd eventually have to address.

## Benefiting from Elixir

It would be negligent of us not to mention some of the benefits that we gained from Phoenix being written in Elixir. If you aren't familiar with Elixir, it is a dynamic, functional language that runs on the Erlang VM. Although these weren't immediately apparent at first, they became invaluable pros to our choice of Phoenix.

### Concurrency

Since Wallaroo is designed to be a high-throughput, low-latency, framework, the metrics monitoring system needed to be able to handle the many incoming metric messages without becoming a bottleneck and impacting the performance of a running Wallaroo application. Due to Phoenix being written in Elixir, it takes full advantage of the [OTP](http://learnyousomeerlang.com/what-is-otp) framework, a set of modules and standards designed to help build concurrent applications.

By also utilizing OTP along with Phoenix's use of OTP we were able to process, store, aggregate, and broadcast metric messages without a single process becoming a bottleneck.

### Failing Gracefully

There's a reasonable expectation that something will go wrong in communicating systems. Whether it's something like receiving a completely wrong message or a message of a wrong format, we needed a way to handle these types of scenarios without the Monitoring Hub completely falling apart.

There were two scenarios we needed the Monitoring Hub to handle: errors we expected and errors that would cause things to crash.

In dealing with errors we expected, wrong message type, unprocessable message, etc., it was easy to use `ok/error` tuples to guard in those scenarios. Michal Muskala wrote a great blog post on [Error handling in Elixir Libraries](http://michal.muskala.eu/2017/02/10/error-handling-in-elixir-libraries.html) if you want to look at some of the techniques that can be used in this scenario. These techniques allowed us to move forward without further processing of that message beyond its point of failure and without causing a halt to the rest of the incoming messages.

In the scenario where we ran into unexpected errors, we felt best to follow the ["Let it Crash"](http://verraes.net/2014/12/erlang-let-it-crash/) motto that Erlang is known for. This helped ensure that an unexpected failure wouldn't propagate all the way back up to the socket level and cause a backup of incoming messages and thus become a bottleneck for Wallaroo.

## Conclusion

In the end, we've been happy with the benefits provided by Phoenix and Elixir to power our metrics monitoring system. The Channels abstraction exceeded our needs and allowed for rapid development of this system.

The [Monitoring Hub](https://github.com/WallarooLabs/wallaroo/tree/master/monitoring_hub) and the [Phoenix TCP Transport](https://github.com/WallarooLabs/phoenix_tcp) layer are both open source, feel free to take a look at the codebases for each and give feedback if you'd like.

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!


