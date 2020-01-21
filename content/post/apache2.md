+++
title = "Wallaroo goes full Apache 2.0"
date = 2018-10-03T12:00:00-04:00
draft = true
author = "seantallen"
description = "In which we announce that Wallaroo is now 100% open source"
tags = [
    "open source",
    "announcement",
]
categories = [
    "announcement"
]
+++
I'm writing today to announce that with the [release of Wallaroo 0.5.3](https://github.com/WallarooLabs/wallaroo/releases/tag/0.5.3), we have switched our licensing over to a pure open source model.

What does all this mean for you? Well, if you are a current Wallaroo user, you get all the features you've been using plus no limit on the numbers of CPUs your application can use. Previously, you had to get a license from us if you were using more than 24 cores to run Wallaroo. That is no longer the case. There are no limits.

If you are a new Wallaroo user, you don't need to get lawyers involved to understand the licensing. It's just the familiar Apache 2 license you already know and love.

This is an exciting moment for us, and I want to share with you a bit about what it means and where Wallaroo is headed. In the rest of this post, I'll...

- bring folks who haven't heard of Wallaroo up to speed on [what Wallaroo is](#what-is-wallaroo)
- give a quick overview of [why we made this licensing change](#why-we-open-sourced-all-of-wallaroo) (if you love to argue about software licenses on the Internet - who doesn't? - this is the section for you!)
- give you an idea of [what is coming](#what-s-coming) from us (including many open source features that are on the way)
- try to get you to [download wallaroo](#give-it-a-try) and give it a spin (we really hope you do this, its kind of why we wrote this post)

If you are familiar with what Wallaroo is, you can skip the next section "What is Wallaroo?" and proceed straight to "[Why we open sourced all of Wallaroo](#why-we-open-sourced-all-of-wallaroo)."

## What is Wallaroo?

Wallaroo is an elastic data processing engine. We’ve designed Wallaroo to make it [easy to scale applications with no code changes and allow programmers to focus on business logic](https://vimeo.com/270509076). If you are familiar with the “Big Data” landscape, Wallaroo falls into the “streaming data” category along with tools like Apache Flink and Apache Storm. That should help you triangulate in general where Wallaroo falls as a tool but there is more to Wallaroo than that. For example, a recent use case has been to help a scale some [event-driven Pandas workloads](https://blog.wallaroolabs.com/2018/09/make-python-pandas-go-fast/).

So what sets Wallaroo apart from similar tools? Well, there are some deep technical reasons, but the short answer would be: Python. We aim to make Python a first-class citizen in the data processing world. With Wallaroo, you get a high-performance runtime with an embedded Python interpreter. Our approach gives you performance that is better than you'd get by writing everything in pure Python while maintaining compatibility with all the Python libraries you love.

Hopefully, you have a decent feel for that Wallaroo is by now. If not, here are few example use cases that a tool like Wallaroo is good for:

- [Scaling Pandas with Wallaroo](https://blog.wallaroolabs.com/2018/09/make-python-pandas-go-fast/)
- [Event triggered customer segmentation](https://blog.wallaroolabs.com/2018/07/event-triggered-customer-segmentation/)
- [Chatbot spam detection](https://blog.wallaroolabs.com/2018/07/detecting-spam-as-it-happens-getting-erlang-and-python-working-together-with-wallaroo/)
- [Detecting trends in data streams](https://blog.wallaroolabs.com/2018/06/stream-processing-trending-hashtags-and-wallaroo/)
- [Still more...](https://blog.wallaroolabs.com/categories/wallaroo-in-action/)

Interested in learning more? Our GitHub repo is a [good place to start](https://github.com/wallaroolabs/wallaroo), as is the [developer section](https://www.wallaroolabs.com/developers/) of our website.

## Why we open sourced all of Wallaroo

The straightforward answer is: we think this is the right thing to do for Wallaroo and its users. If that is good enough answer for you, feel free to skip the rest of the section.

Last August, when we prepared to open source Wallaroo, we were more concerned with "how do we support the development team we are paying to build Wallaroo" than "how do we build a community around Wallaroo." We didn't realize that at the time, but looking back it's clear to me that we were.

We adopted an open core model for Wallaroo and made most of Wallaroo open source under the Apache 2 license, but held some back as "source available" under a commercial license where the source code was freely available.

The features we kept under our enterprise license were scaling related features. If you wanted to use Wallaroo on more than 24 CPUs, you needed to pay us money. Upon reflection, that was a mistake. Wallaroo is about making scaling easy. We locked the core value proposition of the product behind a commercial license and tried to build an open source community. It feels silly and foolish when I write it now; I wish it had felt silly and foolish back then.

Today, we are rectifying that mistake and redrawing the line so that everything in [our Wallaroo monorepo](https://github.com/wallaroolabs/wallaroo) is now available under the [Apache 2.0 license](https://github.com/WallarooLabs/wallaroo/blob/f99792dc5072a4606207dbd2de2bcdb18e9ba546/LICENSE).

We hope that with clearer, better licensing that we can grow the community around Wallaroo more quickly than we were before. We are proud of what we are building and want to get more people using it. We don't want an "unusual" license scaring folks off.

## What we are releasing under the Apache 2.0 license

All of it. Everything that we had previously held back? It's all under the Apache 2.0 license now.

All of Wallaroo is yours to use without limitation.

The Python framework API? Apache 2.0.
Testing tools? Apache 2.0.
Metrics UI? Apache 2.0.
New Connectors API? Apache 2.0.
Scaling to the heavens? Apache 2.0.

You get the idea.

In the end, you aren't just getting the "old" features. We released everything in [our latest release](https://github.com/WallarooLabs/wallaroo/releases/tag/0.5.3) under Apache 2.0 as well. There's some awesome stuff in that release. You should check out [the release notes](https://github.com/WallarooLabs/wallaroo/releases/tag/0.5.3).

I'm particularly excited by the preview release of the [Connectors API](https://docs.wallaroolabs.com/book/python/using-connectors.html) that allows you to write [sources and sinks](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) in Python (or any other language).

## What's coming

### Python 3

Need we say more? Python 3 has been our number one requested feature for a while.

Big shout out to [Caj Larsson](https://github.com/caj-larsson) who [started the Python 3 work](https://github.com/WallarooLabs/wallaroo/pull/2354) that engineers at Wallaroo Labs picked up this week and plan on getting into preview release availability over the next few weeks.

### General Availability release for Connectors

With the release of Wallaroo 0.5.3, we added a preview release of our [Connectors API](https://docs.wallaroolabs.com/book/python/using-connectors.html). Connectors allow you to write Wallaroo sources and sinks in any language. Our primary focus will be on supporting folks writing them in Python, but the underlying protocol allows for any language to be used.

Over the next few months, we look forward to getting your feedback on the Connectors API and pushing it towards general availability and API stability.

### Windowing API

Wallaroo's lower level API is quite powerful and allows the programmer to express a wide variety of streaming data patterns. Amongst them is windowing.

You [can do windowing now](https://blog.wallaroolabs.com/2018/06/implementing-time-windowing-in-an-evented-streaming-system/), but there is no "Wallaroo supplied Windowing API." We feel that windowing is an essential part of streaming patterns. Over the coming months, we plan to make it a first class citizen in our API.

### Enterprise Support

Selling support for open source software is a well-understood business model. Are you using Wallaroo and looking for support? We are putting together a package of offerings that are available now and will evolve it over time. Need help running Wallaroo in production? Need help designing and building your Wallaroo application? We're here and ready to help you succeed! Feel free to drop us a line any time at [sales@wallaroolabs.com](mailto:sales@wallaroolabs.com).

## Give it a try

Hopefully, I've gotten you excited about Wallaroo and our roadmap over the next few months. We'd love for you to give it a try and give us your feedback. Your feedback helps us drive the product forward. Thank you to everyone who has contributed feedback so far and thank you to everyone who does after reading this blog post. Y'all rock!

[Get started with Wallaroo now!](https://docs.wallaroolabs.com/book/getting-started/choosing-an-installation-option.html).
