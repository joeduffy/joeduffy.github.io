---
layout: post
title: 'EventWaitHandle and Monitors: how to pick one?'
date: 2006-11-01 20:26:26.000000000 -07:00
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
People often ask whether they should use EventWaitHandle objects or the Monitor.Wait,
Pulse, and PulseAll methods for synchronization.  There is no simple answer
to this question; although, as with most software problems, it can be summarized
as:  It depends.

EventWaitHandle comes in two flavors, auto- and manual-reset.  EventWaitHandle
subclasses WaitHandle and offers two subclasses for convenience: AutoResetEvent and
ManualResetEvent.  These are just thin wrappers on top of the CreateEvent and
related APIs in Win32.  The differences are deceivingly simple.

Auto-reset, when signaled with the EventWaitHandle.Set API (kernel32!SetEvent
internally), allows one thread to witness the signal before the event automatically
transitions back to the unsignaled state.  If there are any waiting threads,
one will be chosen and unblocked.  The waiting threads are maintained in a FIFO
queue, but it's not strictly FIFO for the same reasons very few things on Windows
are FIFO: various events, like device IO completion, kernel-, and user-mode APCs
can wake a thread temporarily, removing it and then requeuing it in the wait queue.
If a thread is constantly woken to process device IO, it might be starved indefinitely
(if the queue is long).  If no threads were waiting at the time of this signal,
the next thread to wait on the event will not block, and instead just moves the event
back to the unsignaled state and returns.  This is all done atomically so you
are guaranteed only one thread will ever witness a signal.

Manual-reset, when signaled, wakes all threads that are waiting on it.  As its
name implies, it must be manually reset with the EventWaitHandle.Reset API (kernel32!ResetEvent
internally).  While the event remains signaled, any threads that try to wait
on it will not block and just return from the wait function immediately.

Signaling an already-signaled event has no effect.  It's easy to get into
trouble in this area with auto-reset events.  If you signal the event N times,
expecting N threads to see the signals and do some amount of processing, you're
betting the farm on a race condition, for instance.  This is easy to get wrong,
very easily leading to deadlocks.  If you have a shared buffer, an attractive
design might to simply call Set on the event each time a new item arrives.
The thinking might be that, while threads might not be sleeping, at least one thread
will wake up per item and process it.  This thinking is dead wrong and
can get you into a quagmire.  The waking threads would need to contain a loop
'while (!empty) { … }' before going back to sleep, otherwise one of the signals
may go missing.  If production of new items depended on consumers making forward
progress, the program might lock up.  And it entirely depends on consumers going
to sleep in the first place which, if producers typically produce faster than consumers,
might only happen occassionally (and hence not show up during testing).

Monitor.Wait, Pulse, and PulseAll are very different from their close Win32 event
cousins.  They are much more akin to the new Windows Vista APIs, SleepConditionVariableCS
and SleepConditionVariableSRW.  Wait will exit the monitor (lock) for the object
in question until another thread pulses the object.  Once the thread wakes up,
it immediately reacquires the lock on the object.  Pulse wakes up one waiting
thread, in FIFO order, while PulseAll wakes all waiting threads.  Notice that
the monitor has no residual effect from the pulse; that is, if no threads were waiting
at the exact moment of a pulse, there is no evidence that it actually happened.
This leads to the notorious missed-pulse problem.  To solve it, you just have
to ensure that the wait condition is always tested (in a loop) around the Wait.

Note that Wait does something a little dirty.  It releases an arbitrary amount
of recursive acquisitions.  As soon as it does this, other threads can acquire
the monitor.  If you are not careful with recursion, you can end up Waiting
with broken invariants, accidentally letting other threads peer into this state.
This is just another bit of evidence that recursion is something that is best avoided.

