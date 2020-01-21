+++
title = "Implementing Time Windowing in an Evented Streaming System"
date = 2018-06-21T12:49:47-04:00
draft = true
author = "seantallen"
description = "A closer look at how you can do windowing in Wallaroo to implement applications like Twitter's trending topics."
tags = [
    "python",
    "use case",
    "windowing",
    "example",
    "twitter"
]
categories = [
    "Trending Twitter Hashtags",
]
+++
Hi there! Welcome to the second and final installment of my trending twitter hashtags example series. In [part 1](https://blog.wallaroolabs.com/2018/06/stream-processing-trending-hashtags-and-wallaroo/), we covered the basic dataflow and logic of the application. In part 2, we are going to take a look at how windowing for the "trending" aspect of our application is implemented.

When implementing any sort of “trending” application, what we are really doing is implementing some kind of windowing. That is, for some duration of time, we want to know what was popular, what was “trending” during that period of time. To do that, we need to implement an appropriate windowing algorithm. We’ll start by taking a look at a few different types of windowing and then proceed to dive into how windowing was implemented in our [Twitter Trending Hashtags example application](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags).

## Types of windowing

There are a few types of windowing that can be implemented, and it is crucial that we clarify the distinctions.

#### External event-based windowing

External event-based windowing is the most arbitrary kind of windowing. The boundaries of each window are determined outside of Wallaroo and can be triggered by any event. Event-based windowing is also the simplest kind of windowing to think about: when we are told that a window ends, we perform any end-of-window computation that our application requires, then we update the aggregate state to be ready for new events that arrive during the new window.

#### Internally triggered windowing

Internally triggered windowing is very similar to event-based windowing, except that the window is triggered from within the computation. Triggering is usually based on the internal state of the computation, and it is the responsibility of the computation itself to determine when a window has finished and when to start a new one. The code we will be looking at in this post is an example of internally triggered windowing.

#### Time-based windowing (Wall clock)

A new window is started at regular intervals based on the current wall clock. For example, every 5 minutes we start a new window. Time-based windowing is currently not supported in Wallaroo.

#### Time-based windowing (Event clock)

The time element is taken from information from the message rather than a timer, and windows are created accordingly. To implement this type of windowing, multiple windows have to be accumulated simultaneously as all events are not guaranteed to arrive during the same window. It's possible to implement event clock based windowing in Wallaroo in combination with internally triggered windowing.

## Windowing in Trending Twitter Hashtags

The windowing in our trending twitter hashtags code is an example of internally triggered windowing. Let's dive into the code and take a look at how it's implemented.

We have a state object class [HashtagCounts](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py#L70) that keeps track of counts for hashtags over a window of time. There are [multiple `HashtagCounts` state objects within the application](https://blog.wallaroolabs.com/2018/06/stream-processing-trending-hashtags-and-wallaroo/#the-guts), but for the rest of this post, we are only interested in how any individual instance works.

[`HashtagCounts`' `increment` method](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py#L78) is called [each time we intend to increment the count for a given hashtag](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py#L47).

```python
def increment(self, hashtag):
    """
    Increment the count for `hashtag`
    """
    mse = self.__minutes_since_epoch()
    window_gap = int(mse % TRENDING_OVER)

    # have we rolled over?
    if self.__window[window_gap][0] < mse:
        self.__rollover(hashtag, window_gap, mse)
    else:
        self.__increment(hashtag, window_gap)

    # did our top ten change?
    new_top_tags = self.__calculate_top_tags()

    if new_top_tags != self.__top_tags:
        self.__top_tags = new_top_tags
        return self.__top_tags.copy()
    else:
            return None
```

The core of our windowing logic is in the first few lines of `increment`:

```python
mse = self.__minutes_since_epoch()
window_gap = int(mse % TRENDING_OVER)

# have we rolled over?
if self.__window[window_gap][0] < mse:
    self.__rollover(hashtag, window_gap, mse)
else:
    self.__increment(hashtag, window_gap)
```

Alrighty, so what is going on here? The first thing to know is that we store our counts per hashtag on a per minute basis in the `__window` variable.  If our window is 5 minutes then `__window` would have a length of 5.

We need to determine if the current time is outside of an existing window or within a current window. First, we need to get which `window_gap` that our time is in. That is, which bucket in our `__window` array are we in. We do this by getting the minutes since the Unix epoch and then taking the modulus of that over our `TRENDING_OVER` time period:

```python
mse = self.__minutes_since_epoch()
window_gap = int(mse % TRENDING_OVER)
```

The [default value](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py#L8) of `TRENDING_OVER` is 5 minutes. So if our minutes since epoch was 31 and we are trending over 5 minutes, then our "window gap" would 1.

The question is, is that "window gap" current or is it a new window? That we address with this bit of code:

```python
# have we rolled over?
if self.__window[window_gap][0] < mse:
    self.__rollover(hashtag, window_gap, mse)
else:
    self.__increment(hashtag, window_gap)
```

So, what exactly are we storing in `__window` anyway? Without knowing that, the "have we rolled over" logic is pretty opaque. Each element in `__window` is a tuple. The tuple is:

```python
(minutes_since_epoch, map_of_hashtags_to_counts)
```

This is most clearly seen in our [`__rollover` method](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/parallel-twitter-trending-hashtags/twitter_wallaroo_app.py#L107):

```python
def __rollover(self, hashtag, gap, mse):
    self.__window[gap] = (mse, {hashtag: 1})
```

So, back to our "is this a new window" logic...

```python
# have we rolled over?
if self.__window[window_gap][0] < mse:
    self.__rollover(hashtag, window_gap, mse)
else:
    self.__increment(hashtag, window_gap)
```

When we check `self.__window[window_gap][0] < mse`, what we are checking is if the minutes since epoch stored in __window is less than the one we are currently processing. If yes, then we have worked our way around `__window`'s various indexes and are back at `window_gap` at a later point in time. When that happens, we want to roll over our window by getting rid of the existing data in our window gap and starting fresh with the hashtag we are processing:

```python
def __rollover(self, hashtag, gap, mse):
    self.__window[gap] = (mse, {hashtag: 1})
```

and if the minutes since epoch stored in __window isn't less than one we are currently processing, that means we are within the same minute window and should augment our current counts:

```python
def __increment(self, hashtag, gap):
    current_count = self.__window[gap][1].get(hashtag, 0)
    self.__window[gap][1][hashtag] = current_count + 1
```

And that is a complete windowing solution for our trending hashtags example app.

## Windowing, what's coming

Our approach with Wallaroo has been to provide programmers with core primitives for building event-by-event applications that give them the flexibility to implement the business logic their domain requires. Our current approach to windowing is an example of this. We have left windowing entirely in the hands of the Wallaroo user. You can implement any sort of windowing that is triggered by an event, from internally triggered, to externally triggered, to the handling of out of order or late arriving data.

We also know, that with this power and flexibility comes a cost. You have to implement windowing yourself, and for common use cases, it would be nice if Wallaroo provided APIs to make those common cases as easy as an API call. Such APIs (including time-based windowing) are on our roadmap. If you have interesting windowing use-cases, we'd love to talk to you. Talking to our users both current and future helps us build better solutions. Please, [get in touch](mailto:hello@wallaroolabs.com). And, in the meantime, we have the [Twitter Trending Hashtags code](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/parallel-twitter-trending-hashtags) available for you to clone, inspect, and play around with.
