---
layout: post
title: Some performance implications of CAS operations
date: 2009-01-08 19:15:51.000000000 -08:00
categories:
- Technology
tags: []
status: publish
type: post
published: true
meta:
  _wpas_done_all: '1'
author:
  login: admin
  email: joeduffy@acm.org
  display_name: joeduffy
  first_name: ''
  last_name: ''
---
CAS operations _kill_ scalability.

("CAS" means compare-and-swap.  This is the term most commonly used in academic
literature, but it is commonly referred to under many guises.  Windows has historically
called it an "interlocked" operation and offers a bunch of such-named Win32 APIs;
.NET does the same.  This set entails X86 instructions like XCHG, CMPXCHG, and
certain instructions prefixed with LOCK, such as INC, ADD, and so on.)

My opening statement is a bit extreme, but it's true enough.  There are several
reasons:

0. CAS relies on support in the hardware to ensure atomicity.  Namely, most
Intel and AMD architectures use a MOSEI cache coherency protocol to manage cache
lines.  In such an architecture, CAS operations on uncontended lines that are
owned exclusively (E) within a processor's cache are relatively cheap.  But
any contention -- false or otherwise -- leads to invalidations and bus traffic.
The more invalidations, the more saturated the bus, and the greater the latency for
CAS completion.  Cache contention is a scalability killer for non-CAS memory
operations too, but the need to acquire a line exclusively makes matters doubly worse
when CAS is involved.

1. CAS costs more than ordinary memory operations, in CPU cycles.  This is due
to the additional burden on the cache hierarchy, and also because of requirements
around flushing write buffers, restrictions on speculation across the fences, and
impact to a compiler's ability to optimize around the CAS.

2. CAS is often used in optimistically concurrent operations.  That means a
failed CAS will lead to a retry of some sort -- typically with some kind of backoff
-- which is purely wasted work that isn't present when there isn't any contention.
And 0 and 1 both increase the risk of contention.

The most common occurrence of a CAS is upon lock entrance and exit.  Although
a lock can be built with a single CAS operation, CLR monitors use two (one for Enter
and another for Exit).  Lock-free algorithms often use CAS in place of locks,
but due to memory reordering such algorithms often need explicit fences that are
typically encoded as CAS instructions.  Although locks are evil, most good developers
know to keep lock hold times small.  As a result, one of the nastiest impediments
to performance and scaling has nothing to do with locks at all; it has to do with
the number, frequency, and locality of CAS operations.

As a simple illustration, imagine we'd like to increment a counter 100,000,000
times.  There are a few ways we could do this.  If we're just running
on a single CPU, we can use ordinary memory operations:

```
**Variant #0:**
static volatile int s_counter = 0;
for (int i = 0; i < N; i++) s_counter++;
```

This clearly isn't threadsafe, but provides a good baseline for the cost of incrementing
a counter.  The first way we might make it threadsafe is by using a LOCK INC:

```
**Variant #1:**
static volatile int s_counter = 0;
for (int i = 0; i < N; i++) Interlocked.Increment(ref s_counter);
```

This is now threadsafe.  An alternative way of doing this -- commonly needed
if we must perform some kind of validation (like overflow prevention) -- is to use
a CMPXCHG:

```
**Variant #2:**
static volatile int s_counter = 0;
for (int i = 0; i < N; i++) {
    int tmp;
    do {
        tmp = s_counter;
    } while (Interlocked.CompareExchange(ref s_counter, tmp+1, tmp) != tmp);
}
```

An interesting question to ask now is: How much slower will each variant be when
cache contention is introduced?  In other words, run a copy of each code on
P separate processors, incrementing the same s\_counter variable by N/P, and compare
the running times for different values of P, including 1.  You might be surprised
by the results.

