---
layout: post
title: A more scalable reader/writer lock, and a bit less harsh consideration of the idea
date: 2009-02-20 19:33:45.000000000 -08:00
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
I was very harsh in [my previous post](http://www.bluebytesoftware.com/blog/2009/02/12/ReaderwriterLocksAndTheirLackOfApplicabilityToFinegrainedSynchronization.aspx)
about reader/writer locks.

The results are clearly very hardware-specific.  And one can certainly argue
that better implementations are possible.  (In fact, I will show one momentarily.)
But no matter which way you slice-and-dice it, a lock implies mutable shared state
which implies contention.  [Herb](http://gotw.ca/) argued this point quite well,
and rather thoroughly, in his [recent Dr. Dobb's article](http://www.ddj.com/architect/214100002).
Interference due to contention means more time spent resolving memory conflicts and
less time doing useful work.  A reader/writer lock can be infinitely clever,
but there is still a consensus protocol that must be established: and that implies
a loss of scalability.  Pretty simple.

It's very tricky to develop a consensus protocol that is sufficiently lossy so
as to relieve memory contention while at the same time being sufficiently precise
that the lock works right.  In the case of a spinning reader/writer lock (which
is, for what it's worth, overly naïve an approach for most circumstances), you
need to ensure that a writer knows for sure when there are 0 readers, and that each
reader knows for sure whether there is 0 or 1 writer.  (For blocking reader/writer
locks, there's a whole lot more.)  One promising thing to note is that the
writer only needs to know whether there are 0 or N readers, but not the specific
value N; there's a fair bit of research on scalable counters (like [this](http://research.sun.com/scalable/pubs/PODC2007-SNZI.pdf))
which exploit problems of this nature.  Unfortunately, it's not completely
relevant here.  You need to know exactly when the transition from N to
0 readers happens in order to let the writer through in a timely fashion; and in
order to account for that transition, a consensus among readers is needed.
That's hard to do.

More scalable solutions are possible than [the simple lock I showed previously](http://www.bluebytesoftware.com/blog/2009/01/30/ASinglewordReaderwriterSpinLock.aspx).
Although writers need to know whether readers are present, the readers themselves
could care less about other readers.  As a result, we can make the lock slightly
more expensive for the writer, because it needs to accumulate the count of readers,
but this allows us to make it it slightly cheaper for the readers to enter and exit.
Where cheaper means less contention.

Here's one possible algorithm.  We'll keep an array of read flags and a
single write flag:

```
private volatile int m_writer;
private ReadEntry[] m_readers = new ReadEntry[Environment.ProcessorCount * 16];
```

A few things are noteworthy about the read flags.

First, it's an array of ReadEntry values.  These are just simple structs that
wrap a volatile int, but we also pad the struct so that it's 128 bytes in total
size.  That avoids the situation where multiple read flags just happen to end
up sharing the same cache line (which are usually either 64 or 128 bytes in size),
which leads to false sharing in the memory system (destroying our aim to reduce contention).

```
[StructLayout(LayoutKind.Sequential, Size = 128)]
struct ReadEntry {
    internal volatile int m_taken;
}
```

Second, we size the array to be 16-times the number of processors.  We hash
into it based on the calling thread's unique identifier, so to reduce (but not
eliminate) the chance of hashing collisions, we'll use a few times more buckets
than the total number of concurrent threads.  Hashing collisions are expensive:
they incur some amount of memory contention, and also demand that we use an atomic
CAS increment instead of an ordinary ++.  (While a super-duper-cheap TLS solution
might seem more ideal, there isn't any good per-object TLS solution to use.
The array hashing approach is actually quite fast.)

Notice that we're using an awful lot of space for a single lock.  This means
the techniques I show here wouldn't be readily applicable to a system that uses
lots of fine-grained locks, like transactional memory.  But similar ideas can
be extrapolated, e.g., by using shared lock tables.

Lastly, some invariants among these fields are self-evident.  When the
writer flag is 0, no writers are waiting; when it is 1, either a writer is actively
in the critical section, or there is a writer waiting for readers to exit.
When at least one reader flag entry is non-0, there is a reader either inside
the lock or attempting to enter it.  Thus, no new writer is permitted while
there's a non-0 reader entry, and no new reader is permitted while there's a
non-0 writer flag.  This is sufficient to ensure the reader/writer
lock properties hold.

Now let's look at how the EnterReadLock and ExitReadLock methods work.

When a reader arrives, it spins until the writer flag is non-0.  It then hashes
into the read flag array using its unique thread identifier, and then atomically
increments the read counter.  It then needs to recheck that a writer didn't
arrive in the meantime.  (The CAS increment means we can safely do this without
worry for reordering bugs, like the read of the writer flag passing the write to
the reader flag.)  If a writer hasn't arrived, the read lock has been successfully
acquired and we're done; if a writer has arrived, however, the reader needs to
back out the change (since the writer might be waiting for the read flag to become
0) and then go back to spinning.  It will retry again once the writer exits.

```
private int ReadLockIndex {
    get { return Thread.CurrentThread.ManagedThreadId % m_readers.Length; }
}

public void EnterReadLock() {
    SPW sw = new SPW();
    int tid = ReadLockIndex;

    // Wait until there are no writers.
    while (true) {
        while (m_writer == 1) sw.SpinOnce();

        // Try to take the read lock.
        Interlocked.Increment(ref m_readers[tid].m_taken);
        if (m_writer == 0) {
            // Success, no writer, proceed.
            break;
        }

        // Back off, to let the writer go through.
        Interlocked.Decrement(ref m_readers[tid].m_taken);
    }
}
```

(Note that SPW is a little type to encapsulate the spin-wait logic, including some
amount of backoff to reduce contention.  An example implementation at the bottom
of this essay, along with the full reader/writer lock code.  .NET 4.0 includes
a SpinWait type that provides this same functionality.)

Exiting the read lock is pretty simple.  We just need to decrement our counter.

```
public void ExitReadLock() {
    // Just note that the current reader has left the lock.
    Interlocked.Decrement(ref m_readers[ReadLockIndex].m_taken);
}
```

The writer lock is pretty straightforward.  It works the same way most spin-based
mutually exclusive locks work, but using a CAS on the writer flag, but has an extra
step after successfully acquiring the lock: a writer must walk the list of read flags,
and wait for each one to become 0.  (This is similar to Peterson's mutual exclusion
algorithm for N-threads.)  Because the write flag is set first (using a CAS),
and because new readers won't enter if the flag is set, we can be assured this
works correctly without hokey memory reordering problems cropping up.

```
public void EnterWriteLock() {
    SPW sw = new SPW();
    while (true) {
        if (m_writer == 0 &&
                Interlocked.Exchange(ref m_writer, 1) == 0) {
            // We now hold the write lock, and prevent new readers.
            // But we must ensure no readers exist before proceeding.
            for (int i = 0; i < m_readers.Length; i++) {
                while (m_readers[i].m_taken != 0) sw.SpinOnce();
            }
            break;
        }

        // We failed to take the write lock; wait a bit and retry.
        sw.SpinOnce();
    }
}
```

And exiting the write lock is even simpler than exiting the read lock.  We just
set the writer flag to 0.

```
public void ExitWriteLock() {
    // No need for a CAS.
    m_writer = 0;
}
```

Given all of that, you might wonder how well this bad boy performs.  Well, single-threaded
performance is a bit worse than the previous spin reader/writer lock: about 1.55x
the cost of a monitor acquisition for the read lock instead of 0.95x, and about 5.52x
for the write lock instead of 0.85X.  This makes sense.  There's simply
a whole lot more work going on in this new lock compared to the old, simple one.

But scalability is vastly improved.  Our hard work has apparently paid off.
Here's a table much like the one in the previous post: scaling over the equivalent
mutually exclusive monitor code, for various percentages of writers and various amounts
of "work" (counts of function calls) inside the lock region.  (I have left out
the legacy .NET ReaderWriterLock type because it is embarassingly terrible.)
Remember: 1.0x means it scales the new lock is the same as monitor, 0.5x means
twice as fast, and 2.0x means twice as slow.  0.25x is ideal speedup (4x) since
I am running the tests on a four way machine.

```
**0% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.11x       2.01x       0.96x       0.32x
SpinRWL (old)       9.63x       7.04x       1.02x       0.26x
SpinRWL (new)       0.39x       0.36x       0.28x       0.25x

**5% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.29x       2.36x       1.18x       0.61x
SpinRWL (old)       5.69x       5.59x       1.43x       0.94x
SpinRWL (new)       1.01x       0.96x       0.45x       0.38x

**10% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.26x       2.04x       1.15x       1.00x
SpinRWL (old)       6.87x       5.03x       1.42x       1.34x
SpinRWL (new)       1.60x       1.51x       0.63x       0.53x

**25% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.09x       2.10x       1.14x       1.00x
SpinRWL (old)       4.70x       4.20x       1.43x       1.69x
SpinRWL (new)       2.81x       2.29x       1.27x       0.73x

**50% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.18x       1.95x       1.15x       0.95x
SpinRWL (old)       3.23x       3.73x       1.54x       1.39x
SpinRWL (new)       3.16x       2.76x       1.73x       1.10x

**100% writers:**
                    *0 calls*   *10 calls*  *100 calls* *1000 calls*
RWLSlim (3.5)       2.18x       1.95x       1.04x       0.92x
SpinRWL (old)       2.63x       2.04x       1.06x       0.87x
SpinRWL (new)       6.79x       3.96x       1.62x       1.06x
```

You can see there are now several more cases where the new reader/writer lock beats
out both the .NET 3.5 ReaderWriterLockSlim type in addition to our previous attempt.
In fact, we now have a few new scenarios that scale, like 5% or 10% writers where
the amount of work being done is at least 100 function calls.  (Unfortunately,
doing 100 or more function calls inside a lock that uses spin-waiting is dangerous
and considered a very bad practice: you should be able to count the number of instructions
on your fingers (and toes).  But that's somewhat beside the point.)
In summary, so long as there is a fair amount of work going on and the percentage
of writers remains very low, we might see a benefit.

So was I overly harsh on reader/writer locks in my last post?  Sure, maybe a
little.  While I am still very disappointed in the current .NET reader/writer
locks (and, I imagine, the Vista SRWLock), the results I was able to get here are
a bit more promising.

But the point I was trying to get across is the same: sharing is sharing is sharing.
Avoid it like the plague.

_(Thanks to _ [_Tim Harris_](http://research.microsoft.com/en-us/um/people/tharris/)_
for sending me private email about my previous posts.  The brief discussion
inspired me to pick this back up.)

Here's the full code for the reader/writer lock.

```
using System;
using System.Threading;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// We use plenty of interlocked operations on volatile fields below. Safe.
#pragma warning disable 0420

/// <summary>
/// A very lightweight reader/writer lock.  It uses a single word of memory,
/// and only spins when contention arises (no events are necessary).
/// </summary>
public class ReaderWriterSpinLockPerProc {
    private volatile int m_writer;
    private volatile ReadEntry[] m_readers =
        new ReadEntry[Environment.ProcessorCount * 16];

    [StructLayout(LayoutKind.Sequential, Size = 128)]
    struct ReadEntry {
        internal volatile int m_taken;
    }

    private int ReadLockIndex {
        get { return Thread.CurrentThread.ManagedThreadId % m_readers.Length; }
    }

    public void EnterReadLock() {
        SPW sw = new SPW();
        int tid = ReadLockIndex;

        // Wait until there are no writers.
        while (true) {
            while (m_writer == 1) sw.SpinOnce();

            // Try to take the read lock.
            Interlocked.Increment(ref m_readers[tid].m_taken);
            if (m_writer == 0) {
                // Success, no writer, proceed.
                break;
            }

            // Back off, to let the writer go through.
            Interlocked.Decrement(ref m_readers[tid].m_taken);
        }
    }

    public void EnterWriteLock() {
        SPW sw = new SPW();
        while (true) {
            if (m_writer == 0 &&
                    Interlocked.Exchange(ref m_writer, 1) == 0) {
                // We now hold the write lock, and prevent new readers.
                // But we must ensure no readers exist before proceeding.
                for (int i = 0; i < m_readers.Length; i++) {
                    while (m_readers[i].m_taken != 0) sw.SpinOnce();
                }
                break;
            }

            // We failed to take the write lock; wait a bit and retry.
            sw.SpinOnce();
        }
    }

    public void ExitReadLock() {
        // Just note that the current reader has left the lock.
        Interlocked.Decrement(ref m_readers[ReadLockIndex].m_taken);
    }

    public void ExitWriteLock() {
        // No need for a CAS.
        m_writer = 0;
    }
}

struct SPW {
    private int m_count;

    internal void SpinOnce() {
        if (m_count++ > 32) {
            Thread.Sleep(0);
        }
        else if (m_count > 12) {
            Thread.Yield();
        }
        else {
            Thread.SpinWait(2 << m_count);
        }
    }
}
```

