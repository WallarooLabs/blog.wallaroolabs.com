+++
title = "Speeding up a Pandas job with Parallel Computations"
date = 2018-09-17T15:16:44-07:00
draft = false
author = "simonzelazny"
description = "Converting a batch job to a parallel Wallaroo pipeline."
tags = [
    "python",
    "batch-processing",
	"data-engineering",
	"pandas",
	"use-case"
]
categories = [
    "Data Science at Scale"
]
+++

## Some Background

Suppose you have a Data Analysis batch job that runs every hour on a dedicated
machine. As the weeks go by, you notice that the inputs are getting larger and
the time taken to run it gets longer, slowly nearing the one hour mark. You
worry that subsequent executions might begin to 'run into' each other and cause
your business pipelines to misbehave.

This sounds like you [might have a streaming problem](
https://blog.wallaroolabs.com/2018/01/you-might-have-a-streaming-data-problem-if.../)!
But --you say--
other parts of the analytics pipeline are owned by other teams, and getting
everyone on board with migrating to a streaming architecture will take time and
a lot of effort. By the time that happens, your particular piece of the
pipeline might get completely clogged up.

You can use Wallaroo to efficiently parallelize the work so you can be sure it
completes in time. Let’s see how we can dip our toes in Wallaroo-land!  We’ll
use an ad-hoc cluster to parallelize a batch job and reduce its run-time by ¾
on one machine, with the potential to easily scale out horizontally onto
multiple machines, if needed. This means that we can roll out a little piece of
streaming architecture in our own backyard, and have a story ready when the
time comes to move other parts of the stack into the evented streaming world.

## The Existing Pipeline

```python
# file: old_pipeline.py

df = pd.read_csv(infile, index_col=0, dtype=unicode, engine='python')
fancy_ml_black_box.classify_df(df)
df.to_csv(outfile, header=False)
```

The bottleneck lies in `fancy_ml_black_box.classify_df`. This function runs a
classifier, written by our Data Analysts, on each row of the [pandas
dataframe](https://pandas.pydata.org/pandas-docs/stable/generated/pandas.DataFrame.html). Since
the results of classifying a particular row are independent of classifying any
other row, it seems like a good candidate for parallelization.


______________________________________________
#### A note on the fancy black box classifier

If you look inside the classifier source code, you’ll find that it calls
[dataframe.apply](https://pandas.pydata.org/pandas-docs/stable/generated/pandas.DataFrame.apply.html)
with a rather meaningless computation. We’ve chosen something that burns CPU
cycles in order to simulate an expensive machine learning classification
process and showcase the gains to be had from parallelizing it.
______________________________________________


Here's how we can do it with Wallaroo:

```python
    ab = wallaroo.ApplicationBuilder("Parallel Pandas Classifier with Wallaroo")
    ab.new_pipeline("Classifier",
                    wallaroo.TCPSourceConfig(in_host, in_port, decode))
    ab.to_stateful(batch_rows, RowBuffer, "CSV rows + global header state")
    ab.to_parallel(classify)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encode))
```

The idea is to ingest the csv rows using our TCP source, batch them up into
smal dataframes, and run the classification algorithm in parallel.

We’ll preserve the input and output formats of our section of the pipeline,
maintaining compatibility with upstream and downstream systems, but hopefully
see significant speed increases by leveraging all the cores on our server.

## Baseline Measurements

Let's get some baseline measurements for our application. Here are the
run-times for input files of varying sizes:


| input size     | time taken (AWS c5.4xlarge) |
|----------------|------------|
| 1000 rows      |    3.7s    |
| 10,000 rows    |     35s    |
| 100,000 rows   | 5m  53s    |
| 1,000,000 rows | 58m 21s    |


These numbers make it clear that we're dealing with an algorithm of linear
run-time complexity -- the time taken to perform the task is linearly dependent on
the size of the input. We can estimate that our pipeline will be in trouble if
the rate of data coming in exceeds ~270 rows/second, on average.

This means that if the hourly job inputs start to approach 1 million rows, new
jobs may start 'running into' old jobs that haven't yet finished.


## Parallelizing Pandas with Wallaroo

Let's see if we can improve these numbers a bit, by splitting all the work
among the available CPU cores (8 of them) on this machine. First, we'll need some
scaffolding to set up input and output for Wallaroo.


![Three process architecture: send.py sends data, wallaroo processes it, and sends to data_receiver](/images/post/speeding-up-a-pandas-job-with-parallel-computations/sendpy-wallaroo-data-receiver.png)


### Step 1: Sending the CSV file to Wallaroo

We'll use a Python script to read all the lines in our input csv file and send
them to our Wallaroo TCP Source. We'll need to
[frame](https://docs.wallaroolabs.com/book/appendix/tcp-decoders-and-encoders.html#framed-message-protocols)
each line so that they can be decoded properly in the Wallaroo source:

```python
try:
   with open(filename, 'rb') as f:
     for line in f.readlines():
       line = line.strip()
       sock.sendall(struct.pack(">I",len(line))+line)

finally:
   sock.sendall(struct.pack(">I",len(EOT))+EOT)
   print('Done sending {}'.format(filename))
   sock.close()
```

`sock.sendall(struct.pack(">I",len(line))+line)` means: encode the length of
the line as a 4-byte, big-endian integer (`I`), then send both that integer,
and the full line of text, down the TCP socket.

In the `finally` clause, we also encode and send down a single [ASCII
EOT](https://en.wikipedia.org/wiki/End-of-Transmission_character) byte, to
signal that this is the end our our input.

This TCP input is received by our decoder:

```python
@wallaroo.decoder(header_length=4, length_fmt=">I")
def decode(bs):
    if bs == "\x04":
        return EndOfInput()
    else:
        return bs
```

As you can see, if our data is the EOT byte (`\x04`), we'll create an object
that makes the "End Of Input" meaning explicit. Otherwise, we'll take the data as-is.

### Step 2: Batching the CSV Rows

The next step in the pipeline is where we batch input rows into chunks of 100.

```python
@wallaroo.state_computation(name='Batch rows of csv, emit DataFrames')
def batch_rows(row, row_buffer):
    return (row_buffer.update_with(row), True)
```

The `RowBuffer` state object will take the first row it sees and save that
internally as a `header`. Then it will accept incoming rows until it stores a
certain amount (100 rows in our app). The `.update_with(row)` method will
return `None` if the `row` was added but there's still room in the buffer.  If
the update fills the buffer, it will zero out internally and emit a
`BatchedRows` object with 2 fields: a `header` and `rows`. This object will get
passed down to the next computation, while the `RowBuffer` will start
collecting another batch.


_________________________________________
#### A note on serialization efficiency

Why go through the exercise of batching, when we can simply send each entry in
the CSV file as a single-row dataframe to our classifier? The answer is: for
speed. Every transfer of data between computation steps in Wallaroo can
potentially entail coding and decoding the data on the wire, and the creation
of dataframe objects is not without its own cost.
_________________________________________


### Step 3: Classifying mini-dataframes in parallel

This is the part of the pipeline where we can bring Wallaroo's built-in
distribution mechanism down to bear on our problem:

```python
@wallaroo.computation(name="Classify")
def classify(batched_rows):
    df = build_dataframe(batched_rows)
    fancy_ml_black_box.classify_df(df)
    return df
```

There is some massaging involved in getting a `BatchedRows` object converted into a
dataframe:

```python
def build_dataframe(br):
    buf = StringIO(br.header + "\n" + ("\n".join(br.rows)))
    return pd.read_csv(buf, index_col=0, dtype=unicode, engine='python')
```

Essentially, we glue the `BatchedRows.header` to the `BatchedRows.rows` to
simulate a stand-alone csv file, which we then pass to `pandas.read_csv` in the
form of a [StringIO](https://docs.python.org/2/library/stringio.html)
buffer. We can now pass the resulting enriched dataframe to the
`fancy_ml_black_box.classify_df()` function.

All of the above work, including marshalling the data into a dataframe, happens
in parallel, with every Wallaroo worker in the cluster getting a different
instance of `BufferedRows`.

### Step 4: Encoding back to a file

The dataframe output by `classify()`, above, gets serialized and framed by the
`encode` step. By now you should be somewhat familiar with the simple TCP
framing used throughout this project:

```python
def encode(df):
    s = dataframe_to_csv(df)
    return struct.pack('>I',len(s)) + s
```

With the helper function `dataframe_to_csv` defined as:

```python
def dataframe_to_csv(df):
    buf = StringIO()
    df.to_csv(buf, header=False)
    s = buf.getvalue().strip()
    buf.close()
    return s
```

This representation is read by the Wallaroo tool `data_receiver`, which is told
to listen for `--framed` data:

```shell
nohup data_receiver  \
      --framed --listen "$LEADER":"$SINK_PORT" \
      --ponynopin \
      > "$OUTPUT" 2>&1 &
```

Which is great, because that's what it's going to get. The output will be
written to a file, specified by the environment variable `OUTPUT`.


## The Effects on Run-Time

First, let's verify that the new code produces the same output as the old code:

```shell
$ /usr/bin/time make run-old INPUT=input/1000.csv
./old_pipeline.py input/1000.csv "output/old_1000.csv"
3.85user 0.47system 0:03.70elapsed 116%CPU (0avgtext+0avgdata 54260maxresident)k
176inputs+288outputs (0major+17423minor)pagefaults 0swaps

$ /usr/bin/time make run-new N_WORKERS=1 INPUT=input/1000.csv
INPUT=input/1000.csv OUTPUT="output/new_1000.csv" N_WORKERS=1 ./run_machida.sh
(..)
4.48user 0.90system 0:04.13elapsed 130%CPU (0avgtext+0avgdata 63808maxresident)k
0inputs+352outputs (0major+989180minor)pagefaults 0swaps

$ diff output/new_1000.csv output/old_1000.csv
$ echo $?
0
```

Yay! The results match, and the run-time is only 1 second slower, which is not
that bad, considering we're launching 3 separate processes (sender, wallaroo,
and receiver) and sending all the data over the network twice.

Now, let's see the gains to be had on bigger inputs. First, the 10,000-line file:

| original code | 1 worker | 4 workers | 8 workers |
|---------------|----------|-----------|-----------|
| 35s           | 39s      | 20s       | 11s       |


Now, with the 100,000-line file:

| original code | 1 worker | 4 workers | 8 workers |
|---------------|----------|-----------|-----------|
| 5m48s         | 6m28s    | 3m16s     | 1m41s     |


And with the million-line file:


| original code | 1 worker | 4 workers | 8 workers |
|---------------|----------|-----------|-----------|
| 58m21s        | 1h03m46s | 32m12s    | 16m33s    |


_________________________________________________________

#### Why didn't you test on 2 workers?

Due to the single-threaded constraints of Python's execution model, the
initializer in a wallaroo cluster will often aggressively undertake its share
of a parallel workload before sending out work to the rest of the cluster.

This means that running a parallel job on 2 workers will not yield speed
benefits. We recommend running clusters of at least 4 workers in order to
leverage Wallaroo's scaling capabilities.
_________________________________________________________


As you can see above ([and verify for yourself by cloning this example
project](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master)),
we were able to cut the million-line processing time down to sixteen
minutes. Moreover, if the input datasets become too large for our
single-machine, eight-worker cluster, we can very easily add more machines and
leverage the extra parallelism, without changing a single line of code in our
Wallaroo application.

This gives us considerable capacity to weather the storm of increasing load,
while we design a more mature [streaming
architecture](https://blog.wallaroolabs.com/categories/wallaroo-in-action/) for
the system as a whole.

## What's Next?

Hopefully I've made the case above that Wallaroo can be used as an ad-hoc
method for adapting your existing [pandas](https://pandas.pydata.org/)-based
analytics pipelines to handle increased load. Next time, I'll show you how to
spin up Wallaroo clusters on-demand, to handle those truly enormous jobs that
will not fit on one machine.

Putting your analytics pipelines in a streaming framework opens up not only
possibilities for scaling your data science, but also for real-time
insights. Once you're ready to take the plunge into a true evented model, all
you have to do is send your data directly to Wallaroo, bypassing the CSV stage
completely. With a little up-front investment, you've unlocked a broad range of
possibilities to productionize your Python analytics code.

If you'd like to find out more how Wallaroo can help out with scaling Python
analytics, please reach out to
[hello@wallaroolabs.com](mailto:hello@wallaroolabs.com). We're always happy to
chat!
