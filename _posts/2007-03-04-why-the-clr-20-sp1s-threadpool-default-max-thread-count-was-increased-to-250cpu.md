---
layout: post
title: Why the CLR 2.0 SP1's threadpool default max thread count was increased to
  250/CPU
date: 2007-03-04 18:01:21.000000000 -08:00
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
In 2.0 SP1, we changed the threadpool's default maximum worker thread count from
25/CPU to 250/CPU.

The reason wasn't to encourage architectures that saturate so many threads with CPU-bound
work, nor was it to suggest that having 249 threads/CPU blocked and 1/CPU actively
running is actually a good design.  A non-blocking, continuation-passing/event-driven
architecture is generally a better approach for the latter case.  Rather, we
did this to statistically reduce the frequency of accidental and nondeterministic
deadlocks.

Believe it or not, deadlocking the threadpool was the most frequently reported threading-related
customer problem/complaint during my tenure as the CLR's concurrency PM.  There
are KB articles and a wealth of customer and Microsoft employee blog posts about
this issue.

Many algorithms demand dependencies between parallel tasks.  And sometimes—as
is frequently the case in data parallel algorithms—the number of tasks can be variable
up to a factor of the input size.  A "task" in this context is just the closure
passed to QueueUserWorkItem.  Consider a dumb parallel merge sort, which uses
divide-and-conquer style parallelism, for example:

```
void Sort(int[] numbers, int from, int to)
{
    if (from < to) { ...
        ThreadPool.QueueUserWorkItem(delegate {
            Sort(numbers, from, (from+to+1)/2); }); // T1
        Sort(numbers, (from+to+1)/2, to); // T2
        ... Wait for T1 to finish ...
        ... Merge left and right ...
    }
}
```

In this case, T1 is run in parallel and sorts the left half; T2 runs on the calling
thread and sorts the right.  After T2 runs sequentially, it must wait for T1
to complete before moving on to the merge step.  As written, this algorithm
is clearly inefficient and deadlocks easily.  Pass it an array of size 33 on
a 2-CPU machine, and the threadpool's default maximums will ensure that some T1's
can't even get scheduled, leaving threadpool threads blocked waiting for their queued
(and stuck) counterparts to finish.  Depending on how tasks are scheduled at
runtime this could deadlock.

Clearly the programmer needs to "stop" dividing the problem at some reasonable point,
i.e. limit the maximum number of tasks generated; otherwise the task count will grow
with some factor of the input size, causing deadlocks for large inputs (not to mention
huge context switch and resource consumption overheads).  When might that point
be?  Perhaps the programmer calculates some degree-of-parallelism (DOP) at the
top of the recursive call stack, say log2(#ofCPUs).  DOP is passed to the first
call to Sort and each subsequent recursive call decrements the DOP by 1.  So
long as the DOP argument is >0, T1 is run in parallel; otherwise, T1 is run sequentially
on the same thread, just like T2.  This ensures we don't spawn more tasks than
there are CPUs.

And this will probably work.  Most of the time.

What if, just by chance, the stars aligned and 25 instances of this algorithm ran
simultaneously?  Seems farfetched?  Maybe so.  Consider this: using
log2(#ofCPUs) might not be enough in the case that some comparison routines block
during sorting, possibly suggesting log2(2(#ofCPUs)) as a better DOP instead.
And then all we need is 12.5 occurrences.  Still a little farfetched, but not
quite as much.  But wait: there could be other algorithms using the thread pool
simultaneously, particularly on a server.  (Yes, data parallelism on a server
is probably suspect in the first place, but for highly parallel servers with volatile
loads, it could be useful.)  And remember, the thread pool is shared across
all AppDomains in the process, so if you've written a reusable component, you're
relying on all other software in the process to behave properly too (which you may
have absolutely no control over).

Most of these admittedly represent imperfections in the overall design and architecture
of the application, but the sad fact is that they tend to be somewhat common.
Especially when components are dynamically composed in the process, as is common
with server and AddIn-style apps.  And they are very nondeterministic and hard
to test for.  Our platform doesn't offer a mechanism today that allows developers
to write code that is intelligently-parallel, particularly when many heterogeneous
components are trying to use concurrency for performance.  Even with the suggested
improvements and the CLR threadpool's old 25/CPU thread limit, the Sort routine could
deadlock once in a while, maybe under extreme stress and very hard to reproduce conditions.
This will occur less frequently, statistically speaking, with the 250/CPU limit.
The problem is that all of this is just a heuristic, there aren't any hard numbers
and coordination involved.

It's also worth noting that the threadpool throttles its creation of threads to
2/second once the count has exceeded the #ofCPUs.  That means if a programmer
sees this situation happening with regularity, they will also observe hard to diagnose
performance degradations.  Once in a while, that sort algorithm might take 10-times
longer to run, inexplicably.  If this happens a lot, the developer will notice,
profile, and fix the issue.  While this isn't great, this problem is typically
quite rare in any one (properly written) program, and doesn't happen with regularity.
Our first priority was to prevent the periodic and sporadic hangs, the things eating
away at the reliability and uptime of programs, to trade them off for possible periodic
performance blips.  Many of those horribly misarchitected programs will still
deadlock deterministically with the new limits, and the thread injection throttling
will help to discourage them from being written this way.  (It would take 125
seconds to create 250 threads on a 1-CPU machine, and it seems unlikely that a 2
minute-plus delay would be tolerated.  Some people use SetMinThreads to get
around this, which is (usually) inexcusable.)

With all of this said, we clearly have a lot of work to do in the future to encourage
better parallel program architectures and to provide better tools for diagnostics
in this area.  I agree with the basic tenet "use as few threads as possible,
but no fewer," but sometimes we have to sacrifice idealism to solve practical real-world
problems.  In my experience, this should solve many such problems.

