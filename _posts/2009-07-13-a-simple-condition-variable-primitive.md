---
layout: post
title: A simple condition variable primitive
date: 2009-07-13 21:52:50.000000000 -07:00
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
In this blog post, I'll demonstrate building some very simple (but nice!) synchronization
abstractions: a Lock type and a standalone ConditionVariable class.  And we'll
use a few new types in .NET 4.0 in the process.  I had to implement a condition
variable recently -- the joys of developing a new operating system / platform from
the ground up -- and decided to put together a toy example for a blog post as I went.
Warning: this is for educational purposes only.

Not to sound like a broken record, but it is a very good idea to manage locks intentionally.
Doing so makes synchronization code easier to write, understand, and, correspondingly,
maintain; given the difficult nature of concurrency, any opportunity for simplification
is always welcomed.  Yes, that means avoiding the CLR's dreadful capability
to lock on arbitrary objects.  (Which, by the way, is effectively just a holdover
from the days where .NET was trying to woo developers from Java onto the platform.)
In retrospect, this ability was a bad idea, and we should have provided and embellished
a System.Threading.Lock class from Day One.

Well, rewind the clock and imagine we had provided such a Lock class.  In fact,
here's an overly simple one right here.  I'm going to cheat a little, and reuse
two locks that come with .NET 4.0: Monitor itself, and the new SpinLock class:

```
//#define SPIN_LOCK
public class Lock
{
#if SPIN_LOCK
    private SpinLock m_slock = new SpinLock();
#else
    private object   m_slock = new object();
#endif

    private ThreadLocal<int> m_acquireCount = new ThreadLocal<int>();

    public void Enter() {
#if SPIN_LOCK
        bool ignoreTaken;
        m_slock.Enter(ref ignoreTaken);
#else
        Monitor.Enter(m_slock);
#endif
        m_acquireCount.Value = m_acquireCount.Value + 1;
    }

    public void Exit() {
        m_acquireCount.Value = m_acquireCount.Value - 1;
#if SPIN_LOCK
        m_slock.Exit();
#else
        Monitor.Exit(m_slock);
#endif
    }

    public bool IsHeld {
        get { return m_acquireCount.Value > 0; }
    }

    public int RecursionCount {
        get { return m_acquireCount.Value; }
    }
}
```

Okay, this is not rocket science.  And to be fair, it's missing some critical
features, like reliable acquisition (finally available on Monitor in 4.0, and also
SpinLock), and lock leveling.  But it's a start.

Once we've got such a Lock class, we may want to extend it with 1st class condition
variable support.  Condition variables are core to the monitor concept, and
provide a synchronization point that combines a lock with some condition that may
be waited upon and triggered.  They help to avoid all the pitfalls of standalone
events: mainly missed pulses due to the lack of synchronization involved between
producers and consumers.

Furthermore, imagine we allow multiple separate ConditionVariable objects per single
Lock object.  This is a feature that Monitor doesn't currently support (though
Win32 CONDITION_VARIABLEs do).  This capability would enable us to, say, create
a bounded buffer with a single lock to protect the queue, and two separate condition
variables: one for the non-empty condition, and the other for the non-full condition.
This simplifes the implementation, and helps to avoid deadlock-prone techniques that
result from trying to use multiple separate synchronization objects.

The trick is that the Lock and ConditionVariable class need to be well-integrated.
So we will provide a constructor that accepts a Lock object:

```
public class ConditionVariable
{
    private Lock m_slock;

    public ConditionVariable(Lock slock) {
        if (slock == null)
            throw new ArgumentNullException("slock");
        m_slock = slock;
    }
```

Once we've got that, there are two basic operations to implement: waiting and pulsing
(signaling).  To achieve this, we'll give each thread its own ManualResetEventSlim
object -- a lightweight event class, new to .NET 4.0.  (Ironically, it uses
Monitor.Wait and Pulse under the covers.)  This event will be stored in an
instance of the new .NET 4.0 type, ThreadLocal<T>.  (An alternative is
to store it in a [ThreadStatic], and reuse the same event across all ConditionVariables.
Since we only support waiting on one such condition at a time (currently), there
is no reason we can't just have one per thread.  This is precisely what the
CLR does internally, though it's a shame we can't grab hold of that preexisting event.)
In addition to that, we'll need a wait-list, maintained in FIFO order as a
Queue&lt;ManualResetEventSlim&gt;:

```
    private Queue<ManualResetEventSlim> m_waiters =
        new Queue<ManualResetEventSlim>();
    private ThreadLocal<ManualResetEventSlim> m_waitEvent =
        new ThreadLocal<ManualResetEventSlim>();
```

