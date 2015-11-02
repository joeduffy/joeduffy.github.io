---
layout: post
title: 'Building a custom thread pool (series, part 2): a work stealing queue'
date: 2008-08-11 19:53:28.000000000 -07:00
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
The primary reason a traditional thread pool doesn't scale is that there's a
single work queue protected by a global lock.  For obvious reasons, this can
easily become a bottleneck.  Two primary things contribute heavily to whether
the global lock becomes a limiting factor for a particular workload's throughput:

1. As the size of work items become smaller, the frequency at which the pool's
threads must acquire the global lock increases.  Moving forward, we expect the
granularity of latent parallelism to become smaller such that programs can scale
as more processors are added.

2. As more processors are added, the arrival rate at the lock will increase when
compared to the same workload run with fewer processors.  This inherently limits
the ability to "get more work through" that single straw that is the global queue.

For coarse-grained work items, and for small numbers of processors, these problems
simply aren't too great.  That has been the CLR ThreadPool's forte for quite
some time; most work items range in the 1,000s to 10,000s (or more) of CPU cycles,
and 8-processors was considered pushing the limits.  Clearly the direction the
whole industry is headed in exposes these fundamental flaws very quickly.  We'd
like to enable work items with 100s and 1,000s of cycles and must scale well beyond
4, 8, 16, 32, 64, ... processors.

Decentralized scheduling techniques can be used to combat this problem.  In
other words, if we give different components their own work queues, we can eliminate
the central bottleneck.  This approach works to a degree but becomes complicated
very quickly because clearly we don't want each such queue to have its own pool
of dedicated threads.  So we'd need some way of multiplexing a very dynamic
and comparatively large number of work pools onto a mostly-fixed and comparatively
small number of OS threads.

**Introducing work stealing**

Another technique -- and the main subject of this blog post -- is to use a so-called
work stealing queue (WSQ).  A WSQ is a special kind of queue in that it has
two ends, and allows lock-free pushes and pops from one end ("private"), but
requires synchronization from the other end ("public").  When the queue
is sufficiently small that private and public operations could conflict, synchronization
is necessary.  It is array-based and can grow dynamically.  This data structure
was made famous in the 90's when much work on dynamic work scheduling was done
in the research community.

In the context of a thread pool, the WSQ can augment the traditional global queue
to enable more efficient private queuing and dequeuing.  It works roughly as
follows:

- We still have a global queue protected by a global lock.

- (We can of course consider the ability to have separate pools to reduce pressure
on this.)

- Each thread in the pool has its own private WSQ.

- When work is queued from a pool thread, the work goes into the WSQ, avoiding all
locking.

- When work is queued from a non-pool thread, it goes into the global queue.

- When threads are looking for work, they can have a preferred search order:

    - Check the local WSQ.  Work here can be dequeued without locks.

    - Check the global queue.  Work here must be dequeued using locks.

    - Check other threads' WSQs.  This is called "stealing", and requires locks.

If you haven't guessed, this is by-and-large how the Task Parallel Library (TPL)
schedules work.

For workloads that recursively queue a lot of work, the use of a per-thread WSQ substantially
reduces the synchronization necessary to complete the work, leading to far better
throughput.  There are also fewer cache effects due to sharing of the global
queue information.  "Stealing" is our last course of action in the abovementioned
search logic, because it has the secondary effect of causing another thread to have
to visit the global queue (or steal) sooner.  In some sense, it is double the
cost of merely getting an item from the global queue.

Another (subtle) aspect of WSQs is that they are LIFO for private operations and
FIFO for steals.  This is inherent in how the WSQ's synchronization works
(and is key to enabling lock-freedom), but has additional rationale:

1. By executing the work most recently pushed into the queue in LIFO order, chances
are that memory associated with it will still be hot in the cache.

2. By stealing in FIFO order, chances are that a larger "chunk" of work will
be stolen (possibly reducing the chance of needing additional steals).  The
reason for this is that many work stealing workloads are divide-and-conquer in nature;
in such cases, the recursion forms a tree, and the oldest items in the queue lie
closer to the root; hence, stealing one of those implicitly also steals a (potentially)
large subtree of computations that will unfold once that piece of work is stolen
and run.

