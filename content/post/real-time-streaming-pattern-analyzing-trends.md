+++
title= "Real-time Streaming Pattern: Analyzing Trends"
date = 2018-08-23T19:42:35+00:00
draft = false
author = "erikn"
description = "This week, we continue to look at data processing patterns used to build event driven stream processing applications with Wallaroo. One of our most frequent use-cases is Analysing trends, either from third-party external or your internal data."
tags = [
    "use case"
]
categories = [
    "Wallaroo in Action"
]
+++

## Introduction

This week, we continue to look at data processing patterns used to build event triggered stream processing applications, the use cases that the patterns relate to, and how you would go about implementing within Wallaroo.

This purpose of these posts is to help you understand the data processing use cases that Wallaroo is best designed to handle and how you can go about building them right away.

I will be looking at the Wallaroo application builder, the part of your application that hooks into the Wallaroo framework, and some the business logic of the pattern.

You should also check out all the posts in the ["Wallaroo in Action"](https://blog.wallaroolabs.com/categories/wallaroo-in-action/) category.

## Pattern: Analyzing Trends

What makes stream processing different from alternatives like batch processing is that we continuously run our application logic over data as it comes in. Rather than running that logic in periodic intervals.

Similar to triggering alerts based on an event, sometimes you want to perform more detailed analysis on events in your application. We can all benefit from more monitoring or testing of user interface improvements.

Some specific examples could include:

- A/B testing
- Analyzing rage clicking in your application
- Determining infrastructure load based on user location
- Sentiment analysis of reviews for your product
- Updating the "Most Popular" filter for an e-commerce website

## Use Cases

In this post we continue to use Twitter's tweet api like in previous Wallaroo posts; [Real-time Streaming Pattern: Preprocessing for Sentiment Analysis](https://blog.wallaroolabs.com/2018/06/real-time-streaming-pattern-preprocessing-for-sentiment-analysis/) and [Identifying Trending Twitter Hashtags in Real-time with Wallaroo](https://blog.wallaroolabs.com/2017/11/identifying-trending-twitter-hashtags-in-real-time-with-wallaroo)

Like in the more detailed "Identifying Trending Twitter Hashtags in Real-time with Wallaroo" post, imagine we are creating an application showing the trending hashtags on Twitter.

The application itself requires only two computations. One to extract the hashtags in a tweet and a stateful computation to keep the count of hashtags.

## Wallaroo Application Builder

### Overview

```python
ab.new_pipeline(
            "Analyzing Trends",
            wallaroo.TCPSourceConfig(in_host, in_port, in_decoder)
        )
ab.to_parallel(extract_hashtags)
ab.to_stateful(compute_hashtags, HashtagState, "hashtags state")
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
return ab.build()
```
![Decoder -> extract_hashtags -> compute_hashtags](/images/post/real-time-streaming-pattern-analyzing-trends/image1.png)

```python
ab.new_pipeline(
            "Analyzing Trends",
            wallaroo.TCPSourceConfig(in_host, in_port, in_decoder)
        )
```
We define a new pipeline named `"Analyzing Trends"` and the source of the data, in this case it's coming from a socket over TCP.

```python
ab.to_parallel(extract_hashtags)
```

Our first computation, is on that in parallel calls `extract_hashtags`. Like other examples in the past `extract_hashtags` isn't modifying state and by calling `to_parallel` we're able to send the computation to all the workers available.

```python
ab.to_stateful(compute_hashtags, HashtagState, "hashtags state")
```

Takes a commutation, a state class, and a name. `HashtagState` describes how we would define our state. More information on [`State`](https://docs.wallaroolabs.com/book/python/api.html#state) in our documentation.

```python
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
return ab.build()
```

Lastly we tell Wallaroo the host and port to send the results. This could be another application listening on that host and port or a Kafka topic. In the case of our Twitter trending hashtags example, this data eventually was rendered on a webpage so the user could see the top 10 hashtags in real-time.

## Conclusion

There are many different use-cases for stream processing and I hope this provided a good overview on how you could go about integrating Wallaroo into your infrastructure.

If you're interested in running the example application from the [Identifying Trending Twitter Hashtags in Real-time with Wallaroo](https://blog.wallaroolabs.com/2017/11/identifying-trending-twitter-hashtags-in-real-time-with-wallaroo) example you can find the repository [here](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/8b91484b19e6b5a058e04b8f9448f979950f9ba3/twitter-trending-hashtags).

Wallaroo's lightweight API gives you the ability to construct your data processing pipeline and run whatever application logic you need to power your application.

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Wallaroo provides a robust platform that enables developers to implement business logic within a streaming data pipeline quickly. Wondering if Wallaroo is right for your use case? Please reach out to us at [hello@wallaroolabs.com](hello@wallaroolabs.com), and we’d love to chat.
