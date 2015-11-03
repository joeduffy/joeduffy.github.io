---
layout: post
title: Fibers and the CLR
date: 2006-11-09 17:32:44.000000000 -08:00
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
The CLR tried to add support for fibers in Whidbey.  This was done in response
to SQL Server Yukon hosting the runtime in process, aka SQLCLR.  Eventually,
mostly due to schedule pressure and a long stress bug tail related to fiber-mode,
we threw up our hands and declared it unsupported.  Given the choice between
fixing mainline stress bugs (which almost exclusively use the unhosted CLR, meaning
OS threads) and fixing fiber-related stress bugs, the choice was a fairly straightforward
one.  This impacts SQL customers that want to run in fiber mode, but there are
much fewer of those than those who want to run in thread mode.

Perhaps the biggest thing we did to support fibers intrinsically in the runtime was
to decouple the CLR thread object from the physical OS thread.  Since most managed
code accesses thread-specific state through this façade, we are able to redirect
calls to threads or fibers as appropriate.  And we of course plumbed the EE
to call out to hosts so they can perform task management at various points in the
code, enabling a non-preemptive scheduler to do its job.  When a CLR host with
a registered TaskManager object is detected, we defer many tasks to it that we'd
ordinarily implement with OS calls.  For example, instead of just creating a
new OS thread, we will call out through the TaskManager interface so that the thread
can use a fiber if it wishes.

We do various other things of interest:

1. Because the CLR thread object is per-fiber, any information hanging off of it
is also per-fiber.  Thread.ManagedThreadId returns a stable ID that flows around
with the CLR thread.  It is not dependent on the identity of the physical OS
thread, which means using it implies no form of affinity.  Different fibers
running on the same thread return different IDs.  Impersonation and locale is
also carried around with the fiber instead of the thread.  This also ensures
we can properly walk stacks, propagate exceptions, and report all of the active roots
held on stack frames (for all fibers) to the GC.

2. Managed TLS is stored in FLS if a fiber is being used.  This includes the
ThreadStaticAttribute and Thread.GetData and Thread.SetData routines.  We avoid
introducing thread affinity when these APIs are used.

3. Any time we block in managed code or at most places in the runtime, we call out
to the host so that it may SwitchToFiber.  This includes calls to WaitHandle.WaitOne,
contentious Monitor.Enters, Thread.Sleep, and Thread.Join, as well as any other APIs
that use those internally.  Some managed code blocks by P/Invoking, either intentionally
or unintentionally, which leaves us helpless.  The sockets classes in Whidbey,
for instance, make possibly-blocking calls to Win32.  These should really be
cleaned up.  Not only does it prevent us from switching in fiber mode, but it
also prevents us from pumping the message queue on an STA thread.  Apps do this
too, such as P/Invoking to MsgWaitForMultipleObjects in order to do some custom message
pumping code.  The lack of coordination with blocking in the kernel also makes
it way too easy to accidentally forfeit an entire CPU for lengthy periods of time.

4. We do some things during a fiber switch to shuffle data in and out of TLS.
This includes copying the current thread object pointer and AppDomain index from
FLS to TLS, for example, as well as doing general book-keeping that is used by the
internal fiber switching routines (SwitchIn and SwitchOut).

5. Our CLR internal critical sections coordinate with the host.  Anytime we
create or wait on an event, it is a thin wrapper that calls out to the host.
This meant sacrificing some freedom around waiting, like doing away with WaitForMultipleObjectsEx
with WAIT\_ANY and WAIT\_ALL, but ensures seamless integration with a fiber-mode
host.

6. All thread creation, aborts, and joins are host aware, and call out to the host
so they can ensure these events are processed correctly given an alternative scheduling
mechanism.

None of this logic kicks in if fibers are used underneath the CLR.  It all requires
close coordination between the host which is doing user-mode scheduling and the CLR
which is executing the code running on those fibers.  If you call into managed
code on a thread that was converted to a fiber, and then later switch fibers without
involvement w/ the CLR, things will break badly.  Our stack walks and exception
propagation will rely on the wrong fiber's stack, the GC will fail to find roots
for stacks that aren't live on threads, among many, many other things.

Important areas of the BCL and runtime that can introduce thread affinity, then make
a call that might block, and later release thread affinity—such as the acquisition
and release of an OS CRITICAL\_SECTION or Mutex—have been annotated with calls
to Thread.BeginThreadAffinity and Thread.EndThreadAffinity.  These APIs call
out to the host who maintains a recursion counter to track regions of affinity.
If a blocking operation happens inside such a region (i.e. count > 0), the host should
avoid rescheduling another fiber on the current thread and/or moving the current
fiber to another thread.  This can create CPU stalls, so we try to avoid it,
but is better than the consequence of ignoring the affinity.

In reality, there is little code today that actually uses these APIs.  Large
swaths of the .NET Framework have not yet been modified to use these calls and thus
remain unprotected.  We inherit a lot of the affinity problems from Win32.
This can have a dramatic impact on reliability and correctness when used in a fiber-mode
host.  Switching a fiber that has acquired OS thread affinity can result in
data being accidentally shared between units of work (like the ownership of a lock)
or movement of work to a separate thread (which then expects to find some TLS, but
is surprised when it isn't there).  Both are very bad.  If we were serious
about supporting fibers underneath managed code, we really ought to do an audit of
the libraries to find any dangerous unmarked P/Invokes or OS thread affinity.

Spin loops without going through the user-mode scheduler first potentially wastefully
burn CPU cycles.  A lot of the .NET Framework and some of the CLR itself spins
without host coordination.  While not disastrous, presuming they all fall back
to waiting eventually, this can have a negative impact on performance and scalability.

The 2.0 CLR's policy in response to stack overflow is to FailFast the whole process.
Too much of Win32 is unreliable in the face of overflow to try and continue running.
With fibers in the picture it might be attractive to reserve smaller stacks since
presumably the smaller work items will need less.  And you're apt
to have a lot more of them.  This is a dangerous game to play.  This trades
off some amount of committed memory for an increased chance of overflowing the stack,
an event that is clearly catastrophic.

Fibers and debuggers don't interact well today either.  Most rely on Win32
CONTEXTs pulled from the OS thread, in a fiber-unaware way.  Depending on the
frequency at which it resamples the context, this can get out of sync in the face
of fiber switches.  Even if you've suspended all threads, you'll not be
able to peer into the stacks of fibers that aren't currently scheduled.  FuncEval
and EnC also depend on thread suspension and coordination in a way that makes it
hard to predict will happen when fibers are added to the mix.  A lot of the
debugging libraries we have, such as System.Diagnostics, are also not fiber-aware
and may yield surprising answers to API calls.

In the end, remember that we decided to cut fiber support because of stress bugs.
Most of these stress bugs wouldn't have actually blocked the simple, short-running
scenarios, but would have plagued a long-running host like SQL Server.  The
ICLRTask::SwitchOut API was cut, which is unfortunate:  it means you can't
switch out a task while it is running, which effectively makes it impossible to build
a fiber-mode host on the 2.0 RTM CLR.  Thankfully, re-enabling it (for those
playing w/ SSCLI) would be a somewhat trivial exercise.

