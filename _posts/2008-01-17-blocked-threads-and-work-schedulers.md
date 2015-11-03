---
layout: post
title: Blocked threads and work schedulers
date: 2008-01-17 15:29:24.000000000 -08:00
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
Most schedulers try to keep the number of runnable threads (within a certain context)
equal to the number of processors available.  Aside from fairness desires, there's
usually little reason to have more: and in fact, having more can lead to more memory
pressure due to the cost of stacks and working set held on the stacks, non-pageable
kernel memory, per-thread data structures, etc., and also has execution time costs
due to increased pressure on the kernel scheduler, more frequent context switches,
and poor locality due to threads being swapped in and out of processors.  In
extreme cases, blocked threads can build up only for all of them to be awoken and
released to wreak havoc on the system at once, hurting scalability.

A naïve approach of one-thread-per-processor works great until a thread on one of
these processors blocks, either "silently" as a result of a pagefault or "explicitly"
due to IO or a synchronization wait.  (I should mention that due to the plethora
of hidden blocking calls in the kernel, Win32 user-mode code, and the .NET Framework,
a lot of IO and synchronization waiting is "silent" too.)  In this case,
a processor becomes idle (0% utilization) for some period of time.  If there
is other work that could be happening instead, this is clearly bad.

Many programs spend most of their time blocked.

Four particular solutions to this problem are commonplace on Windows:

1. Create more threads than processors and hope for the best.  This trades some
amount of runtime efficiency for the insurance that processor time won't go to
waste.

2. Periodically poll for blocked threads using some kind of daemon and respond to
the presence of one by creating a new thread to execute work.  Eventually this
thread would go away, for instance when the blocked thread awakens.  This is
the approach used by the CLR ThreadPool, although it [caps the total](http://www.bluebytesoftware.com/blog/2007/03/05/WhyTheCLR20SP1sThreadpoolDefaultMaxThreadCountWasIncreasedTo250CPU.aspx).
(The TPL uses this appraoch today also, but we're changing/augmenting it.)
For obvious reasons, this approach is quite flawed: you easily end up with more running
threads than processors, have to trade-off more frequent polling--which implies more
runtime overhead--with less frequent polling--which adds time to the latency in the
scheduler's response to a blocked thread.

3. Block on an IO Completion Port at periodic intervals--e.g. when dispatching a
new work item in a ThreadPool-like thing--which has the effect of throttling running
threads.  This still requires creating more threads than processors, but helps
to ensure few of them run at the same time.  Unfortunately, it still does lead
to more of them actually running than you'd like since the port can only prevent
a thread from running when it goes back and blocks on the port in the kernel.
But this is only done periodically.

4. Specialized systems like SQL have used Fibers in the past to avoid needing full-fledged
threads to replace the blocking ones.  To do this, they ensure all blocking
goes through a cooperative layer, which notifies a user-mode scheduler (UMS).
The user-mode scheduler maintains a list of blocked Fibers, but can multiplex runnable
Fibers onto threads, keeping the number of threads equal to the number of processors.
A thread effectively never blocks, Fibers do, but this requires all blocking to notify
the UMS.  Aside from extraordinarily closed world systems, this approach doesn't
usually work.  That's because Fibers are not threads and multiplexing entirely
different contexts of work onto a shared pool of threads (at blocking points) can
easily lead to thread affinity nightmares.

The CLR facilities #4 by funneling all synchronization waits in managed code through
one point in the VM codebase.  This was done initially to ensure consistent
message pumping on STA threads, via CoWaitForMultipleHandles.  But it was then
exploited in 2.0 to expand the CLR Hosting APIs to enable custom hosts to hook all
synchronization calls.  This is convenient for building interesting debugging
tools, like [deadlock detecting hosts](http://msdn.microsoft.com/msdnmag/issues/06/04/Deadlocks/default.aspx).

A fifth approach is often viable and even preferable, and that is to avoid blocking
altogether.  Often referred to as continuation passing style (CPS), the idea
is that, where you'd normally have blocked, the callstack is transformed into a
resumable continuation.  For an example of this, look at [Jeff Richter's ReaderWriterLockGate
class](http://msdn.microsoft.com/msdnmag/issues/06/11/ConcurrentAffairs/): it's
a reader/writer lock with no blocking.  Asynchronous IO is supported by files
and sockets on Windows, and enables a similar style of programming.  The continuation
is ordinarily just a closure object that has enough state to restart itself when
the sought-after condition arises.  When it does arise, the continuation is
scheduled on something like the CLR ThreadPool.  This avoids burning any threads
while the wait occurs.

For obvious reasons, CPS is usually hard to achieve in .NET: there is no language
support for first class continuations in .NET, all synchronization primitives are
wait-based, and keeping a whole stack around in memory would be a terrible idea
anyway.  You'd also need to worry about resources held on the stack, including
locks.  Instead, you should save only that state which is needed during the
continuation.  In a message passing system this is much simpler, since most
of the program is full of continuations in the form of message handlers.  For
an example of such a system, check out the [Concurrent and Coordination Runtime (CCR)](http://msdn.microsoft.com/msdnmag/issues/06/09/ConcurrentAffairs)
and/or [Erlang](http://www.erlang.org/).

Even in message passing systems, it's impossible to escape the fundamental blocking
issue, since it is platform-wide.  And in ordinary imperative programs, the
CPS transformation is near-impossible at the leaves of callstacks: unless you have
whole program knowledge, who knows what your caller expects?  Most APIs are
synchronous.  Futures and Promises potentially make this style of programming
easier, though in the extreme all APIs would need to return a Promise rather than
a true value.

Nothing conclusive, just some random thoughts ...

