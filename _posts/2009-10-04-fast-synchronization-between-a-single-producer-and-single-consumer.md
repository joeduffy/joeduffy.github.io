---
layout: post
title: Fast synchronization between a single producer and single consumer
date: 2009-10-04 18:03:17.000000000 -07:00
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
Commonly two threads must communicate with one another, typically to exchange some
piece of information.  This arises in low-level shared memory synchronization
as in PLINQ's asynchronous data merging, in the implementation of higher level
patterns like message passing, inter-process communication, and in countless
other situations.  If only two agents partake in this arrangement, however,
it is possible to implement a highly efficient exchange protocol.  Although
the situation is rather special, exploiting this opportunity can lead to some interesting
performance benefits.

The standard technique for shared-memory situations is to use a ring buffer.
This buffer is ordinarily an array of fixed length that may become full or empty.
The two threads in this arrangement assume the role of producer and consumer: the
producer adds data to the buffer and may make it full, whereas the consumer removes
data from the buffer and may make it empty.  It is possible to generalize this
to multi-consumers or multi-producers, with some added cost to synchronization.
What is described below is for the two thread case.

We will call this a ProducerConsumerRendezvousBuffer&lt;T&gt;, and its basic structure
looks like this:

```
using System;
using System.Threading;

public class ProducerConsumerRendezvousPoint<T>
{
    private T[] m_buffer;
    private volatile int m_consumerIndex;
    private volatile int m_consumerWaiting;
    private AutoResetEvent m_consumerEvent;
    private volatile int m_producerIndex;
    private volatile int m_producerWaiting;
    private AutoResetEvent m_producerEvent;

    public ProducerConsumerRendezvousPoint(int capacity)
    {

        if (capacity < 2) throw new ArgumentOutOfRangeException("capacity");

        m_buffer = new T[capacity];
        m_consumerEvent = new AutoResetEvent(false);
        m_producerEvent = new AutoResetEvent(false);
    }

    private int Capacity
    {
        get { return m_buffer.Length; }
    }

    private bool IsEmpty
    {
        get { return (m_consumerIndex == m_producerIndex); }
    }

    private bool IsFull
    {
        get { return (((m_producerIndex + 1) % Capacity) == m_consumerIndex); }
    }

    public void Enqueue(T value)
    {
        ...
    }

    public T Dequeue()
    {
        ...
    }
}
```

There are some basic invariants to call out:

- Our buffer holds our elements, producer index says at what position the next element
enqueued will be stored, and the consumer index says from what position the next
request to dequeue an element will retrieve its value.

- We reserve one element in our buffer to differentiate between fullness and emptiness.
This is why we demand that capacity be >= 2.  We could alternatively know how
to distinguish between a free slot and a used one, such as checking for null, but
keep things simple for now.

- Thus, IsEmpty is true when the consumer and producer index are the same.
Whereas IsFull is true when the consumer is one ahead of the producer, such that
producing would make the producer index collide with the consumer index (otherwise
leading to IsEmpty).

- It should be obvious that our intent is to block consumption when IsEmpty == true
and production when IsFull == true.  This is the point of the waiting flags
and events.

Now let us look at the implementation first of Enqueue and then Dequeue, paying special
attention to the necessary synchronization operations.  They look nearly identical:

```
    public void Enqueue(T value)
    {
        if (IsFull) {
            WaitUntilNonFull();
        }

        m_buffer[m_producerIndex] = value;

        Interlocked.Exchange(
            ref m_producerIndex, (m_producerIndex + 1) % Capacity);

        if (m_consumerWaiting == 1) {
            m_consumerEvent.Set();
        }
    }
```

Enqueue begins, as expected, by checking whether the queue is full.  Notice
that we have not yet issued any memory fences yet.  The only thread that may
make the buffer full is the current one, which will obviously not occur before proceeding,
and therefore we needn't perform any expensive synchronization operation for this
check.  The value seen may of course be stale but we can deal with that possibility
inside the slow path, WaitUntilNonFull.  We'll look at that momentarily.

We then proceed to placing the value in the buffer at the current producer's index.
Only the current thread will update the producer index and a consumer will not read
from the current value so long as the producer index refers to it.  The value
may not even be written atomically, e.g. for T's that are greater than a pointer
sized word.  This is okay: only the act of incrementing the index allows a consumer
to access the element in question.  Writes on the CLR 2.0 memory model are retired
in order and the reading side will use an acquire load of the index before accessing
the element's words.  Indeed we could use complicated multipart value types
that are comprised of lengthy buffers, header words, and so on.

We then increment the producer index, handling the possibility of wrap-around by
modding with the capacity.  This uses an Interlocked.Exchange for one simple
reason: we are about to read a consumer waiting flag, and must prevent the load of
that flag from moving prior to the producer index write.  The consumer sets
this flag when it notices the queue is empty and waits.  This enables us to
use a "Dekker style" check to minimize synchronization.  We could have alternatively
just unconditionally set the event, doing away with the interlocked operation altogether.
But that call, if it involves kernel transitions, which is quite likely, is going
to be much more expensive and would occur on every call to Enqueue.  And any
event of this kind that doesn't require kernel transitions is going to at least
require an interlocked operation for the same reason we require one here.  An
alternative technique involves setting when we transition the buffer from empty to
non-empty or full to non-full, but this wastes a possibly expensive signal if the
other party isn't even currently waiting.  If full or empty is a rare situation,
then full or empty and with a peer actually physically waiting is even rarer.

Let's now look at the WaitUntilNonFull method.  It's really the reverse
of what the consumer does, so based on everything said till this point, I am guessing
it's obvious:

