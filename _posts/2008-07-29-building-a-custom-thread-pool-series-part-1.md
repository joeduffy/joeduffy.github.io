---
layout: post
title: Building a custom thread pool (series, part 1)
date: 2008-07-29 01:44:01.000000000 -07:00
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
This is the first part in a series I am going to do on building a custom thread pool.
Not that I'm advocating you do such a thing, but I figured it could be interesting
to explore the intricacies involved.  We'll start off really simple:

- A CLR monitor based queuing mechanism.

- A static, fixed number of threads.

- The ability to create multiple pools that are isolated from one another.

- Flowing of ExecutionContexts and the ability to turn it off.

As the series progresses, I intend to incorporate some interesting facets such as:

- Dynamic thread injection, so that the number of threads is not fixed.

- Thread sharing among multiple pools in an AppDomain.

- A per-thread work stealing queue to increase the efficiency of recursively queued
work.

- Interoperability with I/O completion ports.

- Returning an IAsyncResult object for seamless APM integration.

- Cancelation.

- Anything else that readers suggest might be interesting.  Let me know.

And with that, let's begin.

For now, we'll use a very simple interface, IThreadPool, under which we can implement
various mechanisms and policies.  This will make it easier to write generic
test harnesses that compare different implementations.  For this post we won't
really make use of that capability (much), but we will use it to compare the stock
CLR ThreadPool against a very simple custom one.

```
interface IThreadPool : IDisposable
{
    void QueueUserWorkItem(WaitCallback work, object obj);
}
```

So that we can subsequently compare implementations, we have two simple implementations
of IThreadPool.  One does safe ThreadPool.QueueUserWorkItem calls, and the other
does unsafe ThreadPool.UnsafeQueueUserWorkItem calls.  The only difference is
that the latter doesn't flow the ExecutionContext across threads.

```
class CLRThreadPool : IThreadPool
{
    public void QueueUserWorkItem(WaitCallback work, object obj)
    {
        ThreadPool.QueueUserWorkItem(work, obj);
    }

    public void Dispose() { }
}

class CLRUnsafeThreadPool : IThreadPool
{
    public void QueueUserWorkItem(WaitCallback work, object obj)
    {
        ThreadPool.UnsafeQueueUserWorkItem(work, obj);
    }

    public void Dispose() { }
}
```

Our simple thread pool, SimpleLockThreadPool, will have 7 fields:

- private int m\_concurrencyLevel: the number of threads to create statically, specified
at construction time (w/ a default of Environment.ProcessorCount);

- private bool m\_flowExecutionContext: whether execution context flowing is turned
on (the default) or off.  Turning it off can provide some performance gains.

- private Queue<WorkItem> m\_queue: the queue of actual work items.  This object
is also used as a monitor.  We'll see what the WorkItem data structure looks
like momentarily.

- private Thread[] m\_threads: the set of threads actively dequeuing and running
work items from this pool.  Each instance of SimpleLockThreadPool has its own
set.

- private int m\_threadsWaiting: a hint used to avoid pulsing on enqueue when no
threads are waiting.  Threads increment and decrement before and after (respectively)
waiting for work.

- private bool m\_shutdown: set to true when threads are requested to exit.

Each WorkItem is a struct with three fields.  Using a struct avoids superfluous
heap allocations.

- internal WaitCallback m\_work: the delegate to invoke.

- internal object m\_obj: some optional state to pass as the argument to m\_work.

- internal ExecutionContext m\_executionContext: a context captured at enqueue time,
to be used when running the callback.  This ensures the appropriate security
context and logical call context flow to the work item's stack, for example.

There are just 4 methods of interest:

- public void QueueUserWorkItem(WaitCallback work, object obj): implements the IThreadPool
interface, and does a few things.  It allocates a new WorkItem, optionally captures
and stores an ExecutionContext, ensures the pool has started, and then enqueues the
WorkItem into the pool, possibly pulsing a single thread (if any are waiting).
There's also a convenient overload that doesn't take an obj for situations where
it isn't needed.

- private void EnsureStarted(): a simple helper method that will lazily initialize
and start the set of threads in a particular pool.  These threads just sit in
a loop and dequeue work.  The lazy aspect ensures that a pool that doesn't
ever get used won't allocate threads.

- private void DispatchLoop(): this is the main method run by each pool thread.
All it does is sit in a loop dequeuing and (if the queue is empty) waiting for new
work to arrive.  When shutdown is initiated, the method voluntarily quits.
If any pool work items throw an exception, this top-level method lets them go unhandled,
resulting in a crash of the thread.

- public void Dispose(): shuts down all the threads in a pool.  It is synchronous,
so it actually waits for them to complete before returning.  If work items take
a long time to finish, this could be a problem.  Extending this to timeout,
etc., would be trivial.

And that's really it.  This is a very simple and naïve start, but it will
prove to be a good starting point for all of the extensions I mentioned at the outset.
Here's the full code.

