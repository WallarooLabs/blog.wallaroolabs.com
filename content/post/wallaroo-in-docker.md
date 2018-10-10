+++
title = "Simplify Stream Processing in Python and Wallaroo using Docker"
date = 2017-12-20T07:45:00-05:00
draft = false
author = "jonbrwn"
description = "Simplifying the installation and setup process for Wallaroo using Docker."
tags = [
    "docker",
    "announcement",
    "installation",
]
categories = [
    "installation"
]
+++

Distributed data stream processing frameworks can be hard to build and setup. The complexities around building a framework of this sort include:

- Creating a robust communication layer between communicating processes
- Efficient sharding of data across multiple processes
- Replaying messages when failures occur
- Deduplicating data on message replay
- Minimizing data movement
- Handling system overloads: e.g. backpressure

Beyond that, setting up the development environment for a framework that solves these problems can include numerous amounts of steps.

[Wallaroo](https://github.com/WallarooLabs/wallaroo), a framework to make it easy for developers to build and operate high performance [distributed data processing applications written in Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/), handles the complexities around building a distributed stream processing application so you only have one thing to worry about: implementing domain logic. While we simplified the building part of this framework, we recognized that work could be done to simplify the installation and setup process. We have been continually looking for ways to make the getting started process with Wallaroo as easy as possible. In this post, I’m going to show you how we are making the installation and setup process easier using Docker.

## Setting up a distributed data process framework isn’t easy

High performance distributed data processing frameworks are by nature, complex. They often rely on specific versions of system libraries (at times specific to OS and OS version), specific versions of languages, and require installing multiple components. You would generally have to make extended modifications to your development environment in order to get started and are almost never left with instructions to uninstall or revert some of these changes.

## What’s hard about setting up Wallaroo?

One of the biggest hurdles while setting up Wallaroo is installing its dependency tree. In order to get high performance, Wallaroo is compiled down to native code and uses the ponyc runtime. We chose Pony to write Wallaroo because of its emphasis on performance and correctness, you can read more on that in our [Why we used Pony to write Wallaroo](/2017/10/why-we-used-pony-to-write-wallaroo/) blog post. However, that decision meant you will be installing tools you wouldn’t necessarily be using on your own. You could take 5 minutes to get everything installed or you could take 30+ minutes. Once you have installed the needed dependencies, you would then need to compile Wallaroo and a few of its support tools. To run an example Wallaroo application you’ll need to compile the following:

- **Giles Sender:** An application to send data into Wallaroo
- **Machida:** A program for running Wallaroo Python applications
- **Giles Receiver:** An application to receive the data coming out of Wallaroo
- **Cluster Shutdown Tool:** An application to instruct the Wallaroo cluster to shutdown cleanly

For a production application, some of these steps are unavoidable but we did want to minimize the number of steps you needed to take in order to get started with Wallaroo.

## Choosing Docker as a simplifier

We explored several options in order to simplify the getting started process and ultimately decided on Docker. If you aren’t familiar with Docker, it is a platform to build, ship, and run distributed applications in any environment. Docker uses containers in order to make this possible. A container is a packaged executable that includes the code, runtime, and system tools needed for it to run. There are two major advantages that Docker provided: Isolation and ease of installation.

### Isolation

- **Dependency Isolation:** By containerizing Wallaroo we were able to avoid having you install all of the required dependencies by having them preinstalled in the container. This significantly reduces the getting started time and means you won’t break your development environment by installing tools required by Wallaroo.
- **Application Isolation:** We can guarantee that the processes within the container won’t interact with any outside of the container. Thus, avoiding any potential conflicts with processes running on the host that may cause a negative user experience.
- **Controlled Environment:** We test to make sure everything works as expected but we can’t test on every machine. By running within a container we can guarantee that Wallaroo will work as expected on any of the platforms supported by Docker, removing some of the trouble that arises when compiling native code.

### Ease of Installation

- Installing Wallaroo became significantly quicker by dramatically reducing the number of steps to get started. With a single command, a user can have Wallaroo on their machine, ready to run.

Docker provided enough advantages for us to see it as a viable solution to improving the getting started process. However, in order to provide a development environment for you, there were a few additional things we needed to add.

## Disadvantages of Docker

In order to feel that Docker provided a solid development environment we needed two additional things from Docker: a persistent code base and dependency management. We couldn’t have an immutable development environment, which is what the Docker lifecycle is designed to be. We decided to add a run option for creating a persistent copy of the code you write while developing for Wallaroo. That means if you kill the Wallaroo container and decide to start a new one at another point, your code will be in the state you left it. An additional benefit is that you aren’t tied to using an editor within the container and can use the editor of your choice to write or edit Wallaroo applications.

We have also included a run option for persisting any Python modules you may install using [virtualenv](https://virtualenv.pypa.io/en/stable/). This way, you won’t have to re-install Python modules if you stop or delete the container. By adding these features, we felt confident in the Wallaroo Docker image providing a good development environment for getting started.

## Give Wallaroo in Docker a try

This is our first pass at creating a completely new setup process to make getting started with Wallaroo quick and easy. We’d love for you to give Wallaroo in Docker a try and give us your feedback. We have instructions for setting up Docker [here](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html) and instructions for running an example Wallaroo application in Docker [here](https://docs.wallaroolabs.com/book/getting-started/run-a-wallaroo-application-docker.html).
We hope you find getting started with Wallaroo in Docker and running one of our example applications easy. We’d love to hear feedback, whether you loved it, hated it, or think there are ways we can improve this process. Get in touch via our [mailing list](https://groups.io/g/wallaroo), our [IRC channel](https://webchat.freenode.net/?channels=#wallaroo), open an issue on [github](https://github.com/WallarooLabs/wallaroo/), or ping us on [Twitter](https://twitter.com/wallaroolabs).
