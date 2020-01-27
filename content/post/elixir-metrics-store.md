+++
title = "Utilizing Elixir as a lightweight tool to store real-time metrics data "
date = 2018-08-15T13:00:00-00:00
draft = false
author = "jonbrwn"
description = "How we use Elixir to store and aggregate Wallaroo's metrics for end-user consumption."
tags = [
    "elixir",
    "phoenix",
    "metrics",
]
categories = [
    "Exploring Wallaroo Internals"
]
+++


Visibility into performance bottlenecks was the driving force behind the design of Wallaroo's Monitoring Hub and Metrics UI. We wanted to provide tooling for users to be able to observe their application as it performed in real-time and provide enough introspection for them to make adjustments to their applications based on what they were seeing; whether that was adding additional workers to distribute a high workload or rewriting a computation to be more efficient. Being able to pre-empt potential bottlenecks would allow our users to take advantage of some of the features Wallaroo has to offer.

While designing the Monitoring Hub and Metrics UI we envisioned a lightweight tool that users can run alongside their applications in a development or production environment. In choosing the tooling to create the Monitoring Hub and the Metrics UI, Elixir had a lot of features that made it stand out as a viable choice. While Phoenix channels, an abstraction of sending and receiving messages in soft real-time, were the motivation behind the decision, we wanted to leverage the Elixir ecosystem as much as possible as part of this project.