```
public class SimpleLockThreadPool : IThreadPool
{
    // Constructors--
    // Two things may be specified:
    //   ConcurrencyLevel == fixed # of threads to use
    //   FlowExecutionContext == whether to capture and flow
    //          ExecutionContexts for work items

    public SimpleLockThreadPool() :
        this(Environment.ProcessorCount, true) { }
    public SimpleLockThreadPool(int concurrencyLevel) :
        this(concurrencyLevel, true) { }
    public SimpleLockThreadPool(bool flowExecutionContext) :
        this(Environment.ProcessorCount, flowExecutionContext) { }

    public SimpleLockThreadPool(int concurrencyLevel, bool flowExecutionContext)
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
                ExecutionContext.Run(m_executionContext, ContextInvoke, null);
        }

        private void ContextInvoke(object obj)
        {
            m_work(m_obj);
        }
    }

    private readonly int m_concurrencyLevel;
    private readonly bool m_flowExecutionContext;
    private readonly Queue<WorkItem> m_queue = new Queue<WorkItem>();
    private Thread[] m_threads;
    private int m_threadsWaiting;
    private bool m_shutdown;

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
        lock (m_queue) {
            m_queue.Enqueue(wi);
            if (m_threadsWaiting > 0)
                Monitor.Pulse(m_queue);
            }
        }
    }

    // Ensures that threads have begun executing.
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

    // Each thread runs the dispatch loop.
    private void DispatchLoop()
    {
        while (true) {
            WorkItem wi = default(WorkItem);
            lock (m_queue) {
                // If shutdown was requested, exit the thread.
                if (m_shutdown)
                    return;

                // Find a new work item to execute.
                while (m_queue.Count == 0) {
                    m_threadsWaiting++;
                    try { Monitor.Wait(m_queue); }
                    finally { m_threadsWaiting--; }

                    // If we were signaled due to shutdown, exit the thread.
                    if (m_shutdown)
                        return;
                }

                // We found a work item! Grab it ...
                wi = m_queue.Dequeue();
            }

            // ...and Invoke it. Note: exceptions will go unhandled (and crash).
            wi.Invoke();
        }
    }

    // Disposing will signal shutdown, and then wait for all threads to finish.
    public void Dispose()
    {
        m_shutdown = true;
        lock (m_queue) {
            Monitor.PulseAll(m_queue);
        }

        for (int i = 0; i < m_threads.Length; i++)
            m_threads[i].Join();
    }
}
```

I think everything should be self-explanatory given the earlier explanation of all
the fields and types.  Let's take a look at a simple test harness for this.
There are a myriad of useful tests, and the one that I will show right now is but
one of them.  It queues a whole lot of work items, and then blocks waiting for
them to complete.  I have two variants: one of them allows work items to begin
executing before the queuing is done, while the other separates the phases.
Here is the general test.

```
class Program
{
    public static void Main(string[] args)
    {
        bool separateQueueFromDrain = bool.Parse(args[0]);

        const int warmupRunsPerThreadPool = 100;
        const int realRunsPerThreadPool = 1000000;

        IThreadPool[] threadPools = new IThreadPool[] {
            new CLRThreadPool(),
            new CLRUnsafeThreadPool(),
            new SimpleLockThreadPool(true),  // Flow EC
            new SimpleLockThreadPool(false), // Don't flow EC
        };

        long[] queueCost = new long[threadPools.Length];
        long[] drainCost = new long[threadPools.Length];

        Console.WriteLine("+ Running benchmarks ({0}) +", threadPools.Length);

        for (int i = 0; i < threadPools.Length; i++) {
            IThreadPool itp = threadPools[i];
            Console.Write("#{0} {1}: ", i, itp.ToString().PadRight(26));

            // Warm up:
            using (CountdownEvent cev =
                    new CountdownEvent(warmupRunsPerThreadPool)) {
                WaitCallback wc = delegate { cev.Decrement(); };
                for (int j = 0; j < warmupRunsPerThreadPool; j++) {
                    itp.QueueUserWorkItem(wc, null);
                }
                cev.Wait();
            }

            // Now do the real thing:
            int g0collects = GC.CollectionCount(0);
            int g1collects = GC.CollectionCount(1);
            int g2collects = GC.CollectionCount(2);

            using (CountdownEvent cev =
                    new CountdownEvent(realRunsPerThreadPool))
            using (ManualResetEvent gun = new ManualResetEvent(false)) {
                WaitCallback wc = delegate {
                    if (separateQueueFromDrain) { gun.WaitOne(); }
                    cev.Decrement();
                };

                Stopwatch sw = Stopwatch.StartNew();
                for (int j = 0; j < realRunsPerThreadPool; j++)
                    itp.QueueUserWorkItem(wc, null);
                queueCost[i] = sw.ElapsedTicks;

                sw = Stopwatch.StartNew();
                if (separateQueueFromDrain) { gun.Set(); }
                cev.Wait();
                drainCost[i] = sw.ElapsedTicks;
            }

            g0collects = GC.CollectionCount(0) - g0collects;
            g1collects = GC.CollectionCount(1) - g1collects;
            g2collects = GC.CollectionCount(2) - g2collects;

            Console.WriteLine("q: {0}, d: {1}, t: {2} (collects: 0={3},1={4},2={5})",
                queueCost[i].ToString("#,##0"),
                drainCost[i].ToString("#,##0"),
                (queueCost[i] + drainCost[i]).ToString("#,##0"),
                g0collects,
                g1collects,
                g2collects
            );

            itp.Dispose();
            GC.Collect(2);
            GC.WaitForPendingFinalizers();
        }

        Console.WriteLine();
        Console.WriteLine("+ Comparison against baseline ({0}) +", threadPools[0]);

        for (int i = 0; i < threadPools.Length; i++) {
            Console.WriteLine("#{0} {1}: q: {2}x, d: {3}x, t: {4}x",
                i,
                threadPools[i].ToString().PadRight(26),
                queueCost[i] / (float)queueCost[0],
                drainCost[i] / (float)drainCost[0],
                (queueCost[i] + drainCost[i]) / ((float)queueCost[0] + drainCost[0])
            );
        }
    }
}
```

