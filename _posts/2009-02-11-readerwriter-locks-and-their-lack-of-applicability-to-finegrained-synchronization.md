---
layout: post
title: Reader/writer locks and their (lack of) applicability to fine-grained synchronization
date: 2009-02-11 20:33:34.000000000 -08:00
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
A couple weeks ago, I illustrated [a very simple reader/writer lock](http://www.bluebytesoftware.com/blog/2009/01/30/ASinglewordReaderwriterSpinLock.aspx)
that was comprised of a single word and used spinning instead of blocking under contention.
The reason you might use a lock with a read (aka shared) mode is fairly well known:
by allowing multiple readers to enter the lock simultaneously, concurrency is improved
and therefore so does scalability.  Or so the textbook theory goes.

As a purely theoretical illustration, imagine we're on a heavily loaded 8-CPU server
where a new request arrives every 0.25ms and runs for 1ms.  In an ideal world,
we could service requests coming in at a rate of 1ms / 8-CPUs = 0.125ms without falling
behind.  But imagine these requests need to access some shared state, and so
there is a bit of serialization required.  In fact, let's imagine each does
0.5ms' worth of its work inside a lock.  If you were to use a mutually exclusive
lock, then you'd have an immediate lock convoy on your hands.  Even with 8-CPUs
you won't be able to keep up.  You'll start off gradually building up a
debt, and eventually come to a crawl.  Let's examine the initial timeline:

```
Req#    Arrival     Acquire     Release     Wait Time
1       0.0ms       0.0ms       0.5ms       0.0ms
2       0.25ms      0.5ms       1.0ms       0.25ms
3       0.5ms       1.0ms       1.5ms       0.5ms
4       0.75ms      1.5ms       2.0ms       0.75ms
5       1.0ms       2.0ms       2.5ms       1.0ms
6       1.25ms      2.5ms       3.0ms       1.25ms
7       1.5ms       3.0ms       3.5ms       1.5ms
8       1.75ms      3.5ms       4.0ms       1.75ms
```

Oh jeez, after only the first 8 requests, we've fallen way behind.

Each new request adds 0.25ms onto the amount of time the request must wait for the
lock.  And it's not going to get any better:

```
9       2.0ms       4.0ms       4.5ms       2ms
10      2.25ms      4.5ms       5.0ms       2.25ms
11      2.5ms       5.0ms       5.5ms       2.5ms
12      2.75ms      5.5ms       6.0ms       2.75ms
... and so on ...
```

By request #9, requests have to wait for twice as long as they run.  Eventually
something has to give, or the server will come tumbling down.

Now, imagine we used a reader/writer lock instead.  Threads would never wait
for each other, and we wouldn't end up with this never-ending buildup of wait times.
In other words, the "Wait Time" column above would always be 0.0ms.  And
because the arrival rate is less than our theoretical limit of one request per 0.125ms,
our lock convoy is gone.  Right?

Unfortunately, probably not; this mental model is overly naïve.

Even when a read lock is acquired, there is mutual exclusion going on:

- Some reader/writer locks actually use mutually exclusive locks to protect their
own internal state, like the list of current readers!  This can come as a surprise,
but it's true of the .NET reader/writer locks.  [Vance's example](http://blogs.msdn.com/vancem/archive/2006/03/28/563180.aspx)
even does and, although it uses a spin lock in an attempt to reduce the overhead,
there's still no denying that it's mutual exclusion.

- And even if they don't use mutually exclusive locks, like the simple spin-based
one from my previous blog post, there are CAS instructions.  And a CAS instruction
actually amounts to a form of mutual exclusion at the hardware level, because the
cache coherency machinery needs to ensure that no two processors try to acquire and
modify the same cache line exclusively.

- In addition to all of that overhead, the cost in CPU cycles of acquiring the read-lock
is nowhere near zero.  Because of the use of locks and/or CAS internally, and
the resulting cache contention and line evictions that this will cause, throughput
will suffer.  If there is contention, threads may end up blocked (if real locks
are being used), spinning (if spin locks are being used), or simply optimistically
retrying CAS's due to line ping ponging.

The result?

Read locks are just as bad as mutually exclusive locks when lock hold times are short.
In fact, they can be worse, because reader/writer locks are more complicated and
therefore cost more than simple mutually exclusive locks: many need to keep track
of read lists in order to disallow recursive acquires, maintain multiple event handles
so certain kinds of waiters can be awakened over others, and store various kinds
of counters and flags.  Even my super simple single-word, spin-based reader/writer
lock needed to worry about blocking out readers when a writer was waiting, properly
incrementing and decrementing the reader count when readers are racing with one another
(leading to more complicated CAS on the exit path than ordinary write locks), and
so on.

That said, a reader/writer lock would in fact probably work in the situation above.
A hold time of 0.5ms is huge, and with only 8 concurrent threads and the arrival
rate we're talking about, the overheads are apt to be quite small in relation to
the work being done.  Another similar setting in which reader/writer locks commonly
make a noticeable difference is in the execution of large database transactions.

But the sad truth is that we tell programmers to keep lock hold times short, and
most locks I see are comprised of two dozen instructions or less.  So we're
in the microsecond range at the very most, which is certainly not large enough for
read locks to pan out.

To illustrate this point, I wrote a little benchmark program that benchmarks the
legacy .NET ReaderWriterLock, the 3.5 ReaderWriterLockSlim type, and my little spin
reader/writer lock.  All it does is spawn 4 threads on my dual-socket, dual-core
(4-CPU) machine, and then loop around so many times acquiring and releasing a certain
kind of lock.  I've written the test so that the amount of work done inside
the lock is parameterized as a certain number of non-inlined function calls.
I also parameterize the percentage of acquires that will be write-locks.  Then
I've run this a bunch of times, and compared the total time taken with the equivalent
code using a CLR Monitor for mutual exclusion instead.

Here are some results, where each column represents the number of function calls.
The entries are the cost relative to Monitor: 1.00x means they are the same, 0.5x
means the alternative lock is twice as fast, and 2.0x means the alternative lock
is twice as slow.  Remember, the ideal situation would be 0.25x: that is, by
allowing four threads to run completely concurrently, we run four times faster.

```
        0% writers:

                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    9.23x       6.46x       0.90x       0.49x
RWLSlim (3.5)   2.11x       2.01x       0.96x       0.32x
SpinRWL         9.63x       7.04x       1.02x       0.26x

        5% writers:
                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    10.55x      8.23x       1.71x       0.63x
RWLSlim (3.5)   2.29x       2.36x       1.18x       0.61x
SpinRWL         5.69x       5.59x       1.43x       0.94x

        10% writers:

                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    20.31x      10.39x      2.34x       0.99x
RWLSlim (3.5)   2.26x       2.04x       1.15x       1.00x
SpinRWL         6.87x       5.03x       1.42x       1.34x

        25% writers:

                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    74.49x      49.59x      9.18x       2.15x
RWLSlim (3.5)   2.09x       2.10x       1.14x       1.00x
SpinRWL         4.70x       4.20x       1.43x       1.69x

        50% writers:

                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    148.34x     98.46x      20.46x      3.63x
RWLSlim (3.5)   2.18x       1.95x       1.15x       0.95x
SpinRWL         3.23x       3.73x       1.54x       1.39x

        100% writers:
                0 calls     10 calls    100 calls   1000 calls
RWL (legacy)    170.59x     123.66x     24.04x      4.29x
RWLSlim (3.5)   2.18x       1.95x       1.04x       0.92x
SpinRWL         2.63x       2.04x       1.06x       0.87x
```

Clearly there are a number of anomalies in these numbers.  Why the legacy ReaderWriterLock
balloons to 170X the cost of Monitor when we have 100% writers is a very interesting
question indeed.  Why my simple spin reader/writer lock is 9.63X when we have
pure reads and 0 calls, and yet the ReaderWriterLockSlim type is only 2.11X is also
interesting.  And so on.  The numbers are very specific to the version
of .NET I am using, and indeed the precise machine configuration, including the number
and layout of cores and caches.

But if we look more generally at the numbers, ignoring some of the surprising ones,
we can make one interesting and safe conclusion: You need a really low percentage
of writers, and a really long amount of time inside the lock, for any scalability
wins to show up as a result of using a reader/writer lock.  Our best case was
the spin reader/writer lock when we had 0% writers and 1000 calls.  But clearly
if you have no writers, i.e., state is immutable, there's little point in
using any locks whatsoever!  This is an extreme result, where threads are hammering
on the lock constantly in a tight loop, but if you stop to think about it: When else
would a reader/writer lock make a difference?  If threads are just getting in
and out of the lock very quickly, and arrivals are infrequent, then there is no benefit
to allowing multiple threads in at once anyway.

The moral of the story?  Besides suggesting that you seriously question whether
a reader/writer lock is actually going to buy you anything, it's the same as the
conclusion in  [my previous post](http://www.bluebytesoftware.com/blog/2009/01/13/SomePerformanceImplicationsOfCASOperationsRedux.aspx) on
the matter:

> _Sharing is **evil** , fundamentally limits scalability, and is best avoided._

