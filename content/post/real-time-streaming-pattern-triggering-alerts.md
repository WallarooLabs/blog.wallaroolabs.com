+++
title= "Real-time Streaming Pattern: Triggering Alerts"
date = 2018-06-28T01:00:00-04:00
draft = false
author = "cblake"
description = "This week, I will continue to look at data processing patterns used to build event triggered stream processing applications, the use cases that the patterns relate to, and how you would go about implementing within Wallaroo."
tags = [
    "use case"
]
categories = [
    "Wallaroo in Action"
]
+++

## Introduction

This week, I will continue to look at data processing patterns used to build event triggered stream processing applications, the use cases that the patterns relate to, and how you would go about implementing within Wallaroo.

This purpose of these posts is to help you understand the data processing use cases that Wallaroo is best designed to handle and how you can go about building them right away.

I will be looking at the Wallaroo application builder, the part of your application that hooks into the Wallaroo framework, and some the business logic of the pattern.

You should also check out my previous post [Real-time Streaming Pattern: Preprocessing for Sentiment Analysis](https://blog.wallaroolabs.com/2018/06/real-time-streaming-pattern-preprocessing-for-sentiment-analysis/), which describes how to use Wallaroo to clean up data so that it ready for later processing stages.


## Pattern: Triggering Alerts

When you think about event triggered applications, sending an alert based on an event is one of the first things to come to mind.

The triggering alerts pattern involves monitoring a stream of even data and triggering some action when a threshold is reached.

You see this pattern implemented in a variety of applications.  Some examples include:

+ Monitoring server infrastructure CPU utilization and sending an alert if a particular server's utilization goes above 90%
+ Monitoring an IoT device that tracks temperature for a zone in an office building and sending an alert if it is too warm or too cold
+ Monitoring a credit card transaction and sending an alert if the transaction appears fraudulent.

You might want to trigger an alert when:

+ A raw threshold is reached (alert if over 100 degrees)
+ A threshold based on a time window is reached (if latest reading is > average of the last 5 minutes)
+ A particular rate of increase or decrease is noticed (previous reading is up 10% compared to 5 minutes ago)

Part of the power of Wallaroo is that we allow you to implement any logic you need to accomplish your business objectives; there is no new API or programming model to learn, you implement your business logic in Python or Golang.



## Use Cases

A good example is triggering an alert when an odd temperature reading is received from a thermostat located in an office building.

In this example, I will be looking at a series of events that represent the temperature of a particular room and trigger an alert if there temperature exceeds some threshold.

For this example we will assume that our Wallaroo cluster is receiving a data stream of temperature readings via Kafka and that the data contains a device_id, zone_id, and temperature reading for each message received.

For any given zone, we will keep the last 500 readings in Wallaroo’s in-memory state and trigger an alert if the latest temperature reading is outside of three standard deviations or if the latest temperature is above 89 degrees.

## Wallaroo Application Builder

### Overview

```python
ab.new_pipeline("Temperature Alerts",
                    wallaroo.DefaultKafkaSourceCLIParser(decoder))
ab.to_state_partition(check_tempature, ZoneTotals, "zone totals",
        partition, zone_partitions)
ab.to_sink(wallaroo.DefaultKafkaSinkCLIParser(encoder))
return ab.build()
```

[Wallaroo application builder reference](https://docs.wallaroolabs.com/book/python/api.html#applicationbuilder)

![Decoder -> check_tempature -> Sink](/images/post/real-time-streaming-pattern-triggering-alerts/image1.png)


```python
ab.new_pipeline("Temperature Alerts",
                    wallaroo.DefaultKafkaSourceCLIParser(decoder))
```

Defines the Wallaroo pipeline including the pipeline name, "Temperature Alerts" and the source of the data, in this example we are receiving messages from a Kafka topic.

```python
ab.to_state_partition(check_tempature, ZoneTotals, "zone totals",
        partition, zone_partitions)
```

The only processing step in this example is a stateful partition that calls a function `check_tempature`. Since this is a partitioning step, the data for Zone A would be routed automatically by Wallaroo to where the state for Zone A resized, the same fr ones B...Z etc. The partition routing is defined in `zone_partitions` and executed via `partition`.

When the message is routed to the correct partition, the state object `ZoneTotals` would be updated with the latest tempature reading, then the `check_tempature` function would run to execute our business logic.

```python
ab.to_sink(wallaroo.DefaultKafkaSinkCLIParser(encoder))
```

If an alert was triggered in the previous step a message would be generated and passed along to the Kafka sink.


## Conclusion
Triggering alerts is one of the most common patterns you will see when thinking about and building event-triggered applications.

As you can see, Wallaroo's lightweight API gives you the ability to construct your data processing pipeline and run whatever application logic you need to power your application.
