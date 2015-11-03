---
layout: post
title: A stopwatch for threads
date: 2006-03-25 14:19:52.000000000 -07:00
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
The profiler that ships with Visual Studio is great for "real" CPU profiling.
But let's face it: there are still some situations where a good ole' stopwatch
works just fine (of the System.Diagnostics.Stopwatch variety). For example,
when you're trying to do some quick and dirty measurement on a very specific
region of code, and don't want to deal with the rest of the noise.

The BCL stopwatch isn't inherently thread-safe. Even if you protect access to
it (and somehow account for the overhead of doing so), it maintains a single
counter. In the past, I've wanted to measure the total amount of time spent
inside a select few regions of code, across all threads. The profiler works for
this, but you need to get the sampling granularity right, and deal with all of
the extra data collected. Then you have to mine it.

So I whipped up a stopwatch that maintains a counter that is the cumulative
total of all threads that have started/stopped it, across an entire AppDomain.
It's nothing incredibly clever, but I've found it to be quite useful. In many
code projects I have, I've simply set up a file that declares a bunch of static
ThreadSafeStopwatches, which I can then just call from anywhere.

Here's the code (also available for download here:
[ThreadSafeStopwatch.cs](http://www.bluebytesoftware.com/code/06/03/ThreadsafeStopwatch.cs)):

using System;

using System.Collections.Generic;

using System.Diagnostics;

using System.Threading;

/// <summary>

/// This class enables AppDomain-wide profiling of multi-threaded

/// code, by tracking a cumulative number of ticks spent across all

/// threads. If multiple threads start the same watch in parallel,

/// this class ensures that we count time for both threads, and that

/// they do not interfere with each other. It does this by storing an

/// internal stop-watch in TLS, and an instance-wide tick counter.

///

/// Note that the cumulative count is only ever incremented if a

/// thread actually calls Stop in its own stop-watch. If a thread

/// routine terminates w/out stopping the watch, it's as if it never

/// began.

/// </summary>

public sealed class ThreadSafeStopwatch : IDisposable

{

    /\*\* Fields \*\*/

    private long ticks;

    // These thread-specific fields are used to maintain a cache

    // of thread-safe stopwatches to actual stopwatches. For long

    // running threads, we can build up some amount of trash over

    // time, so a cache management scheme is implemented via a

    // combination of mechanisms: Dispose, ~ThreadSafeStopwatch,

    // GetWatch, and PruneCache.

    [ThreadStatic]

    private static Dictionary<WeakReference, Stopwatch> threadWatches;

    [ThreadStatic]

    private static int cacheCounter;

    /\*\* Properties \*\*/

    public long ElapsedTicks

    {

        get { return ticks; }

    }

    public float ElapsedMilliseconds

    {

        get { return (float)ticks / TimeSpan.TicksPerMillisecond; }

    }

    /\*\* Methods \*\*/

    ~ThreadSafeStopwatch()

    {

        Dispose(false);

    }

    public void Dispose()

    {

        Dispose(true);

    }

    private void Dispose(bool disposing)

    {

        // Clean up the associated cache entry with this object.

        // NOTE: I am explicitly not guarding this code-path by if

        // (disposing) { ... } because the Dictionary is not finaliz-

        // able. Thus, I know it is safe to access it. In the case of

        // non-process-exit finalizers, we do want to clean up the

        // associated cache entry, thus we access another object on

        // the finalizer code-path.

        if (!Environment.HasShutdownStarted)

        {

            Dictionary<WeakReference, Stopwatch> watches = threadWatches;

            WeakReference thisRef = new WeakReference(this);

            if (watches != null && watches.ContainsKey(thisRef))

            {

                // Deallocate the cache entry:

                watches.Remove(thisRef);

            }

        }

    }

    const int threadCachePruneCount = 100;

    private Stopwatch GetWatch()

    {

        if (threadWatches == null)

        {

            // First time called on this thread, allocate a new dictionary:

            threadWatches = new Dictionary<WeakReference, Stopwatch>(

                WeakRefEqualityComparer.Comparer);

        }

        else

        {

            // This has been called before. Increment the thread counter;

            // every so often, we prune out trash being held alive by our

            // cache.

            if (++cacheCounter % threadCachePruneCount == 0)

            {

                PruneCache();

                cacheCounter = 0;

            }

        }

        // Now look for the associated stopwatch:

        Stopwatch sw;

        if (threadWatches.TryGetValue(new WeakReference(this), out sw))

            return sw;

        // If we didn't find the stopwatch, simply return null to

        // indicate that the caller needs to allocate a new one:

        return null;

    }

    private void PruneCache()

    {

        // BUGBUG: This is probably a poor cache management policy. But

        // I'm only enabling this in DEBUG builds for now, and until I

        // run into a real problem, I'm not spending time on it.

        List<WeakReference> toRemoveWrefs = null;

        // Look for dead references, and add them to the list (which is

        // lazily created, by the way).

        foreach (WeakReference wr in threadWatches.Keys)

        {

            // If the weak-reference is no longer alive, we add it to the

            // list of 'to-remove' stop-watches.

            if (!wr.IsAlive)

            {

                if (toRemoveWrefs == null)

                    toRemoveWrefs = new List<WeakReference>();

                toRemoveWrefs.Add(wr);

            }

        }

        // If we found any dead entries, remove them now.

        if (toRemoveWrefs != null)

        {

            foreach (WeakReference wr in toRemoveWrefs)

            {

                threadWatches.Remove(wr);

            }

        }

    }

    [Conditional("DEBUG")]

    public void Start()

    {

        // We look in TLS to see if this thread has already allocated a

        // stopwatch for the current thread-safe stopwatch. This is

        // thread-safe, of course, since each thread gets their own list

        // of Stopwatches (reentrancy aside--there aren't any blocking

        // points below):

        // Since we are about to retrieve something from TLS, and use it

        // across a set of paired operations (Start/Stop), we mark the

        // beginning of a thread-affinity region.

        Thread.BeginThreadAffinity();

        // Access TLS:

        Stopwatch sw = GetWatch();

        if (sw == null)

        {

            // No watch was found, allocate a new one and publish it.

            sw = new Stopwatch();

            threadWatches.Add(new WeakReference(this), sw);

        }

        // First, ensure we haven't begun it yet. If the stopwatch is

        // already running, we ignore this call. This is consistent with

        the System.Diagnostics.Stopwatch

        // class's behavior.

        if (!sw.IsRunning)

        {

            // And if that check succeeds, start the stop-watch ticking.

            sw.Start();

        }

    }

    [Conditional("DEBUG")]

    public void Reset()

    {

        // Get the current stopwatch in TLS -- see above comments (in

        // Start) for details on thread-safety.

        Stopwatch sw = GetWatch();

        // If we found one, reset it.

        if (sw != null)

            sw.Reset();

        // And also set our cumulative ticks to 0.

        ticks = 0;

    }

    [Conditional("DEBUG")]

    public void Stop()

    {

        // Get the current stopwatch in TLS -- see above comments (in

        // Start) for details on thread-safety.

        Stopwatch sw = GetWatch();

        // First, ensure we are running. If the stopwatch isn't running

        // yet, we ignore this call. This is consistent with the System.

        // Diagnostics.Stopwatch class's behavior.

        if (sw != null && sw.IsRunning)

        {

            // Add the stopwatch's total time to our instance counter.

            // This has to be an interlocked operation, because the whole

            // point of this class is to be shared across threads. 'ticks'

            // is the only instance state.

            Interlocked.Add(ref ticks, sw.ElapsedTicks);

            // We reset the stopwatch because we want to start at 0 upon

            // the next invocation to 'Start' -- the cumulative time is

            // kept in the 'ticks' variable.

            sw.Reset();

            // We can now end the thread-affinity that was started in the

            // Start operation above.

            Thread.EndThreadAffinity();

        }

    }

    class WeakRefEqualityComparer : IEqualityComparer<WeakReference>

    {

        internal static WeakRefEqualityComparer Comparer =

            new WeakRefEqualityComparer();

        public bool Equals(WeakReference wr1, WeakReference wr2)

        {

            // For purposes of our hash-table, if two weak-references

            // refer to the same object, we consider them equal.

            object o1 = wr1.Target;

            object o2 = wr2.Target;

            if (!wr1.IsAlive || !wr2.IsAlive)

                return false;

            // We shouldn't ever have null weak-references that aren't

            // dead.

            Debug.Assert(o1 != null && o2 != null);

            // If the two underlying objects are equal, we pretend the

            // weak-refs are too.

            return o1.Equals(o2);

        }

        public int GetHashCode(WeakReference wr)

        {

            object o = wr.Target;

            // Just return 0 for dead objects. We actually shouldn't

            // ever use a dead object for hashing, although there could

            // be some benign races above that result in this case. I

            // haven't convinced myself otherwise, and they will get clean-

            // ed up with the normal finalization code-path. It's A-OK.

            if (!wr.IsAlive)

                return 0;

            // Again, shouldn't get a live weak-ref that has a null

            // object ref.

            Debug.Assert(o != null);

            // Now, simply return the underlying object's hash-code.

            return o.GetHashCode();

        }

    }

}

