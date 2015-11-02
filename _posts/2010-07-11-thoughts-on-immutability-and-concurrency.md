---
layout: post
title: Thoughts on immutability and concurrency
date: 2010-07-11 20:18:30.000000000 -07:00
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
That immutability facilitates increased degrees of concurrency is an oft-cited dictum.
But is it true? And either way, why?

My view on this matter may be a controversial one. Immutability is an important foundational
tool in the toolkit for building concurrent -- in addition to reliable and predictable
-- software. But it is not the only one that matters. Making all your data immutable
isn't going to instantly lead to a massively scalable program. Natural isolation
is also critically important, perhaps more so. And, as it turns out, sometimes mutability
is just what the doctor ordered, as with large-scale data parallelism.

# Isolation first; immutability second; synchronization last

Stepping back for a moment, the recipe for concurrency is rather simple. Say you've
got multiple concurrent pieces of work running simultaneously (or have a goal of
getting there); for discussion's sake, call them _tasks_. Take two tasks. The first
critical decision has two cases: either these tasks concurrently access overlapping
data in shared-memory, or they do not. If they do not, they are _isolated_, and no
precautions associated with racing memory updates are needed. If they do share data,
on the other hand, then something else must give. If all concurrently accessed data
is _immutable_, or all functions used to interact with data are _pure_, then dangerous
concurrency hazards are avoided. All is well. If some data is mutable, however, then
this is where things get tricky, and higher-level _synchronization_ is needed to
make accesses safe. This decision tree is straightforward and clear.

I have listed those four attributes -- isolated, immutable and pure, and synchronization
-- in a very intentional order. Thankfully, this order mirrors the natural top-down
hierarchical architecture of most modern object- and component-based programs: we
have large containers that communicate through well-defined interfaces, each comprised
of layers of such containers, and somewhere towards the leaves, a fair amount of
intimate commingling of knowledge regarding data and invariants.

This order also reflects the order of complexity and execution-time costs, from least
to most. Isolation is simple, because components depend on each other in loosely-coupled
ways, and in fact scales superiorly in a concurrent program because no synchronization
is necessary, the "right" data structure may be chosen for the job -- immutable
or not -- and locality is part-and-parcel to the architecture. Immutability at least
avoids the morass of synchronization, which can affect programs immensely in complexity,
runtime overheads, and write-contention for shared data. It is clear that synchronization
is something to avoid at all costs, particularly anything done in an ad-hoc manner
like locks.

# Making the concurrency

But where did all this concurrency come from, anyway?

It came from two things:

1. The coarse-grained breakdown of a program into isolated pieces.
2. The fine-grained data parallelism.

On #1: Program fragments that are isolated are already half-way down the road to
running concurrently as tasks. The second half of this journey, of course, is teaching
them to interact with one another asynchronously, most frequently through message-passing
or by sticking them into a pipeline. The details of course depend on what programming
language you are using. It may be through agents, actors, active objects, COM objects,
EJBs, CCR receivers, web-services, something ad-hoc built with .NET tasks, or some
other reification. Nevertheless the isolation is common to all these.

On #2: Data parallelism, it turns out, often works best with mutable data structures.
These structures must be partitionable, of course, so that tasks comprising the data
parallel operations may operate with logically isolated chunks of this data safely,
even if they are parts of the same physical data structure. So chunks of them are
isolated even though they don't appear to be. This is trivially achievable with
many important parallel-friendly data structures like arrays, vectors, and matrices.
Capturing this isolation in the type system is of course no small task, though region
typing gets close (see UIUC's Data Parallel Java).

But you usually don't want these structures to be immutable, because they can be
modified in constant-time and space if they are their classic simple mutable forms.
Programmers doing HPC-style data-parallelism a la FORTRAN, vectorization, and GPGPU
know this quite well. Compare this a world where we are doing data-parallelism over
immutable data structures, where modifications often necessitate allocations or more
complicated big-oh times due to clever techniques meant to avoid such allocations,
as with persistent immutable data structures. This is likely less ideal. It is true
that some data parallel operations are not in-place against mutable data -- as with
PLINQ -- at which point purity, but not immutability, is key. The two are related
but not identical: immutability pervades the construction of data structures, whereas
purity pervades the construction of functions. But if you can get by with one copy
of the data, why not do it? Particularly since most datasets amenable to parallel
speedups are quite large.

# Immutability: the bricks, not the mortar

Notice that the concurrency did not actually come from immutable data structures
in either case, however. So what are they good for?

One obvious use, which has little to do with concurrency, is to enforce characteristics
of particular data structures in a program. A translation lookup table may not have
been meant to be written to except for initialization time, and using an immutable
data structure is a wonderful way to enforce this intent.

What about concurrency? Immutable data structures facilitate sharing data amongst
otherwise isolated tasks in an efficient zero-copy manner. No synchronization necessary.
This is the real payoff.

For example, say we've got a document-editor and would like to launch a background
task that does spellchecking in parallel. How will the spellchecker concurrently
access the document, given that the user may continue editing it simultaneously?
Likely we will use an immutable data structure to hold some interesting document
state, such as storing text in a piece-table. OneNote, Visual Studio, and many other
document-editors use this technique. This is zero-cost snapshot isolation.

Not having immutability in this particular scenario is immensely painful. Isolation
won't work very well. You could model the document as a task, and require the spellchecker
to interact with it using messages. Chattiness would be a concern. And, worse, the
spellchecker's messages may now interleave with other messages, like a user editing
the document. Those kinds of message-passing races are non-trivial to deal with.
Synchronization won't work well either. Clearly we don't want to lock the user
out of editing his or her document just because spellchecking is occurring. Such
a boneheaded design is what leads to spinning donuts, bleached-white screens, and
"(Not Responding)" title bars. But clearly we don't want to acquire a lock
and then make a full copy of the entire document. Perhaps we'd try to copy just
what is visible on the screen. This is a dangerous game to play.

Immutability does not solve all of the problems in this scenario, however. Snapshots
of any kind lead to a subtle issue that is familiar to those with experience doing
multimaster, in which multiple parties have conflicting views on what "the" data
ought to be, and in which these views must be reconciled.

In this particular case, the spellchecker sends the results back to the task which
spawned it, and presumably owns the document, when it has finished checking some
portion of the document. Because the spellchecker was working with an immutable snapshot,
however, its answer may now be out-of-date. We have turned the need to deal with
message-level interleaving -- as described above -- into the need to deal with
all of the messages that may have interleaved within a window of time. This is where
multimaster techniques, such as diffing and merging come into play. Other techniques
can be used, of course, like cancelling and ignoring out-of-date results. But it
is clear something intentional must be done.

# In conclusion

It is safe to say that immutability facilitates important concurrent architectures
and algorithms. It can really help big time, for sure. But it is clearly no panacea.
Whether mutability or immutability is the right choice for a particular data structure
in your program, as with all things, depends.

It could be the case that choosing a piece-table for storing your text facilitates
large-scales of concurrency in version two of your software application, but that
in version one you have no use for it. Making that call ahead of time may pay in
spades down the road, even if it comes at a marginal cost up-front. Or it could be
that choosing an immutable data structure costs you in time and space, and you never
end up exploiting the fact that you could have shared that particular structure in
a zero-cost way across agents in your program.

One thing's for sure: I'm glad to be programming in languages like C#, F#, Clojure,
and Scala, where I've got a choice.

