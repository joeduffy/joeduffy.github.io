---
layout: post
title: On effects and ubiquitous parallelism
date: 2009-07-27 15:57:18.000000000 -07:00
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
I've grown convinced over the past few years that taming side effects in our programming
languages is a necessary prerequisite to attaining ubiquitous parallelism nirvana.
Although I am continuously exploring the ways in which we can accomplish this --
ranging from shared nothing isolation, to purely functional programming, and anything
and everything in between -- what I wonder the most about is whether the development
ecosystem at large is ready and willing for such a change.

It is this that I find the most frightening.  I know we can give the world Haskell,
or Erlang, or simple incremental steps within familiar environments, like Parallel
Extensions.  (Indeed, the world already has these things.)  But elevating
effects to a first class concern in day-to-day programming turns out to be a tough
pill to swallow.  Particularly since the incremental degrees of parallelism
that this switch will unlock are questionable (see [this](http://research.microsoft.com/en-us/um/people/simonpj/papers/parallel/feedback-directed.pdf)
and [this](http://www.haskell.org/~simonmar/papers/multicore-ghc.pdf)); and even
if they were pervasive and impressive, it's unclear what percentage of developers
will pay what specific price for a 2x, 4x, or even 16x increase in compute performance.
It sounds great on paper, but the cost / benefit equation is a complicated one.

"Pay for play" is the standard terminology we use for such things around here, and
the solution needs to have the right amount of it.

Many folks with embarrassingly parallel algorithms will succeed just fine in a shared
memory + locks + condition variables world, and indeed have already begun to do so.
And specialized tools -- like GPGPU programming -- have popped up that, when small
kernels of computations are written in a highly constrained way, will parallelize,
sometimes impressively.  Is this enough?  Perhaps for the next 5 years,
but surely not much longer after that.  It is in my opinion qualitatively very
important for the future of computer science that we provide programming environments
that are more conducive to safe and automatic parallelism.  And yet I cannot
stand up with a straight face and proclaim that each and every developer on the face
of the planet should practice side effect abstinence.  A healthy balance between
cognitive familiarity and pragmatic [r]evolution must be found.  Many promising
approaches are in the works (see [UIUC's DPJ](http://dpj.cs.uiuc.edu/)), but we are
years away.

Until then, parallelism on broadly deployed commercial platforms will likely remain
in the realm of specialists.

Of course, Haskell and Erlang both accomplish the no effects feat in a sneaky way.
For those interested in foisting parallelism unto the masses, lessons can be learned
from these communities.  If you buy into purely functional programming, you
necessarily buy into programming without effects, and the (sparing) use of monads
to represent them.  (Or, as my colleague Erik calls it, [fundamentalist functional
programming](http://en.oreilly.com/oscon2009/public/schedule/detail/9099)).)
And if you buy into large scale message passing, you (typically) necessarily also
buy into programming without shared memory, leaving behind only strongly isolated
effects.  The key here is that developers gain many other benefits by switching
to these platforms -- and the lack of effects is admittedly a consequential byproduct
of this switch.  The lack of effects are not center stage.  The two approaches
have recently begun to converge in what I believe to be the appropriate long-term
approach: strong isolation with effects within, and safe, deterministic data parallelism
through careful control over sharing, aliasing, and heap separation.

That said, though not center stage, the switch to effectless programming is certainly
not painless.

Enabling side effects among otherwise functional code, I think, is a good thing,
because it allows familiar algorithms to be encoded in an ordinary imperative way.
Familiarity is key: it may sound two faced, but I don't think parallelism is sufficiently
top of mind that developers will want to completely rearrange the way that they write
software.  Perhaps we will evolve in this direction, but a significant leap
will fall flat.  Moreover, many algorithms actually depend on stateful updates
to achieve adequate performance, like write in place graphics buffers.  The
Haskell state monad strikes a nice balance between embedding imperative-looking effects,
when coupled with the do notation, within a strictly functional language.

Furthermore, I really respect that Haskell discourages cheating.  (Any unsafePerformIO
is viewed with great suspicion.)  I quite like mostly-functional programming
languages like ML and Scheme, because they tend to be easier on programmers with
C backgrounds, but strongly dislike that a mutation can lurk within what appears
to be an otherwise pure function.  Documenting side effects in the type system
is healthy and allows better symbolic reasoning about the dependencies and implicit
parallelism contained within, transitively, while still providing a way to get at
effectful programming.  Haskell does a great job at this.  The elimination
of dependence ought to be the focus of programmers, and not the elimination of ad-hoc
and unstructured access to shared, mutable state.  These are algorithmic and
important concerns.

What remains unclear is where the boundaries lie.  Part and parcel of documenting
effects is thinking about them when designing your software.  You need to consider
whether IList<T>'s Contains method may mutate the list or not, for example, and hold
the line on implementations of the interface.  Either it returns an 'a' or an
'IO a' -- and this decision is one that has far reaching implications.  This
is a wholly separate kind of interface contract than what most programmers are accustomed
to having to think about during the code-debug-edit cycle.  And surely Python
and JavaScript developers will not care one way or the other, particularly if it
forces more design decisions up front than what is customary today.  This bifurcation
seems inevitable, and yet there is substantial crossover: C# developers will write
Python scripts, and Python developers will consume components written in C#.

And yet, I think we need to venture down this path in order achieve automatically
scalable software.  Parallel computers have become incredibly cheap, and so
the historical barriers into high performance technical computing have been whittled
away to the software skills necessary to write scalable programs; we will likely
succeed at expanding this market without radical changes, but if we stopped there,
vast reams of client-side software will be left in the dust.  I've been making
inroads into solving the problem on my end, with a new language that sits between
C# and Haskell.  I'm biased, have been hard at work on this problem for many
years, and yet still struggle to answer these fundamental questions.  I am a
big believer that there's got to be a happy medium out there.  But I'm still
very perplexed, and face some very high walls to hurdle.  Who will discover
the right balance, and when will they do so?

