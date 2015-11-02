---
layout: post
title: On the imperfect nature of reader/writer lock policies
date: 2007-03-29 01:15:41.000000000 -07:00
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
One of the motivations of [doing a new reader/writer lock in Orcas](http://www.bluebytesoftware.com/blog/PermaLink,guid,c4ea3d6d-190a-48f8-a677-44a438d8386b.aspx)
(ReaderWriterLockSlim) was to do away with one particular scalability issue
that customers commonly experienced with the old V1.1 reader/writer lock type ( [ReaderWriterLock](http://msdn2.microsoft.com/en-us/library/system.threading.readerwriterlock.aspx)).
The basic issue stems from exactly how the lock decides when (or in this case, when
not) to wake up waking writers.  Jeff Richter's [MSDN article from June of
last year](http://msdn.microsoft.com/msdnmag/issues/06/06/ConcurrentAffairs/) highlights
this problem.  This of course wasn't _the_ primary motivation, but it was just
another straw hanging off the camel's back.

Contrast some choice behavior exhibited by the two lock types:

- Both ReaderWriterLock and ReaderWriterLockSlim will block new readers from acquiring
the lock as soon as a writer begins waiting to enter.  That means that as soon
as all active readers exit the lock, the writer will be awoken and allowed to enter
the lock.  (For all intents and purposes, by the way we treat upgrade and
write locks the same.)

- When a write lock is released, the ReaderWriterLock type will wake up all waiting
readers, even if there are waiting writers.  Again, new readers are blocked
and once this awoken batch of read locks exit the lock again, the next writer in
line is awoken.

- When a write lock is released, the ReaderWriterLockSlim type will wake up a waiting
writer instead of readers.  Readers may only proceed once there are no longer
any waiting writers.

These last two points illustrate the basic issue with the old lock.  (And the
new one, too, to be brutally honest.)  If a large number of writers is
waiting to enter the ReaderWriterLock, each will be staggered by the amount of time
it takes for all intervening readers to enter the lock, do their work, and exit.
This can send the wait time for writers through the roof.

To further illustrate the point, imagine we have two writers (W0 and W1) and two
readers (R0 and R1), each of which enters the lock, does some work for 1 unit of
time, exits, and then goes back around and tries to acquire the lock again:

```
Thread  Arrival  Enter  Exit
======= ======== ====== ======
W0      0        0      1
W1      0        3      4
R0      0        1      2
R1      0        1      2
W0      1        5      6
W1      4        8      9
R0      2        4      5
R1      2        4      5
...
R0      5        6      7
R1      5        6      7
```

Notice that the writers have to wait for a very long time to be serviced in comparison
to the readers.  If more and more writers show up, this problem becomes magnified,
regardless of how many readers there are or the ratio of readers to writers.

The new lock doesn't suffer from this same problem.  But it does suffer from
a different one: possible starvation of readers if there is always a writer arriving
or waiting at the lock.  As Jeff mentions in his MSDN article, most reader/writer
locks work best when the ratio of reads to writes is high.  In the above example,
though, the readers actually would never get to enter the lock:

```
Thread  Arrival  Enter  Exit
======= ======== ====== ======
W0      0        0      1
W1      0        1      2
R0      0        ??      ??
R1      0        ??      ??
W0      1        2      3
W1      2        3      4
...
W0      3        4      5
W1      4        5      6
```

So which is better?  If writers are less frequent in your scenario -- as they
usually are -- then the new lock will probably fit the bill.  If not, you might
run into troubles with the new one.

We had originally planned to allow you to configure the contention policy.
In fact, if you picked up an earlier Orcas CTP, you probably noticed the ReaderWriterLockSlim
constructor that took an enumeration value specifying the contention policy: PrefersReaders,
PrefersWritersAndUpgrades, and Fifo.  This simply added too much complexity
for the short timeframe of the Orcas release, so it recently silently disappeared.

Though it's the hardest to implement, I do think FIFO (or some heuristic approximation
thereof) is the right answer here.  Block new readers once a writer begins
waiting.  When the last reader exits, wake up the waiting writer.  When
the writer exits, wake up the next _n_ contiguous waiting readers (all readers between
the exiting writer and the next writer in the wait queue, if any) or the next writer
(if the writer is next in the wait queue).  Or, as noted, some approximation
of this logic, since it could be fairly costly to orchestrate all the bookeeping,
particularly the event waiting and signaling.  But a FIFO-like ordering ensures
some strong correlation between arrival time and relative wait time, which, I think,
is what most people expect and desire.  There are of course [convoy problems
that can happen when strict FIFO ordering is used](http://www.bluebytesoftware.com/blog/PermaLink,guid,e40c2675-43a3-410f-8f85-616ef7b031aa.aspx),
so I would expect we would still allow (some) arriving requests to pass others in
line.

This last suggestion is actually quite similar to what the new SRWLOCK in Vista does.
ReleaseSRWLockShared and ReleaseSRWLockExclusive signal the next threads in line
based on a wait queue structure, without any sort of "prefers readers over writers"
(or vice versa) policy.  But that's a topic for a separate day.

