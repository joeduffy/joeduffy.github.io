---
layout: post
title: More thoughts on transactional memory
date: 2010-05-16 21:48:58.000000000 -07:00
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
[My article about Transactional Memory](http://www.bluebytesoftware.com/blog/2010/01/03/ABriefRetrospectiveOnTransactionalMemory.aspx)
(TM) was picked up by a few news feeds recently.

If I had known this would occur, I would have written it with greater precision.
Because my article presents a mixture of technical challenges interspersed among
more subjective and cultural issues, I am sure it is difficult to tease out my intended
conclusion.  To summarize, I merely believe adding TM to a shared memory
architecture alone is insufficient.

Indeed, I remain a big fan of transactions.  Atomicity, consistency, and isolation,
and coming up with strategies for achieving all three in tandem, are part and parcel
to architecting software.

After [watching Barbara Liskov's OOPSLA Turing Award reprise](http://www.infoq.com/presentations/liskov-power-of-abstraction),
I decided to reacquaint myself with [some old Argus papers](http://portal.acm.org/citation.cfm?id=42399)
this weekend.  It has been some time since I last read them.  Argus was
Liskov's language for distributed programming and her follow-on to CLU.  As
with most research done by brilliant people, the work was way ahead of its time,
has appeared in ad-hoc incarnations and permutations over time, and remains relevant
today.  This research is particularly interesting to work that my team is doing
right now, especially its notion of guardians.  And it is relevant to the TM
discussion too.

The Argus approach of using isolation to coarsely partition state and operations
into independent bubbles, and then communicating asynchronously between the
so-called guardians that are responsible for this state, is an architecture
that is common among most highly concurrent programs.  This aids state management
and fault tolerance.  Argus makes an interesting observation that, although
guardians may be sent messages concurrently -- and indeed activities themselves may
even introduce local concurrency -- manipulation of state can be done safely and
even in parallel thanks to transactions.

The requirement is that messages are atomic and commute.  Transactions, it turns
out, are a convenient way of implementing this requirement.

You will observe a similar architecture in other places, including in some languages
that have adopted TM.  Haskell has moved in this direction.  Everything
is purely functional and so, of course, no state is mutated in an unsafe way by default.
However, with the introduction of concucrrency comes mutable cells for message passing
and with parallelism comes indeterminism.  You can push the state management
problem up indefinitely, but at the top there are almost always mutable operations
on real-world state (even if it is "just I/O").  Haskell programs have a safe
architecture to begin with, and it is the intentional and careful addition of specific
facilities that forces one to focus on the problematic seams.  One could say
that Haskell starts clean and stays clean, versus most shared memory-based languages
which start dirty and try to attain cleanliness (at least when it comes to concurrency).

Why aren't transactions sufficient, then, given that the I in ACID stands for Isolation?
You wouldn't model a database as one flat table in which each row is a single byte,
however, would you?  As you begin to decompose your program into isolated state,
your bubbles (or guardians) are the tables, and your objects are the rows.
This is just an analogy but I find it useful to think in these terms.  Taking
a bunch of intermingled state and pouring transactions on top is not going to give
you this nicely partitioned separation of state which has proven to be the lifeblood
of concurrency.

Even once you've attained a more isolated architecture, however, transactions are
not a panacea.  They are just one of many viable state management techniques
in a programmer's arsenal, hierarchical state machines being another notable example.
And in fact, many of the problems I mentioned in the TM article are still worrisome
even when you start from the right place.  From within a guardian, you may wish
to enlist the aid of another unrelated guardian to perform a coordinated atomic activity,
because a higher level invariant relationship between them must be preserved.
Or an application which composes multiple guardians may wish to do so atomically.
Even Argus required manual compensation for such things.  This can be solved
in part by DTC.  But experience suggests that continuing to push the enlistment
scope one level higher eventually leads to substantial problems.  A topic for
another day, I suppose.

My primary conclusion is that TM is a great complement to highly concurrent programs,
but only so long as you start from the right place.  The Argus and Haskell approaches
are conducive to large-scale concurrency, but it is primarily because of the natural
isolation those models provide; the addition of transactions address problems that
remain after taking that step.  But without that first step, they would have
gotten nowhere.

