+++
title = "Dynamic tracing a Pony + Python program with DTrace"
date = 2017-12-14T06:30:12-06:00
draft = false
author = "slfritchie"
description = "Use the dynamic tracing tool DTrace to observe the internals of a Wallaroo application, observing events in both Pony code and Python code and also inside the OS kernel itself."
tags = [
    "dynamic tracing",
    "dtrace",
    "pony",
    "python"
]
categories = [
]
+++

Your application probably has a performance problem.  Or your app has a
terrible bug.  Or both.  To find and fix these problems, many software
developers use a profiler or a debugger.  Profilers and debuggers are
(usually) fantastic tools for solving performance and correctness
problems.  But many of these fantastic tools also have limitations
such as:

* Requiring access to the application's source code.
* Require changes to how the application is built.
* Require changes to how the application is run.  

The dynamic tracing technique can avoid most of these limitations.
Dynamic tracing tools such as DTrace, SystemTap, uprobes, and perf are
widely available to users of popular open source & commercial
operating systems.

Here's an outline for the rest of this article:

* What are some scenarios where dynamic tracing can be most useful?
  ([Part one](#part1))
* A brief survey of some of the dynamic tracing tools available.
  ([Part two](#part2))
* A demonstration of what those tools can tell us about applications written
  in Pony, Python, and both languages together in a
  [Wallaroo application][hello-wallaroo].
  ([Part three](#part3))
* Please don't miss
[Appendix A](#appendix-a-dynamic-tracing-resources-for-further-study),
with over 20 references to find more information about dynamic
tracing, DTrace, SystemTap and Linux uprobes, eBPF, and much more.

## <a id="part1"></a> What kind of questions can dynamic tracing help answer?

Imagine that you're trying to fix a bug, or find a performance
bottleneck.  You have questions like this:

* Does my program ever call function X?
* How many times per second is my program calling function X?
* How long does it take for function X to run?  Average time? What
  about minimum & maximum times?
* Is function X being called with good arguments?  Bad arguments?
* Is function X returning a good value?  A bad value?
* Is function X making any system calls to the operating system?
* I know function X is being called, but I don't know *which execution*
  path(s) is responsible for calling X.

If you've ever used a debugger or a profiler, you know that they
provide ways to answer these questions.  But using those tools may be
a hassle.  Or impossible.  Let's explore some of those reasons in the
next section.

## Scenarios full of hassle and hell

#### Scenarios in everyday development & debugging

In your everyday development environment, you typically have the
flexibility to change everything.  You can recompile your application.
Adding a call to `printf()` or `print()` or `write()` or whatever is
easy to do.  That extra verbose output may tell you exactly what you
need to know: is function X being called?  How many times?

But the extra print statements come at a price.  They clutter your
application's output.  What if your print statement is called 12
million times per second?  Do you have enough disk space to store the
additional output?

Also, what if you need information about call (or event) counts and/or
latency?  `printf()` doesn't do any counting or timing tasks for you.  You
need to do those things yourself.  Including your own arithmetic.
Perhaps you have a library available to do that for you, perhaps not.

Oh, by the way, is your application multi-threaded?  Don't forget to
do all that stuff in a thread-safe manner.

Also, don't forget to remove all of that debugging code when your task
is finished!

If you need information about what's happening inside of the kernel,
then there isn't much your application can do.  The operating system's
kernel is mostly off-limits, by definition.  You probably can't add
anything to your program to examine the kernel's internals.  You will
need to use an external tool.

#### Scenarios in "production" environments

Imagine that one of these conditions is true, or perhaps all of them.

* The application is already running, in production, in your data
center or someone else's.

* You are not permitted to stop & restart the process now in order to
  enable debugging configuration changes.

* Your IT department's security team doesn't allow you to run a "debug
  build" of your program because it hasn't been vetted like the
  "production build" has been.

* Your program is working perfectly well. (*Of course it is!*) But
  your program is a client to some other service Y, and service Y is
  buggy.  Or slow.  Or both.  And service Y is some other team's
  responsibility.  Understanding service Y's behavior better would
  help you immensely.

* Your application is working well for the first 17 hours, but then it
  suddenly tries & fails to allocate 195GB of memory and crashes.  Why?

## <a id="part2"></a> Dynamic Tracing: safely altering your program while it runs

Tracing is a very broad topic in software engineering.  There isn't
space available here for a long discussion.  Wikipedia provides a
[good introduction to tracing][wikipedia tracing].

Dynamic tracing is a wonderful and powerful twist on tracing: it permits
the addition, change, and removal of custom tracing logic to a program
that's already running.  You don't need access to the program's
original source code.

Safety is also a big concern.  You don't want to crash or interrupt
the program you're trying to investigate.  Fortunately, many operating
systems implement dynamic tracing safely, which means you don't have
to worry about an accidental process crash while you work.

A lot of effort has been spent making dynamic tracing frameworks
efficient.  If you're investigating events that happen millions of
times per second, then any overhead that is added by a dynamic tracing
framework multiplies and grows very quickly.  For example, DTrace can
collect aggregates on millions of events per second without enormous
effects on the running program.

## Roll call: dynamic tracing frameworks

I don't have space for an exhaustive list.  These frameworks are
probably available today for the OS that you use for both your
development environment and production systems.

- OS X/macOS, FreeBSD, Solaris, Illumos, and Linux (depending on
  your Linux distribution & your tolerance of licensing ambiguity):
  [DTrace][DTrace] is a production quality, stable framework.  Apple's
  support for DTrace in recent macOS releases isn't great, but DTrace
  is still very usable.  Linux's DTrace port by Oracle is not as
  comprehensive as the BSD and Solaris flavors.  The stability of the
  unofficial port for Linux is not well known to me.
- Linux: Linux's community has never settled on a single dynamic
  tracing tool.  I mention only the ones that appear most relevant today.
  [SystemTap][SystemTap] was originally designed as a more flexible
  alternative to DTrace.  More recently, a system built around
  [Linux uprobes][linux-uprobes] and [Linux kprobes][linux-kprobes] and
  [the linux `perf` utility][linux-perf] and [eBPF][ebpf] combine to make a useful
  dynamic tracing system.  The best summaries I know of are 
  [Julia Evans's overview][julia-evans-tracing] and
  [Brendan Gregg's various articles][brendan-gregg-tracing].
  Unfortunately, the feature set and stability of this system varies
  tremendously by Linux kernel version, patch level, and OS
  distribution packaging.
- AIX (for IBM lovers): [ProbeVue][ProbeVue] is a DTrace clone,
  created by IBM (I believe) to avoid licensing problems from Sun
  Microsystems (originally) & Oracle (today).
- [Erlang][erlang-provider], [Micro Focus COBOL][opencobol-tracing], ...:
  Many languages include user space-only support for dynamic tracing.

## <a id="part3"></a> Let's demonstrate DTrace's power by examining Pony programs

Writing about dynamic tracing isn't easy.  It's a broad subject.
How do I choose which platform to examine and to demonstrate by
example?  It's difficult!  Do I use macOS?  Or Linux?  Do I demonstrate
DTrace?  Or SystemTap?  Or uprobes & `perf`?  All of them?  Some?

In this section, I'm going to demonstrate the use of user-space DTrace
probes inside of a simple "Hello, world!" Pony program and then
a [Wallaroo application][wallaroo].  [Wallaroo][hello-wallaroo] is a
hybrid application written both in [Pony][pony] and also
[Python][python].  (The Go language will also be fully supported soon.)
DTrace can collect and analyse events from both
halves of the Wallaroo app.

I've chosen to write about DTrace only, using OS X 10.12/macOS Sierra
for the demo.
[Appendix A](#appendix-a-dynamic-tracing-resources-for-further-study)
has links to lots of SystemTap and uprobes+perf
documentation and tutorials, so that you can try to adapt the examples
below to a Linux environment without DTrace.

This is not a hands-on demo where the reader is encouraged to
re-create every step of the demo.  If you wish to do so, you should
start by building a DTrace-enabled Pony language compiler and
Wallaroo runtime.  Please see
[Appendix C](#appendix-c-compiling-pony-to-support-dtrace) for brief
instructions.

## Introducing the USDT: the User-Space DTrace probe

NOTE: SystemTap calls these things a 'mark'.  Linux uprobes calls them a
'uprobe'.

A USDT probe is "a point of instrumentation, [...] a specific location
in a program flow" (source: [Gregg & Mauro](#dtrace-book)).
This type of probe is inserted manually into the
program's source code.  In most programming languages, it looks like
an ordinary function call or macro.  The probe may include arguments,
which can provide additional information during runtime.

Here are some examples taken from the the Pony runtime library, which is
written in C.  The first three probes have zero arguments.  The last
probe, `heap-alloc`, is located inside a heap memory allocation
function.  The probe's two arguments include the scheduler's identity
(i.e., a C pointer to the scheduler structure) and the size of the memory
allocation request.

```C
/* rt-init: Fired when runtime initiates */
DTRACE0(RT_INIT);

/* rt-start: Fired when runtime is initiated and the program starts */
DTRACE0(RT_START);

/* rt-end: Fired when runtime shutdown is started */
DTRACE0(RT_END);

/* heap-alloc: Fired when memory is allocated on the heap */
DTRACE2(HEAP_ALLOC, (uintptr_t)ctx->scheduler, size);
```

#### Hey, you said that my app can be tweaked at runtime without source code changes!

Yes, I did.  Let me clarify.

When compiled, the `DTRACE2()` macro above is transformed by the C
compiler to a `nop` instruction.  Yes, really, a no-operation
instruction.  It literally does nothing.  It takes very little space,
for example, one byte in the X86-64 instruction set.  And when your
program runs normally, it does nothing.

However, when your program runs and also the kernel
instruments this probe, then magic happens.  The kernel will find all
instances of the `heap-alloc` probe (`HEAP_ALLOC` is its name in the C
language's syntax), then replace the `nop` instruction with code that
will ... do something.  What exactly that something does will depend
on the DTrace script that is also provided.

Here is an example.  I will compile the `helloworld` program from the
[Pony language's `examples` collection of sample programs][pony-examples].
The code is nearly as simple as a complete Pony program can be.

```Pony
actor Main
  new create(env: Env) =>
    env.out.print("Hello, world.")
```

The output looks like this when I compile and run this program.  Note
that I'm using a DTrace-enabled version of the Pony compiler, which is
not the default.
(See [Appendix C](#appendix-c-compiling-pony-to-support-dtrace).)

```
% ponyc examples/helloworld
Building builtin -> /usr/local/pony/ponylang.0.20.0/lib/pony/0.20.0-0b2a2d289/packages/builtin
Building examples/helloworld -> /Users/scott/src/pony/ponyc.ponylang/examples/helloworld
Generating
 Reachability
 Selector painting
 Data prototypes
 Data types
 Function prototypes
 Functions
 Descriptors
Optimising
Writing ./helloworld.o
Linking ./helloworld

% ./helloworld
Hello, world.
```

Let's see what happens when we instrument this program with DTrace.
OS X requires superuser privileges to use `dtrace`, so I execute the
command with `sudo`.

```
% sudo dtrace -n 'pony$target:::rt-*' -c ./helloworld
dtrace: description 'pony$target:::rt-*' matched 3 probes
Hello, world.
dtrace: pid 25497 has exited
CPU     ID                    FUNCTION:NAME
  6 517061                pony_init:rt-init 
  6 517062     ponyint_sched_start:rt-start 
  7 517060    ponyint_sched_shutdown:rt-end 
```

That's new, isn't it?  We've learned a lot of things, including:

* We can use a wildcard match, `*`, in the DTrace probe specification.
* The wildcard matched 3 probes, i.e., the first three of the four
  mentioned above.
* When a probe fires, DTrace will provide a default action if no
  action is specified, printing:
  * the CPU number that fired the probe,
  * the DTrace probe ID number,
  * the C function name where the probe is located, and
  * the name of the probe.
* As an extra bonus, we've discovered the names of three C functions in
  the Pony runtime: `pony_init()`, `ponyint_sched_start()`, and
  `ponyint_sched_shutdown()`.
* This program executes in only a few milliseconds.
  However, despite the tiny time interval,  the OS decided to move the
  process's execution from CPU `6` to CPU `7`.

Let's supply a one-line DTrace program to run when the probes fire.  I
also add the `-q` flag to quiet other default printing stuff.

```
% sudo dtrace -q -n \
    'pony$target:::rt-* { printf("%-10s at %d nanoseconds\n", probename, timestamp); }' \
    -c ./helloworld
Hello, world.
rt-init    at 69860375442851 nanoseconds
rt-start   at 69860376068109 nanoseconds
rt-end     at 69860376860607 nanoseconds
```

The time difference between the first and last probe firing is about
1.4 milliseconds.  That is far too quick to demonstrate DTrace's
ability to attach to an already-running program.  So we will use
another program for the next demo.

## Tracing a Pony program and Python code and the kernel, all at once

The DTrace program this time is too long to be comfortable on the
command line.  Instead, I save it to a file and then use the `-s`
flag to allow the `dtrace` command to find it.

This script uses several types of probes:

* Pony's `gc-start` and `gc-end` probes, to count how many times the
  garbage collector is triggered.
* Pony's `heap-alloc` probe, to create a histogram of the memory
  allocation request sizes.
* Python's `function-call` probe, to measure the latency of each
  Python function call.  Python functions may call other Python
  functions, naturally, so we'll use a counter to keep track of how
  far in the Python call stack we are.  When we've returned to the
  top, then we add to the histogram of measured latency in
  nanoseconds.
* We use a probe inside of the kernel, `io:::start`, that fires each
  time that a disk or NFS I/O operation starts.
* A special probe called `tick-5sec` to print the results of
  the DTrace script and then stop tracing.

Here is the DTrace script itself.  Its syntax is a mixture of Awk and
C.  The bookkeeping required for the Python function call latency
makes this script more complicated than many DTrace scripts are.  If
it doesn't make 100% sense right now, feel free to skip ahead.

```awk
#pragma D option aggsize=8m
#pragma D option bufsize=16m
#pragma D option dynvarsize=16m

pony$target:::gc-start,pony$target:::gc-end
{
    @pony[probename] = count();
}

pony$target:::heap-alloc
{
    @heap[probename] = quantize(arg1);
}

python$target:::function-entry
/ self->count == 0 /
{
    self->ts = timestamp;
    self->count = 1;
    self->line = arg2;
}
    
python$target:::function-entry
/ self->count > 0 /
{
    self->count = self->count + 1;
}
    
python$target:::function-return
/ self->ts != 0 && self->count > 1 /
{
    self->count = self->count - 1;
}

python$target:::function-return
/ self->ts != 0 && self->count == 1 /
{
    elapsed_ns = timestamp - self->ts;
    function = copyinstr(arg1);
    module = strjoin(",", basename(copyinstr(arg0)));
    line = strjoin(":", lltostr(self->line));
    @python[strjoin(function, strjoin(module, line))] = quantize(elapsed_ns);
    self->ts = 0;
    self->count = 0;
    self->line = 0;
}

io:::start
{
    @os["Disk I/O operation start count"] = count();
}

tick-5sec
{
    printf("Stopping after 5 seconds.\n");
    printf("\nValues in the @pony array (units = none)\n");
    printa(@pony);
    printf("\nValues in the @heap array (units = bytes)\n");
    printa(@heap);
    printf("\nValues in the @python array (units = nanoseconds/call)\n");
    printa(@python);
    printf("\nValues in the @os array (units = IO ops)\n");
    printa(@os);
    exit(0);
}
```

Let's use the `marketspread` app as discussed in
[this prior blog article about Wallaroo's "Market Spread App"][marketspread-blog]
for our DTrace experiment.  After storing this script in a file called
`/tmp/foo.d` on my Mac and starting the app according to
[the Market Spread app's README.md file][marketspread-readme],
then we see something like this:

```
% sudo dtrace -q -C -s /tmp/foo.d -p 28132
Stopping after 5 seconds.

Values in the @pony array (units = none)

  gc-end                                                         1005
  gc-start                                                       1005

Values in the @heap array (units = bytes)

  heap-alloc                                        
           value  ------------- Distribution ------------- count    
               4 |                                         0        
               8 |@@@@@                                    40128    
              16 |@                                        9492     
              32 |@@@@@@@@@@@@@@@@@                        129100   
              64 |@@@@@@@@@@@@                             85796    
             128 |@                                        10286    
             256 |@                                        5540     
             512 |@                                        6334     
            1024 |@                                        10280    
            2048 |                                         0        


Values in the @python array (units = nanoseconds/call)

  payload_length,market_spread.py:141               
           value  ------------- Distribution ------------- count    
            1024 |                                         0        
            2048 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@     971      
            4096 |@@@                                      78       
            8192 |@                                        28       
           16384 |                                         3        
           32768 |                                         0        

  payload_length,market_spread.py:209               
           value  ------------- Distribution ------------- count    
            1024 |                                         0        
            2048 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@         854      
            4096 |@@@@@@@                                  186      
            8192 |@                                        36       
           16384 |                                         4        
           32768 |                                         0        

  decode,market_spread.py:212                       
           value  ------------- Distribution ------------- count    
            1024 |                                         0        
            2048 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@      5699     
            4096 |@@@@                                     723      
            8192 |                                         54       
           16384 |                                         3        
           32768 |                                         1        
           65536 |                                         0        

  decode,market_spread.py:144                       
           value  ------------- Distribution ------------- count    
            1024 |                                         0        
            2048 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    9031     
            4096 |@@                                       596      
            8192 |                                         86       
           16384 |                                         6        
           32768 |                                         1        
           65536 |                                         0        

  partition,market_spread.py:106                    
           value  ------------- Distribution ------------- count    
            8192 |                                         0        
           16384 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@  2103     
           32768 |@                                        50       
           65536 |                                         7        
          131072 |                                         0        


Values in the @os array (units = IO ops)

  Disk I/O operation start count                                    3

```

We've learned many things here also.

* Garbage collection started & stopped `1005` times, or about 201
  times/second on average.
* Pony's heap allocator is allocating many different sizes of objects,
  but all of them are relatively small.
  * The smallest fall in the 8-16 byte histogram bin.
  * The largest fall in the 1024-2048 byte histogram bin.
  * Objects with sizes 32-64 bytes are the most frequently allocated.
* Most Python functions are executing in 2-3 microseconds.  The
  exception is the `partition()` function, typically requiring 16-32
  microseconds.
* OS X's Python version 2 isn't firing probes for all of the Python
  functions and class methods that we know are being called.
  * That's unfortunate for a demo/tutorial such as this.
  * It is out of scope of this article to figure out why, my apologies.
  * However, it is tantalizing to note that if I create a simple function
    like this: `def excuse(): True`, and then if I call `excuse()` at
    the top of every function and method in the `market_spread.py`
    module, then the Python USDT probes will fire as expected.
  * Very odd, indeed.
* Inside of the kernel, we counted `3` disk I/O operations started.
  This workload is not expected to generate any significant disk
  activity; the average rate disk I/O rate of approximately 1 op/second 
  falls within our expected range.

<a id="lunch"></a>
We also learned something that's useful in many contexts but is
especially valuable in sensitive production environments: the DTrace
script did indeed stop itself after 5 seconds.  When you aren't sure
how much overhead DTrace might add to your program, you can simply add
this fail-safe clause that exits after a short time.  If
your program slows down too much, don't worry.  When the DTrace script
ends (for any reason), the kernel will re-write your program back into
its original `nop` form.

This trick is also lunch-break safe: if you wander away from your
computer to eat lunch and forget that the script is running, it will
stop safely without you.

## Probes available inside of the Pony runtime

[Appendix B](#appendix-b-pony-runtime-dtrace-probes) contains
a complete list of the DTrace USDT probes that are available today
in the Pony runtime.  They include:

* Runtime setup & shutdown events
* Actor allocation, deallocation, and scheduling decisions
* Sending and receiving of inter-actor and inter-thread messages
* Garbage collection begin & end events
* Scheduler-related activity caused by successful & unsuccessful "work
  stealing"

Many other languages also provide DTrace probes in their runtime.
It is interesting to study the differences of Pony's probes with probes
embedded in other languages & their runtimes.

* [Python's DTrace provider file][python provider] for Python 3.7.
  This definition file contains more probes than Python 2.7's
  definition, if you have a Python 2.7 package that supports DTrace.
  As far as I can tell, DTrace support was officially added to Python
  in version 3.6.
* [The Java HotSpot VM's DTrace reference][java provider] describes
  probes in several categories including: VM lifecycle, thread
  lifecycle,  garbage collection, class loading, method compilation,
  monitors, and more.
* [The Erlang and Elixir "BEAM" DTrace overview][erlang dtrace summary]
  and [Erlang DTrace provider file][erlang-provider] contains over 60
  probes in categories similar to HotSpot's probes.

## In conclusion

I hope I've given you a glimpse of the flexibility and power of
DTrace, a dynamic tracing tool that's available in a number of
operating systems.  If you don't have DTrace available, I recommend
learning about the dynamic tracing tool(s) available in your favorite
OS.

The Wallaroo application from Wallaroo Labs is a hybrid, written in
both Pony and Python and also using runtime libraries that are written
in C.  I've used DTrace to measure events created by probes that fire
in the Pony runtime, in the Python interpreter, and also inside
of the operating system.  Wallaroo is a young application written in a
young programming language, Pony.  A lot of work remains to make
all of Wallaroo's computations observable via dynamic tracing.

Dynamic tracing is a fantastic tool to have in your mental toolbox.
However, sometimes
a debugger like GDB or profilers like GProf or Valgrind can do things
that a dynamic tracer will never be able to do.  It isn't a dynamic tracing
versus traditional tools fight.  It's a use-each-when-appropriate
thing!

Remember: you can use dynamic tracing anywhere that your OS supports
it.  That includes "in production", where DTrace can easily
examine otherwise-hidden application & kernel behaviors.

I skipped mentioning that you can use DTrace or SystemTap to
trace the function entry & return events of
*any non-static C function in any program*.
That little trick alone can save you hours of
frustration & guessing about how a program is behaving.  But you can
learn that easily on your own.  Please, go explore!

## Appendix A: Dynamic tracing resources for further study

For general information on dynamic tracing and overviews of
some of the implementations available in open source operating system
today:

* Wikipedia on tracing: https://en.wikipedia.org/wiki/Tracing_(software%29
* Wikipedia on DTrace: https://en.wikipedia.org/wiki/DTrace
* Wikipedia on SystemTap: https://en.wikipedia.org/wiki/SystemTap
* Linux uprobes overview: https://lwn.net/Articles/499190/
  * Try https://events.static.linuxfound.org/slides/lfcs2010_keniston.pdf
    if you prefer presentation slides instead of prose.
* Linux kprobes overview: https://lwn.net/Articles/132196/
* Linux perf overview: https://perf.wiki.kernel.org/index.php/Main_Page

For more about DTrace:

* <a id="dtrace-book"></a> The book "DTrace: Dynamic Tracing in Oracle
  Solaris, Mac OS X, and FreeBSD" by Gregg and Mauro
  is a fantastic guide to using DTrace and
  how to observe nearly every part of the operating system kernel.
  Ask your favorite bookseller to get a hardcopy or a electronic/PDF
  version.  I have both and still use them regularly. `^_^`
* If you prefer starting with someone else's pre-built DTrace
  tools rather than writing DTrace tools from scratch, please read the
  extensive introduction to Brendan Gregg's "DTrace Tools" toolkit:
  http://www.brendangregg.com/dtrace.html
* A book's worth of DTrace reference material is available free in Sun
  Microsystem's DTrace guide from 2008: http://dtrace.org/guide/
* A curated list of awesome DTrace books, articles, videos, tools and
  resources: https://awesome-dtrace.com
  * I highly recommend "The DTrace cheatsheet", which I refer to
  whenever I have a "How do I use...?" senior moment:
  http://www.brendangregg.com/DTrace/DTrace-cheatsheet.pdf
* A collection of 14 DTrace scripts for analyzing Python programs: http://web.mit.edu/freebsd/head/cddl/contrib/dtracetoolkit/Python/
* The User Guide for "Instruments", the DTrace GUI app for OS X:
  https://developer.apple.com/library/content/documentation/DeveloperTools/Conceptual/InstrumentsUserGuide/index.html
* A complete "hands on lab" based on a VirtualBox VM of OpenSolaris,
  with 18 exercises for learning DTrace: http://dtracehol.com/#Intro

For more about dynamic tracing tools for Linux:

* Brendan Gregg's article, "At Long Last, Linux Gets Dynamic Tracing":
  https://thenewstack.io/long-last-linux-gets-dynamic-tracing/
  * Don't miss a link at the end to Brendan's presentation slides,
    "Linux 4.x Tracing Tools Using BPF Superpowers":
  * Another article by Brendan, contains dozens of links for further
    reading about eBPF and dynamic tracing:
    http://www.brendangregg.com/blog/2016-10-27/dtrace-for-linux-2016.html
* An introduction + examples, "Dynamic tracing in Linux user and
  kernel space":
  https://opensource.com/article/17/7/dynamic-tracing-linux-user-and-kernel-space
* Tutorial and lab+exercises by Sergey Klyaus, "Dynamic Tracing with
  DTrace & SystemTap": http://myaut.github.io/dtrace-stap-book/
* The latest BPF-based Linux tools for Linux kernel introspection,
  for "recent" Linux 4.1 and later kernels: https://github.com/iovisor/bcc
  * Includes a treasure trove of 75 utilities for measuring kernel
    activity!  (Scroll down to the middle of the README.)
* Presentation slides by Hiroyuki ISHII, "Dynamic Tracing Tools on
  ARM/AArch64 platform Updates and Challenges": 
  https://elinux.org/images/3/32/ELC_2017_NA_dynamic_tracing_tools_on_arm_aarch64_platform.pdf
* Article by Michael Paquier, "Dynamic tracing with Postgres":
  http://paquier.xyz/postgresql-2/postgres-dynamic-tracing/
* Article by Richard Friedman, "Using DTrace on Oracle Linux":
  http://www.oracle.com/technetwork/articles/servers-storage-dev/dtrace-on-linux-1956556.html
* DTrace for Linux, the unofficial port: https://github.com/dtrace4linux/linux

## Appendix B: Pony runtime DTrace probes


```C
provider pony {
  /**
   * Fired when a actor is being created
   * @param scheduler is the scheduler that created the actor
   * @actor is the actor that was created
   */
  probe actor__alloc(uintptr_t scheduler, uintptr_t actor);

  /**
   * Fired when a message is being send
   * @param scheduler is the active scheduler
   * @param id the message id
   * @param actor_from is the sending actor
   * @param actor_to is the receiving actor
   */
  probe actor__msg__send(uintptr_t scheduler, uint32_t id, uintptr_t actor_from, uintptr_t actor_to);

  /**
   * Fired when a message is being run by an actor
   * @param actor the actor running the message
   * @param id the message id
   */
  probe actor__msg__run(uintptr_t scheduler, uintptr_t actor, uint32_t id);

  /**
   * Fired when a message is being sent to an actor
   * @param scheduler is the active scheduler's index
   * @param id the message id
   * @param actor_from is the sending actor
   * @param actor_to is the receiving actor
   */
  probe actor__msg__push(int32_t scheduler_index, uint32_t id, uintptr_t actor_from, uintptr_t actor_to);

  /**
   * Fired when a message is being run by an actor
   * @param scheduler is the active scheduler's index
   * @param id the message id
   * @param actor_to is the receiving actor
   */
  probe actor__msg__pop(int32_t scheduler_index, uint32_t id, uintptr_t actor);

  /**
   * Fired when a message is being sent to an thread
   * @param id the message id
   * @param thread_from is the sending thread index
   * @param thread_to is the receiving thread index
   */
  probe thread__msg__push(uint32_t id, uintptr_t thread_from, uintptr_t thread_to);

  /**
   * Fired when a message is being run by an thread
   * @param id the message id
   * @param thread_to is the receiving thread index
   */
  probe thread__msg__pop(uint32_t id, uintptr_t thread);

  /**
   * Fired when actor is scheduled
   * @param scheduler is the scheduler that scheduled the actor
   * @param actor is the scheduled actor
   */
  probe actor__scheduled(uintptr_t scheduler, uintptr_t actor);

  /**
   * Fired when actor is descheduled
   * @param scheduler is the scheduler that descheduled the actor
   * @param actor is the descheduled actor
   */
  probe actor__descheduled(uintptr_t scheduler, uintptr_t actor);

  /**
   * Fired when actor becomes overloaded
   * @param actor is the overloaded actor
   */
  probe actor__overloaded(uintptr_t actor);

  /**
   * Fired when actor stops being overloaded
   * @param actor is the no longer overloaded actor
   */
  probe actor__overloaded__cleared(uintptr_t actor);

  /**
   * Fired when actor is under pressure
   * @param actor is the under pressure actor
   */
  probe actor__under__pressure(uintptr_t actor);

  /**
   * Fired when actor is no longer under pressure
   * @param actor is the no longer under pressure actor
   */
  probe actor__pressure__released(uintptr_t actor);

  /**
   * Fired when cpu goes into nanosleep
   * @param ns is nano seconds spent in sleep
   */
  probe cpu__nanosleep(uint64_t ns);

  /**
   * Fired when the garbage collection function is ending
   */
  probe gc__end(uintptr_t scheduler);

  /**
   * Fired when the garbage collector finishes sending an object
   */
  probe gc__send__end(uintptr_t scheduler);

  /**
   * Fired when the garbage collector stats sending an object
   */
  probe gc__send__start(uintptr_t scheduler);

  /**
   * Fired when the garbage collector finishes receiving an object
   */
  probe gc__recv__end(uintptr_t scheduler);

  /**
   * Fired when the garbage collector starts receiving an object
   */
  probe gc__recv__start(uintptr_t scheduler);

  /**
   * Fired when the garbage collection function has started
   */
  probe gc__start(uintptr_t scheduler);

  /**
   * Fired when the garbage collection threshold is changed with a certain factor
   * @param factor the factor with which the GC threshold is changed
   */
  probe gc__threshold(double factor);

  /**
   * Fired when memory is allocated on the heap
   * @param size the size of the allocated memory
   */
  probe heap__alloc(uintptr_t scheduler, unsigned long size);

  /**
   * Fired when runtime initiates
   */
  probe rt__init();

  /**
   * Fired when runtime is initiated and the program starts
   */
  probe rt__start();

  /**
   * Fired when runtime shutdown is started
   */
  probe rt__end();

  /**
   * Fired when a scheduler successfully steals a job
   * @param scheduler is the scheduler that stole the job
   * @param victim is the victim that the scheduler stole from
   * @param actor is actor that was stolen from the victim
   */
  probe work__steal__successful(uintptr_t scheduler, uintptr_t victim, uintptr_t actor);

  /**
   * Fired when a scheduler fails to steal a job
   * @param scheduler is the scheduler that attempted theft
   * @param victim is the victim that the scheduler attempted to steal from
   */
  probe work__steal__failure(uintptr_t scheduler, uintptr_t victim);

};
```

## Appendix C: compiling Pony to support DTrace

Here is a recipe that I use for creating a DTrace-enabled Pony compiler &
runtime environment.  I usually have at least 5 versions of Pony
installed on my laptop at any one time.  I install them all underneath
the `/usr/local/pony` directory.  Here is the recipe that I use to
compile the `master` branch, with and without DTrace enabled.

NOTE: I also assume that you have followed the instructions in the
[Pony README][pony-readme] to set up all prerequisites, for example,
a supported version of the LLVM compiler.

```bash
cd /usr/local/src
git clone https://github.com/ponylang/ponyc.git
cd ponyc
git checkout -f master
make -j8 install destdir=/usr/local/pony/master
make -j8 install use=dtrace destdir=/usr/local/pony/master+dtrace
```

When finished, I add the directory `/usr/local/pony/master+dtrace/bin`
to my shell's search path (i.e., to the `$PATH` or `$path` variable).
If I wish to use the DTrace-unaware version of the compiler & runtime,
then I add `/usr/local/pony/master/bin` instead.

---

[wikipedia tracing]: https://en.wikipedia.org/wiki/Tracing_(software)
[DTrace]: https://en.wikipedia.org/wiki/DTrace
[SystemTap]: https://en.wikipedia.org/wiki/SystemTap
[ProbeVue]: https://www.ibm.com/support/knowledgecenter/en/ssw_aix_61/com.ibm.aix.genprogc/probevue_userguide.htm
[opencobol-tracing]: http://documentation.microfocus.com/help/index.jsp?topic=%2Fcom.microfocus.eclipse.infocenter.cobolruntime.win%2FBKFHFHTRACS004.html
[linux-uprobes]: https://lwn.net/Articles/499190/
[linux-kprobes]: https://lwn.net/Articles/132196/
[linux-perf]: https://perf.wiki.kernel.org/index.php/Main_Page
[julia-evans-tracing]: https://jvns.ca/blog/2017/07/05/linux-tracing-systems/
[brendan-gregg-tracing]: http://www.brendangregg.com/blog/2015-06-28/linux-ftrace-uprobe.html
[python provider]: https://github.com/python/cpython/blob/3.6/Include/pydtrace.d
[java provider]: http://www.math.uni-hamburg.de/doc/java/jdk1.6/docs/technotes/guides//vm/dtrace.html
[erlang-provider]: https://github.com/erlang/otp/blob/maint-20/erts/emulator/beam/erlang_dtrace.d
[erlang dtrace summary]: http://erlang.org/doc/apps/runtime_tools/DTRACE.html
[marketspread-blog]: https://blog.wallaroolabs.com/2017/12/stateful-multi-stream-processing-in-python-with-wallaroo/
[marketspread-readme]: https://github.com/WallarooLabs/wallaroo/tree/master/examples/python/market_spread#market-spread
[pony-readme]: https://github.com/ponylang/ponyc#building-ponyc-from-source
[wallaroo]: https://github.com/WallarooLabs/wallaroo#wallaroo
[hello-wallaroo]: https://blog.wallaroolabs.com/2017/03/hello-wallaroo/
[pony]: https://www.ponylang.org/
[python]: https://www.python.org/
[pony-examples]: https://github.com/ponylang/ponyc/tree/master/examples
[ebpf]: http://www.brendangregg.com/blog/2016-10-27/dtrace-for-linux-2016.html