This decision clearly changes the regular order of execution when compared to a mostly-FIFO
system, and is the reason we're [contemplating exposing options](http://blogs.msdn.com/pfxteam/archive/2008/08/01/8800195.aspx)
to control this behavior from TPL.

**A simple WorkStealingQueue&lt;T&gt; type**

With all that background behind us, let's jump straight into a really simple implementation
of a work stealing queue written in C#.

```
public class WorkStealingQueue<T>
{
```

The queue is array-based, and we keep two indexes: a head and a tail.  The
tail represents the private end and the head represents the public end.  We
also maintain a mask that is always equal to the size of the list minus one, helping
with some of the bounds-checking arithmetic and handling automatic wraparound for
indexing into the array.  Because of the way we use the mask (we will assume
all legal bits for indexing into the list are on), the count must always be a power
of two.  We arbitrarily select the number 32 as the queues initial (power of
two) size.

```
    private const int INITIAL_SIZE = 32;
    private T[] m_array = new T[INITIAL_SIZE];
    private int m_mask = INITIAL_SIZE - 1;
    private volatile int m_headIndex = 0;
    private volatile int m_tailIndex = 0;
```

We also need a lock to protect the operations that require synchronization.

```
    private object m_foreignLock = new object();
```

Although they aren't exercised very much in the code, we have some helper properties.
The queue is empty when the head is equal to or greater than the tail, and the count
can be computed by subtracting the head from the tail.  Because these fields
never wrap (because we use the mask), this is correct.

```
    public bool IsEmpty
    {
        get { return m_headIndex >= m_tailIndex; }
    }

    public int Count
    {
        get { return m_tailIndex - m_headIndex; }
    }
```

OK, let's get into the meat of the implementation.  Pushing is the obvious
place to start, and, for obvious reasons, we only support private pushes.  Public
pushes are useless given the protocol explained above, i.e., the only public operation
we will support is stealing.  Keep in mind when reading this code that m\_tailIndex
and m\_headIndex are both volatile variables.

```
    public void LocalPush(T obj)
    {
        int tail = m_tailIndex;
```

First we must check whether there is room in the queue.  To do so, we just see
if m\_tailIndex is less than the sum of m\_mask (the size of the list minus one)
and m\_headIndex.  False negatives are OK, and are certainly possible because
a concurrent steal may come along and take an element, making room, immediately after
the check.  We will handle this by synchronizing in a moment.

```
        if (tail < m_headIndex + m_mask) {
```

If there is indeed room, we can merely stick the object into the array (masking m\_tailIndex
with m\_mask to ensure we're within the legal range) and then increment m\_tailIndex
by one.  This may look unsafe, but it is in fact safe: writes retire in order
in .NET's memory model, and we know no other thread is changing m\_tailIndex (only
private operations write to it) and that no thread will try to access the current
array slot into which we're storing the element.

```
            m_array[tail & m_mask] = obj;
            m_tailIndex = tail + 1;
        }
```

Otherwise, we need to head down the slow path which involves resizing.

```
        else
        {
```

We will take the lock and check that we still need to make room.

```
            lock (m_foreignLock)
            {
                int head = m_headIndex;
                int count = m_tailIndex - m_headIndex;
                if (count >= m\_mask) {
```

Assuming we need to make more room, we will just double the size of the array, copy
elements, fix up the fields, and move on.  Remember that the array length is
always a power of two, so we can get the next power of two by simply bitshifting
to the left by one.  We do that for the mask too, but need to remember to "turn
on" the least significant bit by oring one into the mask.

```
                    T[] newArray = new T[m_array.Length << 1];
                    for (int i = 0; i < m_array.Length; i++) {
                        newArray[i] = m_array[(i + head) & m_mask];
                    }
                    m_array = newArray;

                    // Reset the field values, incl. the mask.
                    m_headIndex = 0;
                    m_tailIndex = tail = count;
                    m_mask = (m_mask << 1) | 1;
```

