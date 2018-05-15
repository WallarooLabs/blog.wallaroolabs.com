+++
title = "Exploring The GitHub Archive"
date = 2018-05-15T07:30:00-04:00
draft = false
author = "brian"
description = "Learn to use Wallaroo with Python, Kafka, and the GitHub Archive"
tags = [
    "Wallaroo",
    "Integration",
    "Python",
    "Partitioning",
    "State",
    "Resilience"
]
categories = [
    "Hello Wallaroo"
]
+++

I work on Wallaroo day to day and one of early challenges I encountered was to find ways to explain how one might use Wallaroo without assuming anything about what kind of application someone might be working with. On day one, I would have said, it's great for your "stream processing" needs, but this itself is already assuming one might know when they need stream processing. This blog post aims to introduce Wallaroo concepts that an application developer would need to get started, rather than deeper theory on why stream processing might matter to you.

I've prepared a [companion repository](https://github.com/WallarooLabs/wallaroo-python-example) so we don't have to cut & paste or finding the right versions of things to download. I invite everyone to follow along on their machine. You might find yourself surprised at how many things stream processing is a natural fit when the machinery around many of these technologies is set aside and the focus is put on code.

The [GitHub Archive](http://www.gharchive.org/) is a favorite data set of mine. It chronicles all public repository activity data on GitHub. We'll be using this dataset as a simulated real time steam of events (since the HTTP API is throttled for most clients). This stream will give us a glimpse into popularity of repositories by watching which ones get stars. We'll also look at how we can track rich information about a repository using regular Python data types and code.

## Setting Up Docker Compose

Before we dive into the application, though, lets make sure we are ready to run the code. This project uses docker-compose so we can easily get many things up and running with a few commands and very little in the way of local installation work. You'll need to make sure you have a recent enough docker-compose version installed. If you're unsure, I've included a makefile target which installs one local to the repository. You can use it by running:

```bash
$ make env
$ . env/bin/activate
```

It's using virtualenv so advanced users can use something more custom if needed. The makefile has some other useful command targets which we'll be using later on.

To make sure your environment is ready to go, try to run either `make build` or `docker-compose build`.

## What's Included In The Box

Our docker-compose.yaml file lists a number of services. Some of these aren't required to use Wallaroo but the goal is to make this a little more real-world by integrating with a common technology.

In this case, we'll be using Kafka to get data into and out of Wallaroo. I've included a single-node [Kafka](https://github.com/wurstmeister/kafka-docker) and Zookeeper setup in this project since we'll start by running on a single machine. You shouldn't need to change anything here but you can check out the environment variables to get an idea of how we're setting things up.

After that we have the archive_streamer. This is responsible for pulling down the GitHub Archive content in hour by hour chunks and streaming it out to Kafka with a speed relative to timestamps on the events. This allows us to simulate passage of time but also keep data moving quickly during development. We set it to 24x speed on the command line parameter provided to the script.

The dashboard is a minimal Flask application that we'll be using to present the output as a page in a browser. I've taken care to keep it simple since most will likely have their own preferred tools for managing Kafka output as well as building web applications.

Finally, we set up Wallaroo services. I'll explain these a bit later but the most important one is the wallaroo_primary_worker. This is the node that initializes the cluster and is where our Wallaroo code will run first. To kick this off you can run `make start trace` which has some conservative delays built-in to avoid Zookeeper and Kafka racing to start or if you're feeling lucky `docker-compose up`.

## Defining Our Wallaroo Application

Now that we've cleared up the moving parts a little bit, let's take a look at our application code. We've got an entry point called `application_setup` in star_leaders/star_leaders.py.

```python
def application_setup(args):
    source_config = wallaroo.kafka_parse_source_options(args) + (decoder,)
    source = wallaroo.KafkaSourceConfig(*source_config)
    sink_config = wallaroo.kafka_parse_sink_options(args) + (encoder,)
    sink = wallaroo.KafkaSinkConfig(*sink_config)

    ab = wallaroo.ApplicationBuilder("GitHub Star Leaders")

    ab.new_pipeline("star count leaders", source)
    ab.to(filter_interesting_events)
    ab.to_state_partition(
        annotate_repos, RepoMetadata, "repo_metadata",
        REPO_PARTITIONER, REPO_PARTITIONER.partitions)
    ab.to_sink(sink)

    return ab.build()
```

The first block of code is configuration. We're pulling in our application arguments and using Wallaroo to parse out specific options that are predefined for Kafka. The application may also take its own command line arguments here. In our case we'll leave it as is.

`wallaroo.ApplicationBuilder` is where we start describing our application. Each application is defined by a number of pipelines. Each pipeline has a source and usually a sink. Our application here is simple and only needs one pipeline. Each step is a python function which we wrap using a decorator so we can give it a nice display name in our metrics application.

## Filtering Events

In the first step of the pipeline we've said we'll take our source and pipe it to something called `filter_interesting_events`. This is a function we define later in the file and it does pretty much what it says.

```python
@wallaroo.computation(name="filter interesting events")
def filter_interesting_events(event):
    if event['type'] in ['ForkEvent', 'PullRequestEvent', 'WatchEvent']:
        return event
```

This function runs one event at a time. Each event represents something that happened on a public GitHub repository which made it's way to us through the ghevents Kafka topic we're using as a source. There are dozens of events we could look at but for our example here, we'll start with just three types. Forks, pull requests, and watches. The last one there is a bit of a [misnomer](https://developer.github.com/changes/2012-09-05-watcher-api/), as it represents staring a repository not subscribing to its activity.

If we don't return anything here (or return `None`) then Wallaroo will assume we don't want to keep that event around for whatever step follows. We could also do some basic transformations on the event like trimming down fields but we'll keep the whole event payload around for purposes. Here is an example of what one of these might look like as our JSON input.

```json
{
  "id": "7650064541",
  "type": "WatchEvent",
  "actor": {
    "id": 1205691,
    "login": "chuckblake",
    "display_login": "chuckblake",
    "gravatar_id": "",
    "url": "https://api.github.com/users/chuckblake",
    "avatar_url": "https://avatars.githubusercontent.com/u/1205691?"
  },
  "repo": {
    "id": 48806149,
    "name": "WallarooLabs/wallaroo",
    "url": "https://api.github.com/repos/WallarooLabs/wallaroo"
  },
  "payload": {
    "action": "started"
  },
  "public": true,
  "created_at": "2018-05-09T14:19:21Z",
  "org": {
    "id": 11738863,
    "login": "WallarooLabs",
    "gravatar_id": "",
    "url": "https://api.github.com/orgs/WallarooLabs",
    "avatar_url": "https://avatars.githubusercontent.com/u/11738863?"
  }
}
```

## Counting Stars with a State Computation

The next step is a bit more complex: `ab.to_state_partition(...)`. We're doing a couple things here, but let's break it down.

First, we're telling Wallaroo that we're a state computation step. This is a bit of a mouthful but it means we can do more than simple event transformations by using state. This can mean things like keeping a tally on the number of stars a repository has or doing some other kind of book keeping or annotation across many events. To use state we'll need to tell Wallaroo what class we're using to represent our state as well as a name which identifies this specific use of that class (Wallaroo supports something called pipeline joins through named state, though we won't be using it in this application).

Second, we're telling Wallaroo that we're a partitioned step. This means we can break our work up into chunks to be processed in parallel and optionally distributed among many workers on potentially many machines. Wallaroo will handle this state management for you. What you'll need to do is tell it how to route events to a partition. We are using RepoPartitioner for this. You can check it out in repo_partitioner.py. If you'd like to read more on this I'd recommend checking out the [documentation](https://docs.wallaroolabs.com/book/core-concepts/partitioning.html).

Let's take a look at our computation definition now.

```python
@wallaroo.state_computation(name="count stars")
def annotate_repos(event, state):
    time = datetime.strptime(event['created_at'], "%Y-%m-%dT%H:%M:%SZ")
    state.set_current_hour(time.hour)
    repo = event['repo']['name']
    if event['type'] == 'WatchEvent':
        return calculate_leaders(event, state)
    elif state.is_leader(repo):
        state.annotate_with_event(repo, event)
        return (None, True)
    else:
        return (None, False)


def calculate_leaders(event, state):
    repo = event['repo']['name']
    state.add_star(repo)
    changed = state.changed_leaders(top=10)
    part = REPO_PARTITIONER.partition(event)
    if changed:
        return ({"leaders": changed, "partition": part}, True)
    else:
        return (None, True)
```

There is a lot going on here and more in `RepoMetadata` which is defined in repo_metadata.py. Looking at the `calculate_leaders` function, we can see that we're adding a star to each repository and then checking to see if the top 10 in this partition have changed at all (we'll call these the leaders according to recent stars). If we've got new leaders we send a new set down for this partition. Otherwise we send nothing. The tuple is there to let Wallaroo know that [we've changed our state](https://docs.wallaroolabs.com/book/core-concepts/working-with-state.html) and that it might need to checkpoint it if we're running with resilience turned on.

## Windowing

At the start of the "count stars" computation, we parse the timestamp of an event and set the time on our state. We're using this as a mechanism to evict our old data. But why would we want to get rid of our data you ask? At the moment, Wallaroo keeps this state in memory for faster processing. This means that we want to limit what we remember when possible.

In RepoMetadata, we can see that we keep a field called window. We keep a set of entries we've accumulated over each hour until we're full. You can see that we evict that last entry in `_trim_window` which keeps us to a maximum of 24 hours of data at any given point in time.

```python
def _trim_window(self):
    if len(self.window) > 23:
        self.window = self.window[-23:]
        self._recalc_window_cache()
end
```

Upcoming releases of Wallaroo will make dealing with this much easier but even without much help, we've managed to implement our own facilities. This is one of the benefits of allowing regular Python code to be used directly without much modification if any.

## Enriching Our Data

To show that we can do more than count, I've left a bit of a bread crumb here for a question I had when starting this project. What are some of the common activity patterns which occur on repositories which get starred a lot?

To give us a taste of what's happening around these popular repositories, I've started saving a few of the latest events (forks and pull requests in this case). We send these with our leader output when leaders change (which is quite often enough). This shows how we can keep richer data when we need it and otherwise have lighter data for other repositories. If we didn't make this trade-off, we'd likely end up needing many gigabytes of RAM to keep one days worth of data in memory (these events are large and GitHub can see over a million of them per hour).

If you want to get your hands a little more dirty, check out the event type definitions over [here](https://developer.github.com/v3/activity/events/types/) and see if you can get it working!

## Next Steps

There's more to show but this hopefully gives an idea of what Wallaroo is like in practice. There were a few things we didn't have time or space to dive into like testing and clustering which we'll follow up on in future blog posts.

In the meantime, here are some links to learn if you want to learn more:

* [Follow us on Twitter](https://twitter.com/wallaroolabs)
* [Join our Developer Mailing List](https://groups.io/g/wallaroo)
* [Chat with us on IRC](https://webchat.freenode.net/?channels=#wallaroo)
* [Wallaroo Community](https://www.wallaroolabs.com/community)

Thank you! We always appreciate your candid feedback (and a [GitHub star](https://github.com/WallarooLabs/wallaroo))!
