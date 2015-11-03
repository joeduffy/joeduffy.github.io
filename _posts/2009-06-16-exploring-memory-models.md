---
layout: post
title: Exploring memory models
date: 2009-06-16 23:53:26.000000000 -07:00
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
One of my many focuses lately has been developing a memory ordering model for our
project here at Microsoft.  There are four main questions to answer when defining
such a model:

1. What are the ordering guarantees for ordinary loads and stores?

2. What are the ordering guarantees for volatile loads and stores?

3. What kinds of explicit fences are allowed?

4. Where are fences used automatically, e.g. to preserve type safety and security?

These tend to be the differentiation points for any model.  Everything else
is mostly commodity.  Not that there is much else, mind you, but respecting
data dependence, not speculating ahead such that exceptions occur that wouldn't have
occurred in a sequential execution, and so forth are all must haves, for instance.
Most interesting permutations of answers for these questions have already been explored,
and industry consensus is being reached, so it would be better to say I've been picking
a model rather than defining one.

What's interesting is that memory model designers are often colored by their favorite
architecture du jour.  If somebody cares primarily about X86, they are apt to
choose something very strong.  If somebody cares primarily about ARM, however,
they are apt to choose something very weak.  There is a classic tradeoff here.
Stronger means easier to program, while weaker means better performance.  For
some reason, many of the projects I've worked on have had an abundance of strong
hardware (like X86) and a scarcity of weak hardware (like ARM and IA64).  The
reality sinks in: most developers on the team code to X86, and then when it comes
time to getting more serious about the other platforms, code starts breaking all
over the place.  This is why the CLR went so strong in 2.0, even though
IA64 was an important platform to support.

Let's look at some common answers to the above questions.

For #1:

- C++, Visual C++, ECMA 1.0, Java Memory Model, and Prism: no ordering guarantees.

- CLR 2.0: ordered stores, no ordering for loads.

For #2:

- C++: prevents compiler-only code motion, but explicit fences are needed for processor
ordering.

- Visual C++, ECMA 1.0, and CLR 2.0: loads are acquire, stores are release ordered.

- Java Memory Model: loads and stores are fully ordered (sequentially consistent).

For #3:

- C++: implementation-specific.

- Visual C++: intrinsics and Win32 APIs.

- ECMA 1.0 and CLR 2.0: locks, and mostly Win32-style interlocked APIs.

- Java Memory Model: locks, compare-and-swap, atomics, etc.

For #4:

- Managed environments like the CLR and JVM need to ensure type safety, even if ordinary
loads and stores are unordered.  This is nontrivial, because the boundary around
type safety is blurred.  Certainly we must ensure garbage v-table pointers are
not seen.  But is a thread allowed to read non-zeroed memory behind an object
reference?  And can it contain garbage (e.g. "values out of thin air")?
What about writes done by mutator threads, including write barriers, while a concurrent
collector is tracing objects in the heap?  Are array lengths part of the set
of protected fields that mustn't be read out of order?  Strings, since they
are commonly used for security checking?  And so on.

It is mainly the deep questions around #4, and also some simple compatibility struggles
(around things like double checked locking), that caused the stronger answers for #1 in
the CLR 2.0.

In any case, I'm advocating a very different approach than the traditional models.

We pick completely weak ordering for ordinary loads and stores, to enable efficient
execution on weaker platforms like ARM, PowerPC, IA64, etc.  That part isn't
new.  But here's the clincher.  No volatiles.  There _are_ special
variables that are used to communicate between threads (call them volatile if
you'd like), but using them implies no kind of special automatic fencing.  Instead,
whenever accessing such a variable, at the site of usage, the kind of fence desired
_must_ be used (compiler-enforced): full-fence (sequentially consistent), acquire-fence,
release-fence, no-fence, or compiler-only-fence (for things like ensuring loads don't
get hoisted as loop invariant).  Of course, certain kinds of fences are sprinkled
throughout the system to guarantee type safety in all of the aforementioned places
(and more), but these are implementation details.

(This approach is rather like Herb Sutter's Prism and C++0x atomics.  See
[http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2664.htm](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2664.htm).)

Particularly after managing teams who developed a plethora of lock free code, I love
this approach.  I can review code and immediately understand what ordering invariants
the developer assumed when writing the code.  This doesn't really make writing
lock free code any simpler, except that it forces you to pause and think about things
a bit more carefully than you may have otherwise.  But it certainly makes code
easier to understand and maintain, and makes it clear to people that sprinkling
volatile all over the place isn't going to save your butt: the only thing that will
do that is careful thinking and engineering.

