---
layout: post
title: 'Building a custom thread pool (series, part 3): incorporating work stealing
  queues'
date: 2008-09-17 01:51:42.000000000 -07:00
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
In [part 2 of this series](http://www.bluebytesoftware.com/blog/2008/08/12/BuildingACustomThreadPoolSeriesPart2AWorkStealingQueue.aspx),
I described a new work stealing queue data structure used for work item management.
This structure allows us to push and pop elements into a thread-local work queue
without heavy-handed synchronization.  Moreover, this distributed a large amount
of the scheduling responsibility across the threads (and hence processors).
The result is that, for recursively queued work items, scalability is improved and
pressure on the typical bottleneck in a thread pool (i.e., the global lock) is alleviated.

What we didn't do last time was actually integrate the new queue into the thread
pool that was shown in [part 1](http://www.bluebytesoftware.com/blog/2008/07/29/BuildingACustomThreadPoolSeriesPart1.aspx).
This extension is actually somewhat simple.  We'll continue to use the IThreadPool
interface so that we can easily harness and benchmark the various thread pool implementations
against each other.

We'll add a new class LockAndWsqThreadPool, which mimics the design of the original
SimpleLockThreadPool class.  We'll only need to add two fields to it:

- private WorkStealingQueue&lt;WorkItem&gt;[] m\_wsQueues: This is an array of queues -- one
per thread in the pool -- that will be used to store recursively queued work.

- [ThreadStatic] private static WorkStealingQueue&lt;WorkItem&gt; m\_wsq: This represents
the unique work stealing queue for a particular thread in the pool.

OK, so with these extensions there are clearly three specific changes we need to
make:

1. A new thread pool thread needs to allocate its work stealing queue.

2. When queuing a new work item, we must check to see if we're on a pool thread.
If so, we will queue the work item into the work stealing queue instead of the global
queue.

3. When a pool thread looks for work, it needs to:

- First consult its local work stealing queue.

- If that fails, it then looks at the global queue.

- Lastly, if that fails, it needs to steal from other work stealing queues.

Let's review each one individually.  Later we'll see the full code.

\#1 is handled in the DispatchLoop function:

```
private WorkStealingQueue<WorkItem>[] m_wsQueues =
    new WorkStealingQueue<WorkItem>[Environment.ProcessorCount];

private void DispatchLoop()
{
    // Register a new WSQ.
    WorkStealingQueue<WorkItem> wsq = new WorkStealingQueue<WorkItem>();
    m_wsq = wsq; // Store in TLS.
    AddWsq(wsq);

    try {
         /* a whole bunch of stuff ... */
    }
    finally {
        Remove(wsq);
    }
}

private void AddWsq(WorkStealingQueue<WorkItem> wsq)
{
    lock (m_wsQueues) {
        for (int i = 0; i < m_wsQueues.Length; i++) {
            if (m_wsQueues[i] == null) {
                m_wsQueues[i] = wsq;
            }
            else if (i == m_wsQueues.Length - 1) {
                WorkStealingQueue<WorkItem>[] queues =
                    new WorkStealingQueue<WorkItem>[m_wsQueues.Length*2];
                Array.Copy(m_wsQueues, queues, i+1);
                queues[i+1] = wsq;
                m_wsQueues = queues;
            }
        }
    }
}

private void RemoveWsq(WorkStealingQueue<WorkItem> wsq)
{
    lock (m_wsQueues) {
        for (int i = 0; i < m_wsQueues.Length; i++) {
            if (m_wsQueues[i] == wsq) {
                m_wsQueues[i] = null;
            }
        }
    }
}
```

\#2, of course, happens within the QueueUserWorkItem function:

```
public void QueueUserWorkItem(WaitCallback work, object obj)
{
    WorkItem wi = ...;
    /* as before ... */

    // Now insert the work item into the queue, possibly waking a thread.
    WorkStealingQueue<WorkItem> wsq = m_wsq;
    if (wsq != null) {
        // Single TLS to determine if we're on a pool thread.
        wsq.LocalPush(wi);
        if (m_threadsWaiting > 0) { // OK to read lock-free.
            lock (m_queue) {
                Monitor.Pulse(m_queue);
            }
        }
    }
    else {
        /* as before: queue to the global queue */
    }
}
```

Lastly, #3 is the most complicated.  Searching the local queue is done with
a call to wsq.LocalPop.  If that fails, the work stealing queue is empty, and
the logic then looks a lot like the original thread pool's dispatch loop logic
in that we then look for work in the global queue.  If that fails, we will just
iterate over the other threads' work stealing queues, doing a TrySteal operation.
If none of them had work, we go back the global queue, try again, and then finally
wait for work to arrive.  (See the full code sample below for details.)
Notice that there's a fairly tricky race condition here that we're leaving unhandled:
if we search for work, try to steal, and ultimately find no work, we will then embark
on a trip back to the global queue; during this trip, another pool thread might recursively
queue work into its work stealing queue and we will miss it.  Generally speaking,
this is OK because that thread will eventually get to it (presumably) but with some
clever synchronization trickery we can actually handle this case.  Perhaps I
will show such a solution in a subsequent part in this series.

Anyway, what we're left with is code that looks something like this:

```
public class LockAndWsqThreadPool : IThreadPool
{
    // Constructors--
    // Two things may be specified:
    //   ConcurrencyLevel == fixed # of threads to use
    //   FlowExecutionContext == whether to flow ExecutionContexts for work items
    public LockAndWsqThreadPool() :
        this(Environment.ProcessorCount, true) { }
    public LockAndWsqThreadPool(int concurrencyLevel) :
        this(concurrencyLevel, true) { }
    public LockAndWsqThreadPool(bool flowExecutionContext) :
        this(Environment.ProcessorCount, flowExecutionContext) { }

    public LockAndWsqThreadPool(int concurrencyLevel, bool flowExecutionContext)
    {
        if (concurrencyLevel <= 0)
            throw new ArgumentOutOfRangeException("concurrencyLevel");

        m_concurrencyLevel = concurrencyLevel;
        m_flowExecutionContext = flowExecutionContext;

        // If suppressing flow, we need to demand permissions.
        if (!flowExecutionContext)
            new SecurityPermission(SecurityPermissionFlag.Infrastructure).Demand();
    }

    // Each work item consists of a closure: work + (optional) state obj + context.
    struct WorkItem
    {
        internal WaitCallback m_work;
        internal object m_obj;
        internal ExecutionContext m_executionContext;

        internal WorkItem(WaitCallback work, object obj)
        {
            m_work = work;
            m_obj = obj;
            m_executionContext = null;
        }

        internal void Invoke()
        {
            // Run normally (delegate invoke) or under context, as appropriate.
            if (m_executionContext == null)
                m_work(m_obj);
            else
                ExecutionContext.Run(m_executionContext, s_contextInvoke, this);
        }

        private static ContextCallback s_contextInvoke = delegate(object obj) {
            WorkItem wi = (WorkItem)obj;
            wi.m_work(wi.m_obj);
        };
    }

    private readonly int m_concurrencyLevel;
    private readonly bool m_flowExecutionContext;
    private readonly System.Collections.Queue m_queue = new System.Collections.Queue();

    private WorkStealingQueue<WorkItem>[] m_wsQueues =
        new WorkStealingQueue<WorkItem>[Environment.ProcessorCount];

    private Thread[] m_threads;
    private int m_threadsWaiting;
    private bool m_shutdown;

    [ThreadStatic]
    private static WorkStealingQueue<WorkItem> m_wsq;

    // Methods to queue work.
    public void QueueUserWorkItem(WaitCallback work)
    {
        QueueUserWorkItem(work, null);
    }

    public void QueueUserWorkItem(WaitCallback work, object obj)
    {
        WorkItem wi = new WorkItem(work, obj);

        // If execution context flowing is on, capture the caller's context.
        if (m_flowExecutionContext)
            wi.m_executionContext = ExecutionContext.Capture();

        // Make sure the pool is started (threads created, etc).
        EnsureStarted();

        // Now insert the work item into the queue, possibly waking a thread.
        WorkStealingQueue<WorkItem> wsq = m_wsq;

        if (wsq != null) {
            // Single TLS to determine if we're on a pool thread.
            wsq.LocalPush(wi);

            if (m_threadsWaiting > 0) // OK to read lock-free.
                lock (m_queue) { Monitor.Pulse(m_queue); }
        }
        else {
            lock (m_queue) {
                m_queue.Enqueue(wi);
                if (m_threadsWaiting > 0)
                    Monitor.Pulse(m_queue);
            }
        }
    }

    // Ensures tha threads have begun executing.
    private void EnsureStarted()
    {
        if (m_threads == null) {
            lock (m_queue) {
                if (m_threads == null) {
                    m_threads = new Thread[m_concurrencyLevel];
                    for (int i = 0; i < m_threads.Length; i++) {
                        m_threads[i] = new Thread(DispatchLoop);
                        m_threads[i].Start();
                    }
                }
            }
        }
    }

    private void AddWsq(WorkStealingQueue<WorkItemwsq)
    {
        lock (m_wsQueues) {
            for (int i = 0; i < m_wsQueues.Length; i++) {
                if (m_wsQueues[i] == null) {
                    m_wsQueues[i] = wsq;
                }
                else if (i == m_wsQueues.Length - 1) {
                    WorkStealingQueue<WorkItem>[] queues =
                        new WorkStealingQueue<WorkItem>[m_wsQueues.Length*2];
                    Array.Copy(m_wsQueues, queues, i+1);
                    queues[i+1] = wsq;
                    m_wsQueues = queues;
                }
            }
        }
    }

    private void RemoveWsq(WorkStealingQueue<WorkItemwsq)
    {
        lock (m_wsQueues) {
            for (int i = 0; i < m_wsQueues.Length; i++) {
                if (m_wsQueues[i] == wsq) {
                    m_wsQueues[i] = null;
                }
            }
        }
    }

    // Each thread runs the dispatch loop.
    private void DispatchLoop()
    {
        // Register a new WSQ.
        WorkStealingQueue<WorkItemwsq = new WorkStealingQueue<WorkItem>();
        m_wsq = wsq; // Store in TLS.
        AddWsq(wsq);

        try {
            while (true) {
                WorkItem wi = default(WorkItem);

                // Search order: (1) local WSQ, (2) global Q, (3) steals.
                if (!wsq.LocalPop(ref wi)) {
                    bool searchedForSteals = false;
                    while (true) {
                        lock (m_queue) {
                            // If shutdown was requested, exit the thread.
                            if (m_shutdown)
                                return;

                            // (2) try the global queue.
                            if (m_queue.Count != 0) {
                                // We found a work item! Grab it ...
                                wi = (WorkItem)m_queue.Dequeue();
                                break;
                            }
                            else if (searchedForSteals) {
                                m_threadsWaiting++;
                                try { Monitor.Wait(m_queue); }
                                finally { m_threadsWaiting--; }
                            }

                            // If we were signaled due to shutdown, exit the thread.
                            if (m_shutdown)
                                return;

                            searchedForSteals = false;
                            continue;
                        }
                    }

                    // (3) try to steal.
                    WorkStealingQueue<WorkItem>[] wsQueues = m_wsQueues;
                    int i;
                    for (i = 0; i < wsQueues.Length; i++) {
                        if (wsQueues[i] != wsq && wsQueues[i].TrySteal(ref wi))
                            break;
                    }

                    if (i != wsQueues.Length)
                        break;

                    searchedForSteals = true;
                }

                // ...and Invoke it. Note: exceptions will go unhandled (and crash).
                wi.Invoke();
            }
        }
        finally {
            RemoveWsq(wsq);
        }
    }

    // Disposing will signal shutdown, and then wait for all threads to finish.
    public void Dispose()
    {
        m_shutdown = true;
        if (m_queue != null) {
            lock (m_queue) {
                Monitor.PulseAll(m_queue);
            }

            for (int i = 0; i < m_threads.Length; i++)
                m_threads[i].Join();
        }
    }
}
```

I have a little harness that measures the throughput of the different thread pool
implementations for varying degrees of recursively queued work.  I'll share
this out too in a subsequent part in this series, once we have a few more variants
to pit against each other.  Anyway, as you'd imagine, there is very little
difference between LockAndWsqThreadPool and SimpleLockThreadPool when all work is
queued from external (non-pool) threads.  However, when I queue 10,000 items
externally and, from each of those, queue 100 items recursively, I see a 3X throughput
improvement on my four core machine.  When I queue 100 items externally and,
from each of those, queue 10,000 items recursively, the improvement is more than
8X.  And so on.  As the number of cores increases, the improvement only
becomes greater.

Another aspect not shown—because of the very limited QueueUserWorkItem-style API
we're building on—is something called "wait inlining."  We do this in
TPL.  When you recursively queue work items in a divide-and-conquer kind of
problem, there's often more latent parallelism than will be realized.  Instead
of requiring all of that parallelism to consume a thread, and blocking each time
a work item is waited on, we can run work items inline if they haven't started
yet.

One easy way to do this is to limit inlining to only threads that do so from their
own local work stealing queue.  Because we are guaranteed the local pop/push
methods won't interleave with such inlines, we can just acquire the stealing lock
and search the list for the particular element, e.g.:

```
public bool Remove(T obj)
{
    for (int i = m_tailIndex - 1; i m_headIndex; i--) {
        if (m_array[i & m_mask] == obj) {
            lock (m_foreignLock) {
                if (m_array[i & m_mask] != obj)
                    return false; // lost a race.

                // Adjust indices or leave a null in our wake.
                if (i == m_tailIndex - 1)
                    m_tailIndex--;
                else if (i == m_headIndex + 1)
                    m_headIndex++;
                else
                    m_array[i & m_mask] = null;

                return true;
            }
        }

        return false;
    }
}
```

This is just a new method on the WorkStealingQueue&lt;T&gt; data structure.  This
requires that the local and foreign pop methods now check for null values and restart
the relevant operation should one be found, because of the work item to be removed
is not the head or tail item we cannot prevent subsequent removals from seeing it
(i.e., the indices must remain the same).

Next time, in part 4 of this series, we'll take a look at what it takes to
share threads among multiple instances of the LockAndWsqThreadPool class.  This
allows many pools to be created within a single AppDomain without requiring entirely
separate sets of threads to service each one of them.  This capability enables
you to isolate different work queues from one another, to ensure that certain components
aren't starved by other (potentially misbehaving) ones.

