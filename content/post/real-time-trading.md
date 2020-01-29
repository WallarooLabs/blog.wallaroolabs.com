+++
title = "Real-time Streaming Pattern: Fast Algorithmic Trading Checks"
slug = "streaming-with-wallaroo-fast-algorithmic-trading-checks"
date = 2018-05-23T07:30:00-04:00
draft = false
author = "cblake"
description = "In this post, we will be going through the Wallaroo Market Spread example in detail and talk about the use case that inspired it."
tags = [
    "use case"
]
categories = [
    "Wallaroo in Action"
]
+++

## Introduction

Many of you have been reading our engineering blog and enjoy our deep technical dives. You know that we are excited to talk about how we are going about building Wallaroo, hard distributed systems problems, our approach to testing etc.

We think that a another great way to introduce developers to Wallaroo and get them inspired and considering how to apply our technology to their particular use cases is by jumping right in and digging into some examples.

The Wallaroo [repo](https://github.com/WallarooLabs/wallaroo) contains several example applications that give you an idea of how Wallaroo works and how to build out topologies to handle specific use cases.

If you don’t see an example that fits your needs, or if you have any questions about implementation or Wallaroo best practices, please reach out to us.  We enjoy speaking with development folks about use cases and how Wallaroo can help.  Email us  to get the conversation started. [hello@wallaroolabs.com](mailto:hello@wallaroolabs.com).

In this post, we will be going through one such example in detail and talk about the use case that inspired it. Currently, we have both Python and Go APIs, this blog post covers the Python version.

The Python version can respond within a millisecond. For much lower latencies, check out our Golang version which can respond in under 100 microseconds.

Before we step through the use case, we’ll give you a little background on Wallaroo, feel free to skip the next section of you are already familiar with it.

## What is Wallaroo

Wallaroo is a modern framework that makes it simple to build, deploy, and scale data applications that react to events in real-time.

Writing stateful streaming applications in Wallaroo is easy.  We like to say that Wallaroo makes it as easy as writing a Python script!

Wallaroo manages streaming data applications with state on a distributed infrastructure for the application programmer. This allows Wallaroo applications to run on any number of workers without having to make any code changes.  We generally refer to this as ["scale-independent" computing](https://vimeo.com/270509076).

## Background on This Case Study

In the early days of Wallaroo Labs, we were working closely with a large bank on a variety of use cases within their electronic trading division.

Electronic trading requires fast and reliable processing of trade requests and push them out to the various exchanges as quickly as possible.  This is why much of the infrastructure used for electronic trading is located as physically close to the trading venue as possible and runs on custom built hardware that is tuned to get the maximum performance.

You want to minimize any work that happens between the trade request and trading venue.

For this reason, even though applications that support the trading activity need to run at high volumes and low-latency, they are generally not placed in the execution path of the trade where latency would be introduced.

Generally, these supporting applications run in parallel to the execution path and will read messages off the common messaging bus infrastructure, [TIBCO Messaging](https://www.tibco.com/products/tibco-messaging) is one such messaging bus that is commonly used.

## Market Spread

The Market Spread application is based on one of these supporting applications.  Its purpose is to track the current state of the market and incoming orders and generate a warning alert if a particular order violates some risk criteria.

The example code for Market Spread can be found [here](https://github.com/WallarooLabs/wallaroo/tree/0.4.3/examples/python/market_spread).

Our market spread application uses the same risk criteria for all clients in our system.  The alert is generated when a trade happens on an instrument that is trading with the particular bid and ask prices.

The bid and ask represent what the security is currenty trading at. The bid is the maximum price that someone is willing to pay for a security, the ask is the minimum price that someone is willing to sell the security for.

Two data feeds are being consumed and analyzed by our Wallaroo application.  Each feed is fed into their own pipeline and they share a state object between them, “symbol-data.”

The first is market data.  This is a data stream that simulates the latest prices for the financial instruments that the application will track.  The data is in a "FIX-like" format which approximates the standard data format used for trading.

When the Market Spread application receives a market data message, and state object is stored with the latest bid/ask price for that symbol along with a flag that signifies if the spread is considered "risky" for our set of clients.

The second data feed is "orders."  These messages simulate the trades. When our application processes these messages, it uses the symbol for that trade and looks up the latest state object for that symbol. The trade is considered risky (the risk flag is on) an alert message is generated and sent to an external system.

## Application Builder

Now that you have a general idea of how the application works let's take a look at the Wallaroo application builder.

Wallaroo's application builder defines the application's topology and is a great way to get a high-level idea of how the app works.

```python
ab = wallaroo.ApplicationBuilder("market-spread")
ab.new_pipeline(
            "Orders",
            wallaroo.TCPSourceConfig(order_host, order_port,
                                     order_decoder)
        )
ab.to_state_partition_u64(
            check_order, SymbolData, "symbol-data",
            symbol_partition_function, symbol_partitions
        )
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port,
                                  order_result_encoder)
        )
ab.new_pipeline(
            "Market Data",
            wallaroo.TCPSourceConfig(nbbo_host, nbbo_port,
                                     market_data_decoder)
        )
ab.to_state_partition_u64(
            update_market_data, SymbolData, "symbol-data",
            symbol_partition_function, symbol_partitions
        )
ab.done()
return ab.build()
```



Pipelines start with a call to new_pipeline that includes the "source" of the data and end with a call to either a sink or "done" (when the data processing is complete.)

This application has two pipelines, "Orders" and "Market Data."

Each pipeline has a beginning, end, and one computation. The respective beginnings look like this:

```python
ab.new_pipeline(
            "Orders",
            wallaroo.TCPSourceConfig(order_host, order_port,
                                     order_decoder)
        )
```

```python
ab.new_pipeline(
            "Market Data",
            wallaroo.TCPSourceConfig(nbbo_host, nbbo_port,
                                     market_data_decoder)
        )
```

The pipeline has a stateful partition computation and shares a stateful object called "symbol-data."


```python
ab.to_state_partition_u64(
            check_order, SymbolData, "symbol-data",
            symbol_partition_function, symbol_partitions
        )
```

```python
ab.to_state_partition_u64(
            update_market_data, SymbolData, "symbol-data",
            symbol_partition_function, symbol_partitions
        )
```

Both pipelines use the [to_state_partition_u64](https://docs.wallaroolabs.com/book/python/api.html) function, and since they are making use of the same state object, through the "symbol-data" parameter, the parameters are the same except for the computation.

For stateful partitioning you can either use to_state_partition or to_state_partition_u64.  The to_state_partition_u64 expects an unsigned 64-bit data type as a key, which provides better performance.

For the market data pipeline, the state is updated by executing the [update_market_data](https://github.com/WallarooLabs/wallaroo/blob/0.4.3/examples/python/market_spread/market_spread.py#L197) function.  The update logs the last bid and ask price for a particular symbol and sets a true/false flag based on if the security violates our global trading constraint.

For the orders pipeline, the state is read by executing the "check_order" function, and a "rejected order" message is generated and passed along if the order should be rejected.
