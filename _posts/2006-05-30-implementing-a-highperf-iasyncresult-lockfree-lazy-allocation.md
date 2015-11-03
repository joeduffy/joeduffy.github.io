---
layout: post
title: 'Implementing a high-perf IAsyncResult: lock-free lazy allocation'
date: 2006-05-30 21:00:31.000000000 -07:00
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
Lock free code is hard. But it can come in handy in a pinch.

There have been some recent internal discussions about the IAsyncResult pattern 
and performance. Namely that, for high throughput scenarios, where the cost of 
the asynchronous work is small relative to the cost of instantiating new 
objects, there is a considerable overhead to using the IAsyncResult pattern. 
This is due to two allocations necessary to implement the pattern: (1) the 
object that implements IAsyncResult itself, and (2) the WaitHandle for consumers 
of the API who must access the IAsyncResult.AsyncWaitHandle property. I will 
address (2) in this article, since it is much more expensive than (1).

_Update: I've posted an [addendum to this article 
here](http://www.bluebytesoftware.com/blog/PermaLink,guid,df20d0c7-4bf7-443e-8601-b6aa4355a9b1.aspx)._

**Rendezvousing**

Just to recap, there are four broad ways to rendezvous with the IAsyncResult 
pattern:

1. You can poll the IAsyncResult.IsCompleted boolean flag. If it's true, the 
   work has completed. If it's false, you can go off and do some interesting 
   work, coming back to check it once in a while.

2. Supplying a delegate callback to the BeginXxx method. This callback is 
   invoked when the work completes, passing the IAsyncResult as an argument to 
   your callback.

3. Waiting on the IAsyncResult.AsyncWaitHandle. This is a Windows WaitHandle, 
   typically a ManualResetEvent, which allows you to block for a while until the 
   work completes.

4. Call the EndXxx method. Internally, this will often check IsCompleted and, if 
   it's false, will wait on the AsyncWaitHandle.

Notice that in cases 1 and 2, the WaitHandle isn't even needed. And in case 4, 
it's only needed some fraction of the time. Well, it turns out we can avoid 
allocating it altogether for those cases where it's not used. We can "just" 
lazily allocate it. Note that for asynchronous IO, the majority of code will use 
method 2 above. For scalable servers, we often don't want to tie up an extra 
thread polling or waiting for completion, since that contradicts the primary 
benefits of Windows IO Completion Ports.

**The Requirements**

Notice I enclosed the word just above in quotes when mentioning lazy allocation. 
We could of course use a lock. But that would require that we allocate an object 
to lock against. We could of course just lock 'this', but that also comes with a 
performance overhead. We can get away with lock free code in this case, so long 
as we recognize a very important race condition that we must tolerate. Imagine 
this case: Thread A checks IsCompleted. It's false. So it accesses the 
AsyncWaitHandle property, triggering lazy allocation. Meanwhile, Thread B 
finishes the async work, and sets IsCompleted to true. We need to ensure a 
deadlock doesn't ensue.

This race could go one of two ways:

1. Thread A lazily allocates and publishes the WaitHandle before Thread B sets 
   IsCompleted to true. Thread B must now witness a non-null WaitHandle when it 
checks, and it must return the WaitHandle in the signaled state. If it returns 
an unsigned WaitHandle, Thread A will wait on it, and never be woken up. This is 
a deadlock.

2. Thread B finishes first, setting IsCompleted to true, and seeing a null 
   WaitHandle. Thread A must see IsCompleted as true and consequently return the 
event in a signaled state. Just like before, if this doesn't happen, Thread A 
will wait on an unsigned WaitHandle which will never be signaled. Deadlock.

To ensure both of these cases work, Thread A's read of the WaitHandle field and 
Thread B's read of IsCompleted must be preceded by a memory barrier. This 
ensures the memory accesses aren't reordered at the compiler or processor level, 
either of which could lead to the deadlock situations we are worried about. The 
CLR 2.0's memory model is not sufficient even with volatile loads, because the 
load acquire can still move "before" the store release.

**An Implementation**

Here is one simplistic implementation of a FastAsyncResult class, with ample 
comments embedded within to explain things:

```
class FastAsyncResult : IAsyncResult, IDisposable
{
    // Fields
    private object m_state;
    private ManualResetEvent m_waitHandle;
    private bool m_isCompleted;
    private AsyncCallback m_callback;
    internal object m_internal;

    // Constructors
    internal FastAsyncResult(AsyncCallback callback, object state) {
       m_callback = callback;
       m_state = state;
    }

    // Properties

    public object AsyncState {
        get { return m_state; }
    }

    public WaitHandle AsyncWaitHandle {
        get { return LazyCreateWaitHandle(); }
    }

    public bool CompletedSynchronously {
        get { return false; }
    }

    public bool IsCompleted {
        get { return m_isCompleted; }
    }

    internal object InternalState {
        get { return m_internal; }
    }

    // Methods

    public void Dispose() {
        if (m_waitHandle != null) {
            m_waitHandle.Close();
        }
    }

    public void SetComplete() {
        // We set the boolean first.
        m_isCompleted = true;

        // And then, if the wait handle was created, we need to signal it.  Note the
        // use of a memory barrier. This is required to ensure the read of m_waitHandle
        // never moves before the store of m_isCompleted; otherwise we might encounter a
        // race that leads us to not signal the handle, leading to a deadlock.  We can't
        // just do a volatile read of m_waitHandle, because it is possible for an acquire
        // load to move before a store release.

        Thread.MemoryBarrier();

        if (m_waitHandle != null) {
            m_waitHandle.Set();
        }

        // If the callback is non-null, we invoke it.
        if (m_callback != null) {
            m_callback(this);
        }
    }

    private WaitHandle LazyCreateWaitHandle() {
        if (m_waitHandle != null) {
            return m_waitHandle;
        }

        ManualResetEvent newHandle = new ManualResetEvent(false);
        if (Interlocked.CompareExchange(
                ref m_waitHandle, newHandle, null) != null) {
            // We lost the race. Release the handle we created, it's garbage.
            newHandle.Close();
        }

        if (m_isCompleted) {
            // If the result has already completed, we must ensure we return the
            // handle in a signaled state. The read of m_isCompleted must never move
            // before the read of m_waitHandle earlier; the use of an interlocked
            // compare-exchange just above ensures that. And there's a race that could
            // lead to multiple threads setting the event; that's no problem.
            m_waitHandle.Set();
        }

        return m_waitHandle;
    }
}
```

Notice also that we tolerate the race where two threads try to lazily allocate 
the handle. Only one thread wins. The thread that loses is responsible for 
cleaning up after itself so that we don't "leak" a WaitHandle (requiring 
finalization to close it). This is an example of tolerating races instead of 
preventing them, and is similar to the design we use for jitting code in the 
runtime, for example.

