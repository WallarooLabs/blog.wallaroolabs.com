+++
title = "Stateful Multi-Stream Processing in Python with Wallaroo"
slug = "stateful-multi-stream-processing-in-python-with-wallaroo"
draft = false
date = 2017-12-07T00:00:00Z
tags = [
    "wallaroo",
    "state",
    "pipeline",
    "partitioning",
    "python"
]
categories = [
    "State"
]
description = "Implementing the Market Spread application using two pipelines and one shared state partition."
author = "jmumm"
+++

[Wallaroo](https://github.com/WallarooLabs/wallaroo) is a high-performance, open-source framework for building distributed stateful applications. In an earlier [post](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/), we looked at how Wallaroo scales distributed state.  In this post, we’re going to see how you can use Wallaroo to implement multiple data processing tasks performed over the same shared state. We’ll be implementing an application we’ll call “Market Spread” that keeps track of the latest pricing information by stock while simultaneously using that state to determine whether stock order requests should be rejected.

Wallaroo allows you to represent data processing tasks as distinct pipelines from the ingestion of data to the emission of outputs.  A Wallaroo application is composed of one or more of these pipelines.  An application is then distributed over one or more workers, which correspond to Wallaroo processes.  One of the core goals for Wallaroo is that the application developer can focus on the domain logic instead of thinking about scale (see this [post](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/) for more details).

In this post, I’m going to explain how to define Market Spread as a two-pipeline Wallaroo application that involves a single state partition shared by both pipelines. The principles described here can easily be extended to more complex applications.  

First, we’re going to look at what a “pipeline” means in Wallaroo.  Next, we’ll look at how Wallaroo state partitions work.  And then, with these two sets of concepts in mind, we’ll implement “Market Spread” with two pipelines, each interacting with the same state partition.  

The Market Spread application will ingest two incoming streams of data, one representing current information about stock prices (we’ll be calling this “market data”) and the other representing a sequence of stock orders.  The application will use the stock pricing information to update its market state partition.  Meanwhile, it will check the stream of market orders against that same market state partition to determine if it should emit alerts to an external system.  We’ll look at some of the code for this application in the body of the post, but you can go [here](https://github.com/WallarooLabs/wallaroo/tree/master/examples/python/market_spread) to see the entire example.

## Wallaroo Pipelines

Wallaroo applications are composed of one or more __pipelines__. A pipeline starts from a __source__, a point where data is ingested into the application. It is then composed of zero or more computations or state computations. Finally, it can optionally terminate in a __sink__, a point where data is emitted to an external system. 

The simplest possible pipeline would consist of just a source. However, this wouldn’t do anything useful. In practice, a pipeline will either terminate at a sink or at a state computation that updates some Wallaroo state. Here’s an example of a pipeline definition taken from an earlier [post](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) describing a word count application:

```
   ab.new_pipeline("Split and Count",
                    wallaroo.TCPSourceConfig(in_host, in_port, 
                                             Decoder()))
    ab.to_parallel(Split)
    ab.to_state_partition(CountWord(), WordTotalsBuilder(), 
        "word totals", WordPartitionFunction(), word_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))    
    return ab.build()
```

We set up a new pipeline with the `new_pipeline()` API call, where we specify the pipeline source. Here, the source receives lines of text over TCP. We send these lines to a parallelized split computation that breaks them into individual words.  These words are then sent to a state computation that counts the words and updates running totals in a state partition.  Finally, we send our running totals to a sink that writes the outputs over TCP to an external system. 

There are two ways to signal the termination of a pipeline. First, as in the above example, we can use a `to_sink()` call to indicate the pipeline terminates at a sink.  Second, we can use a `done()` call to indicate that the pipeline terminates then and there, for example, after a state computation that updates some state.

In addition to computation metrics, Wallaroo records pipeline-specific metrics which are sent over TCP to either the Wallaroo Metrics UI or a user-defined system that understands our protocol. Via the Metrics UI, you can see the latency from the point of ingestion into the pipeline to the end point of that pipeline, whether that is a sink or some state computation.  You can also see the pipeline throughput. 

A Wallaroo application is not limited to only one pipeline.  To add another, you call `new_pipeline()` again after either a `to_sink()` call or a `done()` call.  We will look at an example below when we define the Market Spread application.  But in order to understand how pipelines can share state in a Wallaroo application, we first need to understand something about how Wallaroo handles state.

## State Partitions in Wallaroo

We explored how Wallaroo handles distributed state in some detail in an earlier [post](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/). Here we’re just going to look at the basics. Wallaroo provides in-memory application state. This means that we don’t rely on costly and potentially unreliable calls to external systems to update and read state. This is good for performance and for providing correctness guarantees. For our purposes here, though, the most important aspect of Wallaroo state is how it is partitioned within and across workers.

When you define a stateful Wallaroo application, you define a state partition by providing a set of partition keys and a partition function that maps inputs to keys.  Wallaroo divides its state into distinct state entities in a one-to-one correspondence with the partition keys.  These state entities act as boundaries for atomic transactions (an idea inspired by this [paper](http://queue.acm.org/detail.cfm?id=3025012) by Pat Helland). They also act as units of parallelization, both within and between workers.

In the case of a word count application, we might partition our state by the letters of the alphabet.  In this case, Wallaroo creates a state entity corresponding to each letter. In a two-worker Wallaroo cluster, the state entities corresponding to “a”-”m” might live on Worker 1, while the entities corresponding to “n”-”z” might live on Worker 2. 

![Word Count State Partition](/images/post/name-pending/word-count-letter-state-partition.png)

As words enter the system, they would be routed to the appropriate state entity on the appropriate worker. You must provide a partition function for this purpose.  A partition function derives a partition key from an input type. So, in the word count case, our partition function might take the first letter of each word, which will then serve as the key that Wallaroo uses to determine which state entity is the routing target.  Wallaroo handles laying out state entities across workers.  The Wallaroo app developer only provides the set of partition keys and the partition function. The following diagram illustrates how some words would be routed to Worker 1 under our setup:

![Partition Routing](/images/post/name-pending/state-partition-word.gif)

## Market Spread: Our Two-Pipeline Example Application

So far, we have looked at an application that has a single pipeline. We’re now ready to move to a two-pipeline application. For this purpose, we’re going to build an application called Market Spread. The purpose of this application is twofold: (1) to keep track of recent data about stock prices (“market data”) and (2) to check streaming orders against that market state in order to detect anomalies and, if necessary, send out alerts to an external system indicating that an order should be rejected. These two purposes conveniently map to two Wallaroo pipelines.

As mentioned above, each pipeline has a data source. In the case of the Market Spread application, we have two incoming streams of data. On one hand, we have a stream of recent market data that we will use to update market state by stock symbol. On the other hand, we have a stream of orders that we will check against that market state. The following diagram illustrates the structure of the application:

![Market Spread](/images/post/name-pending/market-spread-diagram.png)

I mentioned above that, in practice, a pipeline will either terminate at a sink or at a state update computation. Our first pipeline ingests recent market data and uses that data to make updates to our market state. At that point, there is nothing left to do, so the pipeline terminates. Our second pipeline ingests orders, checks those orders against the market state, and then, under certain conditions, sends out an alert to an external system indicating that an order should be rejected. This means that the second pipeline terminates at a sink, since we will sometimes be emitting outputs.

You’ve probably already noticed that we’re going to be sharing state across these two pipelines. We want to check our orders against the same market state that we’re updating in our first pipeline.  So how do we do this?  The short answer is that we give the state partition a name (represented as a String) and use this in the definition of both pipelines.  We’ll see how this works in the context of defining the entire application. 

In order to define a Wallaroo application using the Python API, we must first define a function called `application_setup()` where our application definition will go.  We begin by setting up our TCP addresses and our state partition keys:


```
import wallaroo

def application_setup(args):
    input_addrs = wallaroo.tcp_parse_input_addrs(args)
    order_host, order_port = input_addrs[0]
    market_host, market_port = input_addrs[1]

    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    symbol_partitions = [str_to_partition(x.rjust(4)) for x in
                         load_valid_symbols()]
```

Wallaroo provides the helper methods `tcp_part_input_addrs` and `tcp_parse_output_addrs` to parse the command line arguments `--input` and `--output` respectively for addresses in the format `host:port`.  Meanwhile, we define a couple of helper functions to define our partition keys, which are going to be numbers derived from stock symbols. `load_valid_symbols()` loads in a sequence of symbol strings from a text file. If a stock symbol is under 4 characters, we pad it with spaces on the left so that it’s 4 characters long.  `str_to_partition()` then takes the resulting String and derives a numerical value. The numerical values will serve as the keys into our state partition.  Here are the helper functions for reference:

```
def str_to_partition(stringable):
    ret = 0
    for x in range(0, len(stringable)):
        ret += ord(stringable[x]) << (x * 8)
    return ret

def load_valid_symbols():
    with open('symbols.txt', 'rb') as f:
        return f.read().splitlines()
```

We are now ready to define our first pipeline:

```
    ab = wallaroo.ApplicationBuilder("market-spread")
    ab.new_pipeline(
            "Market Data",
            wallaroo.TCPSourceConfig(market_host, market_port,
                                     MarketDataDecoder())
        ).to_state_partition_u64(
            UpdateMarketData(), SymbolDataBuilder(), "symbol-data",
            SymbolPartitionFunction(), symbol_partitions
        ).done()
```

We name this pipeline “Market Data” and define a source and a state partition.  Notice that the pipeline definition ends in a call to `done()`, which means that the pipeline terminates without reaching a sink.  We define this pipeline’s source as a TCP source using the input addresses we parsed earlier and a class called `MarketDataDecoder` for decoding our binary representation of data about a symbol.  `MarketDataDecoder` is defined as follows:


```
class MarketDataDecoder(object):
    def header_length(self):
        return 4

    def payload_length(self, bs):
        return struct.unpack(">I", bs)[0]

    def decode(self, bs):
        """
        0 -  1b - FixType (U8)
        1 -  4b - symbol (String)
        5 -  21b - transact_time (String)
        26 - 8b - bid_px (F64)
        34 - 8b - offer_px (F64)
        """
        order_type = struct.unpack(">B", bs[0:1])[0]
        if order_type != FIXTYPE_MARKET_DATA:
            raise MarketSpreadError("Wrong Fix message type. Did you connect "
                                    "the senders the wrong way around?")
        symbol = struct.unpack(">4s", bs[1:5])[0]
        transact_time = struct.unpack(">21s", bs[5:26])[0]
        bid = struct.unpack(">d", bs[26:34])[0]
        offer = struct.unpack(">d", bs[34:42])[0]
        return MarketDataMessage(symbol, transact_time, bid, offer)
```

The details are not important for our purposes here. What matters is that we implement three methods.  `header_length()` returns the length in bytes of each binary message header sent over TCP.  `payload_length()` takes a header and derives the message payload length.  Finally, `decode()` takes the binary payload itself and derives a `MarketDataMessage`, which we will use to update our market state.

Once the source is defined, we move to the state partition, which was defined as follows:


```
        ).to_state_partition_u64(
            UpdateMarketData(), SymbolDataBuilder(), "symbol-data",
            SymbolPartitionFunction(), symbol_partitions
        ).done()
```

`to_state_partition_u64()` indicates that this is a state partition that uses 64-bit numbers as partition keys.  `UpdateMarketData` is the class that manages state updates based on market data.  `SymbolDataBuilder` is a class that defines how to initialize a market state entity. `”symbol-data”` is the unique name of the state partition. We will use this unique name when defining our second pipeline to indicate that we are using the same state partition across both pipelines. `SymbolPartitionFunction` is a class defining how to derive a partition key from a `MarketDataMessage` in order to route the message to the correct state entity. Finally, `symbol_partitions` is the list of state partition keys we defined above.

This call tells Wallaroo two things.  First, it defines the state partition, telling Wallaroo how many state entities there will be (one per key), how to initialize each state entity, and how to map inputs to partition keys.  Second, it tells Wallaroo that, in this pipeline, we want to perform a certain state computation against whichever state entity we route our input to.  In this case, the state computation is `UpdateMarketData`, which is defined as follows:


```
class UpdateMarketData(object):
    def name(self):
        return "Update Market Data"

    def compute(self, data, state):
        offer_bid_difference = data.offer - data.bid

        should_reject_trades = ((offer_bid_difference >= 0.05) or
                                ((offer_bid_difference / data.mid) >= 0.05))

        state.last_bid = data.bid
        state.last_offer = data.offer
        state.should_reject_trades = should_reject_trades

        return (None, True)
```

The details of the logic are not important for the purposes of this post, but the short version is that we use the current bid-ask spread for a given stock symbol to determine if we should reject orders for that symbol.  

A state computation returns a tuple representing the output of the computation and a boolean signifying whether we changed state.  In this case, we return `None` for our output since we are only updating state.  And we return `True` because we updated state.

Our call to `done()` indicates that we are finished defining this pipeline. But we actually want to use the state we’re updating. So now we must define our second pipeline:

```
    ab.new_pipeline(
            "Orders",
            wallaroo.TCPSourceConfig(order_host, order_port, OrderDecoder())
        ).to_state_partition_u64(
            CheckOrder(), SymbolDataBuilder(), "symbol-data",
            SymbolPartitionFunction(), symbol_partitions
       ).to_sink(wallaroo.TCPSinkConfig(out_host, out_port,
                                        OrderResultEncoder())
```

This time, we name the pipeline “Orders” and we use the `OrderDecoder`, which takes incoming binary data and derives an `Order` object (it’s similar to the `MarketDataDecoder` we saw above).  We then define the state partition again.  You’ll notice that the definition is the same as with the first pipeline with the exception of `CheckOrder`, which is the class responsible for checking the order against market state and potentially emitting an `OrderResult` if an alert is called for.  

Currently, Wallaroo requires some redundant information when specifying that a state partition defined earlier is used in a later pipeline.  We will eventually simplify this aspect of the API, but for now, when sharing the same state partition across pipelines, you will copy the same call with the exception of the state computation class (in this case `CheckOrder`).  In particular, make sure you are using the same string identifier for the state partition.

Here is the definition of our state computation for this pipeline:

```
class CheckOrder(object):
    def name(self):
        return "Check Order"

    def compute(self, data, state):
        if state.should_reject_trades:
            ts = int(time.time() * 100000)
            return (OrderResult(data, state.last_bid,
                                state.last_offer, ts),
                    False)
        return (None, False)
```


If we determine that we should reject the trade, then we return an `OrderResult` as the first member of our return tuple.  If we shouldn’t reject the trade, we return `None`, since there is no need to send an output to the sink.  In both cases, we return `False` as the second member of our return tuple since we are only reading state (and not updating it) in this state computation.

Finally, we define the pipeline sink via a call to `to_sink()`.  We supply the output host and port that we parsed earlier as well as a class responsible for encoding an `OrderResult` object into a binary format that the external system knows how to read.

## Conclusion

In this post, we implemented the Market Spread application as a two-pipeline Wallaroo application.  We looked at what “pipelines” mean in the context of a Wallaroo application.  We saw that Wallaroo partitions state by keys within and across workers, and that an app developer must provide those keys and a partition function that Wallaroo will use to route messages to the appropriate state entities.  Finally, we used these concepts to implement a two-pipeline Market Spread application that used one pipeline to update a state partition and another to check data against that state and potentially output the results to an external system.

If you’d like to see the full code, it's available on [GitHub](https://github.com/WallarooLabs/wallaroo/tree/master/examples/python/market_spread). If you would like to ask us more in-depth technical questions, or if you have any suggestions, please get in touch via [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).
