+++
title = "A Scikit-learn pipeline in Wallaroo"
draft = false
date = 2017-11-16T00:00:00Z
tags = [
    "wallaroo",
    "machine learning",
    "python",
    "example",
    "tutorial"
]
categories = [
    "Machine Learning"
]
description = "Creating an inference pipeline with MNIST"
author = "amosca"
+++

Nowadays, many applications with streaming data are either applying machine learning or have a very good use case for it. In this example, we will explore how we can build a sample pipeline to classify images from the [MNIST dataset](ihttp://yann.lecun.com/exdb/mnist/), using PCA and a regression tree in scikit-learn. As a prerequisite, you should be familiar with some notions of machine learning, and some notions about Wallaroo pipelines.
Everything has been implemented in the [current version of Wallaroo (0.2.2)](https://github.com/WallarooLabs/wallaroo/tree/0.2.2). The full code can be found on [GitHub](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/sklearn-example). If you have any technical questions that this post didn't answer, or if you have any suggestions, please get in touch at [hello@WallarooLabs.com](mailto:hello@WallarooLabs.com), via [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).



## Traning vs Inference

Before we begin looking at any code, we need to make a small distinction.  A machine learning process has two distinct stages: training and inference.  During the training phase, we are creating the model itself, and we prepare it using a dataset that has been designed to do so. Typically, one would then take the trained model and use it repeatedly to make inferences about new, unseen data (hence the "inference" name for the phase).

Whilst training is indeed a fundamental part of the machine learning process, stream computing lends itself much better to those situations where the model is being used for inference, perhaps as part of a bigger pipeline which may include data pre-processing and result intrepretation. Therefore, this blog entry concentrates on how we can use an existing trained model to make inferences on a very data stream of images.

## Creating the models

Even though we have said that the focus will be on inference, we still need to create some models to be able to use them. In this case, all the code for training is contained in `train_models.py`. We invite you to take a detailed look at it, but for the sake of this blog entry we only need to know that it is training a PCA for data preprocessing and a logistic regression for classification. The two models are then serialized to disk using sklearn's built-in pickle compatibility, to two separate file: `pca.model` and `logistic.model`.

## Application Setup

Our application will contain two separate computations, one for the PCA transformation and one for the classification itself.
We set up our Wallaroo application as follows

```python
def application_setup(args):
    with open('pca.model', 'r') as f:
        pca = pickle.load(f)
    with open('logistic.model', 'r') as f:
        logistic = pickle.load(f)
    global pca
    global logistic

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

Note how we are loading our model in `application_setup` and making them global.  This is because loading a pickled scikit-learn model could be a potentially expensive operation, and we want to ensure we do it only once per worker. By doing so in the application_setup, the models are only loaded during initialization, and made available to the computations via the `global` keyword.

### Decoder

We will be sending pickled images from a specialised sender application, and we will have to unpickle them in the decoder as they are received

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

The encoder simply packs the result into a string and sends it across the wire.

```python
@wallaroo.encoder
def encode(data):
    s = str(data)
    return struct.pack('>I{}s'.format(len(s)), len(s), s)
```

## Sending data to Wallaroo

In order to send data into Wallaroo, we must use a special sender that knows how to pickle the images in the right way. We can create this sender by formatting our messages such that they match the working of the decoder:

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

## Next steps

There are obvious limitations to this basic example. For instance, there is no partitioning. And we of course realize that MNIST isn't a useful dataset beyond examples. A lot of extra functionality can be added to production-level code, but for the purpose of illustrating how to run scikit-learn algorithms in Wallaroo, we preferred to narrow the focus and reduce distractions.

If you’d like to see the full code, its available on [GitHub](https://github.com/WallarooLabs/wallaroo_blog_examples/tree/master/non-native-event-windowing). If you would like to ask us more in-depth technical questions, or if you have any suggestions, please get in touch via [our mailing list](https://groups.io/g/wallaroo) or [our IRC channel](https://webchat.freenode.net/?channels=#wallaroo).
