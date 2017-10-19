+++
title = "How Wallaroo Scales Distributed State"
slug = "how-wallaroo-scales-distributed-state"
draft = true
date = "2017-10-19T15:20:13-05:00"
tags = [
    "wallaroo",
    "scaling",
    "scale-independence",
    "partitioning"
]
categories = [
    "Autoscaling",
    "State"
]
description = "How you can develop Wallaroo applications without thinking about scale."
author = "jmumm"
+++

Scaling stateful applications is hard.  As your business grows, you're eventually going to find that demand is greater than capacity. That means you can't simply deploy your application to a set number of servers and forget it. But adding capacity and manually updating code to run on more servers is time-consuming and error-prone. 

Meanwhile, volume spikes, whether throughout the day or in response to major events, mean that the capacity you actually need fluctuates.  If you provision for the worst case, you end up paying for resources you don't normally use.  On the other hand, trying to anticipate spikes and manually manage capacity is a losing battle in the long run.

At Wallaroo Labs, we've been hard at work on solving the scaling problem for distributed stateful applications that need to run very fast or need time to do their job.  When developing applications with [Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release), you don't think about scale.  Wallaroo can adapt to changing resource demands by expanding or shrinking to fit the available resources, both at application startup and dynamically as conditions change.  You don't update any code or bother with stopping your cluster and redeploying.  Combined with the fact that Wallaroo can run on-premise or in any cloud, we think this is a powerful addition to a developer’s toolkit.

