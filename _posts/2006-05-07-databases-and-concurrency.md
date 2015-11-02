---
layout: post
title: Databases and concurrency
date: 2006-05-07 20:43:50.000000000 -07:00
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
Databases have utilized parallelism for a long time now to effectively scale-up 
and scale-out with continuously improving chip and cluster technologies. 
Consider a few high-level examples:

[_Parallel query 
execution_](http://research.microsoft.com/~Gray/papers/CacmParallelDB.pdf) is 
employed by all sophisticated modern databases, including SQL Server and Oracle. 
This comes in two flavors: (1) execution of multiple queries simultaneously 
which potentially access intersecting resources, and (2) implicit 
parallelization of individual queries, to acheive speed-ups even when a large 
quantity of incoming work is not present (e.g. high-cost queries, lots of data, 
etc.). Often a combination of both is used dynamically in a production system. I 
won't say much more, other than to refer to [an interesting new query 
technology](http://msdn.microsoft.com/data/linq/) on the horizon.

_Transactions_ are used as a simple model for concurrency control, enabling high 
scalability due to dynamic fine-grained locking techniques and policies, while 
supplying conveniences such as intelligent contention management and deadlock 
detection. And of course reliability is improved, because of the all-or-nothing 
semantics of transactions. Even in the face of [asynchronous thread 
aborts](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641), 
a transaction can ensure inconsistent state isn't left behind to corrupt a 
process, greatly improving the reliability of software at a surprisingly low 
cost. [Software transactional 
memory](http://research.microsoft.com/~tharris/papers/2003-oopsla.pdf) (STM) 
borrows directly from the field, and applies it to general purpose parallel 
programming.

_Invariants_ about data in databases are often modeled as integrity checks and 
foreign key constraints, which help to maintain reliable and consistent 
execution even in the face of concurrency. This, coupled with transactions, 
helps to ensure invariants aren't broken at transaction boundaries, and [recent 
work done by 
MSR](http://research.microsoft.com/~tharris/drafts/2006-invariants-draft.pdf) 
explores how this might be applied to general programming. STM combined with a 
rich system like [Spec#](http://research.microsoft.com/specsharp/) could 
facilitate highly reliable and consistent systems that don't expose latent race 
conditions in the face of parallel execution.

Assuming you have (1) a lot of data to process, (2) complex computations to 
perform, and/or (3) simply a lot of individual tasks to accomodate, this model 
of parallel programming stretches quite far. With many cores per CPU, TB disks, 
and 100+-GB memories on desktops just around the corner; an order of magnitude 
more network bandwith available to consumers; and a continuing explosion of the 
amount of information humans generate and have to make some sense of, similar 
approaches could enable the next era of computer applications. I will also 
observe that surprisingly similar models of computation are precisely what fuel 
technologies like Google's 
[MapReduce](http://labs.google.com/papers/mapreduce.html), albeit at a coarser 
granularity.

