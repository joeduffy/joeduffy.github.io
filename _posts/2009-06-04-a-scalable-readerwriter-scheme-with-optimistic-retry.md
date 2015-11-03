---
layout: post
title: A scalable reader/writer scheme with optimistic retry
date: 2009-06-04 17:36:23.000000000 -07:00
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
An interesting alternative to reader/writer locks is to combine pessimistic writing
with optimistic reading.  This borrows some ideas from transactional memory,
although of course the ideas have existed long before.  I was reminded of this
trick by a colleague on my new team just a couple days ago.

The basic idea is to read a bunch of state optimistically, without taking a lock
of any sort, and then prior to using it for meaningful work (which may depend on
the state being consistent and correct), a validation step must take place.
This validation uses version numbers which writers are responsible for maintaining.
Specifically, we'll use two version counters, version1 and version2: the writer increments
version1, performs the writes, and then increments version2; and the reader reads
version2, performs its reads, and then verifies that version 1 is equal to the version2
that it saw at the start.  If this verification fails, we'll ordinarily just
do a little spinning and then go back around the loop again.

Stop for a moment and ponder something very critical to this algorithm.  The
writer increments variables in the opposite order of the reader's reads.  To
see why this works, imagine we start with version1 == version2 == 0.  There
are two hazards to worry about.  (1) A reader begins reading, and writes occur
before it has finished.  And (2) a reader begins reading while a write is in
progress.  These are simple to detect, and in fact boil down to the same thing.
A reader sees version2 == 0, and the first thing a writer does is version1++.
So when the reader attempts to validate, it will notice the version2 it saw != version1
any longer.  If the writer has already begun by the time the reader arrives,
it is possible for the reader to know it is doomed even before it has started doing
any of its reads.

Here is the code in its full glory:

```
using System;
using System.Threading;

public class OptimisticSynchronizer
{
    private volatile int m_version1;
    private volatile int m_version2;

    public void BeforeWrite() {
        ++m_version1;
    }

    public void AfterWrite() {
        ++m_version2;
    }

    public ReadMark GetReadMark() {
        return new ReadMark(this, m_version2);
    }

    public struct ReadMark
    {
        private OptimisticSynchronizer m_sync;
        private int m_version;

        internal ReadMark(OptimisticSynchronizer sync, int version) {
            m_sync = sync;
            m_version = version;
        }

        public bool IsValid {
            get { return m_sync.m_version1 == m_version; }
        }
    }

    public void DoWrite(Action writer) {
        BeforeWrite();
        try {
            writer();
        } finally {
            AfterWrite();
        }
    }

    public T DoRead<T>(Func<T> reader) {
        T value = default(T);

        SpinWait sw = new SpinWait();
        while (true) {
            ReadMark mark = GetReadMark();

            value = reader();

            if (mark.IsValid) {
                break;
            }

            sw.SpinOnce();
        }

        return value;
    }
}
```

We leave it to the caller of this class to acquire locks as appropriate to synchronize
writers.  Typically this will just mean wrapping a Monitor.Enter/Exit around
calls to things like BeforeWrite, AfterWrite, and DoWrite.  But readers explicitly
do not need this same protection.  DoRead exemplifies the safe reading pattern,
although it can be done by hand via the ReadMark APIs.

It's also worth considering what kinds of fences are truly required for this to work.
Logically speaking, we need to ensure the entrance to a protected block (either read
or write) is an acquire fence, and exit from the block is a release fence.
This is similar to the ordering semenaitcs necessary for a lock block.  So long
as we use volatile modifiers for the version counters, and for the variables read
within the protected block, this will work fine.  Even on weak models like IA64.
The beautiful thing is that we don't need full fences, even on models like X86 that
make use of store buffer forwarding  The classic store buffering case we
may worry about (on a single-threaded execution) would be something like
this, in pseudo-code:

```
version1++;
X = 42;
Y = 99;
version2++;

tmp = version2;
r0 = X;
r1 = Y;
success = (tmp == version1);
```

