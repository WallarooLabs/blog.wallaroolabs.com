+++
title= "Go Go, Go! Stream Processing for Go"
date = 2018-01-18T12:00:00-04:00
draft = true
author = "aturley"
description = "Wallaroo’s Go API opens the door to writing scale-independent applications in Go."
tags = [
    "golang",
    "api",
    "announcement"
]
categories = [
    "announcement"
]
+++

We've been working on our processing engine, [Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release) for just under two years now. Our goal has been to make it as easy to build fast, scale-independent applications for processing data. When we open sourced Wallaroo last year we provided an API that let developers create applications using [Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/). Over the last few months we've been working to make Wallaroo available to a wider range of programmers by adding a Go API, and that's what I'd like to talk about today.

Whether you're using Python or Go, Wallaroo is designed to let you focus on your business algorithms, not your infrastructure.

## The Go API

### A Few Words About Go and Wallaroo

Wallaroo is written in a language called [Pony](https://blog.wallaroolabs.com/2017/10/why-we-used-pony-to-write-wallaroo/). Wallaroo interacts with Go code using [Pony's foreign function interface](https://tutorial.ponylang.io/c-ffi/). A Wallaroo application that uses the Go API is compiled into a library and then the application itself is built by linking using this library. Wallaroo calls into specific functions that are exported from the application code. In this post we will focus on the Go code required to create a Wallaroo application, but you can find more information about the structure of an application [in our documentation](https://docs.wallaroolabs.com/book/go/api/start-a-project.html).

### A Motivating Example

The canonical streaming data processing application is Word Count, in which a stream of input text is analyzed and the total number of times each word has been seen is reported. This description is broad enough to allow developers to make different design tradeoffs in their implementations. You can find [the example](https://github.com/WallarooLabs/wallaroo/blob/release/examples/go/word_count/) I'll be discussing in it's entirety in our [GitHub repository](https://github.com/WallarooLabs/wallaroo/tree/release).

For this example we will make the following assumptions:

* Incoming messages will come from a TCP connection and be sent to
  another TCP connection.
* Incoming messages will be framed, starting with a 32-bit length
  header.
* Words are sent to the system in messages that can contain zero or
  more words.
* Incoming messages consist of a string.
* Outgoing messages consist of a word and the number of times that
  word has been seen in the event stream.


![Word Count Diagram](/images/post/go-api/word-count-diagram.png)

In our example, we will also partition the state (the number of times each word has been seen) into 26 state entities, where each state entity handles words that start with different letters. For example "acorn" and "among" would go to the "a" state entity, while "bacon" would go to the "b" state entity.

This application will process messages as they arrive. This contrasts with some other streaming data processing systems that are designed around processing messages in micro-batches. This results in lower latencies because message processing is not delayed.

### Wallaroo's Core Abstractions

In order to understand the Go API, it is important to understand Wallaroo's core abstractions:

* State -- Accumulated result of data stored over the course of time.
* Computation -- Code that transforms an input into an
  output.
* State Computation -- Code that takes an input and a state
  object, operates on that input and state
  (possibly making state updates), and optionally produces an output.
* Source -- Input point for data from external systems into an application.
* Sink -- Output point from an application to external systems.
* Decoder -- Code that transforms a stream of bytes from an external
  system into a series of application input types.
* Encoder -- Code that transforms an application output type into
  bytes for sending to an external system.
* Pipeline -- A sequence of computations and/or state computations
  originating from a source and optionally terminating in a sink.
* Application -- A collection of pipelines.

These abstractions will be described in more detail later.

### Application Setup

Wallaroo calls the `ApplicationSetup` function to create a data structure that represents the application.

```go
//export ApplicationSetup
func ApplicationSetup() *C.char {
	fs := flag.NewFlagSet("wallaroo", flag.ExitOnError)
	inHostsPortsArg := fs.String("in", "", "input host:port list")
	outHostsPortsArg := fs.String("out", "", "output host:port list")

	fs.Parse(wa.Args[1:])

	inHostsPorts := hostsPortsToList(*inHostsPortsArg)

	inHost := inHostsPorts[0][0]
	inPort := inHostsPorts[0][1]

	outHostsPorts := hostsPortsToList(*outHostsPortsArg)
	outHost := outHostsPorts[0][0]
	outPort := outHostsPorts[0][1]

	wa.Serialize = Serialize
	wa.Deserialize = Deserialize

	application := app.MakeApplication("Word Count Application")
	application.NewPipeline("Split and Count", app.MakeTCPSourceConfig(inHost, inPort, &Decoder{})).
		ToMulti(&SplitBuilder{}).
		ToStatePartition(&CountWord{}, &WordTotalsBuilder{}, "word totals", &WordPartitionFunction{}, LetterPartition()).
		ToSink(app.MakeTCPSinkConfig(outHost, outPort, &Encoder{}))

	json := application.ToJson()

	return C.CString(json)
}

func hostsPortsToList(hostsPorts string) [][]string {
	hostsPortsList := make([][]string, 0)
	for _, hp := range strings.Split(hostsPorts, ",") {
		hostsPortsList = append(hostsPortsList, strings.Split(hp, ":"))
	}
	return hostsPortsList
}
```

This code creates an application with the topology that was described earlier. It represents one pipeline that consists of a stateless computation called `Split` that splits a string of words into individual words and a state computation called `CountWord` that updates the state of the application and creates outgoing messages that represent the word count. The types used here will be described more in the following sections. At the end, it returns a C string that represents the application, which Wallaroo then uses to build the actual application.

Note that the function `hostPortsToList` is a convenience function that takes the `host:port` pairs from the command line and turns them into slices.

#### State and State Partitions

In this example, the state is the number of times each word has been seen. The easiest way to do this would be with a dictionary where the key is a word, and the value associated with that key is the number of times that word has been seen in the event stream.

Wallaroo lets you divide state into pieces called state partitions. State partitions are pieces of state that are uniquely identified by a key of some sort. A state partition can be divided into any number of state entities. The only restriction is that these state entities must be independent of each other in terms of how they will be accessed, because only one state entity can be accessed at a time.

When a message is sent, Wallaroo applies a partition function to the message to determine which state entity to send it to. Different state entities may live on different workers, and a state entity may move from one worker to another when workers are added or removed from the cluster. This makes it easy to scale the application up and down as the number of workers in the cluster increases and decreases.

This example represents the state as a dictionary that is wrapped in an object that knows how to update it and has a method that returns an outgoing message object representing a given word's count.

```go
func MakeWordTotals() *WordTotals {
	return &WordTotals{ make(map[string]uint64) }
}

type WordTotals struct {
	WordTotals map[string]uint64
}

func (wordTotals *WordTotals) Update(word string) {
	total, found := wordTotals.WordTotals[word]
	if !found {
		total = 0
	}
	wordTotals.WordTotals[word] = total + 1
}

func (wordTotals *WordTotals) GetCount(word string) *WordCount {
	return &WordCount{word, wordTotals.WordTotals[word]}
}
```

There also needs to be a type that can build these state entity objects. In this example, the type is `WordTotalsBuilder`.

```go
type WordTotalsBuilder struct {}

func (wtb *WordTotalsBuilder) Name() string {
	return "word totals builder"
}

func (wtb *WordTotalsBuilder) Build() interface{} {
	return MakeWordTotals()
}
```

`WordPartitionFunction` is a partition function that takes a string and returns the a `uint64` with the ASCII value of the first character if the first character is a lowercase letter, or a `"!"` if it is not.

```go
type WordPartitionFunction struct {}

func (wpf *WordPartitionFunction) Partition (data interface{}) uint64 {
	word := data.(*string)
	firstLetter := (*word)[0]
	if (firstLetter >= 'a') && (firstLetter <= 'z') {
		return uint64(firstLetter)
	}
	return uint64('!')
}
```

For performance reasons, all partition keys are `uint64`s. It is up to the application developer to select an appropriate system for representing their partitions as `uint64`s.

#### Incoming Messages and the Decoder

The `Decoder` contains the logic for interpreting incoming bytes from a TCP stream into an object that represents the message within the application. In this example, incoming messages are represented as strings:

```go
type Decoder struct {}

func (decoder *Decoder) HeaderLength() uint64 {
	return 4
}

func (decoder *Decoder) PayloadLength(b []byte) uint64 {
	return uint64(binary.BigEndian.Uint32(b[0:4]))
}

func (decoder *Decoder) Decode(b []byte) interface{} {
	s := string(b[:])
	return &s
}
```

This decoder is specific to TCP sources. Wallaroo also has support for Kafka sources, and other source types will be added in the future.

#### Stateless Computation

`Split` is a stateless computation. It takes a string and splits it into a list of strings where each string in the list represents a word.

```
"why hello world" -> Split -> ["why", "hello", "world"]
```

Here's what the `Split` computation looks like:

```go
type Split struct {}

func (s *Split) Name() string {
	return "split"
}

func (s *Split) Compute(data interface{}) []interface{} {
	punctuation := " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
	lines := data.(*string)

	words := make([]interface{}, 0)

	for _, line := range strings.Split(*lines, "\n") {
		clean_line := strings.Trim(strings.ToLower(line), punctuation)
		for _, word := range strings.Split(clean_line, " ") {
			clean_word := strings.Trim(word, punctuation)
			words = append(words, &clean_word)
		}
	}

	return words
}
```

The `Split` computation returns a list of individual words that the Wallaroo framework sends along as messages to the next step in the pipeline. Wallaroo takes care of making sure that each message gets delivered to the correct state entity. Your application does not which machine holds that state entity.

There also needs to be a builder that can build instances of the `Split` computation. Our `SplitBuilder` type looks like this:

```go
type SplitBuilder struct {}

func (sb *SplitBuilder) Build() interface{} {
	return &Split{}
}
```

#### State Computation

`CountWord` is a state computation; it uses an incoming message and a state to update the word count for the new word and returns a message for Wallaroo to send on its behalf.

```go
type CountWord struct {}

func (cw *CountWord) Name() string {
	return "count word"
}

func (cw *CountWord) Compute(data interface{}, state interface{}) (interface{}, bool) {
	word := data.(*string)
	wordTotals := state.(*WordTotals)
	wordTotals.Update(*word)
	return wordTotals.GetCount(*word), true
}
```

#### Outgoing Messages and the Encoder

In our example, the outgoing message is represented within the application as an object that stores the word and the count of the number of times that word has been seen in the event stream.

```go
type WordCount struct {
	Word string
	Count uint64
}
```

The `Encoder` contains the logic for transforming this object into a list of bytes that will then be sent on the outgoing TCP connection. In the example, outgoing messages are strings of `WORD => COUNT\n` where `WORD` is the word being counted and `COUNT` is the count.

```go
type Encoder struct {}

func (encoder *Encoder) Encode(data interface{}) []byte {
	word_count := data.(*WordCount)
	msg := fmt.Sprintf("%s => %d\n", word_count.Word, word_count.Count)
	fmt.Println(msg)
	return []byte(msg)
}
```

This example uses a TCP sink, but Wallaroo also supports Kafka sinks. Other types of sinks will be added in the future.

#### Serialization and Deserialization

Wallaroo needs to be able to serialize and deserialize objects in order to store them to disk for resiliency and recovery, and also to send them to other worker nodes when the application is being used in a multi-worker cluster. The developer must create code to do this. We've omitted that code in this blog post, but you can learn more about it in the ["Interworker Serialization and Resilience"](https://docs.wallaroolabs.com/book/go/api/interworker-serialization-and-resilience.html) section of our documentation.

## A Scalable Event Processing Application

This application can run on one worker and can scale horizontally by adding more and more workers. Wallaroo's flexibility makes it easy to adapt to whatever partitioning strategy your application requires. Take a look at our documentation for [information about how to run a Wallaroo cluster](https://docs.wallaroolabs.com/book/running-wallaroo/running-wallaroo.html).

## Check It Out

If you're interested in running this application yourself, take a look at the [Wallaroo documentation](https://docs.wallaroolabs.com) and the [word count example application](https://github.com/WallarooLabs/wallaroo/tree/release/examples/go/word_count) that we've built. You'll find instructions on setting up Wallaroo and running applications. And take a look at our [community page](https://www.wallaroolabs.com/community) to sign up for our mailing list or join our IRC channel to ask any question you may have.

You can also watch this video to see Wallaroo in action. Our VP of Engineering walks you through the concepts that were covered in this blog post using our Python API and then shows the word count application scaling by adding new workers to the cluster.

<iframe src="https://player.vimeo.com/video/234753585" width="640" height="360" frameborder="0" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>

Our Go API is new, and we are looking at ways to improve it. We have a lot of ideas of our own, but if you have any ideas, we would love to hear from you. Please don’t hesitate to get in touch with us through [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo). We also have a short (30 seconds) [survey](https://wallaroolabs.typeform.com/to/PkC7iT?source=blog) that will help us learn more about the people who are interested in using the Go API, so if that's you then I'd encourage you to go fill it out.

We built Wallaroo to help people create applications without getting bogged down in the hard parts of distributed systems. We hope you'll take a look at our [GitHub repository](https://github.com/wallaroolabs/wallaroo) and get to know Wallaroo to see if it can help you with the problems you're trying to solve. And we hope to hear back from you about the great things you've done with it.
