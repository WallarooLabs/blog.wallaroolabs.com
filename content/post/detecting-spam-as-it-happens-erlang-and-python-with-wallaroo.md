+++
title = "Detecting Spam as it happens: Getting Erlang and Python working together with Wallaroo"
date = 2018-07-12T08:15:00-07:00
draft = true
author = "simonzelazny"
description = "An example Wallaroo application that plugs into a live XMPP traffic stream to detect spambots. Built with Erlang and Python. Spambots included."
tags = [
    "example",
    "python",
    "use case",
]
categories = [
    "Example",
]
+++

Suppose your social network for chinchilla owners has taken off. Your
flagship app contains an embedded chat client, where community members discuss
chinchilla-related topics in real-time. As your user base grows, so does its
value as a target for advertising. Soon, purveyors of unsolicited advertising
take notice of this fact.

You now have a spam problem on your hands, and your small team of engineers has
only so much time they can dedicate to this arms race. Here's how Wallaroo can
help.

We'll design and implement a toy spam detection pipeline to demonstrate how to
leverage streaming analytics to tackle the issue. We'll also sketch out the
next steps needed to move this solution into production.


## The Plan

First, we are going to open up a stream of data from the chat server to the
Wallaroo application. This way, our spam detection system becomes decoupled
from the business logic that's being developed on the chat server.

Second, we'll write a script to simulate our adversaries' behavior.

Third, we'll show how to detect the most egregious spammers in near-real-time,
and discuss how to extend the analytics application as the arms race ramps
up.

Once the chat analytics system is in place, the spam problem can be tackled via
various means. We can construct a dashboard to show the detected traffic
anomalies to human operators and let them take action. We can also turn around
and tell the chat server to ban the most egregious offenders as soon as we are
made aware of their activity.

In this blog post, we'll content ourselves with detecting users who send out
too many copies of the same message, but thanks to Wallaroo, our pipeline can
be extended with more sophisticated models (timing, statistical, Bayesian
filters), using nothing but plain Python code.


## The XMPP->Wallaroo Adapter

