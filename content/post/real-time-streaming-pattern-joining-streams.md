+++
title= "Real-time Streaming Pattern: Joining Event Streams"
date = 2018-07-26T01:00:00-04:00
draft = false
author = "cblake"
description = "Looking at data processing patterns used to build event triggered stream processing applications, the use cases that the patterns relate to, and how you would go about implementing within Wallaroo."
tags = [
    "wallaroo",
    "api",
    "example"
]
categories = [
    "Wallaroo in Action"
]
+++

## Introduction

This week I will continue to look at data processing patterns used to build event triggered streaming applications.  I'll cover some related use cases and how you would go about implementing within Wallaroo.

This purpose of these posts is to help you understand the data processing use cases that Wallaroo is best designed to handle and how you can go about building them.

I will be looking at the Wallaroo application builder, the part of your application that hooks into the Wallaroo framework.

Check out my previous posts examining streaming patterns: [Triggering Alerts](https://blog.wallaroolabs.com/2018/06/real-time-streaming-pattern-triggering-alerts/) and [Preprocessing for Sentiment Analysis](https://blog.wallaroolabs.com/2018/06/real-time-streaming-pattern-preprocessing-for-sentiment-analysis/).

## Pattern: Joining Event Streams

The joining event streams pattern takes multiple data pipelines and joins them to produce a new signal message that can be acted upon by a later process.

This pattern can is used in a variety of use cases.  Here are a few examples:

+ Merging data for an individual across a variety of social media accounts
+ Merging click data from a variety of devices (e.g. mobile and desktop) for an individual user
+ Tracking locations of delivery vehicles and assets that need to be delivered
+ Monitoring electronic trading activity for clients on a variety of trading venues

## Use Case
A good example is one that we've looked at in previous Wallaroo posts; [Identifying Loyal customers for segmentation](https://blog.wallaroolabs.com/2018/07/event-triggered-customer-segmentation/).  

For the purpose of this post, I’ve simplified the use case and adapted the application builder code. 

The simplified use case is as follows: an email promotion is sent to the individual who clicks on an ad if they have been identified as a loyal customer.

This use case requires two event streams.  One that ingests records for identified loyal customers and saves them to a state object.  The second ingests a stream of click data.  When an identified loyal customer performed an incoming click, that ad click will trigger an email with the promotion.

## Wallaroo Application Builder

### Overview

![Decoder -> save_loyal_customer](/images/post/real-time-streaming-pattern-streaming-joins/image1.png)
<center>Application Diagram</center>


```python
ab = wallaroo.ApplicationBuilder("Joining Streams Example")

ab.new_pipeline("Loyal Customer Stream", wallaroo.TCPSourceConfig(ll_host, ll_port, ll_decoder))
ab.to_state_partition(save_loyal_customer, LoyaltyCustomers, "loyalty customers", extract_customer_key)
ab.done()
    
ab.new_pipeline("Click Stream",wallaroo.TCPSourceConfig(cc_host, cc_port, cc_decoder))
ab.to_state_partition(check_loyal_click, LoyaltyCustomers, "loyalty customers", extract_customer_key)
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, cc_encoder))
return ab.build()
```
<center>Wallaroo Application Builder Code</center>


Check out the [Wallaroo API reference](https://docs.wallaroolabs.com/book/python/api.html#applicationbuilder) for detailed information about the application builder and computation options.

Now let's break down and describe the individual lines of the application builder.

---

```python
ab.new_pipeline("Loyal Customer Stream", wallaroo.TCPSourceConfig(ll_host, ll_port, ll_decoder))
```

Defines the Wallaroo pipeline including the pipeline name, "Loyal Customer Stream" and the source of the data.

---

```python
ab.to_state_partition(save_loyal_customer, LoyaltyCustomers, "loyalty customers", extract_customer_key)
```

This step is a stateful partition that calls a function `save_loyal_customer`. Since this is a partitioning step, the data for a specific customer would be routed automatically by Wallaroo to where the state object for that customer lives. The partition routing is executed via `extract_customer_key`.

---

```python
ab.new_pipeline("Click Stream",wallaroo.TCPSourceConfig(cc_host, cc_port, cc_decoder))
```

Defines the Wallaroo pipeline including the pipeline name, "Click Stream" and the source of the data.

---

```python
ab.to_state_partition(check_loyal_click, LoyaltyCustomers, "loyalty customers", extract_customer_key, initial_partitions)
```

This step makes use of the same stateful partition that was defined in the previous step, but calls a function `check_loyal_click` that will check to see if the customer who performed the click is indeed a loyal customer.

This is the way that you implement joining in Wallaroo, by having a computation in each pipeline that makes use of a shared state object. Each of these computations will interact with the state object and perform the required join logic.

---

```python
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, cc_encoder))
```

In the last step, we will pass data out of Wallaroo for further processing.  In this case we will only pass along messages for loyal customers to be processed by an email server external to Wallaroo.

---

## Conclusion
The joining streams pattern is used frequently when building streaming data applications and since Wallaroo allows you to implement any joining logic you require for the join, it is a very powerful model.

## Give Wallaroo a try
We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Wallaroo provides a robust platform that enables developers to implement business logic within a streaming data pipeline quickly. Wondering if Wallaroo is right for your use case? Please reach out to us at [hello@wallaroolabs.com](hello@wallaroolabs.com), and we’d love to chat.




