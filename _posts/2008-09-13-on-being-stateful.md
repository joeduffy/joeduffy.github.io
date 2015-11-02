---
layout: post
title: On being stateful
date: 2008-09-13 14:14:41.000000000 -07:00
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
Most programs are tangled webs of data and control dependencies.  For sequential
programs, this doesn't matter much aside from putting constraints on the legal
optimizations available to a compiler.  But it gets worse.  Imperative
programs today are also full of side-effect dependencies.  Unlike data and control
dependence—which most compilers can identify and understand the semantics of (aliasing
aside)—side-effect dependencies are hidden and the semantic meaning of them is
entirely ad-hoc.  These can include scribbling to shared memory, writing to
the disk, or printing to the console.

One of my goals is to push programming languages in the direction of full disclosure
of all kinds of dependencies.  I believe this will eventually help to foster
ubiquitous parallelism.  These dependencies, after all, are what inherently
limit the latent parallelism in a program and are "real" in the sense that they
are typically algorithmic.  I would prefer that developers think about how to
modify or rewrite their algorithm to eliminate any unnecessary dependencies, and
also to be clever about eliminating necessary ones, rather than trying to navigate
a minefield of dependencies that are implicit, undocumented, and often hard to understand.
Our tools should be oriented towards aiding such endeavors.

That's not to say that knowing about dependencies will immediately make all programs
parallel programs.  Research in automatic parallelism for purely functional
languages like Haskell has shown that this is a naïve point of view.  My belief
is that this is a key step along the path, however.  With it new models and
patterns can emerge that reduce dependencies so that parallelism can be introduced
without accidentally violating subtle and hidden dependencies, causing races.

The biggest question left unanswered in my mind is the role state will play in software
of the future.

That seems like an absurd statement, or a naïve one at the very least.  State
is everywhere:

- The values held in memory.

- Data locally on disk.

- Data in-flight that is being sent over a network.

- Data stored in the cloud, including on a database, remote filesystem, etc.

Certainly all of these kinds of state will continue to exist far into the future.
Data is king, and is one major factor that will drive the shift to parallel computing.
The question then is how will concurrent programs interact with this state, read
and mutate it, and what isolation and synchronization mechanisms are necessary to
do so?

I've been working on or around software transactional memory (STM) for over 3 years
now.  Many think it's a panacea, and it has been held up as somewhat of a
"last hope for mankind" kind of technology.  As with anything, it's best
to temper the enthusiasm with some realism.  Things are never so simple.
STM will be one tool (of many) in the toolkit of programmers writing the next generation
of concurrent code.  In fact, I have over time come to believe that it's one
of the least radical ones that we need.  This is probably bad news, given the
vast number of difficulties the community has uncovered in our attempts to efficiently
and correctly implement an STM system.

Many programs have ample gratuitous dependencies, simply because of the habits we've
grown accustomed to over 30 odd years of imperative programming.  Our education,
mental models, books, best-of-breed algorithms, libraries, and languages all push
us in this direction.  We like to scribble intermediary state into shared variables
because it's simple to do so and because it maps to our von Neumann model of how
the computer works.

We need to get rid of these gratuitous dependencies.  Merely papering over them
with a transaction—making them "safe"—doesn't do anything to improve the
natural parallelism that a program contains.  It just ensures it doesn't crash.
Sure, that's plenty important, but providing programming models and patterns to
eliminate the gratuitous dependencies also achieves the goal of not crashing but
with the added benefit of actually improving scalability too.  Transactions
have worked so well in enabling automatic parallelism in databases because the basic
model itself (without transactions) already implies natural isolation among queries.
Transactions break down and scalability suffers for programs that aren't architected
in this way.  We should learn from the experience of the database community
in this regard.

There is a kind of natural taxonomy for the structure concurrent programs:

- A. _Agents_, where isolation is king and interactions are loosely coupled.
    This is classically referred to as "message passing", but there are many different
    reifications of this idea that expose the idea of messages differently: actors (e.g.,
    as in Scheme circa 1980's), active objects, Ada tasks, Erlang processes, web services,
    and so on.
- B. _Task parallelism_, where logically independent activities (from a dependence
    point of view) may be run concurrently.  This can range from coarse- to fine-grained,
    but is normally fixed in number.
- C. _Data parallelism_, in which data drives the coarseness of concurrency.

There is also a natural taxonomy for the way concurrent programs manipulate state:

1. At a coarse-grained level, any changes to state are committed via transactions.
2. At a fine-grained level, all computations are purely functional and without
    side-effects.

You'll notice a nice correlation between { (A) & (1) }, and { (B), (C), & (2) }.

And you'll also notice that I explicitly didn't mention mutable shared state
at all, except for implying mutations would only occur at a coarse granularity and
with transactions.  This is an oversimplification.  Even within the fine-grained
computations, guaranteed isolation can allow computations to allocate new state and
manipulate it in a myriad of ways.  The key here is that the state must be guaranteed
to be isolated, and that within such pockets of guaranteed isolation familiar imperative
programming can be used.  This spans graphs of structured task and data parallelism.

Even this is an oversimplification, but as a broadly appealing programming model
I think it is what we ought to strive for.  There will always be hidden mutation
of shared state inside lower level system components.  These are often called
"benevolent side-effects," thanks to Hoare, and apply to things like lazy initialization
and memorization caches.  These will be done by concurrency ninjas who understand
locks.  And their effects will be isolated by convention.

Any true effects that must escape a pocket of isolation then get communicated transactionally
to others.

Efforts in Haskell have lead to similar conclusions.  Monads, of course, are
the way to get side-effects into a purely functional language like Haskell: [http://portal.acm.org/citation.cfm?id=262011](http://portal.acm.org/citation.cfm?id=262011).
The state monad allows one to manipulate state lazily via a monad, in a semi-imperative
way, and a paper called "Lazy functional state threads" by Launchbury and Peyton-Jones
shows how to combine the state monad with threading to enable a model very similar
to the one I describe: [http://portal.acm.org/citation.cfm?id=178243.178246](http://portal.acm.org/citation.cfm?id=178243.178246).
Combine this with STM and we're getting somewhere: [http://portal.acm.org/citation.cfm?id=1065944.1065952](http://portal.acm.org/citation.cfm?id=1065944.1065952).
Sadly, I do think Haskell's syntax is too mathematical for most and that we need
a fair bit of sugar on top of the raw use of monads and combining stateful effects.
But as an underlying model of computation I think the kernel of the idea is just
right.

I admit that I'm a little sad that F# has taken an impure-by-default stance.
Given the roots in ML and O'Caml, and the more pragmatic goals of the language,
this stance isn't a surprise.  And a bunch of people will be wildly successful
and happy using it as-is.  F# is, however, Microsoft's first attempt to hoist
functional programming unto our professional development community, and pure-by-default
is actually a fairly innocuous (but subtly crucial) position to take.  (Except
for those damn impure libraries.)  I fear we may be missing our "once in every
5 years" chance to do the right thing.  But I guess we don't quite know
for sure what the right thing is just yet; we simply didn't take the leap of faith.

Even with all of this support, we'd be left with an ecosystem of libraries like
the .NET Framework itself which have been built atop a fundamentally mutable and
imperative system.  The path forward here is less clear to me, although having
the ability to retain a mutable model within pockets of guaranteed isolation certainly
makes me think the libraries are salvageable.  Thankfully, the shift will likely
be very gradual, and the pieces that pose substantial problems can be rewritten in
place incrementally over time.  But we need the fundamental language and type
system support first.