In this post, you’ll see how Wallaroo makes scale-independent development possible.  We’ll talk about how you define a scale-independent Wallaroo application, how we manage in-memory application state for you, and how we automatically migrate that state in response to changes in cluster size.  If you want to learn more about how Wallaroo works in general, check out our earlier post [“Hello Wallaroo!”](https://blog.wallaroolabs.com/2017/03/hello-wallaroo/).

## Scale-Independent Development with Wallaroo

Wallaroo provides a scale-independent API.  We also provide integrated, distributed in-memory state management with movable state.  What this means is that we lay out your state partitions over the available workers, and we migrate that state as necessary when we need to expand or contract in response to changes in cluster size. 

Ok, that’s a lot packed into one paragraph.  Let’s break it down step by step, starting with a simple streaming application that might be familiar to you: word count.  The word count application takes in a stream of sentences and outputs running totals of counts by word.  For example, if we send in the sentence 

```
“They know they found it.”
```

we’ll get the output

```
“they”  - 1
“know”  - 1
“they”  - 2
“found” - 1
“it”    - 1
```

We get two counts for `“they”` because these outputs are running totals.

We covered how to implement word count using our Python API in last week’s [post](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/).  Here's the high level code defining the application in Wallaroo:

```
def application_setup(args):
    # Set up TCP source and sink
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]


    # Define partition keys
    word_partitions = list(string.ascii_lowercase)
    word_partitions.append("!")


    # Define pipeline of computations from source to sink
    ab = wallaroo.ApplicationBuilder("Word Count Application")
    ab.new_pipeline("Split and Count",
                    wallaroo.TCPSourceConfig(in_host, in_port, 
                                             Decoder()))
    ab.to_parallel(Split)
    ab.to_state_partition(CountWord(), WordTotalsBuilder(), 
        "word totals", WordPartitionFunction(), word_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
    return ab.build()
```

This defines an application that receives data over a TCP connection and produces outputs via another TCP connection.  It splits any sentence it receives into words and routes those words to state entities representing word counters.  Those counters are partitioned according to letters of the alphabet (with `“!”` as a catchall for anything that begins with a character that’s not a letter).  At a high level, the application looks like this:

![High Level Word Count Diagram](/images/post/how-wallaroo-scales-distributed-state/word-count-diagram-2.png)

The state partition is defined by creating a list called `word_partitions` containing all the partition keys (in this case, the letters of the English alphabet plus “!”) and providing a partition function that maps words to partition keys.  

The partition function, `WordPartitionFunction`, is defined outside of this code block (see last week’s [post](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) for more details), but it takes a word and returns the first character if it’s in the English alphabet.  Otherwise, it returns `“!”`.  Wallaroo uses this information to create the state partition, distribute it over Wallaroo workers, and route messages to the right place in a running application.  

The following animation illustrates how this routing works.  As words arrive, Wallaroo routes them to the corresponding state entities, where they are placed in a Python dictionary mapping words to their running totals:

![Partition Routing](/images/post/how-wallaroo-scales-distributed-state/state-partition-word.gif)

This diagram doesn’t tell us anything about scale.  It’s too abstract.  But it’s all you need to know to write your Wallaroo application.  

Now, in production, we might have one worker in our cluster, or we might have many workers.  That all depends on our workload.  However, since the Wallaroo API is scale-independent, there is nothing in the Wallaroo code that needs to be scale-aware.  This makes it easier to quickly move from development to testing to production (as we discuss in more detail below).  And it also makes it easier to modify or try out new algorithms.  

As we’ll see in the next section, Wallaroo takes care of distributing the state entities in the partition over the available workers in the cluster.  And as the cluster grows and shrinks over time, it handles redistributing state as well.

## How Wallaroo Handles State

Wallaroo provides in-memory application state.  That means that in our word count example, you don’t need to make calls out to an external system every time you need to read or update the running totals.  That’s good for performance, and it’s good for ensuring correct results in the face of failure.  But it’s also part of what makes Wallaroo’s scale-independent API possible.

Wallaroo breaks down application state into discrete state entities that act as boundaries for atomic transactions (see Pat Helland’s [paper](http://queue.acm.org/detail.cfm?id=3025012), which inspired our work in this area).  Currently, there is a one-to-one relationship between keys into a state partition and state entities.  So, in our example above, we have one state entity for `“a”`, one for `“b”`, etc.  A single state entity in that application is responsible for running totals for all words beginning with the corresponding letter (unless they fall into the catchall).  

When a Wallaroo application starts up, state entities are distributed over the workers in the cluster.  Each worker has routing information that allows us to route data to the correct state, whether that state exists locally or on another worker.  

At any time, a new Wallaroo worker can be added to the cluster.  Wallaroo does not need to be shut down, redeployed, or restarted.  Instead, as soon as the worker requests to join the cluster, Wallaroo adds the worker and redistributes application state while still running.  Once the join is complete, our state partition will be distributed over all available workers.  

A simple case is illustrated below, assuming that we only have four state entities corresponding to the first four letters of the English alphabet:

![Grow to Fit](/images/post/how-wallaroo-scales-distributed-state/grow-to-fit.gif)

The app developer never has to think about this!  The ability to resize a cluster without changing code is a powerful thing.  It means you can write your application code on your laptop, running quick tests with one or two Wallaroo processes.  Then, when it’s time for more heavy-duty testing, you can deploy the same binaries to a testing environment, where the cluster might consist of 5 to 10 workers.  If everything looks good, you can deploy those same binaries again to your production environment, where the application can run on a cluster that grows and shrinks over time in response to changing demand.

## Where to Go Next

We’re calling this set of features “autoscaling,” and we're planning to release them for general use in Q4 of this year (2017).  If you want to be the first to know when they’re available, sign up for our [announcement mailing list](!!link).  And if you just can’t wait to see it in action, check out this 15-minute live demo of growing a Wallaroo cluster, presented by our VP of Engineering:
[Scale Independence in Wallaroo](https://vimeo.com/234753585).

As always, if you’d like to ask us more in-depth technical questions, or if you have any ideas to share, please don’t hesitate to get in touch with us through [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.oftc.net/?channels=wallaroo).  

In this post, we only scratched the surface of how Wallaroo handles state, so stay tuned for future posts on the subject. 

