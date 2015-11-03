---
layout: post
title: 'MSDN Magazine: 9 Reusable Parallel Data Structures and Algorithms'
date: 2007-04-12 06:37:10.000000000 -07:00
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
I wrote an article that appears in the May 2007 issue of MSDN Magazine.  It's
now online for your reading pleasure:

> **[CLR Inside Out: 9 Reusable Parallel Data Structures and Algorithms](http://msdn.microsoft.com/msdnmag/issues/07/05/CLRInsideOut/default.aspx)**
> 
> This column is less about the mechanics of a common language runtime (CLR) feature
> and more about how to efficiently use what you've got at your disposal. Selecting
> the right data structures and algorithms is, of course, one of the most common yet
> important decisions a programmer must make. The wrong choice can make the difference
> between success and failure or, as is the case most of the time, good performance
> and, well, terrible performance. Given that parallel programming is often meant to
> improve performance and that it is generally more difficult than serial programming,
> the choices are even more fundamental to your success.
> 
> In this column, we'll take a look at nine reusable data structures and algorithms
> that are common to many parallel programs and that you should be able to adapt with
> ease to your own .NET software. Each example is accompanied by fully working, though
> not completely hardened, tested, and tuned, code. The list is by no means exhaustive,
> but it represents some of the more common patterns. As you'll notice, many of the
> examples build on each other.
> 
> [(Read more...)](http://msdn.microsoft.com/msdnmag/issues/07/05/CLRInsideOut/default.aspx)

The 9 items are: Countdown Latch, Reusable Spin Wait, Barrier, Blocking Queue, Bounded
Buffer, Thin Event, Lock-Free Stack, Loop Tiling, Parallel Reduction.  Much
of the content is closely related to, or even derived from, content that will
appear in my book.  (Yes, it's still in the works.)

As Stephen notes on [the MSDN Magazine blog](http://blogs.msdn.com/msdnmagazine/archive/2007/04/04/2027113.aspx),
there was a printing error which resulted in the last page of the article being printed
twice, one of which overwrote another page in the article.  Thankfully the online
article doesn't suffer from this same problem.  But to remedy this, the article
will also appear in next month's magazine, for double the fun.