After we're done resizing, the m\_headIndex is reset to 0, and the m\_tailIndex
is the previous size of the queue.  We can then store into the queue in same
way we would have earlier.

```
                }

                m_array[tail & m_mask] = obj;
                m_tailIndex = tail + 1;
            }
        }
    }
```

And that's that: we've added an item into the queue with a local push.
Now let's look at the reverse: removing an element with a local pop.  Remember,
it's impossible for a local push and pop to interleave with one another because
they must be executed by the same thread serially.

```
    public bool LocalPop(ref T obj)
    {
```

First we read the current value of m\_tailIndex.  If the queue is currently
empty, i.e., m\_headIndex >= m\_tailIndex, then we just return false right away.
This is how "emptiness" is conveyed to callers.

```
        int tail = m_tailIndex;
        if (m_headIndex >= tail) {
            return false;
        }
```

Now we have determined there is at least one element in the queue (or was during
our previous check).  We will now subtract one from the tail, which effectively
removes the element.  There is still a chance that we will "lose" in a race
with another thread doing a steal, so we'll need to be very careful.  In fact,
there is a subtle .NET memory model gotcha to be aware of: we must guarantee our
write to take the element does not get trapped in the write buffer beyond a subsequent
read of the m\_headIndex.  If that could happen, we might mistakenly think we
took the element, while at the same time a stealing thread thought it took the same
element!  The result would be that the same item will be dequeued by two threads
which could lead to disaster.  In a thread pool, it'd amount to the same work
item being run twice.  To ensure this reordering can't happen, we must use
a XCHG to perform the write to m\_tailIndex.

```
        tail -= 1;
        Interlocked.Exchange(ref m_tailIndex, tail);
```

We detect whether we lost the race by checking to see if our dequeuing of the element
has made the queue empty.  If it hasn't, we can just read the array element
in the new m\_tailIndex position and return it.

```
        if (m_headIndex <= tail) {
            obj = m_array[tail & m_mask];
            return true;
        }
        else {
```

Otherwise, we take the lock and see what to do.  This blocks out all steals.
Either we will find that there indeed is an element remaining, and we can just return
it as we would have done above, or we must "put the element back" by just incrementing
the m\_tailIndex.  If we have to back out our modification, we just return false
to indicate that the queue has become empty.  We know we aren't racing with
it becoming non-empty because only private pushes are supported.

```
            lock (m_foreignLock) {
                if (m_headIndex <= tail) {
                    // Element still available. Take it.
                    obj = m_array[tail & m_mask];
                    return true;
                }
                else {
                    // We lost the race, element was stolen, restore the tail.
                    m_tailIndex = tail + 1;
                    return false;
                }
            }
        }
    }
```

Lastly, let's take a look at the public pop capability.  We allow a timeout
to be supplied, because it's often useful during the stealing logic to use a 0-timeout
on the first pass through all the WSQs.  This can help to eliminate lock wait
times and more evenly distribute contention across the list of WSQs.

```
    private bool TrySteal(ref T obj, int millisecondsTimeout)
    {
```

First we acquire the WSQ's lock, ensuring mutual exclusion among all other concurrent
steals, resize operations, and local pops that may make the queue empty.

```
        bool taken = false;
        try {
            taken = Monitor.TryEnter(m_foreignLock, millisecondsTimeout);
            if (taken) {
```

Once inside the lock, we must increment m\_headIndex by one.  This moves the
head towards the tail, and has the effect of taking an element.  Now this part
gets quite tricky.  We must ensure that we don't remove the last element when
racing with a local pop that went down its fast path (i.e., it didn't acquire the
lock).  Given two threads racing to take an element—a steal and a local pop—we
must ensure precisely one of them "wins".  Having both succeed will lead
to the same element being popped twice, and having neither succeed could lead to
reporting back an empty queue when in fact an element exists.

To do that, we will write to the m\_headIndex variable to tentatively take the element,
and must then read the m\_tailIndex right afterward to ensure that the queue is still
non-empty.  As with the pop logic earlier, we need to use an XCHG operation
to write the m\_headIndex field, otherwise we will potentially suffer from a similar
legal memory reordering bug.

