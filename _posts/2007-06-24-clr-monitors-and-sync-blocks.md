---
layout: post
title: CLR monitors and sync blocks
date: 2007-06-24 12:14:35.000000000 -07:00
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
In response to [a previous post](http://www.bluebytesoftware.com/blog/CommentView,guid,a2787ef6-ade6-4818-846a-2b2fd8bb752b.aspx),
a reader said

> _"I was under the impression that monitors were implemented in .NET in a multiplexed
way, so that events are only allocated to an object while there is contention - and
that they aren't "sticky", becoming permanently attached to the object."_

This is absolutely correct.  My nulling out of the object reference in the example
only has the slight advantage of promoting the object's collection sooner, but
it _does not_ have the effect of speeding up the reclamation of the internally managed
monitor state.  My original posting erroneously said that it would.

Let's take a quick step back, and see exactly what this means.

[Monitors](http://citeseer.ist.psu.edu/169759.html) are comprised of two capabilities:
_critical regions_ (i.e. Monitor.Enter and Exit), to achieve mutual exclusion, and
_condition variables_ (i.e. Monitor.Wait, Pulse, and PulseAll), to coordinate between
threads.  Any CLR object can be used as a monitor.

For the critical region case, the CLR uses an efficient _thin lock_ which simply
embeds locking information as a bit pattern inside the object's header word.
Other parts of the system also try to use the header, e.g. when caching an object's
default hash-code, COM interop, etc.  There are limits to what can be stored
in the header, so use of any two of these things simultaneously causes _inflation_,
meaning the object header's contents become an index into a table of _sync blocks_.
Sync blocks are just little data structures capable of holding all of that state
simultaneously.  The CLR manages a system-wide table of them and recycles and
reuses them as objects need them.  Another event that causes inflation is the
first occasion on which a thread tries to enter the critical region while another
thread holds it (i.e. _contention_).

When contention arises, the CLR will spin briefly before truly waiting, but it may
eventually need to allocate a Windows kernel event object.  This is an auto-reset
(synchronization) event, and a handle to it gets stored on the sync block.
Waiting threads just wait on it, and threads exiting the critical region will set
it (if the wait count is non-zero).  Note that this leads to unfair behavior,
because threads can steal the critical region between the signal and the wake-up, but
[helps to prevent convoys](http://www.bluebytesoftware.com/blog/PermaLink,guid,e40c2675-43a3-410f-8f85-616ef7b031aa.aspx).

Condition variables are implemented slightly differently.  Each CLR thread object
has a single event object dedicated to it.  The first time a thread calls Wait
on a condition variable, the event is lazily allocated.  And then the thread
simply places its own thread-local event into a list of events associated with the
monitor.  Registering the event also requires inflation to a sync block, if
it hasn't happened already, because obviously the event list can't be stored
in the object header.  When a Pulse happens, the pulsing thread just signals
the first event in the list.  Waiting and pulsing is thus actually somewhat
fair, but there are other races that can eliminate this that I won't get into.
When a PulseAll occurs, the pulsing thread walks the whole list and signals each.

So now back to the question: when are sync blocks reclaimed?

When a GC is triggered, objects in the reachability traversal may have their sync
blocks reclaimed, even if the object in question is still alive, and made available
again in the system-wide pool of reusable sync blocks.  This reclamation can
happen so long as the sync block isn't needed permanently (as would be the case
if COM interop information was stored inside of it) and the sync block isn't marked
_precious_.  A sync block is precious anytime there is a thread inside of the
object's critical region, when a thread is waiting to enter the critical region,
or when at least one thread has registered its event into the associated condition
variable list.  Notice that orphaning monitors can thus lead to leaking events,
because they will remain precious, unless the monitor object itself becomes unreachable.
When a sync block is reclaimed in this fashion, certain reusable state is kept, like
the critical region event object, so that the next monitor to use the sync block
can reuse it.