**Some Initial Results**

I'll do a more thorough analysis as follow up to my next post, including 
profiling traces. But the initial results are promising.

I wrote a test harness that calculates the fibonacci series asynchronously, 
based on the sample code used in the Framework Design Guidelines book. As you 
can see by the comparisons, the larger the series being calculated, the less 
substantial the impact my performance work makes:

```
Size         Normal       Lazy         Improvement
1            177 ms       62 ms        185%
2            179 ms       63 ms        184%
3            180 ms       65 ms        177%
4            181 ms       66 ms        174%
5            187 ms       69 ms        171%
6            195 ms       79 ms        147%
7            210 ms       97 ms        116%
8            239 ms       122 ms       96%
9            275 ms       165 ms       67%
10           356 ms       257 ms       39%
12           745 ms       631 ms       18%
15           3217 ms      3075 ms      05%
```

As we would expect, as the ratio of the cost of computation to the cost of 
allocating the WaitHandle increases (with an increased "size" of the fibonacci 
series being calculated), the observed performance improvement also decreases. 
For very small computations, however, this technique can really pay off. In the 
case of high performance asynchronous IO, for example, where completion often 
involves simply marshaling some bytes between buffers, this can be a key step in 
the process of improving system throughput.

As I noted earlier, lock free techniques are almost never worth the trouble 
unless you've measured a problem, especially due to the maintenance and testing 
costs for such code. And I jumped right over using a lock for allocation. It 
turns out in this particular scenario, that technique fares just as well as the 
lock free code, albeit with a lot more simplicity. It only incurs slight 
overhead when checking the handle to see if it has been allocated yet as well as 
when setting it at completion time. Since my test case never has to check the 
WaitHandle, it only has to enter the lock upon completion, which is relatively 
cheap. As always, start simple and then go from there.

