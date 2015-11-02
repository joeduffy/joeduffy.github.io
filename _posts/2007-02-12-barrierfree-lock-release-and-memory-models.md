---
layout: post
title: Barrier-free lock release and memory models
date: 2007-02-12 13:22:09.000000000 -08:00
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
Somebody [recently asked in a blog comment](http://www.bluebytesoftware.com/blog/CommentView,guid,c4ea3d6d-190a-48f8-a677-44a438d8386b.aspx)
whether the new [ReaderWriterLockSlim](http://www.bluebytesoftware.com/blog/PermaLink,guid,c4ea3d6d-190a-48f8-a677-44a438d8386b.aspx)
uses a full barrier (a.k.a. two-way fence, CMPXCHG, etc.) on lock exit.  It
does, and I claimed that "it has to".  It turns out that my statement was actually
too strong.  Doing so prevents a certain class of potentially surprising results,
so it's a matter of preference to the lock designer whether these results are so
surprising as to incur the cost of a full barrier.  Vance Morrison's ["low lock"
article](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/), for instance,
shows a spin lock that doesn't make this guarantee.  And, FWIW, this is also
left unspecified in the CLR 2.0 memory model.  [Java's memory model](http://www.cs.umd.edu/~pugh/java/memoryModel/jsr133.pdf)
permits non-barrier lock releases, though I will also note the JMM is substantially
weaker in areas when compared to the CLR's.

Here's an example of a possibly surprising result that non-barrier releases can cause:

Initially _x == y == 0_.

```
Thread 0        Thread 1
=============== ===============
lock(A);        lock(B);
x = 1;          y = 1;
unlock(A);      unlock(B);
t0 = y;         t1 = x;
```

Is it possible after executing both that: _t0 == t1 == 0_?

It is simple to reason that this is impossible with sequential consistency.
In SC the only way that _t0 == 0_ is if Thread 0's _t0 = y_ statement (and therefore
_x = 1_, assuming a memory model in which writes happen in order) were to occur before
Thread 1's _y = 1_ (and therefore _t1 = x_).  In this case, _t1 = x_ must subsequently
see _t1 == x == 1_, otherwise the history contradicts SC.  The only other possibility
is that Thread 1's _t1 = x_ happens before Thread 0's _x = 1_ and therefore also
_t0 = y_, in which case it must be the case that the subsequent _t0 = y_ by Thread
0 yields _t0 == y == 1_.  In both cases, either _x_ or _y_ must be seen
as 1.  (Interleavings are clearly possible that result in _x == y == 1_.)

The CLR 2.0's memory model guarantees that, if the unlock incurs a barrier,
the same SC reasoning applies.  Unfortunately, if the unlock is not a barrer,
then in both cases the load of _x_ or _y_ may occur before the write buffer has been
flushed, meaning the write to _x_ or _y_ and the unlocking write itself, possibly
leading to _t0 == t1 == 0_.  This happens even on relatively strong processor
consistency memory models such as X86, and on weaker ones such as IA-64 (even when
all loads are acquire and all stores are release, which only happens for volatile
CLR fields).  To ensure the write buffer has been flushed before the read happens,
the unlock statement must flush the buffer (or an explicit barrier is needed), accomplished
with CMPXCHG on X86 ISAs.

Many would argue that, because the locks taken are different between the two threads,
SC does not apply and therefore implementing unlock as a non-barrier write is legal.
JMM takes this stance.  This actually seems like a fine argument to me, and
after thinking about it for a bit, it's probably what I would choose if I were defining
a memory model.  But the CLR 2.0 MM is generally stronger than most, so people
might actually depend on this and expect it to work.  This could cause Monitor-based
code to break when moved to alternative lock implementations that don't issue full
barriers at release time.  This is just one example of why it'd be really great
to have a canonical specification for the CLR's MM.  At least we'd then have
a leg to stand on when faced with tricky compatability trade-offs some day down the
line.

