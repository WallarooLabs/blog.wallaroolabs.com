+++
title= "Converting a Batch Job to Real-time"
date = 2018-09-06T00:00:00-00:00
draft = false
author = "erikn"
description = "In this post, we'll provide an overview of what stream processing is, some of the advantages it has over batch jobs and then take a brief look at an example."
tags = [
  "wallaroo",
  "example",
]
categories = [
  "python"
]
+++

## Introduction

Often called stream processing, real-time processing allows applications to run computations and filter data at any scale. At Wallaroo Labs, we build and offer support for an event-based stream processing framework called [Wallaroo](https://github.com/WallarooLabs/wallaroo). Frameworks like Wallaroo, allow you to do highly parallel computation across clusters of workers without having to worry about any additional complexity.

One of the things we hear from developers who aren’t familiar with stream processing is that they aren’t sure about the use cases. They’re used to using a periodic cron job to do calculations over data at a certain interval. In this post, I am going to take an application that would traditionally use batch processing and show how you could make it a real-time streaming application. This will allow our application to go from periodically triggering our application logic to running the same logic with real-time results.

For this example, imagine that you want to be able to take some data and let users set alerts on this data. Using Django and Celery I’ve created an application that ingests data from Coinbase using the coinbase-pro btc-usd websocket.

```python
wsClient = coinbaseWebsocketClient()
wsClient.start()
# ...
wsClient.close()
```

Using the coinbase-pro client, connecting and managing the websocket connection is pretty straightforward. Since we only care about what Bitcoin is selling and bought at, we filter out all the other kinds of transactions. Once these transactions are saved to a SQLite database, we’re able to perform our calculations.

## Celery Periodic Task Structure

I chose to use Celery to run our periodic tasks. Setting up Celery was pretty simple, just install the pip package and require the celery and crontab packages. For the purpose of this blog post, the calculation is pretty simple. Users set an alert on a price and we send an alert to the client when the average of the last ten minutes of BTC transactions are greater than the specified threshold (You can view the full file [here](https://github.com/enilsen16/pricealert/blob/master/pricealert/tasks.py)).

```python
@app.task
def notify_on_price():
    avg_price = calculate_average_price()
    alerts = get_alerts(avg_price)
    for alert in alerts:
        notify_user(alert, avg_price)
    return True
```

## Stream Processing Overview

There are quite a few problems with the approach above. Batch jobs are hard to scale and if our jobs were to take longer than 10 minutes to run then things really become a problem. Our users are also only getting notifications once every ten minutes. Ideally as soon as the average price of Bitcoin changes, an alert is sent. Imagine if we later decided that we wanted to use this application to purchase and sell bitcoin we'd certainly need to react to prices much faster.

One way this could be done is by using Stream Processor. Rather than batch computation to a larger set of data, we run our application logic on each piece of data individually.

## Wallaroo Application Structure

Our application is a perfect use case for Wallaroo. We have data coming from Coinbase and can save the average price and our user’s alerts in Wallaroo as state objects. If you are not familiar with Wallaroo terminology please see our [documentation](https://docs.wallaroolabs.com/book/core-concepts/core-concepts.html).

For this to work we need to have two different pipelines. One for when we are adding new price data from coinbase and the other to store alert data from our django application. Pipelines in Wallaroo are how you split up your application logic. Each pipeline has its own source, and messages from the source are processed sequentially through the pipeline's computations. Computations can access both the state inside its' own pipeline and the state outside of its' pipeline. This is how updates to buy/sell prices always read the most up to date alert settings that are set by a separate pipeline.

Normally running application logic on each piece of data as it flows through would be considered expensive and we might batch operations to save time or resources. Stream processors like Wallaroo make this style of computation fast through parallelism and scaling ability.

Let’s take a quick look at a few pieces of code to show what the difference between both applications are. The full application is available [here]().

```python
class Alerts(object):
    def __init__(self):
        self.alerts = dict()
```

Rather than access our alerts from the database like we did in the Celery example, our Wallaroo application initializes an Alert object that stores our alerts in a python dictionary. Additionally, we provide two methods to access this object. The ability to add and remove from our dictionary. `Alerts.alerts` eventually will look like this `{"price_to_notify": [user_ids], ...}`.

```python
class BTCPrice(object):
    def __init__(self):
        self.count = 0
        self.total = decimal.Decimal()
        self.average = decimal.Decimal()
```

Our price object also looks a bit different than our Celery example. With Celery we were using SQLite's `AVG` function to take the average of all the prices that came in a predefined time interval. In our Wallaroo application I keep a count of the number of results we've seen so far, the total, and the current average. The average is calculated by dividing the total by the count. It's a fairly basic calculation but you could use any python library to do this as well. Things like Pandas and NumPy work great with Wallaroo.

The computation logic is very similar to what we we're doing with Celery. The Wallaroo computations(view the full file [here](https://github.com/enilsen16/pricealert/blob/master/coinbase.py)) may be more explicit but both extract the price data from Coinbase, calculate the average price, and then check to see if any users' alert thresolds were crossed.

```python
def maybe_send_alerts_based_on_average_price(btc_price, alerts):
# ...
    for (k,v) in alerts.alerts.items():
        if decimal.Decimal(k) <= btc_price.average:
            notify[k] = list(v)
            alerts.remove(k)
# ...
    return (None, False)
```

In our `maybe_send_alerts_based_on_average_price` function, we call this inside of our `average BTC price` pipeline but we first created it in our `Load users' created alerts` pipeline. Instead of needing to query a snapshot of the database(which could be outdated by the time our application logic runs), sharing state like this lets us make sure that we are always using the most up-to-date data.

If you haven't already, go ahead and try running this application on your own. Clone the repository [here](https://github.com/enilsen16/pricealert) and start messing around with different intervals or add the ability to set alerts on eth-usd on the same pipeline.

## Conclusion

As you can see while there are a few differences between our Celery logic and our Wallaroo logic, the advantages between batching up our computation and running our application logic using a stream processor are quite large. We're able to go from running our logic periodically to receiving notifications in real-time.

Wallaroo allows us to avoid all the problems we first talked about. We went from running somewhat simple logic every ten minutes to being able to react to prices in real-time. Which is great if we wanted to add more functionality to our application, like buying and selling on our behalf or viewing real-time charts of this data.

There are many different use-cases for wanting to use a Stream Processor over Batch Processing. Many of which have been covered as examples in our blog. If you're interested in learning more about Wallaroo for a personal project or for use at your company, send us an [email](hello@wallaroolabs.com).

Thanks to my coworkers Simon, Nisan, Andy and Jonathan for providing feedback on both the blog post and the application.