For example, on one of my dual-processor/dual-core (that's 4-way) Intel machines,
the results are as follows.  I've run Variant #0 even though it's not threadsafe,
simply because it shows the effects of cache contention on ordinary memory loads
and stores.

```
#0, P = 1: 1.00X
#1, P = 1: 4.73X
#2, P = 1: 5.38X
#0, P = 2: 2.11X
#1, P = 2: 10.74X
#2, P = 2: 16.70X
#0, P = 4: 3.87X
#1, P = 4: 7.57X
#2, P = 4: 73.35X
```

All numbers are normalized and compared to the ++ code on a single processor.
In other words, Variant #0 run on 2 processors is 2.11X the cost of Variant #0 run
on 1 processor; similarly, Variant #0 run on 4 processors is 3.87X the cost of Variant #0
run on 1 processor.  Variant #1 gets even worse at 4.73X, 10.74X, and 7.57X,
respectively.  And Variant #2 explodes in cost as more contention is added,
going from 5.38X, to 16.70X, to a whopping 73.35X.  Adding more concurrency
actually makes things substantially worse.

(The absolute numbers are not to be trusted, and there are anomalies undoubtedly
introduced based on how threads are scheduled; I've not affinitized them, so they
may end up sharing sockets at will.  A more scientific experiment needs to consider
such things.)

The CMPXCHG example (Variant #2) can be improved by strategic spinning when a CAS
fails.  Part of what makes the numbers so bad -- particularly the P = 4 case
-- is the amount of lost time due to livelock and the associated memory system interference.

This is an extreme example.  Few workloads sit in a loop modifying the same
location in memory over and over and over again.  Even if they do -- as in
the case of a parallel for loop in which all threads fight to increment the shared
"current index" variable -- these accesses are ordinarily broken apart by sizeable
delays during which useful work is done.  Augmenting the test to delay accessing
the shared location by a certain number of function calls certainly relieves pressure.

For example, here are the numbers if we add a 2-function-call delay in between accesses:

```
#0, P = 1: 1.00X
#1, P = 1: 2.54X
#2, P = 1: 2.77X
#0, P = 2: 1.47X
#1, P = 2: 5.19X
#2, P = 2: 8.59X
#0, P = 4: 2.78X
#1, P = 4: 3.67X
#2, P = 4: 26.55X
```

And if we add a 64-function-call delay in between accesses, the micro-cost between
the three variants doesn't matter much.  But the contention behavior sure
is different.  And we can even find some cases where the multithreaded variants
run faster than the single-threaded counterpart:

```
#0, P = 1: 1.00X
#1, P = 1: 1.00X
#2, P = 1: 1.00X
#0, P = 2: 0.59X
#1, P = 2: 0.74X
#2, P = 2: 0.85X
#0, P = 4: 0.51X
#1, P = 4: 0.45X
#2, P = 4: 1.23X
```

This is the first time we have seen a number < 1.00X.  That's a speedup;
remember, we are using parallelism after all.

As you might guess, in the region between 2 and 64 function calls the results gradually
get better and better; and beyond 64, they get substantially better.  In fact,
when we insert 128 function calls in between, we get very close to perfect, linear
scaling for all 3 variants:

```
#0, P = 1: 1.00X
#1, P = 1: 1.00X
#2, P = 1: 1.00X
#0, P = 2: 0.50X
#1, P = 2: 0.52X
#2, P = 2: 0.52X
#0, P = 4: 0.30X
#1, P = 4: 0.29X
#2, P = 4: 0.27X
```

(As a reminder, 0.50X is a perfect speedup on a 2-CPU machine, and 0.25X is a perfect
speedup on a 4-CPU machine.)

The moral of this story is that nothing is free, and CAS is certainly no exception.
You should be extremely stingy with adding them to your code, and conscious of the
frequency at which threads will perform them.  The same is generally true of
all memory access patterns when parallelism is in play, but particularly for expensive
operations like CAS.

And even if you're not using CAS's directly in your code, you may be using them
via some system service.  Parallel Extensions uses them in many ways.
For instance, when you're doing a Parallel.For loop, we internally share a counter
that is accessed by multiple threads.  So even if your algorithm is theoretically
embarrassingly parallel, the internally counter management could get in your way.
We try to be intelligent by chunking up indices, but we aren't perfect: if you
have very small loop bodies the overhead of CAS could begin to impact scalability.
You can work around this by making loop bodies more chunky; one example of how is
by doing your own partitioning on top of our library (like executing multiple loop
iterations inside the body passed to Parallel.For).  Even things like allocating
memory with the CLR's workstation GC requires the occasional roundtrip to reserve
a thread-local allocation context by issuing a CAS operation against a shared memory
location.

