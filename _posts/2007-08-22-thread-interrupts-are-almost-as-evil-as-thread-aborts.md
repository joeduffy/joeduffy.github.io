---
layout: post
title: Thread interrupts are (almost) as evil as thread aborts
date: 2007-08-22 23:52:33.000000000 -07:00
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
Most managed code in the .NET Framework has not been hardened against asynchronous
exceptions.  This includes out of memory (OOM) conditions and asynchronous thread
aborts, and is entirely by design.  Hardening against OOM, for example, is historically
an extraordinarily difficult feat, and few systems undertake the development and
QA costs needed to do so.  (FWIW, the CLR VM is one such system.)  Simply
failing gracefully is usually hard enough.  Failing gracefully is admittedly
leaps and bounds easier in managed code because allocation failures are communicated
via exceptions rather than return values, and are thus transitively propagated "by
default."  Thread aborts are even more difficult to harden against, however,
because they can originate at any instruction (with a handful of exceptions).
Ensuring data invariants are protected for every single instruction is clearly just
a little difficult.

These things are certainly not impossible.  With enough effort, you can make
inroads toward solutions for both issues.  Portions of the .NET Framework have
gone to such lengths.  For example, code that manipulates process-wide state
spanning AppDomains needs to ensure that this state is not corrupted by an unfortunately
placed thread abort when run inside systems like SQL Server that use aborts to tear
down boundaries of isolation.  While possible, the important thing to understand
here is that most of the .NET Framework is in fact not resilient to these things.
See [this doc](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641)as
an example of guidance the CLR team provided to other developers inside of Microsoft
to this effect.  OOMs are in a similar category, though many subsystems take
different, inconsistent approaches to memory allocation failures (e.g. WPF takes
a different stance than WCF).

All of this is a long winded build up to the following problem:  thread interrupts
are just about as evil as these sorts of asynchronous exceptions.  The failure
injection points are more constrained—e.g. an OOM can occur wherever an allocation
occurs, a thread abort can happen in between nearly any two instructions, and thread
interruptions can only occur at blocking calls that transition the managed thread
into the state WaitSleepJoin—but this doesn't change the fact that most code
is unprepared to deal properly with such interruptions.  Once again, it's
not that managed code cannot be constructed to be resilient to interruptions—in
fact, it's much easier than OOMs and thread aborts—it's simply that the .NET
Framework hasn't been constructed to tolerate arbitrary interruptions.  If
threads are calling into these APIs and thread interruptions are provoked, state
corruption, memory leaks, and possible deadlocks can be left in the wake.

To take a brief example of where such a problem might crop up, imagine a thread has
blocked on FileStream.EndRead because it is finishing some asynchronous IO operation.
After a brief inspection of the code, I'm convinced interrupting the call it makes
to WaitHandle.WaitOne internally will lead to a memory leak:

```
    if (1 == Interlocked.CompareExchange(ref result._EndXxxCalled, 1, 0)) {
        __Error.EndReadCalledTwice();
    }

    WaitHandle handle = result._waitHandle;
    if (handle != null) {
        try {
            handle.WaitOne();
        }
        finally {
            handle.Close();
        }
    }

    NativeOverlapped* nativeOverlappedPtr = result._overlapped;
    if (nativeOverlappedPtr != null) {
        Overlapped.Free(nativeOverlappedPtr);
    }
```

The method ensures only one call to EndRead can occur, and will throw on subsequent
attempts.  So the above code will only ever run once.  Sadly, EndRead needs
to free the NativeOverlapped structure used internally for asynchronous IO completion.
But because the call to Overlapped.Free follows the call to WaitOne, and doesn't
occur inside of a finally block, it won't execute.  In summary: interrupt
that call to WaitOne, and boom, we leak a NativeOverlapped object.  Whether
or not this is disastrous of course depends on the precise scenario.  A few
bytes here and a few bytes there can quickly add up, particularly for long running
programs.  At least this particular example protects invariants sufficiently
well to avoid state corruption that would lead to further unpredictability.
But recall that this is just one example.  In my experience, the BCL represents
some of the most carefully written code in the .NET Framework, so this problem is
undoubtedly scattered about all over the place.

Unfortunately, it's become somewhat common advice that using thread interruption
as a synchronization and control mechanism is a GoodThing&8482;.  Andrew Birrell,
a researcher from Microsoft Research, for example, suggested this in his paper ["An
Introduction to Programming with C# Threads"](http://research.microsoft.com/~birrell/papers/ThreadsCSharp.pdf):

> _"Interrupts are most useful when you don't know exactly what is going on.
For example, the target thread might be blocked in any of several packages, or within
a single package it might be waiting on any of several objects. In these cases an
interrupt is certainly the best solution. Even when other alternatives are available,
it might be best to use interrupts just because they are a single unified scheme
for provoking thread termination." (p33)_

While I am sure this advice is well intentioned, it is extremely dangerous for the
subtle reasons outlined above and can lead to reliability problems in any programs
that follow it.  My recommendation is to build this kind of higher level synchronization
into the code that you actually own, and handle shutdown and interruption logic yourself.
This is a bit cumbersome and is more work, but it also ensures that arbitrary blocking
points in the libraries you use will not be affected by interruptions.

With the increase in hardware parallelism over the coming years, I worry that the
use of interruptions will become more widespread as a popular technique developers
use to control threads.  And as more and more of the .NET Framework uses higher
degrees of concurrency, necessarily requiring more internal synchronization, the
number of blocking points that are vulnerable to this kind of abuse will grow accordingly.
So, please, do your part… avoid Thread.Interrupt like the plague.  In fact,
perhaps we should deprecate it.

