+++
title= "Announcing our new connector APIs"
date = 2018-10-16T19:42:35+00:00
draft = false
author = "erikn"
description = "We're excited today to introduce you to a preview release of a new Wallaroo feature: Connectors. Connectors make inputting and receiving data from Wallaroo even easier than before."
tags = [
    "announcement",
    "python"
]
categories = [
    "announcement"
]
+++

## Introduction

We're excited today to introduce you to a preview release of a new Wallaroo feature: Connectors. Connectors make inputting and receiving data from Wallaroo even easier.

In this post, we'll briefly go over what Wallaroo is, the role connectors now play as Sources and Sinks for Wallaroo, how to get started with connectors, and talk about what is coming next.

If you're familiar with what Wallaroo is feel free to [skip the next section](#sources-and-sinks).

## What is Wallaroo

Wallaroo is a framework designed to make it easier for developers to build and operate high-performance applications written in Python. It handles the complexity of building distributed data processing applications so all that you need to worry about is the domain logic.

Our goal is to make sure regardless of where you data is coming from you can scale your application logic horizontally. All while removing the challenges that otherwise come with distributed applications.

## Sources and Sinks

There are a few pieces of terminology that I would like to go over before we continue.

Here's a high level diagram of how data moves from an external source through Wallaroo to an external sink:

![high-level-overview](/images/post/connectors/high-level-image.png)

There are two terms that may be new to you that I'll mention quite a bit in this blog post. An external source is the application that sends Wallaroo data from an external system; this can also be considered the input. An external sink is the application Wallaroo sends data to or the output. Currently every pipeline needs a Source and a Sink.

## Overview

With our 0.5.3 release last month, we released a preview of our new Connector APIs. Before when you wanted to write a Source or Sink, we didn't provide a recommended way to encode/decode your data to and from Wallaroo. This led to the user needing to come up with a protocol to serialize their data.

The preview release of these new APIs includes a new Python module containing a set of simple abstractions. Connectors are swappable. You can switch your data source from one type to another by changing the connector. Nothing about your Wallaroo application has to change. You can even use other Python libraries, like Wallaroo applications you aren't constrained to which additional libraries you can use.

![high-level-overview](/images/post/connectors/connectors.png)
Each blue square is a separate OS process

The Connector APIs and Wallaroo don't make any assumptions on how you are communicating with your external data sources. Connectors can be run on the same machine or a separate machine from your Wallaroo application. This is because Connectors are a separate OS process and communicate to Wallaroo via TCP.

## Templates and Starting Points

Along with these new APIs, we've written some example Connectors. These are designed to be copied and pasted as Python applications and started like scripts. You can use these starting points either from the Wallaroo repository or bring them into your own repository and modify them to fit your needs. Take a look at our [Connector documentation](https://docs.wallaroolabs.com/book/python/using-connectors.html) to learn more.

```Python
connector = wallaroo.experimental.SinkConnector(
    required_params=[], optional_params=[])
```

The new APIs include an easy way to pass additional arguments to your Connector scripts. These can either be passed in as required or optional parameters. See ["Running Connector Scripts"](https://docs.wallaroolabs.com/book/python/using-connectors.html#running-connector-scripts) for more information.

The examples we have provided are [Kafka](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/kafka_source), [Redis](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/redis_subscriber_source), [RabbitMQ](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/rabbitmq_source), [UDP](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/udp_source), [S3](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/s3_bucket_sink), and [Kinesis](https://github.com/WallarooLabs/wallaroo/blob/0.5.3/connectors/kinesis_source). Use these as starting points for your Sources and Sinks. We really appreciate any feedback you provide and your feedback will help shape our APIs as we look to release these. When writing a Connector feel free to use other Python libraries as well.

Additionally we have a PostgreSQL template that demonstrates how to use the postgreSQL `LISTEN/NOTIFY` API to pass change events to Wallaroo. This template requires a little more specific logic to get working but should be a great example on how to get started.

## Conclusion

To Summarize:
  - Connectors can use any other additional Python libraries
  - Connectors are separate OS processes to your Wallaroo application
  - The new APIs provide an easier abstraction around the original TCP Connector
  - How your data sources and the Connectors communicate is up to you. This could be something like JSON or a custom protocol.

We're continuing to develop these APIs, so look for developments in the next few releases.

If you're interested in giving the new APIs a try, see the available examples [here](https://github.com/WallarooLabs/wallaroo/tree/0.5.3/connectors) and our [Connectors documentation](https://docs.wallaroolabs.com/book/python/using-connectors.html). While this is a preview release of Connectors, please let us know if you thoughts or feedback. The best way is either via [IRC](https://webchat.freenode.net/?channels=#wallaroo) or our [mailing list](https://groups.io/g/wallaroo).

If you're looking to get started with Wallaroo for the first time, you can install Wallaroo via docker:

```
docker pull \
  wallaroo-labs-docker-wallaroolabs.bintray.io/release/wallaroo:latest
```

Other installation options can be found [here](https://docs.wallaroolabs.com/book/getting-started/choosing-an-installation-option.html).


Thank you to my co-workers Andy and John who helped me outline and proof-read this post.