```
    private void WaitUntilNonFull()
    {
        Interlocked.Exchange(ref m_producerWaiting, 1);

        try {
            while (IsFull) {
                m_producerEvent.WaitOne();
            }
        }
        finally {
            m_producerWaiting = 0;
        }
    }
```

We begin by issuing a memory fence and setting the producer waiting flag.  This
memory fence is necessary to advertise that we are about to wait, and also to ensure
the subsequent check of IsFull is synchronized.  The consumer does something
very much like the producer does (above) after taking an element: if the producer
is waiting, the consumer has made space for it and therefore must signal.  But
it could be the case that the consumer has already made the queue non-full before
it could notice the producer's waiting flag.  We catch this by ensuring the
producer's check of IsFull cannot go before setting the producer waiting; similarly,
the consumer cannot make IsFull false without subsequently noticing that the producer
is waiting; this avoids deadlock.

Everything else is self explanatory.  Well, almost.  We need a loop here
to catch one subtle situation.  Imagine a producer enters into this method thinking
the buffer is full.  It sets its flag, and then immediately notices that the
buffer is not full anymore.  A consumer has generated a new item of interest.
But imagine that consumer noticed that the producer was waiting and hence set its
event.  This is an auto-reset event, so the next time the producer must wait,
the event will have already been set and it'll likely wake up before IsFull has
become true.  An alternative way of dealing with this is to call Reset on the
event if we didn't actually wait on the event, but again we keep things simple.

At this point, the consumer side is going to look very familiar:

```
    public T Dequeue()
    {
        if (IsEmpty) {
            WaitUntilNonEmpty();
        }

        T value = m_buffer[m_consumerIndex];
        m_buffer[m_consumerIndex] = default(T);

        Interlocked.Exchange(
            ref m_consumerIndex, (m_consumerIndex + 1) % Capacity);

        if (m_producerWaiting == 1) {
            m_producerEvent.Set();
        }

        return value;
    }

    private void WaitUntilNonEmpty() {
        Interlocked.Exchange(ref m_consumerWaiting, 1);

        try {
            while (IsEmpty) {
                m_consumerEvent.WaitOne();
            }
        }
        finally {
            m_consumerWaiting = 0;
        }
    }
```

This is near-identical to Enqueue and WaitUntilNonFull, and so needs little explanation.
The acquire load inside IsEmpty of the producer index ensures that we observe the
producer index for this particular value being beyond the current consumer's index
before loading the value itself, thereby ensuring we see the whole set of written
words.  The one other thing to point out is that we "null out" the element
consumed which, for large buffers, helps to avoid space leaks that would have otherwise
been possible.

There are certainly some opportunities for improving this.

For example, we might add a little bit of spinning in the wait cases.  This
would be worthwhile for cases that exchange data at very fast rates and have small
buffers, meaning that the chance of hitting empty and full conditions is quite high.
Avoiding the context switch thrashing is likely to lead to hotter caches, because
threads will remain runnable for longer, and the raw costs of switching themselves.

Additionally, we technically could use a single event if we wanted to spend the effort.
We'd have to handle a few tricky cases, however: namely, the case where a producer
or consumer ends up waiting on an event because it "just missed" the event of
interest, thus satisfying the event.  Indeed both threads could actually end
up waiting on the event simultaneously and we need to somehow ensure the right one
eventually gets awakened.  This leads to some chatter and probably isn't worth
the added complexity.

Here is a peek at some rough numbers from a little benchmark that has two threads
enqueuing and dequeuing elements as fast as humanly (or computerly) possible.
This is a particularly unique and unlikely situation, but stresses the implementation
in a few interesting ways.  In particular, it will stress the contentious slow
paths; although these are expected to be rarer, the fast paths are just so easy to
get right in this data structure that they are mostly uninteresting to stress performance-wise.
There are then a few variants, each based on the original version shown above:

- 2 element capacity, which means we'll be transitioning from empty to full and
back a lot.

- 1024 element capacity, which means we won't.

- With spinning, using .NET 4.0's new System.Threading.SpinWait type.

- An implementation that overuses interlocked operations as many naïve programmers
would do.

The 2 element capacity situation is common in some message passing systems, e.g.
Ada rendezvous, Comega joins, and the like.  Whereas the 1,024 element capacity
situation is common for more general purpose channels, where some amount of pipelining
is anticipated.

I whipped together a benchmark -- so quickly that we can barely trust it, I might
add -- to measure these things.  Here's a small table, showing the observed
relative costs:

```
                2 capacity      1024 capacity
                --------------- ---------------
As-is  No-spin  100.00%         1.93%
       Spin     56.41%          1.66%

Naiive No-spin  101.20%         2.09%
       Spin     67.73%          1.87%
```

As with most microbenchmarks, take the results with a grain of salt.  And there
are certainly more interesting variants to compare this against, including a monitor-based implementation
that locks around access to the buffer itself.  Nevertheless, we can draw a
few conclusions from this: as expected, the version that uses a single interlocked
on enqueue and single interlocked on dequeue is faster than the naïve version that
uses multiple (surprise!); spinning makes a much more interesting difference on the
2 element capacity situation, as expected, because it reduces the number of context
switches dramatically; and, finally, the larger capacity enables a producer to race
ahead of the consumer, hence avoiding far fewer transitions from full to empty to
full and so forth.

This post was more of a case study than anything else.  There is nothing conclusive
or groundbreaking here, and I suppose I should have said that would be the case up
front.  That said, I've seen this technique used in over a dozen situations
in actual product code now, so I figured I'd write a little about it, with a focus
on how to minimize the synchronization operations.  We even contemplated shipping
such a type in Parallel Extensions to .NET, but it's just too darn specialized
to warrant it.  So the closest thing we provided is BlockingCollection&lt;T&gt;.
Enjoy.

