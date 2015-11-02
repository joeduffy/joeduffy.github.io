---
layout: post
title: Uniqueness and Reference Immutability for Safe Parallelism
date: 2012-10-28 15:58:30.000000000 -07:00
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
A glimpse of some research we've done recently just appeared [at OOPSLA last week](http://splashcon.org/2012/schedule/tuesday-oct-23/462):

> **Uniqueness and Reference Immutability for Safe Parallelism**
>
> _A key challenge for concurrent programming is that side-effects (memory operations)
in one thread can affect the behavior of another thread. In this paper, we present
a type system to restrict the updates to memory to prevent these unintended side-effects.
We provide a novel combination of immutable and unique (isolated) types that ensures
safe parallelism (race freedom and deterministic execution). The type system includes
support for polymorphism over type qualifiers, and can easily create cycles of immutable
objects. Key to the system's flexibility is the ability to recover immutable or externally
unique references after violating uniqueness without any explicit alias tracking.
Our type system models a prototype extension to C# that is in active use by a Microsoft
team. We describe their experiences building large systems with this extension. We
prove the soundness of the type system by an embedding into a program logic._

The official ACM page is [here](http://dl.acm.org/citation.cfm?id=2384619), and a
tech report version is available on [MSR's website](http://research.microsoft.com/apps/pubs/default.aspx?id=170528).

As I said, this is just a glimpse. Its focus was mainly on the type soundness work
we've done jointly with MSR, and less about the language, syntax, and uses. You'll
have to use your imagination to fill in the rest ;-)