If we pass 'true' on the command line, the phases are separated, and if we pass
'false' they are not.  The 'true' part allows us to hone in on the source
of overhead (is it the queuing itself, or the dispatching of work items?), but at
the expense of needing to keep more of the work items in memory at once (because
pool threads can't drain them as we queue them).  We run the test over an
array of IThreadPool implementations, and for each one print out the cost to queue
work, drain work, and the number of Gen0, Gen1, and Gen2 collections performed for
each one.  The GC statistics are interesting because they tell us how much more
memory (roughly speaking) we are allocating for the same workload on different pool
implementations.  As our pool gets more complicated, this will be something
to keep your eye on.

Here are some sample numbers on my dual-core laptop.  Your results will vary.
When 'true' is passed, I see numbers like the following:

```
+ Running benchmarks (4) +
#0 CLRThreadPool       : q: 3,163,506, d: 5,137,893, t: 8,301,399 (collects: 0=16,1=8,2=3)
#1 CLRUnsafeThreadPool : q: 1,285,806, d: 4,428,451, t: 5,714,257 (collects: 0=5,1=4,2=1)
#2 SimpleLockThreadPool: q: 4,208,686, d: 11,839,614, t: 16,048,300 (collects: 0=104,1=14,2=4)
#3 SimpleLockThreadPool: q: 499,575, d: 3,992,190, t: 4,491,765 (collects: 0=1,1=1,2=1)

+ Comparison against baseline (CLRThreadPool) +
#0 CLRThreadPool       : q: 1x, d: 1x, t: 1x
#1 CLRUnsafeThreadPool : q: 0.4064497x, d: 0.8619196x, t: 0.6883487x
#2 SimpleLockThreadPool: q: 1.330387x, d: 2.304371x, t: 1.933204x
#3 SimpleLockThreadPool: q: 0.1579181x, d: 0.7770092x, t: 0.5410853x
```

And when 'false' is passed, I see similar but subtly different numbers:

```
+ Running benchmarks (4) +
#0 CLRThreadPool       : q: 3,476,630, d: 27,592, t: 3,504,222 (collects: 0=20,1=6,2=0)
#1 CLRUnsafeThreadPool : q: 2,636,319, d: 140,653, t: 2,776,972 (collects: 0=5,1=2,2=0)
#2 SimpleLockThreadPool: q: 4,850,171, d: 6,227,052, t: 11,077,223 (collects: 0=95,1=14,2=4)
#3 SimpleLockThreadPool: q: 826,987, d: 132,755, t: 959,742 (collects: 0=1,1=1,2=1)

+ Comparison against baseline (CLRThreadPool) +
#0 CLRThreadPool       : q: 1x, d: 1x, t: 1x
#1 CLRUnsafeThreadPool : q: 0.7582973x, d: 5.097601x, t: 0.7924646x
#2 SimpleLockThreadPool: q: 1.395078x, d: 225.6832x, t: 3.161108x
#3 SimpleLockThreadPool: q: 0.2378703x, d: 4.811358x, t: 0.2738816x
```

Notice right away that we are handily beating the heck out of the CLR thread pool
in the case where we don't flow ExecutionContext objects (the #3 case).  In
fact, we are only 27% the cost for the 'false' variant.  But we unfortunately don't
fare nearly as well when we flow ExecutionContext objects (the #2 case).  It turns
out that's because the CLR has a unique advantage over us when compared to our
naive call to ExecutionContext.Capture.  Just look at the sizeable difference
in Gen0 collections; we are clearly allocating a lot more memory.  This will be a
topic for a subsequent post.

