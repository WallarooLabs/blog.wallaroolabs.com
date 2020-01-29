+++
title = "Adventures with cgo: Part 2- Locks and other things that go bump in the night"
date = 2018-04-26T16:42:42-04:00
draft = true
author = "seantallen"
description = "We've learned quite a lot while working on the Go API for Wallaroo. Come along for the journey with us as we teach you about the fun and foibles that await when you go adventuring with cgo. In part 2, we follow up on some lessons learned in part 1."
tags = [
    "cgo",
    "golang",
    "performance"
]
categories = [
    "Adventures with cgo", "Exploring Wallaroo Internals"
]
+++
Hi there! You're about to read part 2 of a 4 part series about Go performance as told from the perspective of [Wallaroo](https://github.com/wallaroolabs/wallaroo), our distributed stream processor. [Part 1](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/) covered issues around having non-Go code holding on to pointers to Go objects. This post builds on part 1.

In this post, we're going to cover some problems you can run into when using locks within Go code. While the examples discussed are based on the code presented in part one, the general information should be useful to any Go programmer who needs synchronize data using locks. This post “closes to loop” on a few issues that weren’t addressed in [part 1](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/). Reading [part 1](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/) before this post will help with understanding nuance in this post, but I'll be providing enough background so that it isn't required.

If you’re an expert user of locks, mutexes, atomics and what not, the content of this post probably seems obvious to you. Just remember, there was a time when they weren’t obvious to you. I feel it would be remiss to not address them as an addendum to part 1. Between part 1 and this post, you should be in a good place to implement a similar solution yourself without encountering any pitfalls.

Let's get started by looking at a bit of background on our product Wallaroo and why we ended up needing to become well-versed in the ways of Go, cgo, and locks within Go. If you are familiar with [Wallaroo](https://github.com/wallaroolabs/wallaroo), its [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/), and where we left off at the end of [part 1](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/) feel free to skip ahead to ["Generating Keys"](#generating-keys).

## The Wallaroo Go Story

