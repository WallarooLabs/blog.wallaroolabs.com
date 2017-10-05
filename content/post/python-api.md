# A Python API for Building Highly Scalable Applications

We created a framework for writing scalable data processing
applications. And then we made it simple to use by taking care of all
of the hard parts of building a distributed system and presenting the
user with a simple, understandably Python API for describing their
business logic.

## Why?

We wanted to build a tool that allows developers to use
languages that are sometimes considered
. Our first API is for Python. This allows people who
are familiar with Python to quickly and easily build data processing
applications using the language and libraries that they are already
familiar with.

## How?

The core of Wallaroo is written in a language called Pony. Pony is a
fast, type-safe, compiled language based on the actor model. As much
as we love Pony here, most developers have never even heard of it,
much less used it.

Wallaroo uses an embedded Python interpreter to run the user's
application code. The Wallaroo framework takes care of routing
messages, managing message redelivery, and persisting state for
resilient operation. The programmer is then free to use Python, a
language they already know with libraries they used before, to build
their application.

## Who

Wallaroo was created by a team of engineers who have spent years
building and managing systems for processing large amounts of data in
a timely manner. They've taken their experiences and used them to
inform the design of Wallaroo and the APIs that it presents to
developers.
