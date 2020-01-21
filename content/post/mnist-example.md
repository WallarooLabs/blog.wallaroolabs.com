+++
title = "A Scikit-learn pipeline in Wallaroo"
draft = true
date = 2018-02-08T00:00:00Z
tags = [
    "python",
    "example",
    "data engineering"
]
categories = [
    "example"
]
description = "Creating an inference pipeline with MNIST"
author = "amosca"
+++

While it would seem that machine learning is taking over the world, a lot of the attention has been focused towards researching new methods and applications, and how to make a single model faster. At Wallaroo Labs we believe that, to make the benefits of machine learning ubiquitous, there needs to be a significant improvement in how we put those impressive models into production. This is where the stream computing paradigm becomes useful: as for any other type of computation, we can use streaming to apply machine learning models to a large quantity of incoming data, using available techniques in distributed computing.

Nowadays, many applications with streaming data are either applying machine learning or have a use case for it. In this example, we will explore how we can build a machine learning pipeline inside Wallaroo, our high-performance stream processing engine, to classify images from the [MNIST dataset](http://yann.lecun.com/exdb/mnist/), using a basic two-stage model in Python. While recognizing hand-written digits is a practically solved problem, even a simple example like the one we are presenting provides a real use case (imagine automated cheque reading in a large bank), and the same setup can be used as a starting point for virtually any machine learning application - just replace the model.

We've been working on our processing engine, [Wallaroo](https://github.com/wallaroolabs/wallaroo/tree/release) for just under two years now. Our goal has been to make it as easy to build fast, scale-independent applications for processing data. When we open sourced Wallaroo last year, we provided an API that let developers create applications using [Python](https://blog.wallaroolabs.com/2018/01/how-to-update-your-wallaroo-python-applications-to-the-new-api/). The example discussed in this blog entry is written using that API. We also have a [Go API](https://blog.wallaroolabs.com/2018/01/go-go-go-stream-processing-for-go/). Everything has been implemented in the [current version of Wallaroo (0.4.0)](https://github.com/WallarooLabs/wallaroo/tree/0.4.0). The full code can be found on [GitHub](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/sklearn-example). If you have any technical questions that this post didn't answer, or if you have any suggestions, please get in touch at [hello@WallarooLabs.com](mailto:hello@WallarooLabs.com), via [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).

## The MNIST dataset

The MNIST dataset is a set of 60000 black and white images, of size 28 x 28 pixels, containing hand-written digits from 0 to 9. Each of these images has been classified, and it is often used as a benchmark for computer vision and machine learning. The pixels are real-valued, between 0 (completely black) and 1 (completely white).

## The model

One of the simplest models for classifying digits is a [Logistic Regression](https://en.wikipedia.org/wiki/Logistic_regression) on the numeric values of each pixel. An improvement to this simple model is to add a [Principal Component Analysis](https://en.wikipedia.org/wiki/Principal_component_analysis) preprocessing that presents the transformation with the most information content as an input to the classifier. We will be using this two-stage approach to classify our digits.

## Training vs. Inference

Before we begin looking at any code, we need to make a small distinction.  A machine learning process has two distinct stages: training and inference.  During the training phase, we are creating the model itself, and we prepare it using a dataset that has been designed to do so. Typically, one would then take the trained model and use it repeatedly to make inferences about new, unseen data (hence the "inference" name for the phase).

While training is indeed a fundamental part of the machine learning process, stream computing lends itself much better to those situations where the model is being used for inference, perhaps as part of a more significant pipeline which may include data pre-processing and result interpretation. Therefore, this blog entry concentrates on how we can use an existing trained model to make inferences on a very data stream of images.

## Creating the models

Even though we have said that the focus will be on inference, we still need to create some models to be able to use them. In this case, all the code for training is contained in [`train_models.py`](https://github.com/WallarooLabs/wallaroo_blog_examples/blob/master/sklearn-example/train_models.py). We invite you to take a detailed look at it, but for the sake of this blog entry, we only need to know that it is training a PCA for data preprocessing and a logistic regression for classification. The two models are then serialized to disk using sklearn's built-in pickle compatibility, to two separate files: `pca.model` and `logistic.model`.

## Application Setup

Our application will contain two separate computations, one for the PCA transformation and one for the classification itself. The flow of data is [In] --> Decoder --> PCA --> Logistic Regression --> Encoder --> [Out]
We set up our Wallaroo application as follows

```python
def application_setup(args):
    global pca
    global logistic
    with open('pca.model', 'r') as f:
        pca = pickle.load(f)
    with open('logistic.model', 'r') as f:
        logistic = pickle.load(f)

    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    ab = wallaroo.ApplicationBuilder("MNIST classification")
    ab.new_pipeline("MNIST",
                    wallaroo.TCPSourceConfig(in_host, in_port, decode))
    ab.to(pca_transform)
    ab.to(logistic_classify)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encode))
    return ab.build()
```

Note how we are loading our model in `application_setup` and making them global.  This is because loading a pickled scikit-learn model could be a potentially expensive operation, and we want to ensure we do it only once per worker. By doing so in the application_setup, the models are only loaded during initialization and made available to the computations via the `global` keyword.

### Decoder

We will be sending pickled images from a specialised sender application, and we will have to unpickle them in the decoder as they are received.

```python
@wallaroo.decoder(header_length=4, length_fmt=">I")
def decode(bs):
    return pickle.loads(bs)
```

### PCA Computation

The first computation applies the PCA that has been previously loaded.

```python
@wallaroo.computation(name="PCA")
def pca_transform(x):
    return pca.transform([x])
```

### Logistic Regression computation

The second computation applies the logistic regression, also previously loaded.

```python
@wallaroo.computation(name="Logistic Regression")
def logistic_classify(x):
    return logistic.predict(x)
```

### Encoder

The encoder packs the result into a string and sends it across the wire with a framed header containing the length of the string.

```python
@wallaroo.encoder
def encode(data):
    s = str(data)
    return struct.pack('>I{}s'.format(len(s)), len(s), s)
```

## Sending data to Wallaroo

To send data into Wallaroo, we must use a special sender that knows how to pickle the images in the right way. We can create this sender by formatting our messages such that they match the working of the decoder:

* 4 bytes representing the length of the message, followed by
* a UTF-8 encoded string, containing the pickled object

Our sender will send the entire MNIST dataset.

```python
import sys
import socket
import struct
from sklearn import linear_model, decomposition, datasets

import cPickle as pickle

def send_message(conn, x):
    msg = pickle.dumps(x)
    conn.sendall(struct.pack('>I', len(msg)))
    conn.sendall(msg)

if __name__ == '__main__':
    add = sys.argv[1].split(':')
    wallaroo_input_address = (add[0], int(add[1]))
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    print 'connecting to Wallaroo on %s:%s' % wallaroo_input_address
    sock.connect(wallaroo_input_address)
    digits = datasets.load_digits()
    for x in digits.data:
        send_message(sock, x)
```

## Running our application

To run our application, we need to follow these steps:

- start a listener so we can view the output : `nc -l 7002`
- start the Wallaroo application from within its directory: `PYTHONPATH=:.:../../../machida/ ../../../machida/build/machida --application-module digits --in 127.0.0.1:8002 --out 127.0.0.1:7002 --metrics 127.0.0.1:5001 --control 127.0.0.1:6000 --data 127.0.0.1:6001 --worker-name worker1 --external 127.0.0.1:5050 --cluster-initializer --ponythreads=1`
- send our files to Wallaroo via our sender: `python sender.py`

This will send the entire MNIST dataset to the Wallaroo application and will send the encoded output classifications to the `nc` program. If you look at the output, you will see something similar to the following:

```
[0][1][2][3][4][9][6][7][8][9][0][1]
```

where each classification is a list of one element, converted to its string representation before sending.

## Next steps

There are obvious limitations to this basic example. For instance, there is no partitioning. And we, of course, realize that MNIST isn't a useful dataset beyond examples. A lot of extra functionality can be added to production-level code, but for the purpose of illustrating how to run scikit-learn algorithms in Wallaroo, we preferred to narrow the focus and reduce distractions.

If you're interested in running this application yourself, take a look at the [Wallaroo documentation](https://docs.wallaroolabs.com) and the [Full source code](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/sklearn-example). You'll find instructions on setting up Wallaroo and running applications. And take a look at our [community page](https://www.wallaroolabs.com/community) to sign up for our mailing list or join our IRC channel to ask any question you may have.

You can also watch this video to see Wallaroo in action. Our VP of Engineering walks you through the concepts that were covered in this blog post using our Python API and then shows the word count application scaling by adding new workers to the cluster.

<iframe src="https://player.vimeo.com/video/234753585" width="640" height="360" frameborder="0" webkitallowfullscreen mozallowfullscreen allowfullscreen></iframe>

Our Python API is new, and we are looking for ways to improve it. We have a lot of ideas of our own, but if you have any ideas, we would love to hear from you. Please don’t hesitate to get in touch with us through [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).

We built Wallaroo to help people create applications without getting bogged down in the hard parts of distributed systems. We hope you'll take a look at our [GitHub repository](https://github.com/wallaroolabs/wallaroo) and get to know Wallaroo to see if it can help you with the problems you're trying to solve. And we hope to hear back from you about the great things you've done with it.
