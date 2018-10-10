+++
title= "Wallaroo Up: automating the Linux developer experience for Wallaroo"
date = 2018-08-30T00:00:00-00:00
draft = false
author = "dipin"
description = "Streamlining the Wallaroo installation process with Wallaroo Up."
tags = [
	"installation",
  "announcement"
]
categories = [
	"installation",
  "announcement"
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

[Wallaroo](https://github.com/WallarooLabs/wallaroo), a framework to make it easy for developers to build and operate high performance distributed data processing [applications written in Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) and [applications written in Go](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/), handles the complexities around building a distributed stream processing application so you only have one thing to worry about: implementing domain logic. While we simplified the building part of this framework, we recognized that work could be done to simplify the installation and setup process. We have been continually looking for ways to make the getting started process with Wallaroo as easy as possible. In this post, I’m going to show you how we are making the installation and setup process easier using automation via Wallaroo Up.

## Setting up a distributed data process framework isn’t easy

High performance distributed data processing frameworks are by nature, complex. They often rely on specific versions of system libraries (at times specific to OS and OS version), specific versions of languages, and require installing multiple components. You would generally have to make extended modifications to your development environment in order to get started and are almost never left with instructions to uninstall or revert some of these changes.

## What’s hard about setting up Wallaroo?

One of the biggest hurdles while setting up Wallaroo is installing its dependency tree. In order to get high performance, Wallaroo is compiled down to native code and uses the ponyc runtime. We chose Pony to write Wallaroo because of its emphasis on performance and correctness, you can read more on that in our [Why we used Pony to write Wallaroo](/2017/10/why-we-used-pony-to-write-wallaroo/) blog post. However, that decision meant you will be installing tools you wouldn’t necessarily be using on your own. You could take 5 minutes to get everything installed or you could take 30+ minutes. Once you have installed the needed dependencies, you would then need to compile Wallaroo and a few of its support tools. To run an example Wallaroo application you’ll need to compile the following:

- **Giles Sender:** An application to send data into Wallaroo
- **Machida:** A program for running Wallaroo Python applications
- **Go Compiler:** Compiler for building Wallaroo Go applications
- **Data Receiver:** An application to receive the data coming out of Wallaroo
- **Cluster Shutdown Tool:** An application to instruct the Wallaroo cluster to shutdown cleanly

For a production application, some of these steps are unavoidable but we did want to minimize the number of steps you needed to take in order to get started with Wallaroo.

## Wallaroo Up

We explored several options in order to simplify the getting started process and have previously provided one [simplified option via Docker](https://blog.wallaroolabs.com/2017/12/simplify-stream-processing-in-python-and-wallaroo-using-docker/). However, there are some drawbacks to Docker for a development environment as mentioned in the Docker blog post. Wallaroo Up is a faster, easier, and less error-prone way to install Wallaroo on Linux than our manual install from source instructions. With Wallaroo Up, you can now accomplish in one command what used to take 20 mins and multiple commands to complete. Additionally, Wallaroo Up also introduces a way to run the Wallaroo Metrics UI without Docker; making this the first time you can install Wallaroo without needing Docker installed. We created Wallaroo Up because we've heard your feedback that our current process is onerous. With Wallaroo Up the process is much shorter, has less potential for error and supports many Linux distributions.

## Functionality

Wallaroo Up officially supports CentOS 7, Fedora 28, Debian Stretch, Ubuntu Trusty, Ubuntu Xenial, and Ubuntu Bionic Linux distributions. Additionally, it should work on Red Hat Enterprise Linux 7, Fedora 26, Fedora 27, Ubuntu Artful, Debian Jessie, Debian Buster/Testing Linux distributions.

Wallaroo Up allows you to preview the actions it will take (including adding repositories, installing development compilers and libraries, and setting up Wallaroo itself) and also keeps a detailed log of all actions to ensure you're able to examine everything that it does. Wallaroo Up takes the first step to allow you to have multiple versions of Wallaroo installed concurrently by installing each version of Wallaroo in its own version specific directory. Wallaroo Up also includes a handy script to source that automagically sets up your environment for compiling and running wallaroo applications (i.e. like python virtualenv).

![Wallaroo Up](/images/post/wallaroo-up/wallaroo-up.png)

## Future

We're very excited with Wallaroo Up and opening up Wallaroo to more of you. We're planning to add support to Wallaroo Up for more Linux distributions (let us know which ones you use via [twitter](https://twitter.com/wallaroolabs), [IRC](https://webchat.freenode.net/?channels=#wallaroo), [email](hello@wallaroolabs.com), [our mailing list](https://groups.io/g/wallaroo), or [a github issue](https://github.com/WallarooLabs/wallaroo/issues/new)). We're also looking to enhance Wallaroo Up to be able to handle errors more gracefully and automagically retry when possible.

We would like to encourage you to give Wallaroo Up a try, just run the following to get up and running:

```
curl -o /tmp/wallaroo-up.sh -J -L \
  https://raw.githubusercontent.com/WallarooLabs/wallaroo/0.5.2/misc/wallaroo-up.sh
# replace python with golang for Wallaroo Go
bash /tmp/wallaroo-up.sh -t python
```

Wallaroo provides a robust platform that enables developers to implement business logic within a streaming data pipeline quickly. Wondering if Wallaroo is right for your use case? Please reach out to us at [hello@wallaroolabs.com](hello@wallaroolabs.com), and we’d love to chat.
