++++
+title= "The Treacherous Tangle of Redundant Data: Resilience for Wallaroo"
+date = 2018-11-01T09:00:05+00:00
+draft = true
+author = "slfritchie"
+description = ""
+tags = [
+    "resilience",
+    "state"
+]
+categories = [
+    "Exploring Wallaroo Internals"
+]
++++

# The Treacherous Tangle of Redundant Data: Resilience for Wallaroo

## Introduction: we need data redundancy, but how, exactly?

You now have your distributed system in production, congratulations!
The cluster is starting at six machines, but it is expected to grow
quickly as it is assigned more work.  The cluster's main application
is stateful, and that's a problem.  What if we lose a local disk
drive?  Or a sysadmin runs `rm -rf` on the wrong directory?  Or else
the entire machine cannot reboot, due to a power failure or
administrator error that destroys an entire virtual machine?

Today, the application is writing all of its critical data to the
files in local file system of each machine.  Tomorrow, that data needs
to be redundant.  The scenarios above, hardware failing or an
administrator doing something wrong: at least one will happen.

How should we add the data redundancy that we know that we need?
You ask for advice, and the answers you get are scattered all over the
map of tech.

- Store the files with an NFS NAS or perhaps SAN or iSCSI service or
  an AWS Elastic Block Store (EBS) volume?

- Store the files in non-traditional shared file service like Hadoop
  or Ceph?

- Switch to a relational database like replicated MySQL or PostgreSQL
  or Azure's CosmosDB?

- Use a non-relational database like Cassandra or Amazon's DynamoDB?

Each of those answers could make sense, depending on the application
and your company and the company's broader goals.  This article
explores how Wallaroo Labs chose a data redundancy technique that fits
the needs of our product, Wallaroo.

## What is Wallaroo?

[Credit: Erik!]

Wallaroo is a framework designed to make it easier for developers to
build and operate high-performance applications written in Python. It
handles the complexity of building distributed data processing
applications so all that you need to worry about is the domain logic.

Wallaroo is a streaming data processing framework.  One
property of "streaming data" is that the total size of the input
is unknown.  How many events will arrive in the next minute?  Zero?
One thousand?  Ninety million?  You aren't certain when or how much
data will arrive for processing.

## Options for partial failure in distributed stream processing

When a machine in a distributed stream processor fails, there are two
basic options for recovery:

1. Start over. That is, process all of stream data again, starting from the beginning.
2. Restore system state from some snapshot or backup that was made in
   the recent past, then resume processing.

Option 1 is what streaming systems based on Apache Spark and Kafka do:
they store all the input event data, so they can resend the events
after a component has rebooted.

