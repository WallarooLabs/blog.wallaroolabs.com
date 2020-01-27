+++
title = "Adventures with cgo: Part 1- The Pointering"
date = 2018-04-19T11:42:42-04:00
draft = true
author = "seantallen"
description = "We've learned quite a lot while working on the Go API for Wallaroo. Come along for the journey with us as we teach you about the fun and foibles that await when you go adventuring with cgo. In part 1, we cover fun with sharing pointers between the Go runtime and foreign systems."
tags = [
    "cgo",
    "golang",
    "performance"
]
categories = [
    "Adventures with cgo", "Exploring Wallaroo Internals"
]
+++
A lot of materials have been created to help Go programmers implement Go "best performance practices". The same can not be said of cgo performance. This is the first post in a series of posts that will discuss cgo performance considerations. Today's post will focus on calling Go code from another language like C. Let's get started by looking at a bit of background on our product Wallaroo and why we ended needing to become well-versed in the ways of cgo. Then, for those you who aren't familiar with what cgo is and how it differs from Go, a quick cgo primer. If you are familiar with [Wallaroo](https://github.com/wallaroolabs/wallaroo), it's [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/) and [cgo](https://golang.org/cmd/cgo/), feel free to skip ahead to ["What's tricky about calling Go from 'C'"](#what-s-tricky-about-calling-go-from-c).

## The Wallaroo Go Story

Wallaroo is a distributed stream processor. The first public release was of our [Python API](https://blog.wallaroolabs.com/2018/02/idiomatic-python-stream-processing-in-wallaroo/) in September 2017. Earlier this year, we did a preview release of our new [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/).

Wallaroo is not a pure Go system. The core of Wallaroo is written in [Pony](https://www.ponylang.io/). Developers writing Go applications using the Wallaroo Go API implement their logic in Go. Our [blog post introducing the Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/) has an excellent overview of what a developer is responsible for writing.

"Go applications" that are a hybrid of Go and code written in another language (like Pony or C) aren't actually "Go applications". They are "cgo applications."

## What is cgo?

Cgo is like Go, but not quite Go. Cgo allows you to call C code from Go and more importantly for Wallaroo, will enable you to call Go code from any language (like Pony) that supports a C-style [FFI](https://en.wikipedia.org/wiki/Foreign_function_interface).

You have to use cgo rather than Go if:

- you want to write code in Go and have it called from another language
- you want to call code written in another language from Go

Cgo isn't an FFI system. At a surface level it looks like one, but if you approach it expecting it to behave like a C-FFI system that you might have encountered with something like Python, you'll be in for surprises.

To get started learning more about cgo, I suggest the following resources:

The golang website has a [high-level overview of cgo](https://golang.org/cmd/cgo/). It's an excellent intro and covers some gotchas that will be surprising to anyone who tries to treat cgo as an FFI system.

Dave Cheney's ["cgo is not Go"](https://dave.cheney.net/2016/01/18/cgo-is-not-go) covers the many ways cgo is not Go and why the average Go user should avoid using cgo to write their application.

["The cost and complexity of cgo"](https://www.cockroachlabs.com/blog/the-cost-and-complexity-of-cgo/) from the folks over at CockroachDB provides a nice balance to Dave Cheney's piece and discusses in-depth why CockroachDB is a cgo application.

## What's tricky about calling Go from C

Short answer: pointers.

If you've written any amount of code that interfaces with C using FFI, then you've probably passed a lot of pointers around. You can't do that with cgo.

With cgo, you can’t [pass pointers to Go objects back to C code](https://golang.org/cmd/cgo/#hdr-Passing_pointers). Why?

Short answer: the Go garbage collector.

However, [it wasn’t always this way](https://github.com/golang/proposal/blob/master/design/12416-cgo-pointers.md). Before Go 1.6, you were allowed to pass pointers to Go objects back to C code. The change came about because of possible changes to the Go garbage collector.

Currently, the Go garbage collector doesn't move memory in when doing garbage collection. That is, after a garbage collection run is done, any Go objects that haven't been freed with still be in the same memory location. Not all garbage collectors work this way; some [will relocate objects in memory](http://www.cs.cornell.edu/courses/cs312/2003fa/lectures/sec24.htm) as part of the garbage collection process.

The developers of Go want to allow themselves the possibility of having the Go garbage collection process relocate objects in memory. To do that, they can't allow "external" pointers to Go objects.

As of Go 1.6, if you try to pass a pointer to a Go object back to C, your Go program will fail at runtime. From [the cgo documentation](https://golang.org/cmd/cgo/#hdr-Passing_pointers):

> These rules are checked dynamically at runtime. The checking is controlled by the cgocheck setting of the GODEBUG environment variable. The default setting is GODEBUG=cgocheck=1, which implements reasonably cheap dynamic checks. These checks may be disabled entirely using GODEBUG=cgocheck=0. Complete checking of pointer handling, at some cost in run time, is available via GODEBUG=cgocheck=2.

> It is possible to defeat this enforcement by using the unsafe package, and of course there is nothing stopping the C code from doing anything it likes. However, programs that break these rules are likely to fail in unexpected and unpredictable ways.

"Likely to fail in unexpected and unpredictable ways" is something we want to avoid, so, how do you work with Go objects from C? Particularly when your C code needs to maintain references to said Go objects?

Short answer: a big old map.

## Cgo and the big old map

The recommended way of having C code hold a pointer to a Go object is to have it hold non-pointer identifier to Go object which can, in turn, be used to lookup the Go object.

The simplest way to make this work would be to have a map of integers to Go objects. A data structure something like:

```go
type BigOldMap struct {
    mu sync.RWMutex,
    items map[uint64]interface{}
    nextID uint64
}

func (bom *BigOldMap) Add(item interface{}) uint64 {
    bom.mu.Lock()
    defer bom.mu.Unlock()

    bom.items[bom.nextId] = item
    lastId := bom.nextId
    bom.nextId++
    return lastId
}

func (bom *BigOldMap) Get(id uint64) interface{} {
    bom.mu.RLock()
    defer bom.mu.RUnlock()

    return bom.items[id]
}
```

Our C code can “hold on to references to Go objects”; in this case, a `uint64` instead of a pointer to a Go object. That integer allows the Go object to be accessed again later by calling `get` on our `BigOldMap`.

We’ve worked around cgo’s “C can’t hold references to Go pointers” problem, but our solution is somewhat naive and not sufficient for a high-performance, high-concurrency system like Wallaroo.

## What’s the problem with the big old map?

Short answer: it’s a concurrency nightmare. You have to put a write lock around any insert into your big old map. The lock creates a point of contention and contention is the concurrency killer.  No more than 1 Wallaroo thread can be updating the map at a single time. And if anything is updating the map, nothing can read. The same would apply in a pure Go application (except it would be only 1 goroutine at a time).

If you are trying to write a high-performance, highly-concurrent application, you aren't going to get very far with the naive "big old map approach."

So, what's the solution? Sharding! In our case, via a concurrent map.

## Concurrent map to the rescue

What is a concurrent map?

From the outside a concurrent map looks like a map but inside, it’s a bunch of maps (in common implementations). We don’t lock the “outer map,” instead, we lock one of the inner maps as needed.

Each “inner map” is a shard. We need to map keys to shards; getting this evenly balanced is important for performance. The more even your mapping of keys to shards, the better your performance. Additionally, the more shards you have, the less likely you are to have contention around a given lock. However, each shard requires additional memory for the “inner map” and the lock to protect it.

Benchmarking is required to find an optimum number of shards for a given workload.  (Most “in the wild implementations I’ve seen default to 64 or 128 shards).

Here's an example of a concurrent map in Go:

```
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

## What’s the impact

Replacing the big old map with a concurrent map was one of many changes that we’ve made so far while improving the performance of the Wallaroo Go Preview Release. This isn’t a post about benchmarking, but to give you a rough idea of the impact of this change, before we made the changes, [our simple test application](https://blog.wallaroolabs.com/2018/03/performance-testing-a-low-latency-stream-processing-system/) was able to handle ~70k messages a second using 8 threads/CPUs, after the change it handled ~160k  messages with the same number of CPUs. Additionally, after the change, there was a significant drop in tail latencies.

In general, moving from a lock around a single map to a concurrent hash map, you’d expect to see a bigger performance increase than we saw with our test application. The "why" of that will be covered in part 3 of this series.

In general, your mileage will vary and you need to do your own benchmarking on possible concurrent data structures. For example, the Go standard library offers a [sync.Map](https://golang.org/src/sync/map.go) concurrent map. For our [particular workload that we were using when testing our changes](https://blog.wallaroolabs.com/2018/03/performance-testing-a-low-latency-stream-processing-system/), we didn’t see much improvement with sync.Map.

## What’s next?

We're working on a series of performance improvements for Wallaroo Go applications. Over the next few weeks, I'll have a few more post on the topic. Check back next week for [part 2](https://blog.wallaroolabs.com/2018/04/adventures-with-cgo-part-2--locks-and-other-things-that-go-bump-in-the-night/) of our series, I’ll cover how we can further improve on the concurrent map solution above. In the meantime, you can give the [preview release of Wallaroo a test spin](https://docs.wallaroolabs.com/book/go/getting-started/setup.html).
