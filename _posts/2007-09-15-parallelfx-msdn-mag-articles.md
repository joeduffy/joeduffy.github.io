---
layout: post
title: ParallelFX MSDN mag articles
date: 2007-09-15 09:30:29.000000000 -07:00
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
Two articles about ParallelFX (PFX) are in the October issue of MSDN magazine
and have been posted online:

1. [Parallel LINQ: Running Queries on Multi-Core Processors](http://msdn.microsoft.com/msdnmag/issues/07/10/PLINQ/default.aspx).
An overview of an implementation of [LINQ-to-Objects](http://msdn2.microsoft.com/en-us/library/bb394939.aspx)
and [-XML](http://msdn2.microsoft.com/library/bb308960.aspx) which automagically
uses data parallelism internally to execute declarative language queries.  It
supports the full set of LINQ operators, and several ways of consuming output in
parallel.

2. [Parallel Performance: Optimize Managed Code for Multi-Core Machines](http://msdn.microsoft.com/msdnmag/issues/07/10/Futures/default.aspx).
Describes the Task Parallel Library (TPL), a new "thread pool on steroids" with cancelation,
waiting, and pool isolation support, among many other things.  Uses dynamic
work stealing techniques (see [here](http://supertech.csail.mit.edu/cilk/) and [here](http://research.sun.com/techrep/2005/abstract-144.html))
for superior scalability.

As noted in the article, there's a PFX CTP planned for 2007\*.  Watch my blog
for more details when it's available.

\*Note: some might wonder why we released the articles before the CTP was actually
online.  When we originally put the articles in the magazine's pipeline, our
intent was that they would in fact line up.  And both were meant to
align with PDC'07.  But when PDC was canceled, we also delayed our CTP so that
we had more time to make progress on things that would have otherwise been
cut.  It's less than ideal, but I'm still confident this was the right choice.

