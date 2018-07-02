+++
title= "Real-time Streaming Pattern: Preprocessing for Sentiment Analysis"
date = 2018-06-14T01:00:00-04:00
draft = false
author = "cblake"
description = "First in a series of posts looking at a variet of data processing patterns used to build real-time stream processing applications."
tags = [
    "wallaroo",
    "api"
]
categories = [
    "Wallaroo in Action"
]
+++

## Introduction
I am starting a series of posts looking at a variety of data processing patterns used to build real-time stream processing applications, the use cases that the patterns relate to, and how you would go about implementing within Wallaroo.

These posts will help you understand the data processing use cases that Wallaroo is best designed to handle and how you can go about building them right away.

I will be looking at the Wallaroo application builder, the part of your application that hooks into the Wallaroo framework, and some the business logic of the pattern.

## Pattern: Preprocessing

Preprocessing involves the transformation of the messages in your data pipeline.

A variety of operations can occur, including:

+ Removing attributes from a message
+ Adding or enhancing attributes in a messaging
+ Filtering out entire messages from a pipeline
+ Splitting messages to be processed by multiple pipelines
+ Combining multiple pipelines into a new pipeline

## Use Cases

It's not unusual to see the preprocessing pattern used in many use cases and combined with other patterns.

One excellent example use case is removing stop words for sentiment analysis.

Sentiment analysis is used by data scientists to look at a piece of text and determine whether the underlying sentiment is positive or negative.

Let's say you are monitoring tweets that mention Nike. You want to know how people are feeling about Nike.  Are the tweets and comments generally positive or negative?  "Nike has some great new looks this season" would be a positive sentiment. Each piece of text is given a score, and you can add up the score over some time, say the last hour, to get an overall sentiment score.

We will assume that upstream from our sentiment processor, so that we only have Nike related Tweets. The next step before doing the actual sentiment analysis is to remove [stop words](https://en.wikipedia.org/wiki/Stop_words).  Stop words are words that are meaningless to the underlying sentiment analysis and therefore can and should be removed before the sentiment algorithm runs.

Stop word lists are customized to the specifics of the use case but would include words like "are, aren't, as, at, be, because, been, has, I'm, it's, on, some, the, this."

In our example message above "@Nike has some great new looks this season" would become "@Nike great new looks season" after stop word preprocessing occurred. This isn't the easiest text for humans to read, but it is just how our sentiment algorithm wants to see it!

## Wallaroo Application Builder

### Overview

```python
ab.new_pipeline(
            "Sentiment Analysis",
            wallaroo.TCPSourceConfig(order_host, order_port, order_decoder)
        )
ab.to_parallel(remove_stop_words)
ab.to_stateful(sum_sentiment, Sentiment, "Sentiment")
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
return ab.build()
```

![Decoder -> remove_stop_words -> sum_sentiment -> Sink](/images/post/real-time-streaming-pattern-preprocessing-for-sentiment-analysis/image1.png)

```python
ab.new_pipeline(
            "Sentiment Analysis",
            wallaroo.TCPSourceConfig(order_host, order_port, order_decoder)
        )
```

Definition of the Wallaroo pipeline that includes the pipeline name, "Sentiment Analysis" and the source of the data, in this example we are receiving tweet messages over TCP.

```python
ab.to_parallel(remove_stop_words)
```

Our first processing step is to call a function called "remove_stop_words."  This function would look at the text of the tweet and strip out any instances of the stop words from our list, then send the processed message to the next step in the pipeline.

In this example, I am using the Wallaroo `to_parallel` method to add a computation to the pipeline.  The `remove_stop_words` function does not need to save anything to state, and the computation can run in parallel across all available workers.

```python
ab.to_stateful(sum_sentiment, Sentiment, "Sentiment")
```

`to_stateful` is a non-parallel method that contains a stateful computation. The `sum_sentiment` function tallies up the sentiment scores and stores the totals in the "Sentiment" state object. You could use a Python library like [NLTK](https://www.nltk.org/) to accomplish the sentiment analysis.

```python
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
    return ab.build()
```

`to _sink` specifies the endpoint of the pipleline and where the messages are sent. `build()` specifies to Wallaroo that there are no more steps for this application.


## Conclusion
The preprocessing pattern is one of the most commonly used patterns that you will come across when building your streaming application.  As you can see, Wallaroo's lightweight API gives you the ability to construct your data processing pipeline and run whatever application logic you need to power your application.

## Give Wallaroo a try
We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Wallaroo provides a robust platform that enables developers to implement business logic within a streaming data pipeline quickly. Wondering if Wallaroo is right for your use case? Please reach out to us at [hello@wallaroolabs.com](hello@wallaroolabs.com), and we’d love to chat.