The first major consideration to make when selecting between EventWaitHandle and
Monitor's methods is whether you need a stand-alone event or a real condition variable
that is integrated with locks.  That is, the two have very distinct and disjoint
feature sets.  Win32 events also let you do more sophisticated waits, with the
WaitHandle.WaitAll or WaitAny APIs, allowing you to wait for all of the events or
a single event in an array to be signaled.  So which feature-set do you want?
That Win32 events give you events without the synchronization looks simpler, but
is probably misleading.  You typically need to manage mutual exclusion in some
way with events, too, so you'll end up using a monitor, ReaderWriterLock, Mutex,
etc. in addition.  The one benefit is that you have more control over locking
and can be more conscious of certain policies like recursion.  The fact that
a Win32 event "sticks" in the signaled state can also be useful to avoid the
missed-pulse problem, although with some discipline it is easily avoided with monitors
too.  Often people end up building a sticky event with a bool and monitor pair.
One-time or lazy initialization is an example of this.

Win32 events are fairly heavyweight too.  Each one consumes some amount of kernel
memory, and setting, resetting, and waiting on one incurs somewhat expensive kernel
transitions.  In managed code, simply allocating one increases pressure on the
GC because of yet another finalizable object to track.  In a well-tuned system,
you have to manage events carefully, which usually means Disposing of them far before
the GC's finalizer thread has a chance to see one.  Even cleverer systems
will pool them to amortize the cost of creating and closing the events.  This
is a double-edged sword.  The V1.1 ReaderWriterLock we shipped in the CLR pools
events.  In my opinion, this is a little too clever and myopic: a good solution
would pool events across many components in the process, not just ReaderWriterLocks.
Imagine if each type we shipped tried to maintain its own pool of events.

As you may have guessed, Monitor actually uses Windows events underneath it all.
Each CLR thread has a manual-reset event, allocated when it is created (or lazily
when the thread first wanders into managed code).  When a Wait is issued, this
per-thread event is stuck on the tail of a linked list associated with the target
object's sync block.  We can use a single event per thread since a thread
can only ever be waiting for a single object at a given time.  (You can't
do a WAIT\_ANY or WAIT\_ALL on monitors.)  The thread then releases the lock
on the object (accounting for any recursion), waits on this event, and then reacquires
the lock on the object (again, accounting for any recursion).  When a Pulse
is issued, the head of the object's linked list of waiters is popped off and its
associated event is signaled.  Similarly, PulseAll clears the entire linked
list and signals all of the events.  Notice I said that Pulse operates on the
head of the list: we use a strict FIFO ordering (as of 2.0).  And since we don't
remove the list entries in the face of an APC, there is no risk of perturbing the
FIFO ordering, aside from premature exits due to thread aborts or interruptions.

There are a few things to note about this.

The signals on the thread events happen while the signaler still owns the lock.
In other words, the thread calling Pulse(o) will still own the lock on o for some
time after the call, yet the thread that called Wait(o) will immediately wake after
the Pulse and try to acquire this lock (failing and waiting).  Yes, all woken
threads have to immediately wait when attempting to reacquire this lock, which is
actually pretty crappy.  If you're using PulseAll, this could have a noticeable
(and in some cases, dramatic) impact on scalability.  Windows uses priority
boosts to "hand off" the current time-slice to the recipient of an event signal,
similar to what occurs when a GUI event is enqueued into a thread's message queue,
which just exacerbates this effect.  You're just about guaranteed that there
will be a scheduler ping-pong effect immediately after a pulse.  I am honestly
surprised we don't enqueue the Pulse/PulseAll calls on the object's sync-block,
processing them only once the lock has been exited.  Yet another benefit to
using events is that you can devise algorithms that signal events outside of critical
sections, often leading to improved scalability.

We also don't do any form of spinning.  Events are generally speaking very
volatile in terms of timing, so spinning only buys you something if you know that
the occurrence of events are frequent enough that wait-avoidance will pay off.
In many low-level concurrent algorithms, this is a worth-while technique, just as
with spinning while trying to acquire a CRITICAL\_SECTION in Win32 (see InitializeCriticalSectionWithSpinCount
and SetCriticalSectionSpinCount) can improve scalability by avoiding expensive kernel-mode
transitions due to waiting.  In fact, it's conceivable that somebody would
want to use an event that never did a real wait, particularly if you're dealing
with a very tiny race condition that is expected to arise very infrequently.
This is also dangerous, however, as it can lead to those rare CPU spikes that are
almost impossible to debug and discern from a crash dump.  This is pretty simple
to build, but very hard to fine-tune so that it performs adequately.

So in the end, I will simply fall back to my original answer:  It depends.

