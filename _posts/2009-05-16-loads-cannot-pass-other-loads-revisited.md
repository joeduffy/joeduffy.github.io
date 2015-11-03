---
layout: post
title: Loads cannot pass other loads, revisited
date: 2009-05-16 22:31:07.000000000 -07:00
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
A while back, [I made a big stink](http://www.bluebytesoftware.com/blog/2008/07/17/LoadsCannotPassOtherLoadsIsAMyth.aspx)
about what appeared to be the presence of illegal load-load reorderings in Intel's
IA32 memory model.  They specifically claim this is impossible in their documentation.
Well, last week I was chatting with a colleague, [Sebastian Burckhardt](http://research.microsoft.com/en-us/people/sburckha/),
about this disturbing fact.  And it turned out he had recently written a paper
that formalizes the CLR 2.0 memory model, and in fact treats this phenomenon with
a great deal of rigor:

> **Verifying Compiler Transformations for Concurrent Programs**
> [http://research.microsoft.com/pubs/76524/tr-2008-171-latest-03-11-09.pdf](http://research.microsoft.com/pubs/76524/tr-2008-171-latest-03-11-09.pdf)

To jog your memory, the problematic example is

```
X = 1;
r0 = X;
r1 = Y;
```

where both X and Y are shared memory locations, and r0 and r1 are processor registers.
According to Intel's IA32 memory model, two loads to different locations cannot reorder.
But it is completely possible for the load of X to be satisfied out of the store
buffer, and for r1=Y to pass the store (thereby also passing the load r0=X).
This is a standard Dekker reordering, but the usual example consists of just { X
= 1; r1 = Y }.

The key to modeling this is to turn an adjacent store-load affecting the same location
into a single instruction.  Therefore, the above becomes something like:

```
r0 = 1;
X = r0;
r1 = Y;
```

Now it becomes entirely clear what has gone wrong.  I have yet to see a clear
description of this phenomenon, but Sebastian's paper does a great job.

During the discussion, Sebastian showed me another disturbing four processor example:

```
P0          P1          P2          P3
==          ==          ==          ==
X = 1;      r0 = X;     Y = 1;      s0 = X;
            r1 = Y;                 s1 = Y;
```

Is it possible, after all four processors complete, that { r0 == 1, r1 == 0 } and
{ s0 == 0, s1 == 1 }?  This seems ridiculous, given a memory model where loads
cannot reorder.  It seems that no serializable execution should lead to this.
But let's look at one problematic interleaving.  First, we merge the instruction
stream on P0 with P1, and also P2 with P3.  This effect could occur if these
writes are in functions that end up running on the same processor, or running on
a machine that shares functional units (like hyperthreading), hierarchies that share
a cache, and so on.  We end up with:

```
P0/P1       P2/P3
=====       =====
X = 1       Y = 1;
r0 = X;     s0 = X;
r1 = Y;     s1 = Y;
```

Now let's permute these with the new rule introduced above in mind:

```
P0/P1       P2/P3
=====       =====
r0 = 1;     s0 = X;
r1 = Y;     s1 = 1;
X = r0;     Y = s1;
```

At this point, it should be obvious what the problematic reordering would be.
Let's continue merging these into a single execution order:

```
P0/P1/P2/P3
===========
r0 = 1; // #1
r1 = Y; // #0
s0 = X; // #0
s1 = 1; // #1
X = r0; // #1
Y = r1; // #1
```

The outcome?  { r0 == 1, r1 == 0 } and { s0 == 0, s1 == 1 }.  Whoops.

I have yet to observe this happening in practice, but models that permit store buffer
forwarding are fundamentally vulnerable to this reordering.  The solution here
is the same as with Dekker.  Marking the volatiles is insufficient: you need
to insert full memory fences between the store-load adjacent pairs.

