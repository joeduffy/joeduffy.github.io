---
layout: post
title: RegisterWaitForSingleObject and mutexes don't mix
date: 2007-05-13 20:09:37.000000000 -07:00
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
Everybody's probably aware of the RegisterWaitForSingleObject method: it exists
in the native and CLR thread pools, and does pretty much the same thing in both.
(It's called CreateThreadpoolWait and SetThreadpoolWait in Vista.)  This feature
allows you to consolidate a bunch of waits onto dedicated thread pool wait threads.
Each such thread waits on up to 63 registered objects using a wait-any-style WaitForMultipleObjects.
When any of the objects become signaled, or a timeout occurs, the wait thread
just wakes up and queues a callback to run on the normal thread pool work queue.
Then it updates timeouts and possibly removes the object from its wait set, and then
goes right back to waiting.

This is great.  Fewer threads, more overlapped waiting, better performance.
If you wait on 1,024 objects, you only need 17 threads instead of 1,024.  Not
only do you end up with fewer threads, but your program can actually handle the case
where all 1,024 objects become signaled at once, because the thread pool throttles
the number of threads that can run callbacks.

But you really don't want to register a wait for a mutex.  If you stop to
think about it for a moment, the reason will become clear.  It just doesn't
make any sense with the architecture I just explained.

The pool's wait threads are the ones that do the actual waits.  And when a
wait for a mutex is satisfied, the thread which performed the wait now owns the mutex.
Uh oh.  In our case that means the wait thread owns the mutex.  But all
the wait thread knows how to do is wait on stuff and queue callbacks.  There
are two problems here.

The first problem is that the thread which will run the callback lives in the thread
pool's worker queue, and doesn't actually own the mutex.  Which means it
can't actually release the mutex either.  In fact, nobody really can, except
for the wait thread that performed the wait, but remember all that thread knows how
to do is wait on stuff and queue callbacks.  A mutex?  What the heck is
that?  Eventually the wait thread may exit and the mutex may become abandoned,
but whether this actually happens depends on the ebb and flow of wait registrations.

(With the Win32 thread pool, you can specify the WT\_EXECUTEINWAITTHREAD flag during
registration, which ensures the callback is run in the wait thread itself and not
queued to worker thread.  While this can suffice as a workaround to this problem,
it's generally a bad practice to hold up the wait thread from doing its job.
And there is no equivalent in Vista or with the CLR thread pool.)

The second problem may or may not surface depending on whether you've specified
that the wait callback should execute only once.  If the callback executes only
once, the thread pool will remove it from its wait set after waking up once.
Otherwise, it keeps it in the wait set and goes back to waiting on it right after
queuing the callback.  Here are the "only once" defaults for the Vista, legacy,
and CLR pools: yes in Windows Vista (and no way to specify otherwise, other than
reregistering manually), no in the legacy Win32 pool (unless the WT\_EXECUTEONLYONCE
flag is passed during registration), and you always have to specify in managed code
with the executeOnlyOnce argument.

So what's the problem?  Because mutexes allow recursive acquires, then if the
callback is set to execute multiple times, the wait thread will simply go back and
wait on all of its objects, including the mutex, after it queues a callback.
The same thing that happens with a persistent signal object like a manual-reset event
now happens.  Each time the wait thread tries to wait, the acquisition
of the mutex immediately succeeds, incrementing its recursion counter by one, and
each time causing the wait thread to queue yet another callback.  Ouch.
The insanity never stops:

```
Mutex m = new Mutex();
m.WaitOne();
ThreadPool.RegisterWaitForSingleObject(
    m, delegate { Console.WriteLine("The insanity!"); }, null, -1, false);
m.ReleaseMutex();
```

The moral of the story?  Nothing terribly deep.  Thread affinity strikes
once again.

