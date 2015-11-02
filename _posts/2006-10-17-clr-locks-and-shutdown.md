---
layout: post
title: CLR locks and shutdown
date: 2006-10-17 12:42:42.000000000 -07:00
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
The CLR's approach to monitor acquisition (i.e. Monitor.Enter and Monitor.Exit) during
shutdown is very different from native CRITICAL\_SECTIONs and mutexes ( [as described
in my last post](http://www.bluebytesoftware.com/blog/PermaLink,guid,86195ce0-3e2d-4477-9739-896862c8c08d.aspx)).
In particular, the CLR does **not**  ensure requests to acquire monitors on
the shutdown path succeed, preferring instead to cope with the risk of deadlock rather
than the risk of broken state invariants.

Managed code is run during orderly shutdowns in two places: the AppDomain.ProcessExit
event and inside the Finalize method for all finalizable objects in the heap. (The
term "orderly shutdown" is used to distinguish an Environment.Exit from a P/Invoke
to kernel32!TerminateProcess, for instance.) Just as with the example described for
native code, threads can be suspended while they hold arbitrary locks and have partially
mutated state to the point where invariants do not hold any longer. Instead of permitting
the shutdown code to observe this state--possibly causing corruption or unhandled
exceptions on the finalizer thread--the CLR treats lock acquisitions as it normally
does.

If a lock was orphaned in the process of stopping all running threads, then, the
shutdown code path will fail to acquire the lock. If these acquisitions are done
with non-timeout (or long timeout) acquires, a hang will ensue. To cope with this
(and any other sort of hang that might happen), the CLR annoints a watchdog thread
to keep an eye on the finalizer thread. Although configurable, by default the CLR
will let finalizers run for 2 seconds before becoming impatient; if this timeout
is exceeded, the finalizer thread is stopped, and shutdown continues without draining
the rest of the finalizer queue.

This is typically not horrible since many finalizers are meant to cleanup intra-process
state that Windows will cleanup automatically anyway. This covers things like file
HANDLEs. But it does mean that any additional logic won't be run, like flushing file
write-buffers. And for any cross-process state, you're screwed and had better have
a fail-safe plan in place, like detecting corrupt machine-wide state and repairing
upon the next program restart. (For what it's worth, DLL\_PROCESS\_DETACH notifications
aren't run in all process exits either, so this really is not any worse than what
you have with native code today.)

AppDomain unloads are very different beasts. Any reliability-critical code that will
run as part of unload (CERs, critical finalizers, and generally any Cer.Success/Consistency.WillNotCorruptState
methods) should strictly only ever acquire locks that are always dealt with in a
reliable manner throughout the code-base. That statement is actually a little
too strong. In reality, either (1) locks must never be orphaned (aside from process
exit) or (2) the associated broken state invariants that will occur (e.g. in the
face of asynchronous exceptions) can be tolerated.

Unfortunately, we don't give you access to Monitor.ReliableEnter (the BCL team gets
to use it, though, as it's internal to mscorlib), which means almost nobody is equipped
to do (1) today. It's impossible to write code that will reliably release a monitor
in the face of possible asynchronous thread aborts and out of memory exceptions without
it. Only a very tiny fraction of the BCL actually deals with locks in such a strictly
reliable manner, so as a general rule of thumb very little of it actually acquires
and releases locks while executing reliable-critical code. Without the risk
of deadlock that is. Hosts will of course use policy to escalate to rude AppDomain
unloads in the face of hangs, much like the CLR does by default for process exit.

_(Note: Thanks to Jan Kotas--a SDE on the CLR team--for noticing that I confused
AppDomain unloads with process exit in my last post, in addition to pointing out
that appearances are deceiving: the multi-threaded CRT_ can _actually suffer from
the sort of shutdown problems outlined in the last post.)_