For illustrative purposes, we'll assume the chat server we're running is a
variant of [Ejabberd](https://github.com/processone/ejabberd) or [MongooseIM](https://github.com/esl/MongooseIM). For each [XMPP stanza](https://xmpp.org/rfcs/rfc3920.html#stanzas) that passes through
our system, we'd like to capture some metadata and construct a JSON payload for
Wallaroo to consume. The below function receives: the sender's [jid](https://www.jabber.org/faq.html#jid); the
entire stanza serialized to a binary form; and the Epoch time at the time of
routing. These are packaged into a binary that Wallaroo can consume:

```erlang

    make_event(BinFrom, BinStanza, POSIXMilliseconds) ->
        Bin = jiffy:encode(#{<<"from">> => BinFrom,
                             <<"stanza">> => BinStanza,
                             <<"ts">> => POSIXMilliseconds}),
        Size = byte_size(Bin),
        <<Size:32, Bin/binary>>.


    % Fig. 1. Serializing XMPP messages with extra metadata (Erlang)
```

The crucial bit here is that after we encode all our data to a JSON
representation, we prefix it with its size, encoded as an integer in 4 bytes (
`Size:32` ). This framing is needed for the [Wallaroo TCP decoder](https://docs.wallaroolabs.com/book/python/api.html#tcp-source-decoder) to work correctly.

After the binary payload is constructed, it's sent down the wire to our
Wallaroo app.

```erlang

    Event = make_event(BinJid, BinStanza, erlang:system_time(1000)),
    gen_tcp:send(ensure_client(), Event),


    % Fig. 2. Sending the payload on our TCP connection (Erlang)
```


Sending binaries over TCP is the minimalist's way of feeding data to
Wallaroo. If you need resilience, replayability, and the capability to connect
multiple applications to the same data source, you'll want to use [Kafka](http://kafka.apache.org/) as
the message bus. If you’d like to integrate different sources, there’s good news around the corner: we are in the process of rolling out our BYOI (Bring Your Own Integrations) framework, which will let you leverage existing libraries to connect to other systems, such as Amazon Kinesis, RabbitMQ, etc. Join our low-traffic [announcement group at Groups.io](https://groups.io/g/wallaroo) to stay in the loop!


## The Traffic Simulator

Before we start to analyze our stream of XMPP data, let's take a few minutes to
create a traffic generator that will give us an ever-fresh stream of chat
messages to work with. In keeping with our Erlang/XMPP theme, we'll employ
[amoc](https://github.com/esl/amoc), an XMPP load-testing tool that lets us define scenarios in plain Erlang.

We'll simulate two kinds of users: one kind occasionally sends messages to
other chat participants, and sometimes replies to inbound messages. The message
bodies in each case are completely novel and unique. These users also take some
time to 'type out' their messages or replies. This class of bot will represent
our 'regular' chinchilla enthusiasts.

The other class of users will represent accounts that have been set up or
hijacked with the purpose of indiscriminately sending out spam. These users
will initiate *a lot* more conversations, but their messaging repertoire will
consist only of a couple canned phrases. These are spammers, not
spear-phishers, after all. They will also reply immediately, as if typing speed
was not a factor for them.

We model the above characteristics in Erlang code as a map with the following
fields:

```erlang

    make_behavior_model(Id) ->
        case Id rem 13 == 0 of
            true ->
                #{spammer => true,
                  wpm => 1000,     %% impossibly fast typist
                  chattiness => 1, %% chance to initiate chat per second
                  phrases => random_phrases(5), %% limited no. of messages
                  reply_rate => 0.8}; %% eager to reply
            false ->
                #{spammer => false,
                  wpm => random_wpm(),
                  chattiness => abs(rand:normal(1,0.2))/60.0, %% mean: ~1/min
                  phrases => infinity,
                  reply_rate => 0.5}
        end.


    % Fig. 3. Modeling spammy and non-spammy user behavior (Erlang)

```

We deterministically generate a spammer account for all `Id`s that are evenly
divisible by 13. This means that we can easily verify, by looking at the user
id, that the accounts we 'catch' were actually simulated spammers.


The scenario can be launched manually by running:

```
    $ CHAT_SERVER_HOSTNAME=localhost ./amoc/run.sh spambots 1 100
```


## The Spam detector

Our app will listen for TCP connections from our chat server, parse incoming
JSON according to the scheme defined above, and send out `Reports` of
misbehaving users to a downstream TCP sink. Currently, this sink is simply a
`netcat` process that writes incoming data to `sink.log`, a local file.

The Wallaroo application is defined as follows:

```python
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]
    tcp_source = wallaroo.TCPSourceConfig(in_host, in_port, decoder)
    tcp_sink = wallaroo.TCPSinkConfig(out_host, out_port, encoder)

    ab = wallaroo.ApplicationBuilder("Spam Detector")
    ab.new_pipeline("Message text analysis", tcp_source)
    ab.to(filter_messages_only)
    ab.to_stateful(update_user_stats, MessagingStatistics,
                   "Count per-user messaging statistics")
    ab.to_stateful(classify_user, Classifier,
                   "Classify users based on statistics")
    ab.to_sink(tcp_sink)
    return ab.build()


    # Fig. 4. Application setup
```

Let's take a look at the step definitions and follow the flow of data through
the system. First, we have our decoder, which is attached to our tcp source and
[marked as such via a decorator](https://blog.wallaroolabs.com/2018/02/idiomatic-python-stream-processing-in-wallaroo/). This
decoder declares that the incoming discrete events will be prefixed by their
length, encoded as a Big-Endian integer 4 bytes in length. Hence the
`<<Size:32` header in the Erlang code above. (Fig.1)

```python

    @wallaroo.decoder(header_length=4, length_fmt=">I")
     def decoder(bs):
       stanza = Stanza.from_dict(json.loads(bs.decode("utf-8")))
       return stanza


    # Fig. 5. Decoding TCP data to construct our model
```

Glossing over the definition of `Stanza`, ([you can find it here](https://github.com/WallarooLabs/spamdetector/blob/master/spamdetector/models.py#L5-L22)), let's take a look at what we do with one once we have it. The first
step of the analytics pipeline is `filter_messages_only`.

```python
    @wallaroo.computation(name="Filter XMPP Messages from other stanzas")
    def filter_messages_only(stanza):
      if stanza.type == "message":
        return stanza
      else:
        pass


    # Fig. 6. Removing non-message stanzas from our processing pipeline
```

For this iteration of our app, we'll only be interested in XMPP messages that
actually contain user-visible text. In the future, if we wanted to implement
session-based [windowing](https://blog.wallaroolabs.com/2018/06/implementing-time-windowing-in-an-evented-streaming-system/), we could also handle `presence` stanzas. If we
wanted to prevent API abuse, we might also allow `iq`-type stanzas into our
Pipeline. This is an application of the [preprocessing pattern](https://blog.wallaroolabs.com/2018/06/real-time-streaming-pattern-preprocessing-for-sentiment-analysis/).

For now, this step is where `iq`s and `presence`s are dropped and forgotten,
while `message` stanzas are passed on to the next computation,
`update_user_stats`:

```python
    @wallaroo.state_computation(name="Count per-user messaging statistics")
    def update_user_stats(stanza, state):
      user_stats = state.update_for_sender(stanza)
      return (user_stats, True)


    # Fig. 7. Our first state computation
```

This is where our pipeline plugs into our business models. In this step, we use
the stanza to update the per-user messaging statistics kept in the `state`. In
particular, we save how many unique chat buddies this user has, and how many
distinct chat messages he or she has sent so far. The `MessagingStatistics`
object is essentially a dictionary of (User, UserStats).

```python
	class UserStats():
       def __init__(self, user):
        self.user = user
        self.message_count = 0
        self.unique_bodies = set()
        self.unique_recipients = set()


    # Fig. 8. The UserStats object, instantiated per-user
```

Note: while for illustrative purposes we store all unique message bodies in
their entirety, this would be a problem were we to analyze our actual
production traffic. The structures would grow unbounded and eventually exhaust
all available memory.

A quick optimization that doesn't involve changing the object's interface would
be to replace the `Set` with a [Bloom filter](http://llimllib.github.io/bloomfilter-tutorial/). More involved approaches
include keeping an N-session window, and cleaning out messages from old
sessions when the window overflows.

Once we have the updated `UserStats`, we pass them on to another state
computation: one which determines whether the given user is likely to be a
spammer or not. While this next step could be implemented as a stateless
computation, we're going to hold a bit of state, for two reasons:

  1. If a given user has already been classified as a spammer, we'd like to
     refrain from publishing another notification to our downstream consumers.

  2. If the classification step itself becomes resource-intensive, we'd want to
     avoid doing work that's already been done.

The `classify` step is defined as:

```python
    @wallaroo.state_computation(name="Classify users based on statistics")
    def classify_user(stats, state):
      maybe_report = state.classify(stats)
      if maybe_report:
        return (maybe_report, True)
      else:
        return (None, False)


    # Fig. 9. Our second state computation: Spammer or Not-Spammer?
```

Our `state` is responsible for making and persisting the decision if no
decision has been made yet, or returning None when we don't want to generate a
Report.

```python
    class Classifier():
    def __init__(self):
        self._reported_users = {}

    def classify(self, user_stats):
        user = user_stats.user
        if self._has_been_reported(user):    ## No need to generate a new report
            return None
        elif len(user_stats.unique_bodies) < (user_stats.message_count/2):
                                             ## Too many duplicated messages!
                                             ## We will issue a Report!
            self._mark_as_reported(user)
            return Report(user, "repeated_message_bodies")
        else:                                ## Not suspicious
            return None

    def _has_been_reported(self, user):
        return self._reported_users.get(user, False)

    def _mark_as_reported(self, user):
        self._reported_users[user] = True


    # Fig. 10. Reporting spammers and saving the results
```

As it stands, our spam detection system is incredibly crude, consisting of one
check on the UserStats object:

```python

        len(user_stats.unique_bodies) < (user_stats.message_count/2)


	# Fig. 11. Checking for unique message bodies
```

which checks that at least half of the messages sent by a given user have
unique bodies. While this is an oversimplification, it will suffice to
eventually catch all our simulated spammers, as they each send out only a
limited number of message bodies. There's only so much variety in the sketchy
ads for Chinchilla feed that they're broadcasting.

It is here that we could plug in whatever tools we have in our spam fighting
arsenal: check if the user is inputting text faster than feasible for a human,
feed the entire `UserStats` to a Bayesian filter, or even apply machine learning
techniques to discover patterns in the user fingerprint that point to malicious
activity.

If the classification step produces a `Report`, it will end up as input for our
[last function](https://github.com/WallarooLabs/spamdetector/blob/master/spamdetector/spamdetector.py#L46-L49), which produces a simple JSON object using
`json.dumps`.


## What have we achieved?

The fight against spam in semi-open systems is usually a kind of tug-of-war,
where advances made by one side are often countered by the opponent. In our
case, we have put in place an architecture for dealing with spammers that is:

  1. Decoupled from the main chat service

  2. Extensible, allowing for more sophisticated strategies to be put in place
     as the 'arms race' progresses

What's most exciting about this approach is that it makes it easy for Data
Scientists to play an active part in the building of a real-time application,
using their statistical expertise to make sense of an ever-flowing stream of
data.

This has several distinctive advantages over batch processing done
retroactively over collected chat data:

  1. With near-real-time processing, it's possible to detect and take action on
	 abuse *as it's happening*, which limits the extent of the
	 damage. Statistical models are updated continuously, which gives us a
	 slight edge against new, previously unknown patterns.

  2. Being able to run analytics on the stream means that it's not necessary to
     store extensive chat logs for analytics purposes. This is a boon in the
     era of GDPR and a more privacy-conscious public.

  3. Changes or tweaks to the pipeline can be implemented and deployed quickly,
     and the results evaluated immediately after deployment.

If you'd like to see how you could integrate a Wallaroo streaming analytics
application with your near-real-time system, don't hesitate to get in touch,
we'd love to talk!
