+++
title= "The Snake and the Horse: How Wallaroo's Python API Works With Pony"
date = 2018-04-05T01:00:00-04:00
draft = false
author = "aturley"
description = "Learn more about how we implemented Wallaroo's Python API on top of Pony."
tags = [
    "wallaroo",
    "python",
    "api",
    "pony"
]
categories = [
    "Python API"
]
+++

## Introduction

Welcome to our continuing series on building Wallaroo.

Our goal with Wallaroo is to relieve developers of the burden of writing reliable, scalable distributed applications so that they can focus on the code that matters to the business.

We think that this is an incredibly powerful vision, which brings with it a unique set of challenges, so we want to lift the curtain and share with the developer community how we went about building various components of Wallaroo.

This week, the Python API ...

When we started building [Wallaroo](https://github.com/wallaroolabs/wallaroo/) we [decided](https://blog.wallaroolabs.com/2017/10/why-we-used-pony-to-write-wallaroo/) to write it in [Pony](https://ponylang.org). Pony is a great language and we all really enjoy working with it every day, but the fact is that most programmers don't know Pony. They want to be able to leverage their existing knowledge of other languages to build data processing systems. For that reason, we built APIs for [Go](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/) and [Python](https://blog.wallaroolabs.com/2018/02/idiomatic-python-stream-processing-in-wallaroo/); folks can write the stream processing logic in these languages, using the libraries that they already know. We have already written about the APIs, but this blog post will dive into the details of how we implemented the Python API.

## How Wallaroo Works

Wallaroo is based on some [core concepts](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html).

* State -- Accumulated result of data stored over the course of time
* Computation -- Code that transforms an input of some type In to an output of some type Out (or optionally None if the input should be filtered out).
* State Computation -- Code that takes an input type In and a state object of some type State, operates on that input and state (possibly making state updates), and optionally producing an output of some type Out.
* Source -- Input point for data from external systems into an application.
* Sink -- Output point from an application to external systems.
* Decoder -- Code that transforms a stream of bytes from an external system into a series of application input types.
* Encoder -- Code that transforms an application output type into bytes for sending to an external system.
* Pipeline -- A sequence of computations and/or state computations originating from a source and optionally terminating in a sink.
* Application -- A collection of pipelines.
* Topology -- A graph of how all sources, sinks, and computations are connected within an application.

Wallaroo manages the interactions between these components so that developers can write application code without thinking about where data lives or how to get it there; scaling an application horizontally is completely transparent to the developer.

## Machida: A Home for Wallaroo Python API Applications

In order to run Wallaroo Python API applications you use a program called Machida. Machida is a generic Wallaroo application that runs Python code in an embedded Python interpreter. It uses Pony objects that wrap the Python object; when methods on the Pony objects are called they call the corresponding methods of the Python objects via Python’s C API. In the rest of this article we will learn about how these pieces fit together.

## The Pony API

It isn't documented, but there's actually a Pony API that can be used to write Wallaroo applications directly in Pony. You can see examples of Pony applications [here](https://github.com/WallarooLabs/wallaroo/tree/0.4.1/examples/pony). The Pony API provides interfaces and traits that the application developer uses to build their application. For example, here's a computation that is part of [the application](https://github.com/WallarooLabs/wallaroo/blob/0.4.1/examples/pony/celsius/celsius.pony) that converts temperatures from Celsius to Fahrenheit:

```pony
primitive Multiply is Computation[F32, F32]
  fun apply(input: F32): F32 =>
    input * 1.8
  fun name(): String => "Multiply by 1.8"
```

It implements the `Computation` interface that is [defined](https://github.com/WallarooLabs/wallaroo/blob/master/lib/wallaroo/core/topology/computations.pony) like this:

```pony
interface Computation[In: Any val, Out: Any val] is BasicComputation
  fun apply(input: In): (Out | Array[Out] val | None)
  fun name(): String
```

Writing a Wallaroo application using the Pony API involves defining classes specific to your application that implement the interfaces that Wallaroo provides and then telling Wallaroo which pieces are connected to each other. Our Python API takes advantage of this Pony API to wrap calls to Python code inside Wallaroo Pony API classes.

## Foundation: The Pony FFI and the Python C API

In order to bridge the gap between Pony and Python we need a way to call code written in other languages from Pony. Fortunately, Pony provides a [foreign function interface](https://tutorial.ponylang.org/c-ffi/) (FFI). This lets Pony programs call functions that conform to the C [ABI](https://en.wikipedia.org/wiki/Application_binary_interface). Pony also has a `Pointer` type that lets you store an opaque reference to a pointer, and Pony types like integers (`I32`, `U64`, etc), floats (`F32`, `F64`) and `String`s (using the `cstring()` method) are compatible with their C counterparts. So you can fairly easily take advantage of existing C functions from Pony.

Python provides a [C API](https://docs.python.org/2/c-api/index.html) for interacting with embedded Python interpreters. The API lets you create Python objects, call methods on objects, access items in lists, and do many other useful things. Using the C API and Pony's FFI we can run Python code from Pony.

# Pony Wrappers

As I mentioned, our Python API wraps calls to Python code inside Wallaroo Pony API classes. We discussed the `Computation` interface earlier; it says that a `Computation` must have a `name()` method and an `apply(...)` method. The Wallaroo Python API has a Pony class called `PyComputation` that generically wraps computations that are written in Python and calls the appropriate compute method on the Python object when the Pony object's `apply(...)` method is called, and method for getting the object’s name when the Pony object’s `name()` method is called.

```pony
class PyComputation is Computation[PyData val, PyData val]
  var _computation: Pointer[U8] val
  let _name: String
  let _is_multi: Bool

  new create(computation: Pointer[U8] val) =>
    _computation = computation
    _name = Machida.get_name(_computation)
    _is_multi = Machida.implements_compute_multi(_computation)

  fun apply(input: PyData val): (PyData val | Array[PyData val] val |None) =>
    let r: Pointer[U8] val =
      Machida.computation_compute(_computation, input.obj(), _is_multi)

    if not r.is_null() then
      Machida.process_computation_results(r, _is_multi)
    else
      None
    end

  fun name(): String =>
    _name
```

The `_computation` field holds a pointer to the Python object that represents the computation. When the `apply(...)` method is called, this pointer, along with a pointer to the underlying Python object stored in `input`, is passed on to `Machida.computation_compute(...)`.

```pony
  fun computation_compute(computation: Pointer[U8] val, data: Pointer[U8] val,
    multi: Bool): Pointer[U8] val
  =>
    let method = if multi then "compute_multi" else "compute" end
    let r = @computation_compute(computation, data, method.cstring())
    print_errors()
    r
```

This in turn calls `@computation_compute(...)`. We can tell this is an FFI call to a C function, because of the `@` at the beginning of the function name. `computation_compute(...)` is [a C function that we have defined](https://github.com/WallarooLabs/wallaroo/blob/0.4.1/machida/cpp/python-wallaroo.c#L151); it calls the Python C API functions required to look up the appropriate method on the Python computation object, call it, and return the value.

```c
extern PyObject *computation_compute(PyObject *computation, PyObject *data,
  char* method)
{
  PyObject *pFunc, *pValue;

  pFunc = PyObject_GetAttrString(computation, method);
  pValue = PyObject_CallFunctionObjArgs(pFunc, data, NULL);
  Py_DECREF(pFunc);

  if (pValue != Py_None)
    return pValue;
  else
    return NULL;
}
```

The pattern of storing a pointer to a Python object and calling methods on that object by passing the object and its arguments through helper functions is used throughout the API. It gives us a bridge between the object-oriented worlds of Pony and Python, and the non-object-oriented world of C.

### Garbage Collection

In addition to allowing us to call methods on the Python objects, the Pony wrapper objects also give us a way to coordinate garbage collection in Pony and Python. Python uses [reference counting](https://docs.python.org/2/c-api/intro.html#objects-types-and-reference-counts) to identify and collect unused object, while Pony uses a [per-actor tracing garbage collector](https://www.doc.ic.ac.uk/~scd/icooolps15_GC.pdf). Systems that embed Python must keep track of references to Python objects and decrease the reference counts of objects that they are no longer using; when the reference count falls to zero then Python can reuse the memory occupied by that object because no other object uses it. We want to make sure that our reference to a Python object remains valid for the lifetime of the Pony object, otherwise a method call on the Python object could crash our system. Pony objects can have a `_final()` method that is called when the Pony object is garbage collected by the Pony runtime; by decrementing the reference count of the Python object inside the Pony wrapper object's `_final()` method we can guarantee that the object will be valid as long as the Pony object exists.

Here's the garbage collection-related code from `PyComputation`:

```pony
class PyComputation is Computation[PyData val, PyData val]
  var _computation: Pointer[U8] val
  let _name: String
  let _is_multi: Bool

  // ommiting other methods ...

  fun _final() =>
    Machida.dec_ref(_computation)
```

### Serialization

Wallaroo is a distributed system, so data needs to be passed between workers in a Wallaroo cluster. The wrapper objects provide methods called `_serialise_space()`, `_serialise()`, and `_deserialise(...)` that are called by Pony's serialization system to serialize and deserialize this data. By default the Wallaroo Python API uses Python's `pickle` package for serialization and deserialization, but users can provide their own functions if they have specific needs that are not met by `pickle`.

Here's the serialization-related code from `PyComputation`:

```pony
class PyComputation is Computation[PyData val, PyData val]
  var _computation: Pointer[U8] val
  let _name: String
  let _is_multi: Bool

  // omitting other methods ...

  fun _serialise_space(): USize =>
    Machida.user_serialization_get_size(_computation)

  fun _serialise(bytes: Pointer[U8] tag) =>
    Machida.user_serialization(_computation, bytes)

  fun ref _deserialise(bytes: Pointer[U8] tag) =>
    _computation = recover Machida.user_deserialization(bytes) end
```

## Setting Up the Application

The first bit of Python code that Machida runs is the function called `application_setup(...)` in the application module. This function uses the `wallaroo.ApplicationBuilder` class to build up a description of the application. This description is encoded as a list of Python dictionaries that describe pipelines. The `apply_application_setup(...)` function goes through the list and builds the Wallaroo application by wrapping the Python classes in their associated Pony wrapper classes and using the Pony API application builder mechanism to build the application. Once Wallaroo has the object that represents the application, it runs it just like it would run an application written using the Pony API. Here's the `application_setup(...)` function from our [Word Count example](https://github.com/WallarooLabs/wallaroo/blob/0.4.1/examples/python/word_count/word_count.py):

```python
def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    word_partitions = list(string.ascii_lowercase)
    word_partitions.append("!")

    ab = wallaroo.ApplicationBuilder("Word Count Application")
    ab.new_pipeline("Split and Count",
                    wallaroo.TCPSourceConfig(in_host, in_port, decoder))
    ab.to_parallel(split)
    ab.to_state_partition(count_word, WordTotals, "word totals",
                          partition, word_partitions)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
    return ab.build()
```

The important thing to remember is that Wallaroo runs the Python API applications just like a Pony API application because the all of the objects look the same to Wallaroo. The only difference is that the Python API objects are generic and will work with any Python object that exposes the correct functions.

## Conclusion

We were able to take advantage of some useful features of Pony's FFI and pointer types, as well as Python's C API, to build a system for creating Wallaroo applications in Python. It was an interesting technical challenge that was made easier by the design of Wallaroo itself. Overall, Pony and Python work remarkably well together. I hope this blog post gave you enough insight into how we did it that you can start thinking about how you might use Pony together Python and with other languages.

## Give Wallaroo a try

We hope that this post has piqued your interest in Wallaroo!

If you are just getting started, we recommend you try our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), which allows you to get Wallaroo up and running in only a few minutes.

Some other great ways to learn about Wallaroo:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
