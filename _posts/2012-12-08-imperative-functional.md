---
layout: post
title: Imperative + Functional == :-)
date: 2012-12-08 11:42:47.000000000 -08:00
categories:
- Technology
tags: []
status: publish
type: post
published: true
meta:
  _wpas_done_all: '1'
  _edit_last: '1'
author:
  login: admin
  email: joeduffy@acm.org
  display_name: joeduffy
  first_name: ''
  last_name: ''
---
I [mentioned recently](http://www.bluebytesoftware.com/blog/2012/10/28/UniquenessAndReferenceImmutabilityForSafeParallelism.aspx)
that a paper from my team appeared at OOPSLA in October:

> **Uniqueness and Reference Immutability for Safe Parallelism** ( [ACM](http://dl.acm.org/citation.cfm?id=2384619),
[MSR Tech Report](http://research.microsoft.com/pubs/170528/msr-tr-2012-79.pdf) [PDF])

It's refreshing that we were able to release it. Our project only occasionally gets
a public shout-out, usually when something leaks by accident. But this time it was
intentional.

I began the language work described about 5 years ago, and it's taken several turns
of the crank to get to a good point. (Hint: several more than even what you see in
the paper.) Given the novel proof work in collaboration with our intern, folks in
MSR, and a visiting professor expert in the area, however, it seemed like a good
checkpoint that would be sufficiently interesting to release to the public. Perhaps
some day Microsoft's development community will get to try it out in earnest.

There seems to have been some confusion over the goals of this work. I wanted to
take a moment to clear the air.

First, despite assertions elsewhere, the primary focus of this work was not "implicit
parallelism." Instead, I would summarize our goals as:

1. Create a single language that incorporates the best of functional and imperative
programming. Both offer distinct advantages, and we envisioned marrying the two.
2. Codify and statically enforce common shared-memory state patterns, such as immutability
and isolation, with minimal runtime overhead (i.e., virtually none).
3. Provide a language model atop which can be built provably safe data, task, and
actor-oriented concurrency abstractions. Both implicit and explicit. This includes,
but is not limtied to, parallelism.
4. Do all of this while still offering industry-leading code quality and performance,
rivaling that of systems-level C programs. Yet still with the safety implied by the
abovementioned goals.

The language features in the paper are a vast subset of the full suite needed to
achieve our overall project goals. However, these alone have exceeded our original
expectations.

I've programmed a great deal in functional languages. I'm a long-time lover of LISP
and ML, and my closest friends know about my hard-core dedication to Haskell (expressed
in an admittedly odd manner). In fact, Haskell's elegant marriage of pure functional
programming with monads, notably the state monad, was a major inspiration for the
design of the type system. There are of course many other influences, such as regions,
linear types, affine types, etc.; however, I'd say Haskell was the strongest.

In some sense, we have simply taken the reverse angle of Haskell with its monads:
what would it be like to embed pure functional programming within an otherwise imperative
language?

This first goal is proving to be my fondest aspect of the language. The ability to
have "pockets of imperative mutability," familiar to programmers with C, C++, C#,
and Java backgrounds, connected by a "functional tissue," is not only clarifying,
but works quite well in practice for building large and complex concurrent systems.
It turns out many systems follow this model. Concurrent Haskell shares this high-level
architecture, as does Erlang. Well-written C# systems do the same, though the language
doesn't (yet) help you to get it right.

Of course, as called out by the second goal, immutability and controlled side-effects
are tremendously useful features on their own. Novel optimizations abound.

And it helps programmers declare and verify their intent. As mentioned in the paper,
we have found/prevented many significant bugs this way. Did you ever want to verify
that your contracts and assertions are pure, such that conditional compilation doesn't
change the outcome of your program? Or that your sort comparator isn't mutating the
elements while performing its comparisons? Neither has much to do with concurrency,
although the latter facilitates parallel sorts. Many other systems introduce specific
verification techniques to address specific problems, rather than employing a general
purpose type system.

I would say the strength with respect to concurrency is not the type system itself,
but rather what you can do with it.

The focus on implicit parallelism in the recent forum discussions was unfortunate.
I guess "implicit parallelism" just makes for catchy and controversial titles. Yes,
the type system makes implicit parallelism "safe and possible," some forms of which
are indeed profitable, but it's not as though suddenly all of your for loops are
going to run 8-times faster after a recompile. The optimization angle is an orthogonal,
but very real, concern. There are [decades of research and experience](http://www.cs.cmu.edu/~scandal/nesl.html)
here.

Even when tasks are explicitly spawned, however, the fact that the type system catches
unsafe mutable state capture that would lead to race conditions is, I dare say, game
changing. I could never go back to the old model of instruction-level races, which
now-a-days feels like programming a PDP6 to me (no insults implied). And yes, data
parallel works great in this model. It may take a bit of imagination, rereading the
article, and perhaps looking at related work such as [Deterministic Parallel Java](http://dpj.cs.uiuc.edu/DPJ/Home.html),
to understand how, but it does.

The effort grew out of my work on Software Transactional Memory in 2004, then Parallel
Extensions (TPL and PLINQ), and then [my book](http://www.bluebytesoftware.com/books/winconc/winconc_book_resources.html),
a few years later. I had grown frustrated that our programming languages didn't help
us write correct concurrent code. Instead, these systems simply keep offering more
and more unsafe building blocks and synchronization primitives. Although I admit
to contributing to the mess, it continues to this day. How many flavors of tasks
and blocking queues does the world need? I was also dismayed by the oft-cited "functional
programming cures everything" mantra, which clearly isn't true: most languages, Haskell
aside, still offer mutability. And few of them track said mutability in a way that
is visible to the type system (Haskell, again, being the exception). This means that
races are still omnipresent, and thus concurrent programs expensive and error prone
to write and maintain.

Reflecting back, I am somewhat amazed that the language has taken so long to hatch.
Type systems that are sound and strike the right balance of utility and approachability
are hard work!

I am ecstatic that we've been able to make inroads towards solving these hard problems.
My team is, quite simply, an amazing group of people, and without them the ideas
would have never made it beyond the "that will never work" phase. I look forward
to sharing more about our work in the years to come.

