+++
title = "Reasons to scale horizontally"
slug = "horizontal-scaling-reasons"
date = 2018-11-20T11:00:00-04:00
draft = false
author = "seantallen"
description = "An introduction to horizontal scaling: what is it and why you might want to do it."
tags = [
  "foo"
]
categories = [
    "foo"
]
+++

Here at Wallaroo Labs, we build [Wallaroo](https://github.com/wallaroolabs/wallaroo) a distributed stream processor designed to make it easy to scale real-time Python data processing applications. That's a real mouthful. What does it mean? To me, the critical part is the "scale" from "easy to scale."

What does it mean to easily scale a data processing application? In the case of Wallaroo applications, it means that it's easy to [scale those applications horizontally](https://en.wikipedia.org/wiki/Scalability#Horizontal_and_vertical_scaling). 

In this post, I'm going to cover what horizontal scaling is, how it's different from vertical scaling, and some reasons why you would horizontally scale an application. 

By the time you finish this post, you should have a decent understanding of what horizontal scaling is and when you should consider doing it. 

## What is horizontal scaling?

When we in computer science discussing "scaling," we are referring to a process by which we add more "something" to a system to allow it to handle more "something else." For example, you might add more memory to your laptop to be able to run more programs at one time. That's a form of scaling your computer. The key idea is that you have a task that you want to accomplish and the lack of some resource is preventing you from accomplishing that task. In our laptop example, the resource you were lacking was memory. We can say that you were constrained by a lack of memory.

We further distinguish scaling into two broad categories: vertical scaling and horizontal scaling. Vertical scaling means that we add more of a resource to a single computer. For example, we add more disk space, more memory, or more CPUs. Each of these is a form of vertical scaling.

Eventually, vertically scaling is going to hit limits. We have a limit to the amount of memory and CPUs our computers can support. It varies from computer to computer, but the limit is there. Eventually, if we need to scale further, we need to scale by adding more computers. This process of adding more computers is horizontal scaling. 

![Picture of computers](/post/horizontal-scaling/types-of-scaling.png "Scaling!")

Scaling vertically is also known as "scaling up", whereas horizontal scaling is known as "scaling out." So vertical scaling is adding more resources to a single node in a system, and horizontal scaling is the process of adding more nodes to a system.

There are many reasons why you might want to horizontally scale a system. I'll be covering 3 of them:

- Handle more throughput
- Fault tolerance
- Need more resources than you can get from a single node

## Handle more throughput

Sometimes, you need to be able to handle more throughput than you can get from a single node. A typical scenario is to run multiple web servers to handle all that traffic that your popular website gets. Most small websites can get by with a single web server. As the site gets more popular, eventually that single web server isn't able to handle all the incoming requests, and more web servers will need to be added to handle the load.

For some use cases, horizontally scaling for throughput is easy to do. For other use cases, it can be challenging to increase your throughput by scaling horizontally. 

What's the difference between the scenarios where it's difficult and those where it’s easy? The primary difference is one of coordination. If you can add new nodes that don’t need to know anything about any other node, then it’s relatively straightforward to add new nodes that will allow you to handle more throughput.

Take our web server example. Websites can be a great candidate for scaling horizontally. If each web server has a copy of the content for the site (this is common for many websites), then we can add new node after new node after new node to handle more and more traffic. This is often called a "shared nothing" architecture. Each new web server is self-contained. They don't talk to each other, and they don't share any shared resources.

As you add coordination and communication between nodes, or if they depend on shared resources,scaling horizontally to handle more throughput starts to become more difficult.

## Fault tolerance

It's relatively common to see people want to add more nodes to a system to provide more fault tolerance. Adding more nodes to better cope with failures is often called "high-availability" or "HA." 

Let's say I have a website that is served by a single web server. If that web server goes down, my website is no longer available. Bummer. One approach I could take is to add more web servers so if one goes down, I still have others available. Adding more nodes works so long as each new node can operate independently from the others. If my website is a simple [static website](https://en.wikipedia.org/wiki/Static_web_page), then I can probably add more nodes and get higher fault tolerance. However, to achieve this, I need each of my webservers to be "stateless." This allows any individual node to handle any request to the system. Stateless, [shared-nothing](https://en.wikipedia.org/wiki/Shared-nothing_architecture) systems are the easiest to add fault tolerance to.

Even if my system isn't a stateless, shared-nothing system, it's still possible to add fault tolerance by scaling horizontally. Distributed databases provide fault tolerance by running on several nodes (3 or more) and then replicating data across those nodes. The number of replicas, also known as "the replication factor," allows us to survive the loss of some members of the system (usually referred to as a "cluster"). The higher the replication factor, the more nodes we can lose and continue to operate. Why? The data we need exists on more than 1 node so, even if we lose that node, we still access it somewhere in our cluster.

## Need more resources than you can get from a single node

When pursuing a vertical scaling strategy, you will eventually run up against limits. You won't be able to add more memory, add more disk, add more "something." When that day comes, you'll need to find a way to scale your application horizontally to address the problem.

Imagine a batch data processing system. Every night, it runs and churns through a bunch of files to create some business output. Over time, there are more and more input files that keep getting larger and larger. The increase in input volume results in more and more data that you need to hold in memory as you generate that very important business output. 

There's a physical limit to the amount of memory you can add to the machine doing the processing. You can upgrade to a machine that can hold still more memory but eventually, you aren't going to be able to keep getting beefier single nodes. You will reach a physical limit on the amount of memory you can add to a given node. You are going to need to add more nodes so you can keep adding more memory. Let’s say your machine has a maximum of 64 gigs of memory it can hold. When you hit that limit, if you need more memory, you’ll need to start adding additional nodes. Instead of being stuck at 1 machine with 64 gigs of memory, you can grow to have 2 machines, each of which has 64 gigs of memory. 

Scaling to handle a lack of a physical resource sounds like a relatively simple task. However, when your system grows big enough to actually require this kind of transition, you may find out that it is a painful engineering challenge. Why? We are talking about scaling a shared resource. Most applications that run on a single node don't have any means of taking a shared resource like memory (which is stateful) and working with it across more than one machine. Depending on your particular problem, there might be a framework to help you with that (like [Wallaroo](https://blog.wallaroolabs.com/2017/10/how-wallaroo-scales-distributed-state/)). 

Here's the important takeaway: if you think there is a decent chance that you will eventually need to scale horizontally because you will need more disk, memory, or CPUs, plan for it ahead of time. Know how you will do it, so you don't suddenly find yourself needing to do it in a couple of days, and your best case scenario is measured in weeks.

## Wrapping up 

Horizontal scaling is a deep and complicated subject. I hope you are feeling a little more educated than when you started this post. If you'd like to explore more, I'd recommend my [2018 Papers We Love San Francisco talk on Pat Helland's “Beyond Distributed Transactions”](https://www.youtube.com/watch?v=xI56ox7dcRQ&feature=youtu.be). The talk covers how to scale stateful applications horizontally and how we implemented them in Wallaroo.

Additionally, I'll be diving into different horizontal scaling related topics here on the blog and covering them in more depth. Up next, a scenario when it’s hard to achieve more throughput while horizontally scaling. [Sign up to receive notifications of new posts](https://blog.wallaroolabs.com/subscribe/) so you'll know when we publish more posts in this series.