We'd be worried about satisfying some loads out of the store buffer, while satisfying
others out of the memory system.  But this is safe: if the load of X or Y sees
a different processor's writes, then the subsequent load of version1 necessarily
must witness the new value written by the other processor too.  And therefore
the validation will fail as we would expect and hope.

Here is a quick performance benchmark I whipped together, much in the same spirit
as my previous reader/writer lock examples.  I've measured varying numbers of
writers (0%, 5%, 10%, 25%, 50%, and 100%), and each thread spends a certain amount
of time inside the "lock region" doing some nonsense busy work.  The certain
amount of time is measured in terms of number of function calls (0, 10, 100, and
1000), and the work doesn't vary at all depending on whether a thread is reading
or writing.  I've measured four things: (1) Monitor.Enter/Exit as the baseline
(where both readers and writers just acquire the mutually exclusive lock), (2) ReaderWriterLockSlim,
(3) [the spin-based lock that I showed previously](http://joeduffyblog.com/blog/2009/02/21/AMoreScalableReaderwriterLockAndABitLessHarshConsiderationOfTheIdea.aspx),
and (4) the new OptimisticSynchronizer class with optimistic retry.  The values
are the ratio compared to the baseline (1), so that >1.0x means the particular entry
is slower, while <1.0x is faster.  I did these measurements on an 8-way machine
-- unlike [the previous study which was on a 4-way machine](http://joeduffyblog.com/blog/2009/02/21/AMoreScalableReaderwriterLockAndABitLessHarshConsiderationOfTheIdea.aspx)
-- which means that 0.125x would be a linear speedup compared to the serialized Monitor
version:

```
**_0% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.26      1.55        1.39        0.38
SpinRWL       0.12      0.17        0.13        0.18
OptSync       0.05      0.08        0.11        0.12

**_5% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.36      1.70        1.40        1.07
SpinRWL       0.98      1.07        0.55        0.30
OptSync       0.35      0.43        0.31        0.24

**_10% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.42      1.66        1.23        1.06
SpinRWL       1.41      1.61        0.91        0.51
OptSync       0.56      0.66        0.46        0.31

**_25% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.36      1.97        1.24        1.03
SpinRWL       2.39      2.22        1.08        0.89
OptSync       0.84      0.99        0.86        0.59

**_50% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.48      1.80        1.21        1.05
SpinRWL       3.16      3.30        1.81        1.19
OptSync       0.91      0.94        1.10        0.92

**_100% writers:_**
              0 calls   10 calls    100 calls   1000 calls
RWLSlim       1.35      1.67        1.22        1.09
SpinRWL       5.84      5.84        2.49        1.18
OptSync       0.93      0.99        1.13        1.17
```

For all cases but the 100% writers case, the OptimisticSynchronizer class does
extraordinarily well.

Although this approach screams performance-wise, it is admittedly much more difficult
and error-prone to use.  If the variables protected are references to heap
objects, you need to worry about using the read protection each time you touch a
field.  Just like locks, this technique doesn't compose.  As with anything
other than simple locking, use this technique with great care and caution; although
the built-in acquire and release fences shield you from memory model reordering issues,
there are some easy traps you can fall into.  And as with any optimistic reading,
memory safety is a necessity; trying to use these techniques in C++, for example,
can easily lead to access violations and memory corruption.  Tread with caution.

**Update 6/4:** This technique, of course, is subject to ABA problems.  I failed
to mention that originally.  That is, if between reading version2, Int32.MaxValue
writers perform writes, the version1 field will wrap around such that the reader
will (erroneously) successfully validate.  Fixing this on 64-bit is simple (use
a 64-bit counter) but is less so on 32-bit due to the lack of atomicity on loads
and stores of 64-bit values (without using, say, an XCHG or related primitive).

**Update 6/18:** My original write-up incorrectly made some hidden assumptions about
the use of volatile.  This has now been cleared up.

