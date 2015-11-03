---
layout: post
title: Volatile reads and writes, and timeliness
date: 2008-06-13 12:52:45.000000000 -07:00
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
We had an interesting debate at a Parallel Extensions design meeting yesterday, where
I tried to convince everybody that a full fence on SpinLock exit is not a requirement.
We currently offer an Exit(bool) overload that accepts a flushReleaseWrite argument.
This merely changes the lock release from

```
m_state = 0;
```

to

```
Interlocked.Exchange(ref m_state, 0);
```

The main purpose of this is to announce "availability" of the locks to other
processors.  More specifically, it ensures that before the current processor
is able to turn around and reacquire the lock in its own private cache, that other
processors at least have the opportunity to see the write.  This is a fairness
optimization, and avoiding the CAS on release halves the number of CAS operations
necessary (which are expensive), so we would generally like to avoid superflous ones.
It turns out you could easily do this without our help.  Instead of

```
slock.Exit(true);
```

you could say

```
slock.Exit();
Thread.MemoryBarrier();
```

Most of the debate about whether the default Exit should use a fence centered around
confusion over the strength of volatile vs. a full fence.  For example, the
C# documentation for volatile is highly misleading ([http://msdn.microsoft.com/en-us/library/x13ttww7(VS.71).aspx](http://msdn.microsoft.com/en-us/library/x13ttww7(VS.71).aspx)):

> _The volatile modifier is usually used for a field that is accessed by multiple
> threads without using the lock statement to serialize access. Using the volatile
> modifier _ensures that one thread retrieves the most up-to-date value written by
> another thread_. 

The confusion is over the "ensures that one thread receives the most up-to-date
value written by another thread" part.  Technically this is somewhat-accurate,
but is worded in a very funny and misleading way.  To see why, let's take
a step back and consider what volatile actually means in the CLR's memory model
(MM) for a moment, to set context.  Note that I did my best to concisely summarize
the MM here: [http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx](http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx).

Volatile on loads means ACQUIRE, no more, no less.  (There are additional compiler
optimization restrictions, of course, like not allowing hoisting outside of
loops, but let's focus on the MM aspects for now.)  The standard definition
of ACQUIRE is that subsequent memory operations may not move before the ACQUIRE instruction;
e.g. given { ld.acq X, ld Y }, the ld Y cannot occur before ld.acq X.  However,
previous memory operations can certainly move after it; e.g. given { ld X, ld.acq
Y }, the ld.acq Y can indeed occur before the ld X.  The only processor Microsoft
.NET code currently runs on for which this actually occurs is IA64, but this is a
notable area where CLR's MM is weaker than most machines.  Next, all stores
on .NET are RELEASE (regardless of volatile, i.e. volatile is a no-op in terms of
jitted code).  The standard definition of RELEASE is that previous memory operations
may not move after a RELEASE operation; e.g. given { st X, st.rel Y }, the st.rel
Y cannot occur before st X.  However, subsequent memory operations can indeed
move before it; e.g. given { st.rel X, ld Y }, the ld Y can move before st.rel X.
(I used a load since .NET stores are all release.)  Note that RELEASe is the
opposite of ACQUIRE: you can think of an acquire as a one-way fence that prohibits
passes downward, and a release as a one-way fence that prohibits passes upward.
A full fence prohibits both (lock acquire, XCHG, MB, etc).

Note one very interesting thing in this discussion: a release followed by an acquire,
given the above rules, does not prohibit movement of the instructions with respect
to one another!  Given { st.rel X, ld.acq Y }, even though they are both volatile
(i.e. acquire and release), so long as X!=Y, it is perfectly legal for the ld.acq
Y to move before st.rel X.  We aren't limited to single instructions either,
e.g. { st.rel X, ld.acq A, ld.acq B, ld.acq C }, all three loads (A, B, C) may indeed
happen before the X.  This occurs with regularity in practice, on X86, X64,
and IA64, because of store buffering.  It would just be too costly to hold up
loads until a store has reached all processors.  Superscalar execution is meant
to hide such latencies.

(As an aside, many people wonder about the difference between loads and stores of
variables marked as volatile and calls to Thread.VolatileRead and Thread.VolatileWrite.
The difference is that the former APIs are implemented stronger than the jitted code:
they achieve acquire/release semantics by emitting full fences on the right side.
The APIs are more expensive to call too, but at least allow you to decide on a callsite-by-callsite
basis which individual loads and stores need the MM guarantees.)

I have to admit the store buffer problem is mostly theoretical.  It rarely comes
up in practice.  That said, on a system which permits load reordering, imagine:

```
Initially: X = Y = 0

T0                          T1
=====                       =====
X = 5; // st.rel            while (X == 0); // ld.acq
while (Y == 0) ; // ld      X = 0; // st.rel
A = X; // ld.acq            Y = 5; // st.rel
```

After execution, is it possible that A == 5?

If the read of Y is non-volatile on T0 (which would be bad because a compiler may
hoist it out of the loop, but ignore compilers for a moment), then the fact that
the subsequent read of X is volatile does not save us from a reordering leading to
A == 5.  This is the { ld, ld.acq } case described earlier.  Why might
this physically occur?  Well, it won't happen on X86 and X64 because loads
are not permitted to reorder.  However!!  IA64 permits non-acquire loads
(non-volatile) to reorder, and so the A = X may actually be satisfied out of the
write buffer before the store even leaves the processor.  It's as though the
program became:

```
T0                          T1
=====                       =====
X = 5; // st.rel            while (X == 0) ; // ld.acq
A = X; // ld.acq            X = 0; // st.rel
while (Y == 0) ; // ld      Y = 5; // st.rel
```

Whoops!  This should make it apparent that this outcome is indeed a real possibility.
And clearly it may cause bugs.

_Note 6/13/08: [Eric](http://blogs.msdn.com/ericeil/) pointed out privately that
compilers need only respect the CLR MM, and can freely reorder loads.  Thus,
this problem may actually arise on non-IA64 machines.  He is correct._

All that said, let's get back to the original concern about visibility of writes.
This issue doesn't even really involve reordering.  Imagine one processor
continuously executes a stream of lock acquires and releases, and that the stream
goes on indefinitely (perhaps because it's in a loop):

```
while (Interlocked.CompareExchange(ref m_state, 1, 0) != 0) ;
m_state = 0;
while (Interlocked.CompareExchange(ref m_state, 1, 0) != 0) ;
m_state = 0;
...
```

The Interlocked operation acquires the cache line in X mode.  After it executes,
other processors will notice that the lock is taken.  But right away, the processor
writes 0 to the line without a fence, and immediately goes on to execute another
acquire.  It is highly likely that the line will be marked dirty in the processor's
cache by the time that it acquires it in X mode again, something that the cache coherency
system makes very cheap.  In fact, the write of m\_state = 0 probably hasn't
left the write buffer yet due to latency.

So before another processor can even see m\_state as 0, the processor will have already
gotten around to taking the lock again.  Even for volatile loads and stores,
there is no MM guarantee that writes will leave the processor immediately; hence
the documentaiton earlier is slightly confusing; yes, the processor doing a volatile
read will see the "most recent" value, but that "most recent" value (a) may
be satisfied out of the local write buffer, and (b) may simply not have the ability
to observe writes that occurred in practice due to the above timeliness issue.