Wallaroo is a distributed stream processor. The first public release was of our [Python API](https://blog.wallaroolabs.com/2018/02/idiomatic-python-stream-processing-in-wallaroo/) in September 2017. Earlier this year, we did a preview release of our new [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/).

Wallaroo is not a pure Go system. We wrote the core of Wallaroo in [Pony](https://www.ponylang.org/). Developers writing Go applications using the Wallaroo Go API implement their logic in Go. Our [blog post introducing the Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/) has an excellent overview of what a developer is responsible for writing.

"Go applications" that are a hybrid of Go and code written in another language (like Pony or C) aren't actually "Go applications." They are "cgo applications."

In order deal with some [complications that cgo introduces](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/#what-s-tricky-about-calling-go-from-c), we [introduced a new data structure](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/#concurrent-map-to-the-rescue) that would be used extensively by our application, a `ConcurrentMap`. The concurrent map allowed us to maintain “references” (in the form of unique uint64) to Go objects in C code despite Go not allowing pointers to Go objects to be held by foreign code.

Our example `ConcurrentMap` ended up in its “final” version as:

```go
import (
  "C"
  "sync"
)

var SHARDS = uint64(64)

type ConcurrentMap []*ConcurrentMapShared

type ConcurrentMapShared struct {
  items map[uint64]interface{}
  sync.RWMutex
}

func NewConcurrentMap() ConcurrentMap {
  m := make(ConcurrentMap, SHARDS)
  for i := uint64(0); i < SHARDS; i++ {
      m[i] = &ConcurrentMapShared{items: make(map[uint64]interface{})}
  }
  return m
}

func (m ConcurrentMap) GetShard(key uint64) *ConcurrentMapShared {
  return m[key%SHARDS]
}

func (m ConcurrentMap) Store(key uint64, value interface{}) {
  shard := m.GetShard(key)
  shard.Lock()
  shard.items[key] = value
  shard.Unlock()
}

func (m ConcurrentMap) Load(key uint64) (interface{}, bool) {
  shard := m.GetShard(key)
  shard.RLock()
  val, ok := shard.items[key]
  shard.RUnlock()
  return val, ok
}

func (m ConcurrentMap) Delete(key uint64) {
  shard := m.GetShard(key)
  shard.Lock()
  delete(shard.items, key)
  shard.Unlock()
}
```

## Generating Keys

Let’s pick up from where we left off, we have our `ConcurrentMap,` and we are going to be using `uint64`s as keys. The question is, how do we generate them?

The most straightforward means would be to keep a counter and increment it each time we need a new identifier. This approach has a couple of welcome qualities.

- It's easy to understand what is happening.
- It works well with the sharding strategy in our `ConcurrentMap.`

That would look something like:

```go
type IdGenerator struct {
  mu sync.Mutex
  id uint64
}

func (stuff *OurStuff) id() uint64 {
  stuff.mu.Lock()
  currentId := stuff.id
  stuff.id++
  stuff.mu.Unlock()
  return currentId
}
```

It's straightforward to understand how identifiers are generated. Each time we need a new one, return the current value of `OurStuff.id` to our caller and increment the value of `OurStuff.id` so we'll have a unique identifier for the next caller.

This strategy works well with our sharding strategy for our `ConcurrentMap`:

```go
func (m ConcurrentMap) GetShard(key uint64) *ConcurrentMapShared {
  return m[key%SHARD_COUNT]
}
```

By using an “increment by 1” id, we will get an "even at any time distribution" across `ConcurrentMap` shards. If we have 64 shards, then our use of modulo of key over shard count would result in something like:

```
id:0 => shard:0
id:1 => shard:1
id:2 => shard:2
```

We will try to add new items to each shard one after another until we reach the last shard until we start over from the beginning. This even distribution of writes should mean that unless we have more than 64 different attempts at once to write a new item into our map, each one should be able to obtain the shard’s write lock without having to wait for the mutex.

This naive solution can be improved. We don't need to use a mutex. Locking and unlocking a mutex is a relatively expensive operation. And, in our case, given that we are only protecting the incrementing of an integer, there's a better approach: atomic operations.

## Atomics

The Go standard library contains a [package of atomic operations](https://golang.org/pkg/sync/atomic/). From the documentation:

> Package atomic provides low-level atomic memory primitives useful for implementing synchronization algorithms.

Package atomic is exactly what we need. Rather than using the heavy-weight `sync.Mutex`, we'll use `atomic.AddUint64`.

From the documentation:

> AddUint64 atomically adds delta to *addr and returns the new value. To subtract a signed positive constant value c from x, do AddUint64(&x, ^uint64(c-1)). In particular, to decrement x, do AddUint64(&x, ^uint64(0)).

Using `AddUint64`, we can change our id generator to:

```go
type IdGenerator struct {
  mu sync.Mutex
  id uint64
}

func (stuff *OurStuff) id() uint64 {
  var id = atomic.AddUint64(&stuff.id, 1)
  return id
}
```

Our atomic version will have much better performance characteristics than our mutex version. If you need to write your own synchronization code in Go, be sure to check out [the atomic package](https://golang.org/pkg/sync/atomic/) and use the functions it provides when you are trying to protect an atomic operation. It will end up being a lot more efficient than using `Mutex` or `RWMutex`.

## `RWMutex` vs `Mutex`

The Go standard library contains both an exclusive mutex that we saw in our `IdGenerator` and a read/write mutex that was used earlier in our `ConcurrentMap`.

You should use `Mutex` when you want to make sure that only one thing has access to the protected code at a time. Use `RWMutex` when it’s safe to allow many readers to have access, but you want to make sure that access is exclusive if you need "write access," that is, you intend to update a variable that is protected by the lock.

This post isn't an exhaustive exploration of locks. However, I think it’s important to note that there are many types of lock and many implementations of those locks. Each of those comes with its own set of drawbacks. A safe rule of thumb is that no two locks are the same, including no two read/write lock implementations. Before using a lock, be sure you understand its performance characteristics and, if performance is important to you, be sure to benchmark different implementations using your specific workload.

Here's my rule of thumb:

Locks are bad. Avoid them. Except of course you can't. But where possible, if you care about concurrency, design your program so you don't need locks and, where you do need them, try to limit the contention on them (like we did in [part 1](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-1--the-pointering/) by moving from `BigOldMap` to `ConcurrentMap`).

## `RWMutex` doesn't scale

Saying, "you need to benchmark different implementations" is one thing. I think it would help to drive home the point a little. Here we go, `sync.RWMutex` in the Go standard library doesn't scale with the number of CPUs available. No really, you don't have to believe me, [there's an open issue](https://github.com/golang/go/issues/17973), and the developer of `drwmutex` has some [quickly accessible numbers](https://github.com/jonhoo/drwmutex/) to demonstrate it as well.

The critical point here is, locks are tricky. Performance is tricky on its own. When you start adding in contention with locks, look out!

And here's the kicker. Even if you don't introduce locks, you still might run into problems with locks and need to understand the performance characteristics of different locks.

## Beware! There might be a lock in there!

Are you familiar with `Gob`? It's a serialization format that ships with the [Go standard library](https://golang.org/pkg/encoding/gob/). You might be using it right now. The code you rely on might be using it. Did you know there's a mutex in the [Gob decoder](https://github.com/golang/go/blob/22115859a513b77ed9d966a356902630eff9e71b/src/encoding/gob/decoder.go)?

Well, there is. You can see it defined [here](https://github.com/golang/go/blob/22115859a513b77ed9d966a356902630eff9e71b/src/encoding/gob/decoder.go#L27), and used later [here](https://github.com/golang/go/blob/22115859a513b77ed9d966a356902630eff9e71b/src/encoding/gob/decoder.go#L204).

The comment there should give you pause:

> // Make sure we're single-threaded through here.

The point of my highlighting this isn't to spread [FUD](https://en.wikipedia.org/wiki/Fear,_uncertainty_and_doubt) about using Gob. Instead, I want to stress that there could be locks all over the place in your dependencies and if you're going to get excellent performance and scale smoothly, you need to know where they are and understand their impact.

## What’s next?

Check back in a couple of weeks for part 3 of our series. I'll be covering a performance issue in the Go runtime that impacts on applications that call Go from other languages.
