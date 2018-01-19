+++
title = "You might have a streaming data problem if..."
date = 2018-01-17T07:11:00-05:00
draft = false
author = "seantallen"
description = "When processing data, we often categorize a job as either a batch or streaming job. However, this is a bit of a false dichotomy. In this post, I’ll explore how we ordinarily define batch and stream processing, and show how some tasks that we think of as batch jobs can be seen as a subset of stream processing."
tags = [
    "stream processing",
    "batch processing"
]
categories = [
    "Stream Processing"
]
+++
When processing data, we often categorize a job as either a batch or streaming job. However, this is a bit of a false dichotomy. In this post, I’ll explore how we ordinarily define batch and stream processing, and show how some tasks that we think of as batch jobs can be seen as a subset of stream processing.

## Batch processing

The definition of batch processing has changed over time. The current conventional usage is some data transformation over a finite set of data. The finite nature of the data means that the job has a beginning and an end. 

An example would be, "I want to process all the logs that my web servers generated yesterday." 

Here we have a finite set of data: "all the logs my web servers generated yesterday." I can start processing those logs and eventually that task will finish. 

## Stream processing

In contrast to batch processing, stream processing commonly refers to data transformations that are done over an infinite set of data. Or, more realistically, once a stream processing system is turned on, there's no fixed end. It will keep processing data as it arrives until the job is turned off because it’s no longer needed.

## The missing "How"

While helpful for grounding conversations, these definitions overlook an essential aspect of batch and stream processing: how the data is processed. 

One of the characteristics of stream processing that is implicit in our definition is that we engage in "item-at-a-time" processing. What is item-at-a-time processing? It means that we process each piece of data, each item, as it arrives. An auction site that takes action for each bid as it arrives is practicing item-a-time processing. It's handling each bid placed event as it arrives, one bid a time. 

What's interesting is that many "batch processing" jobs are also "item-at-a-time" and are good candidates for processing by an "item-at-a-time engine." That is, a lot of batch jobs, with their finite set of data with a start and an end, make good stream processing jobs.

Let's take a look at a ubiquitous batch processing example, log file analysis.

## Log file analysis

Log file analysis is commonly thought of as a batch processing job because we have a finite, fixed set of data. We have some log files, covering a specific period of time, that we want to process. 

Log file analysis often involves taking each line of the log, examining it for different features, and updating aggregations of those features. For example, getting the geographic distribution of visitors over a given time frame. Or ranking the most popular pages on a website.

Note that I said our log analysis involves "taking **each** line of the log." Almost all log analysis is item-at-a-time. Instead of thinking of the problem as "take a bunch of files and process them," we can think of it as "process a stream of entries from logs."

## Recommendation engine

Recommendation engines are often item-at-a-time systems as well. A company wants to recommend a product to its customers. The goal is to get them interested in products they might not be aware of. 

Once again, there's a finite data set, in this case a list of customers that we want to generate recommendations for.

Every so often, perhaps daily or weekly, the company needs to generate new product recommendations that will be mailed to their customers. This fits under our earlier definition of batch processing: processing over a finite data set with a beginning and an end.

However, recommendations are done “per customer.” That’s “item-at-a-time.” Recommendations are generated for each customer independent of the suggestions for any other customer. That’s a streaming problem. 

Ok, so there are batch problems that are also streaming problems. Why would we want to use a stream processing engine instead of a batch processing engine? There are many reasons to consider a steam processing engine, but I want to focus on one: extracting value from your data sooner than you could with a batch engine.

## Unlock the value of your data sooner with stream processing

Let's take our product recommendation engine. If we treat it as a streaming problem, that means we could start generating recommendations in real-time. No need to wait for daily or weekly emails. We can begin to create and update recommendations, on the fly. We can generate them while a customer is on the website, while we already have their attention. Stream processing can take the data we have and unlock its value sooner. No need to wait for the next batch to run.

How about log analysis? What's the value of real-time log analysis? Well, that depends on you and your company. Off the top of my head, threat analysis immediately pops to mind. If your logs can be analyzed to look for malicious behavior, would you rather do that every day, every hour, or as it is happening?

## Wrapping up

The simple definitions that we started with set up batch and stream processing as being a binary choice. A job is either batch or its streaming. We’ve shown with a couple of examples that it isn’t a binary choice. Many tasks that we think of as batch processing jobs are also stream processing jobs because many batch jobs are a subset of stream processing.

Any batch job that loads and processes its dataset an item at a time is a subset of stream processing. Our finite, bounded batch data set is merely a window of time extracted from the theoretically infinite data set of a stream processing job.

Any data processing job where you operate on a single item at a time is a candidate to processed by a stream processing engine. Using a stream processing engine has many advantages, including the ability to extract value from your data in real-time.

## Let's talk

Over the last few years, I've spent a lot of time helping people turn their batch problems into streaming problems and unlock the value of their data. When I started, it was as an author of [Storm Applied](https://www.manning.com/books/storm-applied), a book about [Apache Storm](https://storm.apache.org/). Now, it's as the VP of Engineering here at [Wallaroo Labs](http://www.wallaroolabs.com/).

Got a data processing problem? Let's talk. We can cover your general problem or how [Wallaroo](https://github.com/wallaroolabs/wallaroo), the real-time streaming data platform that we've been building for [Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) and Go can help you.

My email is [sean@wallaroolabs.com](mailto:sean@wallaroolabs.com), and I'm looking forward to talking to you.
