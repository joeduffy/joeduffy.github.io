---
layout: post
title: A single-word reader/writer spin lock
date: 2009-01-29 20:03:33.000000000 -08:00
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
Reader/writer locks are commonly used when significantly more time is spent reading
shared state than writing it (as is often the case), with the aim of improving scalability.
The theoretical scalability wins come because the lock can be acquired in a special
read-mode, which permits multiple readers to enter at once.  A write-mode is
also available which offers typical mutual exclusion with respect to all readers
and writers.  The idea is simple: if many readers can read simultaneously, the
theory goes, concurrency improves.

(I'll be posting an analysis of reader/writer lock scalability in an upcoming post.
For a variety of reasons--most related to [my recent CAS post](http://www.bluebytesoftware.com/blog/2009/01/13/SomePerformanceImplicationsOfCASOperationsRedux.aspx)--they
seldom make a dramatic impact in practice.)

In addition to showing up in libraries--such as [Vista's new SRWLock](http://www.bluebytesoftware.com/blog/2006/06/22/NewVistaConcurrencyFeatures.aspx),
.NET's ReaderWriterLock, and [.NET 3.5's ReaderWriterLockSlim](http://www.bluebytesoftware.com/blog/2007/02/07/IntroducingTheNewReaderWriterLockSlimInOrcas.aspx)--they
are used pervasively in relational databases, distributed transactions, and software
transactional memory.

Vance Morrison [demonstrated a lightweight reader/writer lock](http://blogs.msdn.com/vancem/archive/2006/03/28/563180.aspx)
on his blog a couple years back.  Although quite small, you can get smaller.
Much like [the new SpinLock type](http://blogs.msdn.com/pfxteam/archive/2008/06/18/8620615.aspx)
being made available in .NET 4.0, we can build a ReaderWriterSpinLock that offers
several advantages:

1. It's a struct, and so there is no object allocation or space for an object header
necessary.

2. It's a single word in size (i.e., 4 bytes).

3. No kernel events are ever allocated; we will spin instead.

For cases in which reads are extraordinarily frequent, and writes are extraordinarily
rare, this approach can actually be useful.  Unfortunately, because one common
case in which reader/writer locks scale very well is when hold times are lengthy,
as will be shown in my upcoming post, even moderately common writes will result in
chewing up a whole lot of wasted CPU time due to (3).  If there's interest,
I will look into implementing a variant of this type that uses events for waiting.
Clearly this would sacrifice (2).

Some design decisions have been made in the name of keeping this thing lightweight:

1. No thread affinity will be used.

2. And therefore no recursive acquires will be allowed.

The full code is below, at the bottom of this post.  But let's review the
details one-by-one.

First, all state is packed into a single field, m\_state.  We'll use the 32nd
bit to represent whether the write lock is held, and we'll use the 31st bit to
represent whether a writer is attempting to acquire the lock.  As with most
reader/writer locks, we will give writers priority over readers because they are
supposed to be very infrequent.  In other words, once a writer arrives, no more
read lock acquires will be permitted.  The remaining 30 bits will be used to
store the reader count.  Some masks make this convenient:

```
private volatile int m_state;
private const int MASK_WRITER_BIT = unchecked((int)0x80000000);
private const int MASK_WRITER_WAITING_BIT = unchecked((int)0x40000000);
private const int MASK_WRITER_BITS = unchecked((int)(MASK_WRITER_BIT | MASK_WRITER_WAITING_BIT));
private const int MASK_READER_BITS = unchecked((int)~MASK_WRITER_BITS);
```

Now we can write the four methods: EnterWriteLock, ExitWriteLock, EnterReadLock,
ExitReadLock.

Entering the write lock merely entails setting m\_state to MASK\_WRITER\_BIT, provided
that we see it available.  If it's not available, we'll just go ahead and
try to set the MASK\_WRITER\_WAITING\_BIT to prevent subsequent read locks from being
acquired until we get in.  We then go ahead and spin until the lock is available
using the new type SpinWait in .NET 4.0, checking the m\_state field over and over
again.  The lock is available if m\_state is 0 or MASK\_WRITER\_WAITING\_BIT:

```
public void EnterWriteLock()
{
    SpinWait sw = new SpinWait();
    do
    {
        // If there are no readers currently, grab the write lock.
        int state = m_state;
        if ((state == 0 || state == MASK_WRITER_WAITING_BIT) &&
             Interlocked.CompareExchange(
                 ref m_state, MASK_WRITER_BIT, state) == state)
             return;

        // Otherwise, if the writer waiting bit is unset, set it.  We don't
        // care if we fail -- we'll have to try again the next time around.
        if ((state & MASK_WRITER_WAITING_BIT) == 0)
            Interlocked.CompareExchange(
                ref m_state, state | MASK_WRITER_WAITING_BIT, state);

        sw.SpinOnce();
    }
    while (true);
}
```

Leaving the write lock is actually quite simple.  We just set the m\_state field
to 0, preserving the MASK\_WRITER\_WAITING\_BIT just in case another writer has arrived
since we acquired the lock.  We use an Interlocked.Exchange (XCHG) operation
for this, although we technically could have just done an ordinary write, provided
doing so wouldn't cause memory model or availability problems:

```
public void ExitWriteLock()
{
    // Exiting the write lock is simple: just set the state to 0.  We
    // try to keep the writer waiting bit to prevent readers from getting
    // in -- but don't want to resort to a CAS, so we may lose one.

    Interlocked.Exchange(ref m_state, 0 | (m_state & MASK_WRITER_WAITING_BIT));

}
```

Entering the read lock is even more straightforward.  The lock is available
for readers when m\_state & MASK\_WRITER\_BITS is 0.  In other words, no writer
holds the lock and no writer is waiting for the lock.  Once we see the lock
in such a state, we merely try to add one to the state value and CAS it in.
In this way, m\_state & MASK\_READER\_BITS will be equal to the number of concurrent
readers in the lock:

```
public void EnterReadLock()
{
    SpinWait sw = new SpinWait();
    do
    {
        int state = m_state;
        if ((state & MASK_WRITER_BITS) == 0)
        {
            if (Interlocked.CompareExchange(
                    ref m_state, state + 1, state) == state)
                return;
        }

        sw.SpinOnce();
    }
    while (true);
}
```

Lastly, exiting the read lock is the most complicated operation of all.  It
needs to decrement the reader count, while at the same time preserving the
MASK\_WRITER\_WAITING\_BIT:

```
public void ExitReadLock()
{
    SpinWait sw = new SpinWait();
    do
    {
        // Validate we hold a read lock.
        int state = m_state;
        if ((state & MASK_READER_BITS) == 0)
            throw new Exception(
                "Cannot exit read lock when there are no readers");

        // Try to exit the read lock, preserving the writer waiting bit (if any).
        if (Interlocked.CompareExchange(
                ref m_state,
                ((state & MASK_READER_BITS) - 1) | (state & MASK_WRITER_WAITING_BIT),
                state) == state)
            return;

        sw.SpinOnce();
    }
    while (true);
}
```

And that's it.

Here are some single-threaded performance numbers, comparing the relative costs of
several locks out there.  These are taken from a large number of acquire/release
pairs, i.e., 'for (int i = 0; i < N; i++) { lock.Enter(); lock.Exit(); }', for
a very large value of N:

```
Monitor                     0004487479
RWL read lock (legacy)      0023042785      5.13491x
RWL write lock (legacy)     0023118085      5.15169x
SlimRWL read lock (3.5)     0009423579      2.099976x
SlimRWL write lock (3.5)    0008680855      1.934465x
Vance read lock             0004923609      1.097193x
Vance write lock            0004802136      1.070123x
SpinRWL read lock           0004298525      0.9579604x
SpinRWL write lock          0003819024      0.8510431x
````

The Nx ratios compare the lock in question to Monitor as our baseline.  Smaller
is better.  As you can see, we seem to be on pretty solid ground to start with.
But clearly the most interesting part of this whole thing is the scaling numbers--in
particular whether read-mode helps with throughput--both for the existing reader/writer
locks and our new one.  The results may surprise you.  That's coming
in the next post...

_(Here is the full listing.)_

```
using System;

// We use plenty of interlocked operations on volatile fields below.  Safe.

#pragma warning disable 0420

namespace System.Threading
{
    /// <summary>
    /// A very lightweight reader/writer lock.  It uses a single word of memory,
    /// and only spins when contention arises (no events are necessary).

    /// </summary>
    public struct ReaderWriterSpinLock
    {
        private volatile int m_state;
        private const int MASK_WRITER_BIT =
            unchecked((int)0x80000000);
        private const int MASK_WRITER_WAITING_BIT =
            unchecked((int)0x40000000);
        private const int MASK_WRITER_BITS =
            unchecked((int)(MASK_WRITER_BIT | MASK_WRITER_WAITING_BIT));
        private const int MASK_READER_BITS =
            unchecked((int)~MASK_WRITER_BITS);

        public void EnterWriteLock()
        {
            SpinWait sw = new SpinWait();
            do
            {
                // If there are no readers currently, grab the write lock.
                int state = m_state;

                if ((state == 0 || state == MASK_WRITER_WAITING_BIT) &&
                        Interlocked.CompareExchange(
                            ref m_state, MASK_WRITER_BIT, state) == state)
                    return;

                // Otherwise, if the writer waiting bit is unset, set it.  We don't
                // care if we fail -- we'll have to try again the next time around.
                if ((state & MASK_WRITER_WAITING_BIT) == 0)
                    Interlocked.CompareExchange(
                        ref m_state, state | MASK_WRITER_WAITING_BIT, state);

                sw.SpinOnce();
            }
            while (true);
        }

        public void ExitWriteLock()
        {
            // Exiting the write lock is simple: just set the state to 0.  We
            // try to keep the writer waiting bit to prevent readers from getting
            // in -- but don't want to resort to a CAS, so we may lose one.
            Interlocked.Exchange(
                ref m_state, 0 | (m_state & MASK_WRITER_WAITING_BIT));
        }

        public void EnterReadLock()
        {
            SpinWait sw = new SpinWait();
            do
            {
                int state = m_state;
                if ((state & MASK_WRITER_BITS) == 0)
                {
                    if (Interlocked.CompareExchange(
                            ref m_state, state + 1, state) == state)
                        return;
                }

                sw.SpinOnce();
            }
            while (true);
        }

        public void ExitReadLock()
        {
            SpinWait sw = new SpinWait();
            do
            {
                // Validate we hold a read lock.
                int state = m_state;
                if ((state & MASK_READER_BITS) == 0)
                    throw new Exception(
                        "Cannot exit read lock when there are no readers");

                // Try to exit the read lock, preserving the writer waiting
                // bit (if any).
                if (Interlocked.CompareExchange(
                        ref m_state,
                        ((state & MASK_READER_BITS) - 1) | (state & MASK_WRITER_WAITING_BIT),
                        state) == state)
                    return;

                sw.SpinOnce();
            }
            while (true);
        }
    }
}
```

