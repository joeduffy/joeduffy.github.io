---
layout: post
title: The slippery slope of lock-freedom
date: 2007-11-09 16:05:41.000000000 -08:00
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

[Lock-free algorithms](http://en.wikipedia.org/wiki/Lock-free_and_wait-free_algorithms)
are often "better" than lock-based algorithms:

- They are, by definition, wait-free, ensuring threads never block.

- State transitions are atomic such that failure at any point will not corrupt the
data structure.

- Because threads never block, they typically lead to greater throughput, as the
granularity of synchronization is a single atomic write or compare-exchange.

- In some cases, lock-free algorithms incur fewer total synchronizing writes (e.g.
interlocked ops) and thus can be cheaper from a pure performance standpoint.

But lock-freedom is not a panacea.  I've gained a lot more experience using
lock-free algorithms in the past 3 years: first, when working on memory model improvements
for Whidbey, and recently during the implementation of the ParallelFX library and
as I write new content for my book.

There are some obvious drawbacks:

- The use of optimistic concurrency can lead to livelock for hot data structures.

- The code is significantly harder to test.  Usually its correctness hinges
on a correct interpretation of the target machine's memory model --in my case,
the .NET memory model  (the topic of an upcoming post)—which can be misinterpreted
and is hard to validate.  Moreover, because the most popular hardware is stronger
than the lesser popular hardware (e.g. X86 vs. IA64), testing needs to explicitly
focus on the esoteric hardware to expose races.

- The code is significantly harder to write and maintain, for many of the same reasons.

I have learned about a less obvious drawback the hard way.  When initially implementing
a certain data structure, you may make a bunch of assumptions about the use cases
your class needs to accommodate.  And you may actually succeed in writing
an implementation that is correct given those assumptions.  But over time, as
new use cases are discovered, it is much harder to retrofit the code and revalidate
that the lock-free algorithms are still correct given the new assumptions.
There is no magic oracle that says: hey, adding feature X is going to invalidate
assumption Y over there, creating a memory reordering bug.

In several recent cases, I've discovered such problems, and dealt with them one-by-one,
usually by adding additional memory barriers.  As the numbers of memory barriers
increase (roughly ½ the cycle-cost of acquiring and releasing a lock), however,
the benefits of lock-free algorithms begin to dwindle.  It's easy to begin
with an algorithm that scales and performs nicely, and over time add a memory barrier
here and there, and eventually end up with something that performs worse than the
lock-based equivalent.  Unfortunately, this threshold isn't always obvious,
so you can end up with a real mess on your hands: a buggy, impossible to test, and
difficult to understand hunk of code.  All the drawbacks of lock-free code with
none of the benefits.  Whoops.

The moral of the story?  Be careful and conservative in your use of lock-free
code.  There are many well-known published lock-free algorithms, and it's
usually a good idea to stick to them, if you use lock-free code at all.  When
in doubt, just use locks.  Truthfully, they are hard enough.

