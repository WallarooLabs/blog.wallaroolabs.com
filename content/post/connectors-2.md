+++
  title= "Using Wallaroo with PostgreSQL"
  date = 2018-11-27T12:00:35+00:00
  draft = false
  author = "erikn"
  description = "Connectors make working with external systems easy. In this post we show how to use Wallaroo and PostgreSQL together."
  tags = [
    "python",
    "example"
  ]
  categories = [
    "example"
  ]
+++


## Introduction

In the [last blog post](https://blog.wallaroolabs.com/2018/10/introducing-connectors-wallaroos-window-to-the-world/), I gave an overview of our new Connectors APIs, discussing how they work under the hood and some of the examples we provide. In this post, we are going to take a deeper dive into how to build a connector to pull data from PostgreSQL. We'll also talk a bit about some of the different approaches for building both external source and sink connectors.

## What is Wallaroo

Wallaroo is a framework for building and operating scalable Python applications. Write your domain logic once and Wallaroo handles the rest.

Our goal is to make sure—regardless of where your data is coming from—that you can scale your application logic horizontally. All while removing the challenges that otherwise come with distributed applications.

## What are we building

To demonstrate how easy swapping connectors is we are going to use the `alert_stateless` application. In this application, transactions are randomly generated and then if a deposit or a withdrawal is greater than 1000 we trigger an alert. For the Source Connector, instead of generating our data inside of our Wallaroo application, we'll read data from a PostgreSQL table. The Sink Connector will take the alert strings sent by Wallaroo and save them in a table.

One way to get the new data from a PostgreSQL table is to use the `LISTEN/NOTIFY` that PostgreSQL provides. Each time a change is made to a table that you are monitoring `NOTIFY` sends the the data to all the connected clients that have issued a `LISTEN` command.

Before we start building our connectors, the `alert_stateless` application needs a few modifications to the example. First we need to remove this line:

```python
gen_source = wallaroo.GenSourceConfig(TransactionsGenerator())
```

replacing it with this:

```python
# Add an additional import

import wallaroo.experimental

# inside of the application_setup function
gen_source = wallaroo.experimental.SourceConnectorConfig(
    "transaction_feed",
    encoder=encode_feed,
    decoder=decode_feed,
    port=7100)
alert_feed = wallaroo.experimental.SinkConnectorConfig(
    "alert_feed",
    encoder=encode_conversion,
    decoder=decode_conversion,
    port=7200)

# change the to_sink function
.to_sink(alert_feed)
```

## Building a Source

To build our source connector we need to have a table created with the proper schema. If this schema changes, then our Wallaroo application will need to as well. Since we are using the new Python API for Connectors, we're also able to use any python library.

To work with PostgreSQL in Python, we're going to use the [Psycopg](http://initd.org/psycopg/) library. Psycopg works well with the `LISTEN/NOTIFY` API but other libraries would work here as well.

After importing our modules, we need to specify if there are any required or optional parameters.
```python
connector = wallaroo.experimental.SourceConnector(required_params=['connection'], optional_params=[])
connector.connect()
connection_string = connector.params.connection
```

We specify that we're creating a Source Connector and `connection` is a required parameter with no optional parameters. After calling `connect`, we can then extract those parameters as variables and use them later on in our script.

```python
conn = psycopg2.connect(connection_string)
conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)

curs = conn.cursor()
```

Our `connection_string` is passed when we start our connector script and needs to be in the format `"dbname=test user=postgres password=secret"`. More information on `psycopg2.connect` can be found [here](http://initd.org/psycopg/docs/module.html#psycopg2.connect). Then we set the isolation level to autocommit so that each query is explicitly a new transaction. Finally, we create a new [cursor object](http://initd.org/psycopg/docs/cursor.html#cursor).

By now we have a connection to our Postgres DB and now just need to specify a trigger so that Postgres knows which table it should provide events for. For our temperature table, this will look something like this:

```python
# We define a trigger function called Wallaroo_example

curs.execute("""
    CREATE OR REPLACE FUNCTION NOTIFY() RETURNS trigger AS
    $BODY$
    BEGIN
        PERFORM pg_notify('wallaroo_example', row_to_json(NEW)::text);
        RETURN new;
    END;
    $BODY$
    LANGUAGE 'plpgsql' VOLATILE COST 100;
""")
```

```python
# We create a trigger function

curs.execute("""
    CREATE TRIGGER USERS_AFTER
    AFTER INSERT
    ON Alerts
    FOR EACH ROW
    EXECUTE PROCEDURE NOTIFY();
""")

# Then listen on the channel `wallaroo_example`
curs.execute("LISTEN wallaroo_example;")
```

Now all we need to do is poll for events from PostgreSQL. When a new notify event is received, we pop it from the dictionary.

```python
while True:
    if select.select([conn], [], [], 5) == ([], [], []):
        print "Timeout"
    else:
        conn.poll()
        while conn.notifies:
            notify = conn.notifies.pop(0)
            payload = json.loads(notify.payload)
            connector.write(payload["content"])
```

`connector.write()` is what sends data to your Wallaroo application. In our case, we take the payload sent from PostgreSQL and then decodes it into JSON. This is then sent to our Wallaroo application.


## Building a Sink

For PostgreSQL, building a Source Connector meant that we used the `NOTIFY/LISTEN` API to retrieve change events. A Sink Connector is a little different. If we are writing to PostgreSQL we need to know the schema of the table. If changes need to be made to this table then both our External Sink and the External Application need to be aware; otherwise bad things can happen.

When a transaction is over the specified limit in our application we'll take that alert and have our connector save it to a table storing all of those alerts. For our Sink Connector all that's saved is the string sent from Wallaroo. Along with a `created_at` timestamp and an id as the primary key.

First we need to create our tables schema. In production, it'd be a good idea to validate that our connector has the most up to date schema.

```python
curs.execute("""
    CREATE TABLE Alert_log (
        id SERIAL PRIMARY KEY,
        alert_log VARCHAR,
        created_at timestamp with time zone NOT NULL default now()
    )
""")
```

Now that our table is created, we need to write the data coming from Wallaroo to our Postgres database. We're still using the psycopg2 python library.

```python
while True:
    alert_string = connector.read()
    curs.execute("""
        INSERT INTO alert_log (alert_log)
        VALUES (%s);
    """, (alert_string))
```

## Conclusion

Our new connector APIs make getting data in and out of Wallaroo much easier than before. In this post, we took a look at how you could build both a Source and Sink connector with a relational database.

Starting with the 0.5.3 release, we've included [examples](https://github.com/WallarooLabs/wallaroo/tree/0.5.3/connectors) of other connectors, for example for use with Kafka, Kinesis, and S3. Please check them out and let us know if you're writing a connector for your preferred data source.
