+++
title = "Stream processing, trending hashtags, and Wallaroo"
date = 2018-06-06T18:00:00-04:00
draft = false
author = "seantallen"
description = "See how you can chain Wallaroo state computations together for build a Twitter trending hashtags application."
tags = [
    "use case",
    "python",
    "state",
    "example",
    "twitter"
]
categories = [
    "Wallaroo in Action", 
    "Trending Twitter Hashtags"
]
+++


A prospective Wallaroo user contacted us and asked for an example of chaining state computations together so the output of one could be fed into another to take still further action. In particular, their first step was doing aggregation.

Doing chained state computations is a general problem with many applications and is straightforward in Wallaroo. To illustrate the concepts using a realistic yet relatively easy to understand use-case I decided to go with an updated version of a previous blog post. Back in November of 2017, we published an example Wallaroo app that [identified top twitter hashtags in real-time](https://blog.wallaroolabs.com/2017/11/identifying-trending-twitter-hashtags-in-real-time-with-wallaroo/).

My example is a rewrite of the Wallaroo code that powers that example while keeping the supporting twitter client and flask-based web application intact. 

The original ["Trending Hashtags"](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/twitter-trending-hashtags) application differs in a few fundamental ways from our updated example.

First, the original application has no chained state computations. There's a single one. Second, it's not parallelized. There's a single hashtag finder instance and a single state object responsible for tracking the top hashtags.

## The guts

Here's the definition of the data pipeline from our original application:

![Diagram of original data pipeline](/images/post/twitter-trending-hashtags-pt1/old-pipeline.png)

```python
    ab = wallaroo.ApplicationBuilder("Trending Hashtags")

    ab.new_pipeline("Tweets_new", 
      wallaroo.TCPSourceConfig(in_host, in_port, Decoder() ))

    ab.to(HashtagFinder)

    ab.to_stateful(ComputeHashtags(), 
      HashtagsStateBuilder(), "hashtags state")

    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
```

`to` is a non-parallel stateless computation.
`to_stateful` is a non-parallel state computation

The serialized nature of the original example makes the logic very easy to follow but, will never be able to take advantage of parallelization of computation in Wallaroo.

Getting "top K" in a parallel fashion is straightforward but not something a lot of folks have experience with. What you want to do is break your "top" items into a series of smaller parallel aggregates. Creating many smaller parallel aggregates allows you to handle larger incoming streams of data. Each of those smaller aggregates can output its top K as it changes. These are then sent to a single, non-parallelized aggregate that takes the top K from all the smaller aggregates and manages a true "top K" listing. The assumption is that, for a given time window, there will be far fewer outputs from each "smaller aggregate" than the number of inputs to the start of the pipeline. This final aggregation is going to be a bottleneck. There's nothing we can do about that. Our problem requires it; we can, however, decrease the number of messages it receives by doing as much work as possible in parallel before it.

![Diagram of our new data pipeline](/images/post/twitter-trending-hashtags-pt1/new-pipeline.png)

In Wallaroo this would look like:

```python
    ab = wallaroo.ApplicationBuilder("Trending Hashtags")

    ab.new_pipeline("Tweets", 
      wallaroo.TCPSourceConfig(in_host, in_port, decoder))

    ab.to_parallel(find_hashtags)

    ab.to_state_partition(count_hashtags, HashtagCounts, 
      "raw hashtag counts", extract_hashtag_key, raw_hashtag_partitions)

    ab.to_stateful(top_hashtags, TopTags, "top hashtags")

    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
 ``` 
 
 Let's break that apart for folks who aren't familiar with how Wallaroo's [Application Builder API](https://docs.wallaroolabs.com/book/python/api.html#applicationbuilder) works.
 
We declare a new application called "Trending Hashtags":

```python
ab = wallaroo.ApplicationBuilder("Trending Hashtags")
```

That consists of a single data pipeline, "Tweets." This data pipeline will receive data from the Twitter firehose over TCP:

```python
ab.new_pipeline("Tweets", 
  wallaroo.TCPSourceConfig(in_host, in_port, decoder))
```

The incoming data will be routed to an instance of a parallelized stateless computation `find_hashtags`. `find_hashtags` will parse each tweet looking for hashtags:
 
```python
ab.to_parallel(find_hashtags)
```

Any hashtags found in the previous step are sent to a partitioned state computation called `count_hashtags`. Each partition has its own `HashtagCounts` object that we use to maintain a listing of hashtags seen and their count. Data partitioning in Wallaroo is controlled by the developer so we supply a list of valid partition keys (`raw_hashtag_partitions`) and a function that examines incoming hashtags and extracts a key from them `extract_hashtag_key`:

```python
ab.to_state_partition(count_hashtags, HashtagCounts, 
  "raw hashtag counts", extract_hashtag_key, raw_hashtag_partitions)
```

Whenever the "top K" for a given `raw hashtag counts` changes, a new message will be sent to our final step, a non-parallelized state computation (`top_hashtags`) that keeps a listing of the current top K hashtags in a state object `TopTags`. 

```python
ab.to_stateful(top_hashtags, TopTags, "top hashtags")
```

Whenever the `TopTags` managed by `top_hashtags` changes, a message is output with information about the top tags which is sent to our sink where it is sent out via TCP:

```python
ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
```

## Conclusion

All the code for our [Parallel Twitter Trending Hashtags](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags) example is available on GitHub. You can clone the code, [install your Python and Wallaroo dependencies](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags#installation), [supply your Twitter credentials](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags#configuration) and [run it](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags#running-instructions) to see it in action. 

The Wallaroo specific logic is all in a single file [twitter_wallaroo_app.py](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py). Feel free to dive in and check it out. In a couple of weeks, I'm going to publish a post about that looks at how the windowing used to determine trending works in this application.

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Wallaroo provides a robust platform that enables developers to implement business logic within a streaming data pipeline quickly. Wondering if Wallaroo is right for your use case? Please reach out to us at [hello@wallaroolabs.com](mailto:hello@wallaroolabs.com), we’d love to chat.
