---
layout: post
title: 'A Tale of Three Safeties'
date: 2015-11-03 15:45:00.000000000 -08:00
categories: []
tags: []
status: publish
type: post
published: true
author:
  display_name: joeduffy
  first_name: Joe
  last_name: Duffy
  email: joeduffy@acm.org
---
Midori was built on a foundation of three kinds of safety: type, memory, and
concurrency-safety.  These safeties eliminated whole classes of bugs
"by-construction" and delivered significant improvements in areas like
reliability, security, and developer productivity.  They also fundamentally
allowed us to depend on the type system in new and powerful ways, to deliver new
abstractions, perform novel compiler optimizations, and more.  As I look back,
the biggest contribution of our project was proof that an entire operating
system and its ecosystem of services, applications, and libraries could indeed
be written in safe code, without loss of performance, and with some quantum
leaps forward in several important dimensions.

First, let us define the three safeties, in foundational order:

* [Memory Safety](https://en.wikipedia.org/wiki/Memory_safety) prohibits access
  to invalid regions of memory.  Numerous flaws arise when memory safety is
  violated, including buffer overflow, use after free, and double frees. 
  Generally speaking, violation of memory safety is a critical error that can
  lead to exploits such as code injection.

* [Type Safety](https://en.wikipedia.org/wiki/Type_safety) prohibits use of
  memory that is at odds with the type allocated within that memory.  Numerous
  flaws arise when type safety is violated, including type confusion, casting
  errors, and uninitialized variables.  Although generally less severe than
  memory safety violations, type safety violations can lead to exploits,
  particularly when exposing pathways to memory safety holes.

* [Concurrency Safety](https://en.wikipedia.org/wiki/Thread_safety) prohibits
  unsafe concurrent use of shared memory.  These concurrency hazards are widely
  known in the form of [race conditions](
  https://en.wikipedia.org/wiki/Race_condition), or read-write, write-read, and
  write-write hazards.   Generally speaking, if concurrency safety is violated,
  it can frequently lead to type, and therefore memory, safety being violated.
  These exploits are often quite subtle -- like tearing memory -- and we often
  said that concurrency vulnerabilities are the "next frontier" of exploitable
  security holes.

Many approaches exist to establish one or more of these safeties, and/or
safeguard against violations.

[Software fault isolation](http://www.cs.cmu.edu/~srini/15-829/readings/sfi.pdf)
establishes memory safety as a backstop against the most severe exploits.  This
comes at some runtime cost, although [proof carrying code](
https://en.wikipedia.org/wiki/Proof-carrying_code) can lessen it.  These
techniques don't deliver all the added benefits of type and concurrency safety.

Language-based safety, on the other hand, is done through a conjunction of a
type system's construction, via local checks that, inductively, ensure certain
operations do not occur, plus optional runtime checks (like array bounds
checking in the absence of a more capable [dependent type system](
https://en.wikipedia.org/wiki/Dependent_type)).  The benefits of this approach
are often a more productive approach to stopping safety holes because a developer
finds them while writing his or her code, rather than at runtime.  But if you can
trick the type system into permitting an illegal operation, you're screwed,
because there is no backstop to prevent hackers from violating memory safety in
order to running arbitrary code, for example.

Multiple techniques are frequently used in conjunction with another, something
called "defense in depth," in order to deliver the best of all of these
techniques.

So, anyway, how do you build an operating system, whose central purpose is to
control hardware resources, buffers, services and applications running in
parallel, and so on, all of which are pretty damn unsafe things, using a safe
programming environment?  Great question.

The answer is surprisingly simple: layers.

There was of course _some_ unsafe code in the system.  Each unsafe component was
responsible for "encapsulating" its unsafety.  This is easier said than done,
and was certainly the hardest part of the system to get right.  Which is why
this so-called [trusted computing base](
https://en.wikipedia.org/wiki/Trusted_computing_base) (TCB) always remained as
small as we could make it.  Nothing above the OS kernel and runtime was meant to
employ unsafe code, and very little above the microkernel did.  Yes, our OS
scheduler and memory manager was written in safe code.  And all application-
level and library code was most certainly 100% safe, like our entire web browser.

One interesting aspect of relying on type safety was that [your compiler](
https://en.wikipedia.org/wiki/Bartok_(compiler)) becomes part of your TCB.
Although our compiler was written in safe code, it emitted instructions for the
processor to execute.  The risk here can be remedied slightly by techniques like
proof-carrying code and [typed assembly language](
https://en.wikipedia.org/wiki/Typed_assembly_language) (TAL).  Added runtime
checks, a la software fault isolation, can also lessen some of this risk.

A nice consequence of our approach was that the system was built upon itself.
This was a key principle we took to an extreme.  I covered it a bit [in a prior
article](http://joeduffyblog.com/2014/09/10/software-leadership-7-codevelopment-is-a-powerful-thing/).
But when you've got an OS kernel, filesystem, networking stack, device drivers,
UI and graphics stack, web browser, web server, multimedia stack, ..., and even
the compiler itself, all written in your safe programming model, you can be
pretty sure it will work for mostly anything you can throw at it.

You may be wondering what all this safety cost.  Simply put, there are things
you can't do without pointer arithmetic, race conditions, and the like.  Much of
what we did went into minimizing these added costs.  And I'm happy to say, in the
end, we did end up with a competetive system.  Building the system on itself was
key to keeping us honest.  It turns out architectural decisions like no blocking
IO, lightweight processes, fine grained concurrency, asynchronous message
passing, and more, far outweighed the "minor" costs incurred by requiring safety
up and down the stack.

For example, we did have certain types that were just buckets of bits.  But these
were just [PODs](https://en.wikipedia.org/wiki/Passive_data_structure).  This
allowed us to parse bits out of byte buffers -- and casting to and fro between
different wholly differnt "types" -- efficiently and without loss of safety.
We had a first class slicing type that permit us to form safe, checked windows
over buffers, and unify the way we accessed all memory in the system
([the slice type](https://github.com/joeduffy/slice.net) we're adding to .NET
was inspired by this).

You might also wonder about the [RTTI](
https://en.wikipedia.org/wiki/Run-time_type_information) overheads required to
support type safety.  Well, thanks to PODs, and proper support for [
discriminated unions](https://en.wikipedia.org/wiki/Tagged_union), we didn't
need to cast things all that much.  And anywhere we did, the compiler optimized
the hell out of the structures.  The net result wasn't much more than what a
typical C++ program has just to support virtual dispatch (never mind casting).

A general theme that ran throughout this journey is that compiler technology has
advanced tremeodusly in the past 20 years.  In most cases, safety overheads can
be optimized very aggressively.  That's not to say they drop to zero, but we were
able to get them within the noise for most interesting programs.  And --
surprisingly -- we found plenty of cases where safety _enabled_ new, novel
optimization techniques!  For example, having immutability in the type system
permit us to share pages more aggressively across multiple heaps and programs;
teaching the optimizer about [contracts](
https://en.wikipedia.org/wiki/Design_by_contract) let us more aggressively hoist
type safety checks; and so on.

Another controversial area was concurrency safety.  Especially given that the
start of the project overlapped with the heady multicore days of the late 2000s.
What, no parallelism, you ask?

Note that I didn't say we banned concurrency altogether, just that we banned
_unsafe_ concurrency.  First, most concurrency in the system was expressed using
message passing between lightweight [software isolated processes](
http://research.microsoft.com/apps/pubs/default.aspx?id=71996).  Second, within
a process, we formalized the rules of safe shared memory parallelism, enforced
through type system and programming model rules.  The net result was that you
couldn't write a shared memory race condition.

They key insight driving the formalism here was that no two "threads" sharing an
address space were permitted to see the same object as mutable at the same time.
Many could read from the same memory at once, and one could write, but multiple
could not write at once.  A few details were discussed in [our OOPSLA paper](
http://research.microsoft.com/apps/pubs/default.aspx?id=170528), and Rust
achieved a similar outcome [and documented it nicely](
http://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html).  It worked well
enough for many uses of fine-grained parallelism, like our multimedia stack.

Since Midori, I've been working to bring some of our key lessons about how to
achieve simultaneous safety and performance to both .NET and C++.  Perhaps the
most visible artifact are the [safety profiles](
https://github.com/isocpp/CppCoreGuidelines/blob/master/CppCoreGuidelines.md#S-profile)
we recently launched as part of the C++ Core Guidelines effort.  I expect more
to show up in C# 7 and the C# AOT work we're doing right now, in conjunction
with our cross-platform efforts.  Midori was greenfield, whereas these
environments require delicate compromise, which has been fun, but slowed down
some of the transfer of these ideas into production.  I'm happy to finally start
seeing some of it bearing fruit.

The combination of memory, type, and concurrency safety gave us a powerful
foundation to stand on.  Most of all, it delivered a heightened level of
developer productivity and let us move fast.  The extremely costly buffer
overflows, race conditions, deadlocks, and so on, simply did not happen.
Someday all operating systems will be written this way.

In the next article in this series, we'll look at how this foundational safety
let us deliver a [capability-based security model](
https://en.wikipedia.org/wiki/Capability-based_security) that was first class in
the programming model and type system, and brought the same "by-construction"
solution to eliminating [ambient authority](
https://en.wikipedia.org/wiki/Ambient_authority) and enabling the [
principle of least privilege](https://en.wikipedia.org/wiki/Principle_of_least_privilege)
everywhere, by default, in a big way.  See you next time.