Waiting does pretty much what you'd imagine.  The m\_slock object doubly acts
as protection against concurrent access to the waiters list.  So when a Wait
call is made, we demand that the lock is held by the calling thread.  Subtly,
we also demand that it hasn't been recursively acquired, since that would require
exiting the lock multiple times.  This can lead to desynchronization bugs.
Unfortunately, Monitor does this, but is critically broken as a result.  Once
the validation occurs, Wait simply places the current thread into the wait list,
exits the lock, waits to be awakened, and then reacquires the lock before returning.
This is pretty much exactly what the CLR Monitor class does internally:

```
    public void Wait() {
        int rcount = m_slock.RecursionCount;
        if (rcount == 0)
            throw new InvalidOperationException("Lock is not held.");
        if (rcount > 1)
            throw new InvalidOperationException("Lock is held recursively.");

        // Lazily initialze our event, if necessary.
        ManualResetEventSlim mres = m_waitEvent.Value;
        if (mres == null) {
            mres = m_waitEvent.Value = new ManualResetEventSlim(false);
        }
        else {
            mres.Reset();
        }

        m_waiters.Enqueue(mres);
        m_slock.Exit();
        mres.Wait(); // bugbug: interrupt => desync.
        m_slock.Enter();
    }
```

Lastly, we must implement the Pulse and PulseAll methods.  For kicks, we'll
provide an overload of Pulse -- which normally awakens one waiting thread -- that
awakens an arbitrary maximum number of threads.  So you could say Pulse(4) to
awaken at most 4 threads, for example.  These methods are even simpler than
Wait: they dequeue events off the wait list, and just set them.  This awakens
the waiters, as desired:

```
    public void Pulse() {
        Pulse(1);
    }

    public void Pulse(int maxPulses) {
        if (!m_slock.IsHeld)
            throw new InvalidOperationException("Lock is not held.");

        for (int i = 0; i < maxPulses; i++) {
            if (m_waiters.Count > 0) {
                m_waiters.Dequeue().Set();
            }
            else {
                break;
            }
        }
    }

    public void PulseAll() {
        Pulse(int.MaxValue);
    }
}
```

(This has the unfortunate side effect of two-step dances.  The pulse will awaken
threads at the mres.Wait() line in Wait, and they immediately try to call m_slock.Enter()
as a result.  A priority boost may cause them to preempt the pulsing thread,
even though they will just end up waiting.  A possible fix to this is to even
more tightly integrate the Lock and ConditionVariable classes, by having a "deferred
pulse" list attached to the lock.  Once it has been completely exited, the Lock's
Exit method could drain the deferred pulse list and awaken the threads, thus avoiding
the two-step dance.)

As to examples, let's take a quick peek at a blocking / bounded queue.  When
constructed, a capacity is given.  Whenever an Enqueue would cause the buffer's
contents to exceed the capacity, the producer is blocked until space is made by a
consumer.  Whenever a Dequeue is attempted on an empty buffer, the consumer
is blocked until an item is produced.  Though there are opportunities for optimization,
this is encoded straightforwardly as follows:

```
class BlockingQueue<T>
{
    private int m_capacity;
    private Queue<T> m_q;
    private Lock m_qLock;
    private ConditionVariable m_qNonFullCondition;
    private ConditionVariable m_qNonEmptyCondition;

    public BlockingQueue(int capacity) {
        m_capacity = capacity;
        m_q = new Queue<T>();
        m_qLock = new Lock();
        m_qNonFullCondition = new ConditionVariable(m_qLock);
        m_qNonEmptyCondition = new ConditionVariable(m_qLock);
    }

    public void Enqueue(T item) {
        m_qLock.Enter();

        while (m_q.Count == m_capacity) {
            m_qNonFullCondition.Wait();
        }

        m_q.Enqueue(item);
        m_qNonEmptyCondition.Pulse();

        m_qLock.Exit();
    }

    public T Dequeue() {
        m_qLock.Enter();

        while (m_q.Count == 0) {
            m_qNonEmptyCondition.Wait();
        }
        T item = m_q.Dequeue();

        m_qNonFullCondition.Pulse();

        m_qLock.Exit();
        return item;
    }
}
```

The naive approach typically uses a single event to signal the non-empty / non-full
transitions.  The risk of doing this, of course, is that the wrong kind of thread
(producer or consumer) will be signaled, depending on chance and wait arrival order.
This is ordinarily only a concern for bounded queues of reasonably small sizes, and
high degrees of concurrency, but is still an interesting example of why multiple
condition variables per lock is useful.

Enjoy!