Option 2 is what Wallaroo does.  My colleague, John Mumm, wrote a blog
article about
[Wallaroo's checkpointing algorithm a few weeks ago](https://blog.wallaroolabs.com/2018/10/checkpointing-and-consistent-recovery-lines-how-we-handle-failure-in-wallaroo/).
However, that blog post doesn't answer an important question: what
happens if a Wallaroo worker's data is *lost*?

## When data is lost forever, by example

Let's look at a concrete example: a Wallaroo cluster with six worker
processes, each on a different computer (or virtual machine (VM) or
container).

<a name="figure1">
![Six worker Wallaroo cluster, state storage via local disk](/images/post/data-redundancy/dos-clients-all-local.png)
*Figure 1: Six worker Wallaroo cluster, state storage via local disk*

[Figure 1](#figure1) has no data redundancy in it.  If any local disk
dies, then recovery is impossible.  If an entire machine or VM or
container fails or is accidentally destroyed, recovery is impossible.

What if the same cluster were deployed in an Amazon Web Services (AWS)
cluster using Elastic Block Store (EBS) volumes to create data
redundancy?  That's what [Figure 2](#figure2) does.  The same general
principle applies to most file- block-device-centric schemes mentioned
in the introduction, including NAS, SAN, iSCSI, and so on.

<a name="figure2">
![Six worker Wallaroo cluster, state storage via EBS](/images/post/data-redundancy/dos-clients-ebs.png)
*Figure 2: Six worker Wallaroo cluster, state storage via EBS*

Let's assume that worker5's machine caught fire; its data is lost.
See [Figure 3](#figure3).  Also, some inaccuracies of
[Figure 2's](#figure2) placement of the EBS service are corrected in
[Figure 3](#figure3).

<a name="figure3">
![Wallaroo worker5 process restarts on a replacement machine/VM/container, accessing an EBS volume](/images/post/data-redundancy/dos-clients-ebs-failover.png)
*Figure 3: Wallaroo worker5 process restarts on a replacement machine/VM/container, accessing an EBS volume*

When the original machine/VM fails, the EBS volume is
disconnected from the dead VM and attached to a replacement
machine/VM.  Then worker5 is restarted on that machine, and worker5
participates in Wallaroo's internal snapshot recovery protocol to
finish the recovery process.

## Your Boss Says, “Sorry, What About ...?”

At some point, your boss or perhaps you, yourself, will start adding
some annoying restrictions to your app.

- No, we can't use Amazon AWS exclusively for this app.
- No, we can't use our on-premises data center for this app.
- No, the EMC SAN is being phased out soon, so this app cannot use it.

This is just a small sample of the deployment restrictions you might
have to work with.  Now is probably a good time to look at the
properties, restrictions, and priorities that Wallaroo Labs considered
when creating a data redundancy strategy for Wallaroo.

### Recovery data is infinitely sized and arrives at unpredictable times

Wallaroo is a streaming data system.  Two fundamental properties of a
streaming data system are:

1. The input data is infinite.  Truly infinite data is impossible, but
the input data may be very, very large.  Many network data protocols
assume that the amount of data to transfer is known in advance.  An
ideal data replication system would not require Wallaroo to specify
exact data sizes in advance, for example, like Amazon's S3 object
store requires.

2. The input data's arrival time is unknown.  For every data streaming
system that receives at least one byte per second, there is a system
that may receive only one byte every day or every week.  With large
gaps between data input events, Wallaroo could run into data
replication problems related to timeouts.  When writing data to an FTP
server or Amazon's S3 service or to an SQL server, when does the
server disconnect or stop processing due to an idle timeout?

### Append-only files by single producer, single consumer

Wallaroo has some properties that simplify choosing a redundant data
storage scheme: a single producer and a single consumer.

General purpose databases and file systems usually support all kinds
of shared read & write access to their data.  If 700 clients want to
read and write to the same database row or key or file, they will
support it.

In contrast, every Wallaroo worker's recovery data is not shared with
other workers: it is private state, for use by a single worker only.
A single worker process only runs on one machine at any given time.
The worker's recovery data is accessed in a single producer and single
consumer manner.  Again, industry and open source communities have
many solutions for this kind of problem, including:

* Storage Area Networks (SANs) such as Fibre Channel shared disks,
  FCoE (Fibre Channel over Ethernet), and AoE (ATA over Ethernet)

* Exclusive use shared block devices such as AWS's EBS (Elastic Block
  Store) and Linux's NBD (Network Block Device).

However, most of these techniques make assumptions about hardware and
networking that are not available in all public cloud computing
service providers or in private data centers.  We do not want vendor
lock-in for Wallaroo's data redundancy management.

Furthermore, most of Wallaroo worker's data files are append-only.  We
very intentionally made this choice to make file replication easier.
An append-only file's data, once it's written, is not modified by
later writes.  Once written, an append-only file's contents are
immutable.  This immutability makes the task of replicating the file
much, much easier.  (For further reading, see Pat Helland's excellent
article with the punny name,
[Immutability Changes Everything](https://queue.acm.org/detail.cfm?id=2884038).)

### Reduce complexity as much as feasible

There are many open source systems today that can support Wallaroo's
recovery data storage requirements.  Apache Kafka and Bookkeeper are
two of the best-known ones: Wallaroo's use case fits Kafka's &
Bookkeeper's feature sets almost exactly.  Why not use Kafka? Or
Bookkeeper? Hadoop is another excellent fit for Wallaroo's needs.  Why
not use Hadoop?

Alas, Kafka, Bookkeeper, and Hadoop are fairly complex pieces of
software in their own right.  Wallaroo does not need much of that
complexity.  It would be nice to avoid requiring Wallaroo
administrators to be familiar with details of running those services
in development, testing, and production environments.

Kafka, Bookkeeper, and Hadoop have another complex dependency: the
ZooKeeper consensus system.  Nobody in Wallaroo Lab's staff wishes to
make the use of ZooKeeper mandatory for development work or production
systems.  It would be fantastic if we didn't require our customers to
use and maintain ZooKeeper.

### Avoid vendor lock-in

We don't want to restrict Wallaroo deployments to a single cloud
provider like Azure, Google Compute Engine, or Amazon Web Services.
Wallaroo Labs could avoid lock-in by supporting many or all such cloud
services, but a company of our size doesn't have the resources to
quickly develop the code needed for supporting all major players in
the cloud storage market.

Similarly, for traditional or "on premise" data centers, we didn't
want to require the use of a NAS, SAN, or similar storage device.  

## Almost good enough: FTP, the File Transfer Protocol from the 1980's

[RFC 959](https://tools.ietf.org/html/rfc959.html) defines the File
Transfer Protocol, FTP.  FTP services are old, well-tested, and has
abundant implementations.  The problems are:

1. Data arrives at unpredictable times.  We could tweak an
FTP server to use infinite timeouts, if we wished.
 
2. Enforce a single writer restrictions.  Again, we could
tweak an FTP server to enforce this restriction, if we wished.

3. Adding feedback for received & fsync'ed data is not a "simple
tweak" to the FTP protocol.  This would require new additions to the
protocol: FTP provides no status acknowledgement until the end of file
is received.
Also, FTP's [RFC 959](https://tools.ietf.org/html/rfc959.html)
does not explicitly require durable or stable storage of a file's
contents.

## Wallaroo's choice: DOS, the Dumb Object Service, that is almost FTP

The last section listed three problems with
the FTP protocol as defined by RFC 959.  It also mentioned "simple
tweak" three times.  That was not an accident.  If the FTP protocol
were tweaked in those three ways, then the result would fit Wallaroo's
needs exactly.

Rather than "simply tweak" the FTP protocol, we chose to create and
implement a new file transfer protocol very similar to FTP but not
quite FTP. Its name is DOS: the Dumb Object Service.

The DOS protocol is inspired by a small subset of FTP's commands but
without the ASCII-only nature of the FTP commands.  In a very small
binary protocol, we specify these FTP-like commands:

* CWD, change the working directory.  This feature is used to allow a
  single DOS server to store data for multiple DOS clients: each DOS
  client writes its data files into a separate directory.

* APPEND is more similar HTTP's PUT command than to the FTP command
  combination of PASV and STOR.  It is used to append data to a file.

  The APPEND command includes an argument for the DOS server's file
  size (or size $0$ if the file does not yet exist).  The DOS server
  will allow the APPEND operation to proceed only if the server's file
  size is exactly equal to the `size` argument provided by the DOS
  client.

  Also, the server prohibits multiple clients writing to the same file
  simultaneously.

* GET is more similar to HTTP's GET command than to the FTP command
  combination of PASV and RETR.  It is used to
  retrieve a file's contents.  The DOS server's GET command permits
  partial reads of the file by specifying a starting offset and
  maximum number of bytes to send to the client.

* LIST, list files in the current directory.  This feature isn't
  mentioned in the requirements list above, but it is useful for a
  Wallaroo worker client to discover the names & sizes of files stored
  in its own private directory.

* QUIT, which terminates a DOS client session.

## Examples of Wallaroo clusters with DOS servers providing data redundancy

Let's see what happens when we add two DOS servers into our six-worker
Wallaroo cluster.  Each worker is configured to replicate its I/O
journal files to both DOS servers.  Each DOS server uses its local
file system and local disk(s) to store the I/O journals for all six
Wallaroo workers.

<a name="figure4">
![Six worker Wallaroo cluster plus two DOS servers](/images/post/data-redundancy/dos-clients-2servers.png)
*Figure 4: Six worker Wallaroo cluster plus two DOS servers*

When a Wallaroo worker fails catastrophically, its local recovery
files are lost.  We must retrieve a copy from a remote DOS server
before we can restart the worker.  The procedure for figuring out
which DOS server is most "up to date" is described later in this
article.

[Figure 4](#figure4) suggests that 8 different machines (or virtual
machines or containers) are required: six for Wallaroo worker
processes and two for the DOS servers. [Figure 5](#figure5) shows what
happens when we colocate the DOS servers with the boxes that also run
two of the Wallaroo workers.

<a name="figure5">
![Six worker Wallaroo cluster plus two DOS servers sharing hardware](/images/post/data-redundancy/dos-clients-doubleduty.png)
*Figure 5: Six worker Wallaroo cluster plus two DOS servers sharing hardware*

Our last example is another option, using EBS to provide redundant
storage for a single DOS server instead of each of the six worker
servers.  The system in [Figure 6](#figure6) may be a more
cost-effective option when "provisioned IOPS" costs for each EBS
volume are added to the system.  When the DOS server fails, the
replacement procedure is similar to the failover scenario shown in
[Figure 3](#figure3).

<a name="figure6">
![Six worker Wallaroo cluster plus one DOS server plus EBS](/images/post/data-redundancy/dos-clients-ebs-hybrid.png)
*Figure 6: Six worker Wallaroo cluster plus one DOS server plus EBS*

## Implementation overview: client side (inside Wallaroo)

Each Wallaroo worker creates a number of recovery data files inside
the `--resilience-dir` directory specified on the command line.  A
file listing of that directory looks like this:

```
-rw-r--r-- 1 ubuntu ubuntu   48 Oct  3 19:34 my_app-worker3.checkpoint_ids
-rw-r--r-- 1 ubuntu ubuntu  803 Oct  3 19:34 my_app-worker3.connection-addresses
-rw-r--r-- 1 ubuntu ubuntu  447 Oct  3 19:34 my_app-worker3.evlog
-rw-r--r-- 1 ubuntu ubuntu    0 Oct  3 19:34 my_app-worker3.local-keys
-rw-r--r-- 1 ubuntu ubuntu 4144 Oct  3 19:34 my_app-worker3.local-topology
-rw-r--r-- 1 ubuntu ubuntu   18 Oct  3 19:34 my_app-worker3.tcp-control
-rw-r--r-- 1 ubuntu ubuntu   18 Oct  3 19:34 my_app-worker3.tcp-data
-rw-r--r-- 1 ubuntu ubuntu   20 Oct  3 19:34 my_app-worker3.workers
```

The Wallaroo application has been intentionally restricted to only
three file-mutating file I/O operations: append file data, file
truncate, and file delete.  For each of these file I/O operations, the
I/O call + arguments are written to a journal file.  All I/O to a
journal file is strictly append-only.  All journal file data is
written via the DOS protocol to one or more DOS servers.  The
serialization of these I/O operations is described in the next
section.

### Serialized I/O operations in the `my_app.journal` file

In the `my_app-worker3.journal` file, each file write/append event
to a non-journal file (e.g., the `my_app-worker3.checkpoint_ids` file)
is serialized as if a single generic function had the Pony type:

```
encode_request(optag: USize, op: U8,
    ints: Array[USize], bss: Array[ByteSeq]):
    (Array[ByteSeq] iso^, USize)
```

A request has an operation tag, an operation specifying byte, and two
arrays of arguments: one of type `USize` for integers and one of type
`ByteSeq` for strings/byte arrays.  Depending on the operation byte
`op`, the caller includes the appropriate number of elements in each
respective array.

A view of serialized bytes returned by `encode_request` is:

```
/**********************************************************
|------+----------------+---------------------------------|
| Size | Type           | Description                     |
|------+----------------+---------------------------------|
|    1 | U8             | Protocol version = 0            |
|    1 | U8             | Op type: append, delete, ...    |
|    1 | U8             | Number of int args              |
|    1 | U8             | Number of string/byte args      |
|    8 | USize          | Op tag                          |
|    8 | USize          | 1st int arg                     |
|    8 | USize          | nth int arg                     |
|    8 | USize          | Size of 1st string/byte arg     |
|    8 | USize          | Size of nth string/byte arg     |
|    X | String/ByteSeq | Contents of 1st string/byte arg |
|    X | String/ByteSeq | Contents of nth string/byte arg |
 **********************************************************/
 ```

If the binary contents of the `my_app.journal` file were translated
into a human-readable form, they look something like this:

```
version=0 op=1 tag=1 ints=[0] strings=['/tmp/my_app-worker3.tcp-control', 'localhost\n']
version=0 op=1 tag=2 ints=[10] strings=['/tmp/my_app-worker3.tcp-control', '0\n']
version=0 op=0 tag=3 ints=[0] strings=['/tmp/my_app-worker3.connection-addresses']
```

* Where `op=1` is a file write operation:
    - The 1st integer in the `ints` list is the file offset
    - The 1st string in the `strings` list is the path of the file to write to.
    - The 2nd string in the `strings` list is the data written at this offset.
* Where `op=0` is a file truncate operation:
    - The 1st integer in the `ints` list is the file size to truncate to
    - The 1st string in the `strings` list is the path of the file to truncate.

### I/O Journal + Append-Only Journal I/O -> Logical Time as Journal File Size

All file-mutating I/O operations to `--resilience-dir` files are
serialized and appended to a local I/O journal file.  Asynchronously,
the local I/O journal file data is written via the DOS protocol to one
or more remote DOS servers for redundancy.

We can consider the file size of the I/O journal files as "logical
time".  Given the set *F* of all files whose I/O ops are written in
an I/O journal, then for any single file *f* in the set *F* can be
reconstructed at some logical time *t* by extracting all of *f*'s
I/O events from the journal where the file offset of the I/O event is
less than *t*.

For example, if we want to reconstruct the contents of the
`/tmp/my_app-worker3.connection-addresses` (sometimes called a "roll
back") as it existed at the wall clock time of midnight on New Year's
Day 2018, the procedure is:

1. Determine the size of the I/O journal file at midnight on New
   Year's Day 2018.  Let's call this offset *max_offset*.
2. Open the I/O journal file for reading and seek to the beginning of
   the journal.
3. Read each serialized I/O operation in the file until we reach the
   offset *max_offset*.
4. If a serialized operation involves the file path
   `/tmp/my_app-worker3.connection-addresses`, then apply the op
   (i.e., write/file truncate/file delete) to the file path.

#### Chandy-Lamport snapshot consistency across Wallaroo workers

Any logical time construct mentioned in this doc is applicable only to
a single Wallaroo worker and is not valid for comparison with other
Wallaroo workers.

The snapshot algorithm introduced by Wallaroo release 0.5.3 is
responsible for managing logical time consistency across all Wallaroo
workers.  That algorithm, a variation of the Chandy-Lamport snapshot
algorithm, uses a different notion of logical time.
Please see the article
[Checkpointing and Consistent Recovery Lines: How We Handle Failure in Wallaroo](https://blog.wallaroolabs.com/2018/10/checkpointing-and-consistent-recovery-lines-how-we-handle-failure-in-wallaroo/)
for an overview of how the Wallaroo's adaptation of Chandy-Lamport
works.

### Assume no Byzantine failures or data corruption inside I/O journal files

We definitely assume that there are no Byzantine failures, including
software bugs that would do Bad Things(tm) such as reorder records
within a journal.  And we assume that there's no data corruption
(for any reason) inside of a journal file.

The DOS protocol and wider Wallaroo implementation cannot operate
correctly with Byzantine failures.

In the case of data corruption inside of the log, we do have remedies
available.  The best remedy is to add robust checksums to all data
written to a journal.  Today, Wallaroo does not yet use checksums.

## What's next for data redundancy and Wallaroo?

The soon-to-be-released Wallaroo version 0.5.4 will have all of the
raw components for data redundancy.  To date, those components are
only lightly tested for performance.  The DOS client, written purely
in Pony inside of Wallaroo, has not had any performance analysis
performed yet.

The DOS server is written in Python.  That seems an odd choice for a
high-performance server, but early tests have shown that that DOS
server can write over 100 Mbytes/second of recovery data without
significant latency.  A later Wallaroo release may reimplement the DOS
server in Pony for higher efficiency.

The long-term goal is to have a hands-free, turnkey system that will
react to failure of any Wallaroo component and restart it gracefully.
We need to choose the environment for such a system: Kubernetes or
Mesos?  GCE or Azure or AWS?  "On prem" data centers?  All of the
above?  While we wrestle with those choices, we're confident that the
data redundancy components provide a good foundation to build on.

## Give it a try!

Hopefully, I’ve gotten you excited about Wallaroo and our data
redundancy story.  We’d love for you to give it a try and give us your
feedback. Your feedback helps us drive the product forward. Thank you
to everyone who has contributed feedback so far and thank you to
everyone who does after reading this blog post. Y’all rock!

(Get started with Wallaroo now!)[https://docs.wallaroolabs.com/book/getting-started/choosing-an-installation-option.html]


