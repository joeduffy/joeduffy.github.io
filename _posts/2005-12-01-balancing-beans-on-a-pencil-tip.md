---
layout: post
title: Balancing beans on a pencil tip
date: 2005-12-01 23:30:04.000000000 -08:00
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
Lots of people try to roll their own thread-pool. Many people have different
(good) reasons for doing so.

If you're one of these people, please tell me why. Either leave me a comment or
send me an email at [joedu@microsoft.com](mailto:joedu@microsoft.com).

But if you're interested in performance, getting a good heuristic isn't as easy
as you might think. The goal of such a heuristic is to have one runnable thread
per hardware thread at any given moment. (A HT thread isn't equal to a full
thread, but for sake of conversation let's pretend it is.) Acheiving this goal
is much more complicated than it sounds.

- If you have a task sitting in front of you, it's hard to intelligently
  determine whether scheduling it on another thread is the right thing to do.
It might be quicker just to execute it synchronously on the current thread.
When is that the case? When the current number of running threads is equal to
or greater than the number of hardware threads. And any decisions must be made
statistically, because presumably concurrent tasks could be contemplating new
work simultaneously.

- Remember I said _running_ threads. If you have blocked threads, they are not
  making use of the CPU and thus need to be be considered differently in the
heuristic. Just a count of threads isn't enough. If you have 16 tasks, 8
hardware threads, and statistically 50% of those tasks will be blocked at any
given quantum, you want 16 real threads. If they block 75% of the time, you
want 24. And so forth.

- You aren't the only code on the machine. Another process could be happily
  hogging as many threads as there are hardware threads, in which case your
algorithm just got twice as bad (or half as good) as it was originally. This
type of global data is hard to come by. (I should note that most machines have
more than 2 processes running simultaneously. I currently have 67 processes
running with 605 total threads. That's an average of ~9 threads per process.
Clearly this is a real concern.)

Scheduling a task on another thread is costly. Why? For a number of reasons.

- Because unless you have ample hardware resources to run it, this implies at
  least one context switch to swap the work in. If it runs longer than that, it
means many more. If you have more than one long running tasks competing for the
same hardware thread, it means they will continually thrash the thread context
in an attempt to make forward progress. As [Larry puts it so
eloquently](http://blogs.msdn.com/larryosterman/archive/2005/01/05/347314.aspx),
"_...Context switches are BAD. They represent CPU time that the application
could be spending on working for the customer._"

- And not only that (and perhaps worse), you're going to mess with the cache
  hierarchy. Your program might be happily working on conflict-free
cache-lines, CASing right in the local cache without locking the bus, and then
boom: You pass a pointer to an object to another thread (e.g. on the
thread-pool), it pulls in the same lines of cache, and then you're both
contending for the same lines back and forth. Your good locality goes right out
the window and becomes a tax instead of a blessing. This sort of cache
thrashing can kill good performance and scaling.

- Lastly, threads aren't free you know. Just having one around consumes 1MB of
  reserved stack space (0.5MB in SQL Server). Same goes for fibers.

Some people are interested in using thread-pools for other purposes. (That, is:
not performance.) They might want to manage a pool of work items, for example,
which get scheduled fairly with respect to each other (in the fine-grained
sense). No one task will complete very quickly during saturation, but at least
each is guaranteed to move forward. A newly enqueued item won't sit festering
in the queue while an older item continues bumbling along towards its goal. And
sometimes, priorities must be used to evict lesser priority tasks when a higher
priority task gets enqueued. These are all perfect cases where user-mode
scheduling makes sense. Co-routines or (\*cough, cough\*) _perhaps _fibers
could be used. Using threads for this simply adds way too much overhead.

Clearly getting this right is difficult. But the consequence of getting it
horribly wrong _today _isn't too bad. (Although really crappy algorithms are
noticeable.) When you only have 1-4 hardware threads on the average high-end
machine, the difference between a great heuristic and a poor one isn't
significant. That will change.

