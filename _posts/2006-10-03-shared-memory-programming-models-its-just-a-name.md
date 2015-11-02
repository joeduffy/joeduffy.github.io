---
layout: post
title: Shared memory programming models -- it's just a name
date: 2006-10-03 16:13:32.000000000 -07:00
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
I am often confronted with the question of whether concurrency programming models
that employ shared memory are particularly problematic. I was asked this question
directly on the concurrency panel at JAOO'06 earlier this week, for instance, and
STM makes a big bet that such models are tenable.

Without shared memory, it's tempting to think that traditional concurrency problems
go away, as if by magic. If no two pieces of code are simultaneously working on the
same location in memory, for instance, there are (seemingly) no race conditions or
deadlocks. Most people believe this, and it (on the surface) seems somewhat
reasonable. Until you realize that it's fundamentally flawed.

Shared memory systems are just an abstraction in which data can be named by its virtual
memory address (or, indirectly, by a variable name). In fact, one could argue that
it's an optimization—that the same sort of systems could be built by mapping
virtual memory addresses (at a logical level) to some other location (at a physical
level) using an algorithm that doesn't rely on page-tables, TLBs, and so on. Distributed
RPC systems in the past have tried this very thing: to map object references
to data residing on far-away nodes, and have mostly failed in the process. I'm
not trying to convince you that alternative mapping techniques are a good thing,
only that abstractly speaking at least, all of the same concurrency control problems
will arise in systems that exhibit this fundamental property. Interestingly, shared
memory systems have turned into tiny distributed systems with complex cache
coherency logic anyway, so one has to wonder where the boundary between shared memory
and message passing really lies.

There is a fundamental, undeniable law here:

> Any system in which two concurrent agents can name the same piece of information
may also exhibit the standard problems of concurrency: broken serializability, race
conditions, deadlocks, livelocks, lost event notifications, and so on. Concurrency
control is simply a requirement if correctness is desired.

So in reality, the real question at hand should be, would a system in which
every concurrent agent operates on its own, completely isolated piece of data be
more attractive? I personally think that's farfetched and unrealistic. Systems
with shared data need to have shared data; it's a property of the system being modeled.
Even with isolated data, concurrency control would be required if, say, a central
copy is rendezvoused with periodically (which, by the way, is the only way I can
see such a system remaining correct). And then you have to wonder what copying buys
you. It certainly costs you. Data locality is crucial to achieving adequate
performance in most low-to-mid-level systems software. Yet copy-on-send message passing
systems throw this out the window entirely. I refuse to believe that this will ever
be the dominant model of fine-grained concurrency, at least on the current hardware
architectures available by Intel and AMD. And certainly not without a whole lot more
research and perhaps hardware support.

A distributed system in which many simultaneous clients might access the same piece
of data on the server has all the same issues. AJAX systems, for instance, easily
lull the author into a false sense of security. But, unfortunately(?), a transaction
is a transaction, and if concurrency control isn't in place, such systems are effectively
executing without any isolation or serialization guarantees whatsoever—I just
read [an article in the latest DDJ](http://www.ddj.com/dept/lightlang/192700218)
where this was explained. I'm surprised a dedicated article actually needs to
point this out: concurrent access to data under any other name is still concurrent
access to data. And of course, once you start to employ concurrency control,
you are susceptible to deadlocks and so on—unless you have a system that can transparently
resolve them.

Interesting research has been done recently by MSR on static verification to prove
the absence of sharing (across processes)—called [Software Isolated Processes (SIPs)](ftp://ftp.research.microsoft.com/pub/tr/TR-2006-43.pdf)—building
on the type safe, verifiable subset of IL. STM of course also builds on top of the
shared memory programming model; but, although threads can name the same location
in memory, this is completely hidden—concurrency control is still employed in the
implementation where necessary. I believe this systems are promising. They also have
the benefit of building on the same foundational memory performance equations
that software developers are used to relying on today.

