+++
title = "Identifying Trending Twitter Hashtags in Real-time with Wallaroo"
date = 2017-11-14T12:00:00-04:00
draft = false
slug = "twitter-hashtags-real-time"
author = "haneemedhat"
description = "Using Wallaroo to connect to a real-time twitter stream and find trending hashtags"
tags = [
    "wallaroo",
    "twitter",
    "tutorial",
    "example"
]
categories = [
    "Tutorial",
    "Examples"
]
+++


This week we have a guest post written by Hanee' Medhat

Hanee' is a Big Data Engineer, with experience working with massive data in many industries, such as Telecommunications and Banking.

## Overview

One of the primary places where the world is seeing an explosion of data growth is in social media.  [Wallaroo](http://www.wallaroolabs.com/community) is a powerful and simple-to-use open-source data engine that is ideally suited for handling massive amounts of streaming data in real-time.

In this tutorial, I will use Wallaroo to analyze and extract insights from Twitter in real-time and present the results on a dashboard.

First, a little background on Wallaroo.  Wallaroo is a relatively new open-source project that has been getting a lot of attention recently.  Wallaroo Labs, the company behind the project, has shared a good deal of information about their approach and technology. You may have seen some of their recent blog articles on Hacker News.

You can find more information about Wallaroo by visiting [this site](https://wallaroolabs.com/community).

Wallaroo allows developers to write code in native Python and, unlike other streaming projects, doesn't require using Java or the JVM. I was intrigued by their approach and wanted to see how easy it would be to use Wallaroo to do some analysis on Twitter data.

## Tutorial

This post shows a real use case on a massive online data stream, using Wallaroo’s Python API. We will show how easy it is to transform data streams with a small amount of code.

We will create an application that reads a real data stream from Twitter, extracts hashtags, and counts them to identify the top trending hashtags on Twitter. You can create the needed files on your own or follow along by cloning the [Wallaroo Twitter Trending Example](https://github.com/WallarooLabs/wallaroo-twitter-trending-example) from GitHub.


### 1. Install Wallaroo

Before we get started, you should make sure you have Wallaroo installed.  You can find detailed instructions [here](https://docs.wallaroolabs.com/book/getting-started/setup.html).



### 2. Register for Twitter APIs

In order to get real-time tweets, you need to register on [Twitter
Apps](https://apps.twitter.com/) by clicking on “Create new app”, and
filling in the form under “Create your twitter app”.

![](/images/post/twitter-hashtags-real-time/credentials.png)

Go to your newly created app and open the “Keys and Access
Tokens” tab, then click on “Create my access token”.

![](/images/post/twitter-hashtags-real-time/credentials_2.png)

Your new access tokens will appear like this:

![](/images/post/twitter-hashtags-real-time/credentials_3.png)



### 3. Create Twitter Client

Let's start by creating a client that connects to the Twitter API in order to grab the tweets and send them to Wallaroo.

`twitter_client.py` connects to Wallaroo using a TCP connection, calls the Twitter Streaming API to get the tweets in real-time, and forwards them to Wallaroo in order to be processed.

We connect to our Wallaroo application via a socket on `('localhost', 8002)`, then call `get_tweets()`, which initiates the connection to Twitter and forwards the tweets to Wallaroo, with the help of `send_tweets_to_wallaroo(http_resp, tcp_connection)`.

Note that in `send_tweets_to_wallaroo(http_resp, tcp_connection)` we compute `payload_length` for each tweet and format it as a 5-digit string (e.g. `'00005'`), which is sent along with the tweet.

```python
import socket
import sys
import requests
import requests_oauthlib
import json

# Replace the values below with yours
ACCESS_TOKEN = ''
ACCESS_SECRET = ''
CONSUMER_KEY = ''
CONSUMER_SECRET = ''
my_auth = requests_oauthlib.OAuth1(CONSUMER_KEY, CONSUMER_SECRET,ACCESS_TOKEN, ACCESS_SECRET)


def send_tweets_to_wallaroo(http_resp, tcp_connection):
    for line in http_resp.iter_lines():
        try:
            full_tweet = json.loads(line)
            if 'text' in full_tweet:
                tweet_text = full_tweet['text'].encode('utf-8')
                # send the length of text + 1 for newline represented as 5 ASCII
                # characters, followed by the tweet text and \n
                # e.g. if tweet text is 'Hello everyone!', send '00016Hello everyone!'
                tcp_connection.sendall(str(len(tweet_text)+1).zfill(5) +
                        tweet_text + '\n')
        except:
            print "Error decoding data received from Twitter!"


def get_tweets():
    url = 'https://stream.twitter.com/1.1/statuses/filter.json'
    query_data = [('locations', '-130,-20,100,50'), ('track', '#')]
    query_url = url + '?' + '&'.join([str(t[0]) + '=' + str(t[1]) for t in query_data])
    response = requests.get(query_url, auth=my_auth, stream=True)
    return response


# Create a TCP/IP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

# Connect to Wallaroo
wallaro_input_address = ('localhost', 8002)

print 'connecting to Wallaroo on %s:%s' % wallaro_input_address
sock.connect(wallaro_input_address)

resp = get_tweets()
send_tweets_to_wallaroo(resp,sock)
```

### 4. Create the Wallaroo Application

Now we can build the Wallaroo application that identifies the trending hashtags on the real-time stream.

The Wallaroo application logic is self-contained in `twitter_wallaroo_app.py`. We start by importing all the needed libraries.

```python
import struct
import wallaroo
import pandas as pd

```

### 5. Create The Decoder

The [Decoder](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) will translate the raw messages from the network connection and feed the resulting messages to the computations. Create a class called `Decoder` that implements the following three methods.

* `header_length(self)`: This method returns a fixed integer that represents the number of bytes that hold the value of `payload_length`. In this case we return 5, which denotes that the value of `payload_length` is held in 5 bytes.

* `payload_length(self, bs)`: This method takes a parameter `bs` which holds the number of bytes from `header_length` above; in our case 5 bytes of data. We then unpack these into an integer that denotes the length of the current message’s data payload to be read from the network stream.
These are the same 5 bytes that are being sent by `send_tweets_to_wallaroo(http_resp, tcp_connection)` in the Twitter client. For example, if we receive `'00006'`, it is converted to integer value `6`, which tells wallaroo to read the next 6 bytes and give them to the `decode` method.

* `decode(self, bs)`: this method reads the data payload sent through the network, the length of which was returned by `payload_length`. In this case, we convert the bytes to a UTF-8 string and pass that along to the computation.


```python
class Decoder(object):
    def header_length(self):
        return 5

    def payload_length(self, bs):
        return int(struct.unpack("!5s", bs)[0])

    def decode(self, bs):
        return bs.decode("utf-8")
```

### 6. Create The Computation

Now let’s define the [computation](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) class which will be used in the data processing logic. We will be applying this on the tweets received from the Decoder in order to extract all the Hashtags.

Our computation is called `HashtagFinder`, and like all computations, it must implement the following two methods:

* `name(self)`:  returns the name of the computation step.
* `compute(self, input_data)`: takes a parameter `input_data`, containing the data coming from the previous step and implements the current step’s logic.

In this case, we are splitting each tweet into words first, then filtering only for words that begin with `#`, and passing the hashtags along to the next step.

```python
class HashtagFinder(object):
    def name(self):
        return "HashtagFinder"

    def compute_multi(self, data):
        return [word.strip() for word in data.split() if word[0] == '#']
```

### 7. Create The State and StateBuilder

This is a crucial step. We want to count how many times each hashtag was mentioned, and to do so we need to track this information in a [stateful computation](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html). We do this via `State` and `StateBuilder` classes.

We created the State class `HashtagCounts`, which contains a pandas dataframe that holds all aggregated hashtag counts, and is updated at each event.

This State class has the following three methods:

* `__init__(self)`: here we declare and prepare the dataframe that will hold the hashtags counts.
*  `update(self, hashtag_name, counts)`: This method is called in the computation step, in order to update the dataframe with the new values. We add the hashtag and its current count to the dataframe if it is not found, otherwise we increment the count.
*  `get_counts(self)`: This gets the data we want to send to the next step, in the form of a dictionary contaning the counts for the top 10 hashtags.

```python
class HashtagCounts(object):

    def __init__(self):
        self.hashtags_df = pd.DataFrame(columns=['Hashtag','Counts'])
        # We want to be addressing by Hashtag most frequently
        self.hashtags_df = self.hashtags_df.set_index(['Hashtag'])
        # Counts is an int
        self.hashtags_df['Counts'] = self.hashtags_df['Counts'].astype('int')

    def update(self, hashtag_name, counts):
        # if the hashtag is already exists then add its counts to old counts
        # and if not exists, then add it in the dataframe with its current counts
        curr_count = 0
        if hashtag_name in self.hashtags_df.index:
            curr_count = self.hashtags_df.loc[hashtag_name]
        self.hashtags_df.loc[hashtag_name] = curr_count + counts

    def get_counts(self, n=10):
        # Return from the dataframe a dict of top n hashtags
        return self.hashtags_df.nlargest(n,'Counts').to_dict()['Counts']

    def get_count(self, c):
        # int is safe to return as is!
        return self.hashtags_df.loc[c]
```

We also need a StateBuilder class called `HashtagsStateBuilder` that will be used to create State objects from within Wallaroo.

```python
class HashtagsStateBuilder(object):
    def build(self):
        return HashtagCounts()
```
### 8. Create StateComputation

Next is the [StateComputation](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) class that updates the State object. This is similar to a regular Computation, but the `compute` method has an additional `state` argument, which holds the state object.

```python
class ComputeHashtags(object):
    def name(self):
        return "ComputeHashtags"

    def compute(self, data, state):
        # update the state object with the current data
        state.update(hashtag_name=data, counts=1)
        # returns the top 10 hashtags data from the state object
        return (state.get_counts(), True)
```

### 9. Create The Encoder

We can now define the last component of our application: the [Encoder](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) class. Here we transform the data to an array of all hashtags and an array of their counts, to be sent through the network to the front end application.


```python
class Encoder(object):
    def encode(self, data):
        # extract the hashtags from dataframe and convert them into array
        top_tags = [str(hashtag.encode("utf-8")) for hashtag in data]
        # extract the counts from dataframe and convert them into array
        tags_count = [data[hashtag] for hashtag in data]
        # transform the data to be as array of labels and array of counts
        request_data = {'label': str(top_tags), 'data': str(tags_count)}
        # return the data to TCP connection along with a special separator
        return str(request_data) + ';;\n'
```

### 10. Create The ApplicationBuilder

We now need to create the [application topology](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html) from the module’s `application_setup` method.

We create an `ApplicationBuilder` with the name `Trending Hashtags`, and added the following components:

* a `new_pipeline`, with a TCP source with the input and output connection configuration that was passed from the command line, and an instance of our `Decoder`.
* a `HashtagFinder` computation after the input in order to extract the hashtags from the tweets.
* a stateful `ComputHashtags` computation. Note that we also have to pass an instance of the StateBuilder.
* a TCP data sink, and an instance of our `Encoder`, as the output of the data flow.


```python
def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]
    ab = wallaroo.ApplicationBuilder("Trending Hashtags")
    ab.new_pipeline("Tweets_new", wallaroo.TCPSourceConfig(in_host, in_port, Decoder() ))
    ab.to(HashtagFinder)
    ab.to_stateful(ComputeHashtags(), HashtagsStateBuilder(), "hashtags state")
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, Encoder()))
    return ab.build()
```



### 11. Create The Data Receiver

We'll now create an adaptor that will collect the output from our Wallaroo application and send it to the RESTful front-end application. The code for this part is in `socket\_receiver.py`.

The code is very simple, it connects to the TCP output of Wallaroo and looks for our pre-determined message separator `(;;)`, and sends each message to the RESTful web service shown in the next step.


```python
import socket
import requests
import ast

TCP_IP = "localhost"
TCP_PORT = 7002
conn = None
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind((TCP_IP, TCP_PORT))
s.listen(1)
print("Waiting for TCP connection...")
conn, addr = s.accept()
print("Connected... Waiting for data....")

buffer = ""
while True:
    data = conn.recv(5000)
    if not data:
        print("no data received")
        break
    buffer += data
    while True:
        # check if the separator doesn't exist then continue fetching data from network to the buffer
        if ';;' not in buffer:
            break
        # split the buffer data by the separator to extract the full complete data
        # and put the remaining text again in the buffer
        full_message, separator, buffer = buffer.partition(';;')

        # initialize and send the data through REST API
        url = 'http://localhost:5003/updateDashboard'

        # replace some escaping characters that have been added to the data while conversion
        full_message = full_message.replace("\'","'").replace("\\\\","\\")
        # send the data to the RESTful Webservice as a dictionary
        response = requests.post(url, data=ast.literal_eval(full_message))
```

### 12. Create The Dashboard Application

To be able to view the results of our application, we’ll create a simple dashboard that we will update in real-time using Wallaroo’s output.
We’ll build it using Python, Flask and
[Charts.js](http://www.chartjs.org/)

First let’s create a Python project with the below structure, and
download and add the
[Chart.js](https://github.com/chartjs/Chart.js/releases/download/v2.4.0/Chart.js)
file into the static directory.

![](/images/post/twitter-hashtags-real-time/dashboard_app.png)

Then, in `app.py` file, we’ll create a function called `update\_dashboard`
that can be called (by `socket\_receiver.py`) through this URL:
`http://localhost:5001/updateDashboard`

`refresh\_dashboard` is created for periodic Ajax requests that return the new updated `hashtags` and `counts` arrays as JSON.

`get_chart` will render `index.html`.

```python
from flask import Flask,jsonify,request
from flask import render_template
import ast


app = Flask(__name__)

hashtags = []
counts = []


@app.route("/")
def get_chart():
    global hashtags,counts
    hashtags = []
    counts = []
    return render_template('index.html', counts_data=counts, hashtags_data=hashtags)


@app.route('/refreshDashboard')
def refresh_graph_data():
    global hashtags, counts
    return jsonify(r_hashtags=hashtags, r_counts=counts)


@app.route('/updateDashboard', methods=['POST'])
def update_data_post():
    global hashtags, counts
    if not request.form or 'data' not in request.form:
        return "error: no data",400
    hashtags = ast.literal_eval(request.form['label'])
    counts = ast.literal_eval(request.form['data'])
    return "success",201


if __name__ == "__main__":
    app.run(host='localhost', port=5003)
```

Now let’s create a simple chart in `index.html` to display the hashtags data and update them in real-time.

In the body tag, we have to create a canvas and give it an ID in order
to reference it while displaying the chart using JavaScript in the next
step.

```html
<!DOCTYPE html>
<html>
    <head>
        <meta charset="utf-8"/>
        <title>Top Twitter Hashtags Using Wallaroo</title>
        <script src='static/Chart.js'></script>
        <script src="//ajax.googleapis.com/ajax/libs/jquery/1.9.1/jquery.min.js"></script>
    </head>

    <body>
        <center>
            <h2>Top Twitter Hashtags Using Wallaroo</h2>
            <div style="width:800px;height=500px">
                <canvas id="chart"></canvas>
            </div>
        </center>
	</body>
</html>
```

Now let’s construct the chart using the JavaScript code below. First we
get the canvas element.  Then we create a new chart object, and pass it the
canvas and data.

The last part is the function that repeats an Ajax request every second to `/refreshDashboard`, which returns the updated data for the chart.

```javascript
<script>

           var ctx = document.getElementById("chart");

           var myChart = new Chart(ctx, {
                type: 'horizontalBar',
                data: {
                    labels: [{% for item in hashtags_data %}
                              "{{item}}",
                             {% endfor %}],
                    datasets: [{
                        label: 'Hashtags Counts',
                        data: [{% for item in counts_data %}
                                  {{item}},
                                {% endfor %}],
                        backgroundColor: [
                            'rgba(255, 99, 132, 0.2)',
                            'rgba(54, 162, 235, 0.2)',
                            'rgba(255, 206, 86, 0.2)',
                            'rgba(75, 192, 192, 0.2)',
                            'rgba(153, 102, 255, 0.2)',
                            'rgba(255, 159, 64, 0.2)',
                            'rgba(255, 99, 132, 0.2)',
                            'rgba(54, 162, 235, 0.2)',
                            'rgba(255, 206, 86, 0.2)',
                            'rgba(75, 192, 192, 0.2)',
                            'rgba(153, 102, 255, 0.2)'
                        ],
                        borderColor: [
                            'rgba(255,99,132,1)',
                            'rgba(54, 162, 235, 1)',
                            'rgba(255, 206, 86, 1)',
                            'rgba(75, 192, 192, 1)',
                            'rgba(153, 102, 255, 1)',
                            'rgba(255, 159, 64, 1)',
                            'rgba(255,99,132,1)',
                            'rgba(54, 162, 235, 1)',
                            'rgba(255, 206, 86, 1)',
                            'rgba(75, 192, 192, 1)',
                            'rgba(153, 102, 255, 1)'
                        ],
                        borderWidth: 1
                    }]
                },
                options: {
                    scales: {
                        yAxes: [{
                            ticks: {
                                beginAtZero:true
                            }
                        }]
                    }
                }
           });


           var src_Labels = [];
           var src_Data = [];

            setInterval(function(){
                $.getJSON('/refreshDashboard', {
                }, function(data) {
                    src_Labels = data.r_hashtags;
                    src_Data = data.r_counts;
                });

                myChart.data.labels = src_Labels;
                myChart.data.datasets[0].data = src_Data;
                myChart.update();

            },1000);

</script>
```

### 13. Run The Application

Before we run our Twitter Trending Hashtags application, we need to make sure we have the proper Python dependencies installed. We depend on `pandas`, `requests_oauthlib`, and `flask`. These can be installed with the following commands:

```
pip install pandas requests_oauthlib flask
```

Now that we have built all the components, from grabbing the data all the way to representing it on a dashboard, the only remaining step it to run everything:

1. Run the Dashboard application: `app.py`
2. Run `socket_receiver.py`
3. Run the `twitter_wallaroo_app` from terminal using the below commands:

Note: The `machida` executable is in `machida/build/machida` in the [Wallaroo](https://github.com/wallaroolabs/wallaroo) repo. For example, if you’ve followed the Wallaroo installation [instructions](https://docs.wallaroolabs.com/book/getting-started/setup.html) then it will be in `$HOME/wallaroo-tutorial/wallaroo/machida/build/machida`. In order to run `machida` you will need to set up your `PYTHONPATH` to point to the `wallaroo.py` python library. For example, if you’ve followed the [Wallaroo installation instructions](https://docs.wallaroolabs.com/book/getting-started/setup.html) then `machida` will be `$HOME/wallaroo-tutorial/wallaroo/machida/build/machida` and you can set `PYTHONPATH` with `export PYTHONPATH=$HOME/wallaroo-tutorial/wallaroo/machida`

```
export PYTHONPATH="$PYTHONPATH:$HOME/wallaroo-tutorial/wallaroo/machida:."
```

```
$HOME/wallaroo-tutorial/wallaroo/machida/build/machida --application-module twitter_wallaroo_app \
  --in 127.0.0.1:8002 \
  --out 127.0.0.1:7002 \
  --metrics 127.0.0.1:5001 \
  --control 127.0.0.1:6000 \
  --data 127.0.0.1:6001 \
  --worker-name worker1 \
  --ponythreads=1 \
  --external 127.0.0.1:5050 \
  --cluster-initializer \
  --ponythreads=1 \
  --ponynoblock
```

4.  Run `twitter_client.py`

Now you can open the dashboard web application using URL:
<http://localhost:5001/>

you'll see the dashboard being updated in real-time.

![](/images/post/twitter-hashtags-real-time/Wallaroo_Dashboard.gif)

If you've run into trouble setting up the application and do not feel comfortable debugging the issue, we suggest using `virtualenv` to create an isolated Python environment. Here's a good [guide](http://docs.python-guide.org/en/latest/dev/virtualenvs/#lower-level-virtualenv) to help you get `virtualenv` setup if you have not done so already.

## Conclusion
In this post, we've learned how to do simple online data processing on live Twitter data using Wallaroo, and visualizing the results through a simple RESTful Web service.

Even in this simple example, we can see how Wallaroo is able to transform and process a large data stream in real-time, with very little boilerplate code.

If you're interested in learning more about Wallaroo, take a look at the the [Wallaroo documentation](https://docs.wallaroolabs.com) and some of the [examples](https://github.com/WallarooLabs/wallaroo/tree/release/examples/python/word_count) that we've built. Also, check out our [community page](https://www.wallaroolabs.com/community) to sign up for our mailing list or join our IRC channel to ask any question you may have.
