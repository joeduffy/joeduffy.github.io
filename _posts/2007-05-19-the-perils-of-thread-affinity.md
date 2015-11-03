---
layout: post
title: The perils of thread affinity
date: 2007-05-19 17:22:53.000000000 -07:00
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
I've opined on thread affinity several times [in the past](http://www.bluebytesoftware.com/blog/PermaLink,guid,f8404ab3-e3e6-4933-a5bc-b69348deedba.aspx).
I think the term "thread affinity" is en vogue only internal to Microsoft, so
it may help to define what it means for the rest of the world.

Many services on Windows have traditionally associated state with the executing thread
to keep track of certain ambient contextual information.  Errors, security,
arbitrary library state.  Storing data on the physical thread ensures that it
flows around with the logical continuation of work, no matter what APIs are called
or how interwoven the stack ends up, and is therefore "always" accessible.
Thank our imperative history for this one.  People have had to deal with this
in Haskell, though since Haskell generally doesn't have statefulness which persists
across callstacks, they came up with a more elegant ["implicit parameter" solution](http://cvs.haskell.org/Hugs/pages/users_guide/implicit-parameters.html).

Affinity creates difficulties for parallel programming models for a number of reasons.
We'd like it to be the case that work can be transferred for execution on separate
processors when feasible and profitable, and often even implicitly.  For
example in the query 'var q = from x in A where p(x) select f(x);', so long as
'p' and 'f' are sufficiently complicated and 'A' sufficiently large,
perhaps we want to run this in parallel.  But "transferring work for execution
on separate processors" means using many threads to execute the same logical chunk
of work.  If 'p' or 'f' rely on thread affinity, what are we to do?
Affinity becomes a concurrency blocker here: if part of that work depends on the
thread's identity across multiple steps, then how can we possibly use multiple
threads?

One answer is that we first need to know the duration of the affinity if we're
to deal intelligently with it somehow.  That's what the .NET Framework's
Thread.BeginThreadAffinity and EndThreadAffinity are meant for: they denote the boundaries
of affinity that has been acquired and then released.  But this still doesn't
solve the fundamental problem, which is the mere presence of thread affinity in the
first place.  We would presumably respond to the affinity by just suppressing
parallelism.  That's no good.  And sadly affinity isn't really a well-defined
single thing that we can do away with in one well-defined step.

Win32 is littered with affinity: error codes are stored in the TEB (accessible via
GetLastError), as are impersonation tokens and locale IDs.  Arbitrary program
and library can be—and routinely is—stashed away into Thread Local Storage (TLS)
for retrieval later on.  In fact, most mutual exclusion mechanisms today assume
thread affinity: that is, a lock is taken by some thread and then the only agent
in the system working under the protection of that lock is that one thread.
Various transactional memory nesting forms seek to solve this problem, including
what happens when many threads which comprise the same logical piece of work need
to write to overlapping data.  Heck, stacks are even [a subtle form of thread
affinity too](http://www.bluebytesoftware.com/blog/PermaLink,guid,db077b7d-47ed-4f2a-8300-44203f514638.aspx),
in which some portion of the program state is all cobbled up with the thing which
is meant to execute the program itself.  COM introduced an even more grotesque
form of affinity with its Threading apartment model, particularly Single Threaded
Apartments (STAs), in which components created on an STA are only ever accessed from
the single STA thread in that apartment.  And let's not forget all of the
GUI frameworks: all of the Windows GUI frameworks are built on the notion of strong
affinity.  And since the introduction of LIBCMT and MSVCRT those C
Runtime library functions which historically relied on global state now rely on TLS,
so some of the CRT itself is even guilty (which means those programs that use the
guilty parts are also guilty, though perhaps unknowingly).  Managed code adds
one degree of separation by [detaching the CLR thread from the OS thread](http://www.bluebytesoftware.com/blog/PermaLink,guid,2d0038b5-7ba5-421f-860b-d9282a1211d3.aspx),
which is a step in the right direction; but the .NET Framework is still littered
with affinity that is either inherited from Win32 or of its own creation.  And
so on, and so forth.

All of those examples of thread affinity above are cases where the library developer
needed to have an isolated context.  There really is no reason that this context
needs to be specific to a single OS thread, it just so happens the context that
most of them chosen is in fact specific to one.  The .NET Framework's approach
of offering a layered and shiftable abstraction on top of the concrete thing
is promising... assuming you're comfortable using that abstraction.
CLR remoting offers various forms of contexts that flow in a multitude of ways.
Sadly the machinery is complex, not documented satisfactorily, and is, well, tied
to remoting.  We need something more general purpose and ubiquitous.  Maybe
the CLR thread is it.  Until somebody needs to come along and build something
that is one level above CLR threads, I suppose.

So how bad is all of this anyway?  It's actually fairly bad.  Any one
of these things in isolation is teachable and avoidable, but pile it all up and what
you're left with is a veritable minefield to navigate.  Affinity shows up
as a huge concurrency blocker alongside other favorites like mutable data structures
and impure functions.  As if concurrency weren't hard enough!