```
                int head = m_headIndex;
                Interlocked.Exchange(ref m_headIndex, head + 1);
```

If the queue is non-empty, we just read the element as we usually do: by indexing
into the array with the new m\_headIndex value using the proper masking.  We
then return true to indicate an element was found.

```
                if (head < m_tailIndex) {
                    obj = m_array[head & m_mask];
                    return true;
                }
```

Otherwise, the queue is empty and we must return.  Clearly this is racy and
by the time we return the queue may be non-empty.  If the pool will subsequently
wait for work to arrive, this must be taken into consideration so as not to incur
lost wake-ups.

```
                else {
                    m_headIndex = head;
                    return false;
                }
            }
        }
```

We of course need to release the lock at the end of it all.

```
        finally {
            if (taken) {
                Monitor.Exit(m_foreignLock);
            }
        }

        return false;
    }
}
```

And that's it!  As with most lock-free algorithms, the core idea is surprisingly
simple but deceptively subtle and intricate.  After seeing it written out and
explained in detail, I hope that you'll have that "Ah hah!" moment that
always happens after staring at this kind of code for a little while.  In future
posts, we'll take a closer look at the performance differences between this and
a traditional globally synchronized queue, and discuss what it takes to merge the
two ideas implementation-wise.

**Appendix**

For reference, here's the full code without all the explanation intertwined:

```
using System;
using System.Threading;

public class WorkStealingQueue<T>
{
    private const int INITIAL_SIZE = 32;
    private T[] m_array = new T[INITIAL_SIZE];
    private int m_mask = INITIAL_SIZE - 1;
    private volatile int m_headIndex = 0;
    private volatile int m_tailIndex = 0;
    private object m_foreignLock = new object();

    public bool IsEmpty
    {
        get { return m_headIndex >= m_tailIndex; }
    }

    public int Count
    {
        get { return m_tailIndex - m_headIndex; }
    }

    public void LocalPush(T obj)
    {
        int tail = m_tailIndex;
        if (tail < m_headIndex + m_mask) {
            m_array[tail & m_mask] = obj;
            m_tailIndex = tail + 1;
        }
        else {
            lock (m_foreignLock) {
                int head = m_headIndex;
                int count = m_tailIndex - m_headIndex;
                if (count >= m_mask) {
                    T[] newArray = new T[m_array.Length << 1];
                    for (int i = 0; i < m_array.Length; i++) {
                        newArray[i] = m_array[(i + head) & m_mask];
                    }
                    m_array = newArray;

                    // Reset the field values, incl. the mask.
                    m_headIndex = 0;
                    m_tailIndex = tail = count;
                    m_mask = (m_mask << 1) | 1;
                }

                m_array[tail & m_mask] = obj;
                m_tailIndex = tail + 1;
            }
        }
    }

    public bool LocalPop(ref T obj)
    {
        int tail = m_tailIndex;
        if (m_headIndex >= tail) {
            return false;
        }

        tail -= 1;
        Interlocked.Exchange(ref m_tailIndex, tail);

        if (m_headIndex <= tail) {
            obj = m_array[tail & m_mask];
            return true;
        }
        else {
            lock (m_foreignLock) {
                if (m_headIndex <= tail) {
                    // Element still available. Take it.
                    obj = m_array[tail & m_mask];
                    return true;
                }
                else {
                    // We lost the race, element was stolen, restore the tail.
                    m_tailIndex = tail + 1;
                    return false;
                }
            }
        }
    }

    private bool TrySteal(ref T obj, int millisecondsTimeout)
    {
        bool taken = false;
        try {
            taken = Monitor.TryEnter(m_foreignLock, millisecondsTimeout);
            if (taken) {
                int head = m_headIndex;
                Interlocked.Exchange(ref m_headIndex, head + 1);

                if (head < m_tailIndex) {
                    obj = m_array[head & m_mask];
                    return true;
                }
                else {
                    m_headIndex = head;
                    return false;
                }
            }
        }
        finally {
            if (taken) {
                Monitor.Exit(m_foreignLock);
            }
        }

        return false;
    }
}
```

