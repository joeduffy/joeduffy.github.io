---
layout: post
title: Haskell, STM, and love
date: 2005-04-03 23:36:50.000000000 -07:00
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
I love [Haskell](http://haskell.org/). So much that I'm now writing a compiler
for it. In my "spare" time, of course. (Which means just a couple hours a week
since my book is priority #1 at the moment.) :)

I mentioned it briefly before, but I'm basing the generated code's execution
model on [the GHC (i.e. STG)
machine](http://research.microsoft.com/copyright/accept.asp?path=/users/simonpj/papers/spineless-tagless-gmachine.ps.gz#26pub=34).
I've decided to forego all of the front end gunk and instead just hook into the
Core output from GHC. This will work so long as I leave the underlying language
unchanged; I might revisit that decision later on, but for now it seems like
the right approach. [This paper is a great
help.](http://www.haskell.org/ghc/docs/papers/core.ps.gz)

Aside from my self professed admiration of the language, I have a few other
motivations, too.

The [latest release (6.4) of GHC](http://haskell.org/ghc/) contains [STM
(software transactional memory)
abstractions](http://research.microsoft.com/~tharris/papers/2005-ppopp-composable.pdf).
I'm really psyched about the recent work in this space. Because Haskell is
non-strict and I/O (side-effecting) operations are by their very nature easy to
notice, it removes a bunch of roadblocks. But, I intend to look (and I know a
whole set of other folks are already looking) into how imperative and strict
languages could take advantage of this, too. The primary concern is that, if a
transaction fails--more common that you might think due to STM's optimistic
nature--a whole lot of stuff ends up re-executed as part of a retry. For
side-effecting operations, this is dangerous. However, if one could detect
statically what Framework operations would result in I/O, you could get closer
to implementing safe retries.

Drilling one level deeper, STM support baked into the VM would be bliss. Not a
small project no doubt, but interesting nonetheless. I've done some hacking on
Rotor's JIT to see what I can come up with, but it seems difficult to do in an
efficient manner. STM requires that certain activities write to a transaction
log instead of directly to memory. But it's difficult to know statically
whether you're inside a transaction and thus which behavior is
appropriate--e.g. with locked { Foo(); }, Foo() will execute inside a
transaction sometimes but other times not. You can detect this at runtime and
do the right thing, but this would result in a pretty poor global performance
hit.

Further, because of the non-strict nature of Haskell, implicit parallelism
becomes more of a reality. Again, something that's possible in strict
languages, but more difficult to do correctly. With more intent-based
annotations throughout the Framework, I think we could eventually get there. I
absolutely love the existing par and seq explicit abstractions that the
Parallel GHC library provides. They compose beautifully. I think C# could learn
a thing or two.

So, I'm curious what folks think. Anybody out there using Haskell? Wish you had
a reliable implementation on the CLR? What about STM, implicit parallelism, and
concurrency on the CLR? Useful? Interesting at least?

(BTW, I'm aware of the Mondrian effort. We share some similar goals, but mostly
they are sufficiently different to justify both works existing. My focus is
more on the concurrency side of things.)