In the past, we talked about ["Choosing Elixir's Phoenix to power a real-time Web UI"](https://blog.wallaroolabs.com/2018/04/choosing-elixirs-phoenix-to-power-a-real-time-web-ui/), which gave an in-depth look into why we chose Phoenix to power Wallaroo's Monitoring Hub and Metrics UI. In this post, we'll go a bit more in-depth to cover how we took advantage of Elixir to store, aggregate and broadcast Wallaroo's metric messages for end-user consumption.

Before we dive into how we use Elixir to manage Wallaroo's Monitoring Hub and Metrics UI, we wanted to give a bit of background on Wallaroo's metric messages and the information we wanted to convey.

## Breaking down Wallaroo's metric messages

Wallaroo emits metric messages for the following categories of a running application:

- **Pipeline Stats:** Reported for every pipeline within an application. Calculated as the time a message was received in Wallaroo to its completion as defined by the pipeline. A pipeline's total stats is an aggregation of each worker reporting stats for the said pipeline.

- **Worker Stats:** Reported for every worker that is part of an application. Calculated as the time a message was received on a worker to its completion or hand off to another worker. Reported for every pipeline running on a worker. A worker's total stats is an aggregation of each message passing through on this worker for all pipelines.

- **Computation Stats:** Reported for every computation run within an application. Calculated as the time it takes for said computation to complete for a given message. Reported by every worker running said computation. A computation's total stats is an aggregation of each worker reporting for a given computation.

Each metric message belongs to one of the above categories and also contains additional information regarding which worker and which pipeline it belongs to. This information is useful because it allows us to break down stats with even more granularity, like the stats for a computation on a particular worker.

We chose a fixed bin histogram as the way to transport metric messages from Wallaroo to the Monitoring Hub. Each bin represents the power of 2 of nanoseconds for the index of the bin, from 0 to 64. The value of each bin is how many messages fell within the timeframe that bin represents for a given period. If you care to learn more about the decision behind this format, Nisan wrote an excellent blog post ["Latency Histograms and Percentile Distributions In Wallaroo Performance Metrics"](https://blog.wallaroolabs.com/2018/02/latency-histograms-and-percentile-distributions-in-wallaroo-performance-metrics/) covering just that.

Due to how we designed Wallaroo's metric capturing system, Wallaroo's metrics are collected and sent from different steps of the Wallaroo system. This means it is up to the receiving system to combine those messages together in order to get a complete picture of the metrics for a given Wallaroo component.

## Information we want Wallaroo's metric messages to convey

Although a decent amount of information could be pulled out of the histogram provided by Wallaroo, we didn't want our end users to be extracting that information. Instead, we decided on a few core statistics we felt would be valuable in spotting potential bottlenecks.

- **Latency:** the amount of time it takes to process an individual event, measured as the percentile of the latency for a sample of events.
- **Throughput:** a count of events (as defined by their category) processed per second.

### Latency Stats

Latency metric stats are calculated for our last 5 minutes time window and represent the `50th Percentile Bin`, `90th Percentile Bin`, `95th Percentile Bin`, `99th Percentile Bin`, and `99.9th Percentile Bin`. Each `Percentile Bin` represents the upper limit of the bin that x percent of calculated latencies fall within. We also provide a `Percentage by Bin` graph. This graph combines histogram values across a set of key bins to give a quick overview of performance in relation to bins that we find meaningful to the user.

### Throughput Stats

Throughput metric stats are calculated for our last 5 minutes time window, and we provide the `minimum`, `median`, and `maximum` throughput observed. We also provide a `Throughput per Second` graph of the median for the last 5 minutes, which can be used to quickly see if there has been a spike in performance.

If you'd like a deeper dive into the design decisions behind the metric collection system on Wallaroo's side, have a look at our ["Building low-overhead metrics collection for high-performance systems"](https://blog.wallaroolabs.com/2018/02/building-low-overhead-metrics-collection-for-high-performance-systems/) blog post.

Now that we covered how we receive data and how we want to represent it to our end users let's have a look at how we used Elixir to make this possible.

## Storing Wallaroo's Metric Messages

### Storing Metric Messages in ETS Tables

Since we designed the Metrics UI for short-term monitoring, we didn't feel that investing in a time series database made sense. A few members on the team who had previous experience with Erlang suggested Erlang Term Storage (ETS) tables, an efficient in-memory database included with the Erlang virtual machine, as they felt they fit our needs for storing Wallaroo's metric messages.

The design idea behind ETS is described very well in ["The Concepts of ETS"](https://learnyousomeerlang.com/ets#the-concepts-of-ets) section of "Learn You Some Erlang":

   - "The main design objectives ETS had was to provide a way to store large amounts of data in Erlang with constant access time and to have such storage look as if it were implemented as processes in order to keep their use simple and idiomatic."

Each component of a running Wallaroo application has an ETS table to store its latency metrics and another to store its throughput metrics. We opted to use multiple tables for the two types of metrics to avoid access contention to the data.

### Implementing a Sliding Time Window Data Store

Wallaroo's Metrics UI was designed to show a rolling 5-minute window of an application's metrics. Due to this, we didn't want to hold on to Wallaroo's metric messages past a certain point and decided to discard old messages once we no longer needed them. We took advantage of the `ordered_set` type of ETS tables to do this. By using timestamps as keys and having them automatically ordered them in ascending order, we implemented a function to remove stale messages each time we added or read data from the ETS tables to keep them up to date. Effectively, turning our ETS tables into sliding time window data stores.

Although the `ordered_set` type provides slower access time O(log N) where N is the number of objects stored) in comparison to other table types, by setting a limit on the messages we store per ETS table, we know our access time should never grow to a point where it impacts performance.

### Managing our ETS Tables with GenServers

We decided to use Elixir's [GenServer](https://hexdocs.pm/elixir/GenServer.html), a behaviour module for implementing the server of a client-server relation, as the server to our ETS client code. The benefit of this decision was that it abstracted the access to our ETS tables and allowed us to use common access code throughout our codebase. If for some reason we decided to switch out ETS tables for another data store, little or none of the public facing GenServer code will have to change.

If you'd like to have a complete look into how we store and retrieve metric messages from ETS tables, have a look at our [MonitoringHubUtils.MessageLog](https://github.com/WallarooLabs/wallaroo/blob/0.5.1/monitoring_hub/apps/monitoring_hub_utils/lib/monitoring_hub_utils/message_log.ex).

## Aggregating Wallaroo's Metrics

Since we want to show metric stats for the last 5-minutes, we need a way to aggregate the metrics we store for that time window. We implemented a process for each stat for each Wallaroo component that would periodically pull the latest stats from the ETS table for a given component and run specific calculations on them.

### Aggregating Latency Stats

We created a [`LatencyStatsCalculator`](https://github.com/WallarooLabs/wallaroo/blob/0.5.1/monitoring_hub/apps/metrics_reporter/lib/metrics_reporter/latency_stats_calculator.ex) to aggregate and calculate specific latency stats. The end goal of this calculator is to take a list of histograms for a 5 minute window and calculate the `50th Percentile Bin`, `90th Percentile Bin`, `95th Percentile Bin`, `99th Percentile Bin`, and `99.9th Percentile Bin` for a specific set of bins that we feel are meaningful to the user.

### Aggregating Throughput Stats

We created a [`ThroughputStatsCalculator`](https://github.com/WallarooLabs/wallaroo/blob/0.5.1/monitoring_hub/apps/metrics_reporter/lib/metrics_reporter/throughput_stats_calculator.ex) to aggregate and calculate the `min`, `med`, and `max` throughput for a 5-minute window for a given component. Additionally, we send down the throughput for each second for each component for the last 5-minute window.

Utilizing multiple processes for the stats aggregation allows us to take advantage of Elixir's concurrency and parallelism, giving us the ability to both receive and broadcast messages simultaneously.

Now that we have our metrics information configured for end-user consumption, we need a way to get it to them in real-time.

## Broadcasting Wallaroo's Metrics

We utilize the channel feature of Elixir's Phoenix in order to broadcast our newly formed metric messages from the Monitoring Hub to the Metrics UI. The processes which calculate the metric stats for Wallaroo all run on an interval and once each stat is calculated it is broadcasted to the appropriate channel. The benefit of doing a broadcast is that any application or process listening on that channel can receive metric messages.

Although currently, only the Metrics UI is listening for these messages, there is an opportunity for other exciting things to be done with these messages by other tools, such as:

- monitoring a worker's throughput and adding or removing worker's if the throughput reaches a specific threshold.
- monitoring latency and sending alerts if a specific SLA is exceeded.

## Wallaroo's Metric Message Flow

The diagram below gives a full overview of how Wallaroo's metric messages flow through Elixir for our [Celsius](https://github.com/WallarooLabs/wallaroo/blob/0.5.1/examples/python/celsius/README.md) example application:

![monitoring hub metrics message flow](/images/post/elixir-metrics-store/metrics-message-flow.png)

Wallaroo's metric messages arrive via a Metrics Channel. The messages are then divided by component and stored as latency and throughput messages into ETS tables via the Message Log process. On the initial message for a given component, latency stats, throughput, and throughput stats aggregator/broadcaster processes are created which will read the last 5-minutes of data at an interval and broadcast via channels specific to that component and metric stats type.

## Wallaroo’s Metrics in Action

Now that you have background on how we used Elixir to store, aggregate, and broadcast Wallaroo's metric messages, feel free to spin up a Wallaroo application and our Metrics UI to see it all in action!

![metrics ui dashboard](/images/post/metrics-ui.gif)
