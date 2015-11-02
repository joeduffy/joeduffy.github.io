---
layout: post
title: CLR 2.0 memory model
date: 2007-11-10 04:02:06.000000000 -08:00
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
There are several docs out there that describe the CLR memory, most notably [this
article](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/).

When describing the model, one can either use acquire/release, barrier/fence, or
happens-before terminology.  They all acheive the same goal, so I will simply
choose one, acquire/release: an acquire operation means no loads or stores may move
before it, and a release operation means no loads or stores may move after it.
I can explain it with such simple terms because the CLR is homogeneous in the kinds
of operations it permits or disallows to cross such a barrier, e.g. there's never
a case where loads may cross such a chasm but stores may not.

Despite the great article referenced above, I find that it's still not entirely
straightforward.  It is important to code to a well-understood abstract
model when writing lock-free code.  For reference, here are the rules as
I have come to understand them stated as simply as I can:

- Rule 1: Data dependence among loads and stores is never violated.

- Rule 2: All stores have release semantics, i.e. no load or store may move after
one.

- Rule 3: All volatile loads are acquire, i.e. no load or store may move before one.

- Rule 4: No loads and stores may ever cross a full-barrier (e.g. Thread.MemoryBarrier,
lock acquire, Interlocked.Exchange, Interlocked.CompareExchange, etc.).

- Rule 5: Loads and stores to the heap may never be introduced.

- Rule 6: Loads and stores may only be deleted when coalescing adjacent loads and
stores from/to the same location.

Note that by this definition, non-volatile loads are not required to have any sort
of barrier associated with them.  So loads may be freely reordered, and
writes may move after them (though not before, due to Rule 2).  With this
model, the only true case where you'd truly need the strength of a full-barrier
provided by Rule 4 is to prevent reordering in the case where a store
is followed by a volatile load.  Without the barrier, the instructions may reorder.

It is unfortunate that we've never gone to the level of detail and thoroughness
[the Java memory model folks have gone to](http://www.cs.umd.edu/~pugh/java/memoryModel/).
We have constructed our model over years of informal work and design-by-example,
but something about the JMM approach is far more attractive.  Lastly, what
I've described applies to the implemented memory model, and not to what was specified
in ECMA.  So this is apt to change from one implementation to the next.
I have no idea what Mono implements, for example.

