---
layout: post
title: 'PDC: Programming with Concurrency'
date: 2005-07-17 19:41:31.000000000 -07:00
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
I've spent a bit of time this weekend on [my concurrency talk for
PDC](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=e2446e8b-b393-439b-8522-1245166b1801).
It's taking me longer than expected, mostly because I'm writing "a story" up
front... before I even think about touching PPT or writing code. The end result
will be a great story to tell captured in a paper and--so that I have a
convenient way to guide me through the talk--a slide deck. Too many people use
PPT as a crutch for presentations, and most of the time it shows.

The talk's focus is on the hows and whys of concurrency with a good mix of the
realities of the Windows platform thrown in. This necessarily involves some
mechanics (e.g. best practices with explicit threading and the ThreadPool,
synchronization, locks, lock-free programming), but also a detailed look inside
our platform's legacy, how and why we got here, why some of our legacy still
affects how we write concurrent code (anti-concurrency), and where we're
headed.

If you're interested in reading up on this stuff, I'd recommend any of the
following books. It just so happens that they're all sitting in front of me and
being used as references:

- [Parallel Programming : Techniques and Applications Using Networked
  Workstations and Parallel
Computers](http://www.amazon.com/exec/obidos/ASIN/0131405632/bluebytesoftw-20/):
Good survey of the landscape of parallel hardware and software

- [Fundamentals of Parallel
  Computing](http://www.amazon.com/exec/obidos/ASIN/0139011587/bluebytesoftw-20/):
Similar to the above, with some great coverage on implicit parallelism (e.g.
data dependence) and I/O

- [Patterns for Parallel
  Programming](http://www.amazon.com/exec/obidos/ASIN/0321228111/bluebytesoftw-20/):
Catalogue of canonical concurrent programming patterns

- [An Introduction to Parallel Computing: Design and Analysis of
  Algorithms](http://www.amazon.com/exec/obidos/ASIN/0201648652/bluebytesoftw-20/):
Focuses on designing your computationally-bound algorithms for parallel scaling

- [Computer Architecture: A Quantitative
  Approach](http://www.amazon.com/exec/obidos/ASIN/1558605967/bluebytesoftw-20/):
General discussion of hardware concepts, including parallel architectures and
shared memory

- [Concepts, Techniques, and Models of Computer
  Programming](http://www.amazon.com/exec/obidos/ASIN/0262220695/bluebytesoftw-20/):
Broad introduction to programming, but includes some very unique discussion of
dataflow and concurrent styles of programming

- [Multithreading Applications in Win32: The Complete Guide to
  Threads](http://www.amazon.com/exec/obidos/ASIN/0201442345/bluebytesoftw-20/):
Focuses on Win32/64 threading and has a wealth of knowledge on Windows-specific
stuff

- [Windows System
  Programming](http://www.amazon.com/exec/obidos/ASIN/0321256190/bluebytesoftw-20/):
Good general coverage of threading on Win32/64, less specific than the previous

- [Essential
  COM](http://www.amazon.com/exec/obidos/ASIN/0201634465/bluebytesoftw-20/):
Because of it's coverage of COM Apartments

- [Advanced
  Windows](http://www.amazon.com/exec/obidos/ASIN/1572315482/bluebytesoftw-20/):
Discussion of memory management, e.g. process-wide memory, stacks, corruption

- [Microsoft Windows
  Internals](http://www.amazon.com/exec/obidos/ASIN/0735619174/bluebytesoftw-20/):
Deep dives on similar topics as "Advanced Windows"

Another great related resource that you might want to check out is [an article
Vance Morisson wrote for August's MSDN
magazine](http://msdn.microsoft.com/msdnmag/issues/05/08/Concurrency/default.aspx).
Vance is one of the most senior guys on the team, and is the architect for the
CLR's JIT. Bottom line: one of the smartest guys I've ever met.

