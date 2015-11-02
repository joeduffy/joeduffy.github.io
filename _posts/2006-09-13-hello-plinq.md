---
layout: post
title: Hello PLINQ
date: 2006-09-13 04:48:33.000000000 -07:00
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
LINQ coaxes developers into writing declarative queries that specify _what_ is to
be computed instead of _how_ to compute the results. This is in contrast
to the lion's share of imperative programs written today, which are huge rat nests
of for-loops, switch statements, and function calls. The result of this new direction?
Computationally intensive filters, projections, reductions, sorts, and joins can
be evaluated in parallel... transparently... with little-to-no extra input from the
developer. The more data the better.

If you buy the hypothesis--still unproven--that developers will write large swaths
of code using LINQ, then by inference, they will now also be writing large swaths
of implicitly data parallel code. This, my friends, is very good for taking advantage
of multi-core processors.

If you want to get a little glimpse of what I've been spending my time working on,
check out these (brief) stories about Parallel LINQ (aka PLINQ), a parallel query
execution engine for LINQ:

- [Microsoft's PLinq to Speed Program Execution](http://www.eweek.com/article2/0,1895,2009167,00.asp) (eWeek)

- [MS eyes multicore technology](http://weblog.infoworld.com/techwatch/archives/007678.html) (InfoWorld)

We've spent many, many months now cranking out a fully functional prototype. The
numbers were impressive enough to catch the eye of some key people around the company.
And the rest is history... (well, not quite yet...)

I'll no doubt be disclosing more about this in the coming weeks.

(Note: I am in no way committing to any sort of product or release timeframe. This
technology is quite early in the lifecycle, and, while unlikely, might never
actually make the light of day... Label this puppy as "research" for now.)

