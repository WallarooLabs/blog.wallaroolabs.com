+++
title= "Python Python Python! Python 3 Comes to Wallaroo"
date = 2018-11-08T14:50:00-04:00
draft = true
author = "aturley"
description = "Wallaroo is a great solution for building scalable streaming data application in Python. We’ve added Python 3 support to bring it into the future."
tags = [
    "announcement",
    "python"
]
categories = [
    "announcement"
]
+++


If you’ve tried to build a scalable distributed system in Python you could be excused for thinking that the world is conspiring against you; in spite of Python’s popularity as a programming language for everything from data processing to robotics, there just aren’t that many options when it comes to using it to create resilient stateful applications that scale easily across multiple workers. About a year ago we created [the Wallaroo Python API](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/) to help address this problem. At the time we were working with some potential customers who were still using Python 2.7, so that’s what we targeted.

When we created the original Wallaroo Python API, we knew that we would eventually want to add support for Python 3, but Python 3 adoption was still moving slowly and we felt that there were other more pressing technical challenges to address first. But as time went on, we drew closer and closer to the [last day of Python 2.7](https://pythonclock.org/). Finally, GitHub user [caj-larsson](https://github.com/caj-larsson) offered to help us with the initial work to get Python 3 support off the ground.

If you’re familiar with what Wallaroo is, feel free to skip the next section.

### What is Wallaroo

Wallaroo is a framework designed to make it easier for developers to build and operate high-performance applications written in [Python](https://blog.wallaroolabs.com/2017/10/go-python-go-stream-processing-for-python/). It handles the complexity of building distributed streaming data processing applications so all that you need to worry about is the domain logic.

Our goal is to make sure—regardless of where your data is coming from—that you can scale your application logic horizontally. All while removing the challenges that otherwise come with distributed applications.

### From Python 2 to Python 3

Wallaroo's API was already Python 3 compatible, so the only changes Wallaroo needed were internal to the Wallaroo Framework. This allowed support to be added without introducing incompatibilities with existing applications. All of our [examples](https://github.com/WallarooLabs/wallaroo/tree/0.5.4/examples/python) work with both Python 2 and Python 3. But your application code can now use functions and constructs that only exist in Python 3, as well as libraries that are written in Python 3.

The biggest difference that impacted Wallaroo’s implementation was the difference between the way Python 2 and Python 3 treat strings and bytes. In Python 2, a string can contain any sequence of bytes, but in Python 3 strings are explicitly UTF-8 sequences. The differences are mostly transparent to the Wallaroo user, but there’s slightly different logic depending on which version of Python is being used.

Wallaroo programs using Python 2 are run using an executable called `machida`. We created a separate executable called `machida3` for running Python 3 programs. This makes it easier to see which version of Python is being used.

For more details, please take a look at the [Python API](https://docs.wallaroolabs.com/book/python/wallaroo-python-api.html) documentation.

### Using Python 3

Support for Python 3 has been tested to work with Python 3.5 on our [Docker image](https://docs.wallaroolabs.com/book/getting-started/docker-setup.html), our [Vagrant box](https://docs.wallaroolabs.com/book/getting-started/vagrant-setup.html), Ubuntu (Xenial, Artful, Bionic) and Debian (Stretch, Buster). Follow the setup directions for your system, and then [run an application](https://docs.wallaroolabs.com/book/getting-started/run-a-wallaroo-application-wallaroo-up.html) using `machida3` instead of `machida`. From there you can start building your own Python 3 applications.

### Conclusion

Wallaroo now lets you take advantage of the power of Python 3 when creating applications. This means that Wallaroo can move with your organization as you continue to use Python in the future.

We’re continuing to develop our Python API, so look for developments in the next few releases.

If you’re interested in giving the new Python 3 support a try, see the [available examples](https://github.com/WallarooLabs/wallaroo/tree/0.5.4/examples/python) and our [Python documentation](https://docs.wallaroolabs.com/book/python/wallaroo-python-api.html). This is a preview release of Python 3 support, so please let us know if you have thoughts or feedback. The best way is either via [IRC](https://webchat.freenode.net/?channels=#wallaroo) or [our mailing list](https://groups.io/g/wallaroo).

If you’re looking to get started with Wallaroo for the first time, you can install Wallaroo via docker:

```bash
docker pull \
  wallaroo-labs-docker-wallaroolabs.bintray.io/release/wallaroo:latest
```

Other installation options can be found [here](https://docs.wallaroolabs.com/book/getting-started/choosing-an-installation-option.html).

We at Wallaroo Labs would again like to extend a special thank you to [caj-larsson](https://github.com/caj-larsson), who did the first round of work on Python 3 support.
