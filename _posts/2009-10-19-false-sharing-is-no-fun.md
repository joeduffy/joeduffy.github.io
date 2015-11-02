---
layout: post
title: False sharing is no fun
date: 2009-10-19 17:59:20.000000000 -07:00
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
Embarrassingly, I neglected to write about the oldest trick in the book in [my last
post](http://www.bluebytesoftware.com/blog/2009/10/05/FastSynchronizationBetweenASingleProducerAndSingleConsumer.aspx):
designing the producer/consumer data structure to reduce false sharing.  As
I've written about several times previously (e.g. [see here](http://www.bluebytesoftware.com/blog/2009/02/21/AMoreScalableReaderwriterLockAndABitLessHarshConsiderationOfTheIdea.aspx)),
and more so [in the book](http://www.bluebytesoftware.com/books/winconc/winconc_book_resources.html),
false sharing can be deadly and ought to be avoided.

As a simple example, consider a program that merely increments a shared counter over
and over again.  If we give P threads their own separate counters, and ask them
to increment the respective counter an equal number of times.  Each thread
can of course do this without synchronization, because the counters are distinct:
no locks or even interlocked operations are necessary.  Naively, one might expect
that running P of them in parallel leads to no interference, and hence perfect parallelization.
However, when I run a little benchmark on my 8-way machine, the numbers for increasing
values of P tell a very different story:

```
1 = 22425789
2 = 42023726   (187%)
4 = 175828522  (784%)
8 = 333906288  (1489%)
```

It is clear that the throughput drops dramatically as P increases.  The reason?
Each counter, being only 8 bytes wide, shares a cache line with as many as 7 other
counters -- or 15 if we're on a machine with 128 byte cache lines.  A simple
change to the counter's layout, so that individual counters do not share the same
cache line, will remedy the situation.  The numbers improve dramatically.
In fact, they remain constant no matter the value of P:

```
1 = 21914250
2 = 21900392   (100%)
4 = 21865781   (100%)
8 = 21934008   (100%)
```

This perfect scaling isn't always possible due to memory bandwidth, but because we're
just incrementing a single counter per core this doesn't manifest as a problem.

For what it's worth, the machine I am running these tests on is an 8-way, dual-socket,
quad-core.  Pairs of cores share an L1 cache, and all cores in a socket share
an L2 cache.  So the pairs {0,1}, {2,3}, {4,5}, and {6,7} are each expected
to have distinct L1 caches and the groups {0,1,2,3} and {4,5,6,7} are expect to have
distinct L2 caches.  The 2 number above is run with two threads affinitized
such that they share the same L1 cache.  If we force them apart, however, we
get slightly different results:

```
2 = 42023726   (187%) -- same L1 cache
2 = 54706505   (244%) -- same L2 cache
2 = 75030977   (335%) -- separate sockets
```

As expected, the more distance in the cache hierarchy, the greater the slowdown due
to the increased ping pong paths.

The specific results are of course unique to my machine, but nevertheless the conclusion
is clear: reducing sharing leads to substantial performance gains, particularly with
large numbers of threads hammering on the shared lines.  Often more so than
eliminating other sources of wasted cycles, like interlocked operations.  Eliminating
those sources is clearly important too, but it really is amazing how deadly and yet
difficult to discover false sharing can be: few cases are as obvious as this one.

One aside is worth mentioning before winding down.  When I first ran this experiment,
I had done it two ways: (1) with fields of a shared object, then using StructLayout(LayoutKind=Explicit)
to keep fields apart, and (2) with counters crammed into an array, which then contains
padding elements to eliminate the false sharing.  The former is shown above.
If you try the latter, you may be surprised.  The layout of arrays on the CLR
is such that an array's length resides before the first element.  So unless
you pad the first element of the array, all accesses will perform bounds checking
that touches the first element's line.  Because this line is being mutated by
the thread incrementing the first counter, terrible false sharing results.
To solve this, we must pad the first element too.

For example, here are the array numbers with false sharing:

```
1 = 27366202
2 = 125264714  (458%)
4 = 1383953372 (7969%)
8 = 3136996731 (11463%)
```

Notice the P = 8 case is over 100x slower!  Yowzas.  After fixing things,
with the first element padded, we again observe perfect scaling:

```
1 = 27393869
2 = 27465999   (100%)
4 = 27370901   (100%)
8 = 27408631   (100%)
```

Clearly false sharing is not merely a theoretical concern.  In fact, during
our Beta1 performance milestone in Parallel Extensions, most of our performance problems
came down to stamping out false sharing in numerous places: the partitioning logic
of parallel for loops, polling cancellation token flags, enumerators allocated at
the beginning of a PLINQ query and constantly mutated during its execution, and even
in our examples (e.g. see [Herb's matrix multiplication example](http://www.ddj.com/go-parallel/article/showArticle.jhtml?articleID=217500206)),
etc.  It is terribly simple to make a mistake and, in a complicated system,
terribly difficult to pinpoint the origin of what can be a truly crippling scalability
bottleneck.

In the next post, we will go back and take a look at our single-producer / single-consumer
buffer, and redesign it to have substantially better cache behavior.

~

For reference, here's the basic program used for a lot of these tests:

```
// #define CACHE_FRIENDLY
// #define USE_ARRAY

#pragma warning disable 0169

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

class Program
{
    const int P = 1;
#if USE_ARRAY
    class Counters
    {
        long[] m_longs;
        internal Counters(int n) {
#if CACHE_FRIENDLY
            m_longs = new long[(n+1)*16];
#else
            m_longs = new long[n];
#endif
        }

        public void Increment(int i) {
#if CACHE_FRIENDLY
            m_longs[(i+1)*16]++;
#else
            m_longs[i]++;
#endif
        }
    }

#else // USE_ARRAY
#if CACHE_FRIENDLY
    [StructLayout(LayoutKind.Explicit)]
#endif
    struct Counters
    {
#if CACHE_FRIENDLY
        [FieldOffset(0)]
#endif
        public long a;
#if CACHE_FRIENDLY
        [FieldOffset(128)]
#endif
        public long b;
#if CACHE_FRIENDLY
        [FieldOffset(256)]
#endif
        public long c;
#if CACHE_FRIENDLY
        [FieldOffset(384)]
#endif
        public long d;
#if CACHE_FRIENDLY
        [FieldOffset(512)]
#endif
        public long e;
#if CACHE_FRIENDLY
        [FieldOffset(640)]
#endif
        public long f;
#if CACHE_FRIENDLY
        [FieldOffset(768)]
#endif
        public long g;
#if CACHE_FRIENDLY
        [FieldOffset(896)]
#endif
        public long h;
    }

    static Counters s_c = new Counters();
#endif // USE_ARRAY

    public static void Main(string[] args)
    {
        int p = int.Parse(args[0]);
        const int iterations = int.MaxValue / 4;
        ManualResetEvent mre = new ManualResetEvent(false);

#if USE_ARRAY
        Counters c = new Counters(p);
#endif

        Thread[] ts = new Thread[p];
        for (int i = 0; i < ts.Length; i++) {
            int tid = i;
            ts[i] = new Thread(delegate() {
                SetThreadAffinityMask(GetCurrentThread(), new UIntPtr(1u << tid));
                mre.WaitOne();
                for (int j = 0; j < iterations; j++)
#if USE_ARRAY
                    c.Increment(tid);
#else
                    switch (tid) {
                        case 0: s_c.a++; break;
                        case 1: s_c.b++; break;
                        case 2: s_c.c++; break;
                        case 3: s_c.d++; break;
                        case 4: s_c.e++; break;
                        case 5: s_c.f++; break;
                        case 6: s_c.g++; break;
                        case 7: s_c.h++; break;
                    }
#endif
            });
            ts[i].Start();
        }

        Stopwatch sw = Stopwatch.StartNew();
        mre.Set();
        foreach (Thread t in ts) t.Join();
        Console.WriteLine(sw.ElapsedTicks);
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentThread();

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    static extern UIntPtr SetThreadAffinityMask(
            IntPtr hThread, UIntPtr dwThreadAffinityMask);
}
```

