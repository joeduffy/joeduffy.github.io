---
layout: post
title: Butler Lampson's "Hints for Computer System Design"
date: 2007-06-08 21:19:23.000000000 -07:00
categories:
- Miscellaneous
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
I recently read Butler Lampson's immensely wonderful paper ["Hints for Computer
System Design"](http://research.microsoft.com/Lampson/33-Hints/Abstract.html) (
[HTML](http://research.microsoft.com/Lampson/33-Hints/WebPage.html), [PDF](http://research.microsoft.com/Lampson/33-Hints/Acrobat.pdf)).

Yeah, yeah, I'm only 24 years behind the times.  In the paper, Butler offers
many principles backed by concrete examples illustrating tradeoffs between functionality,
speed, and fault-tolerance, drawn mostly from his experience building operating and
distributed systems.  As I read it the paper, I was struck by how much his advice
applies to building just about any kind of complicated software system, including
frameworks.

A few quotes that I quite liked:

--

> Designing a computer system is very different from designing an algorithm:
> 
> > The external interface (that is, the requirement) is less precisely defined,
> > more complex, and more subject to change.
> > 
> > The system has much more internal structure, and hence many internal interfaces.
> > 
> > The measure of success is much less clear.
> 
> The designer usually finds himself floundering in a sea of possibilities, unclear
> about how one choice will limit his freedom to make other choices, or affect the
> size and performance of the entire system. There probably isn't a 'best' way
> to build the system, or even any major part of it; much more important is to avoid
> choosing a terrible way, and to have clear division of responsibilities among the
> parts.

--

> Do one thing at a time, and do it well. An interface should capture the minimum
> essentials of an abstraction. Don't generalize; generalizations are generally wrong.

--

> Keep secrets of the implementation. Secrets are assumptions about an implementation
> that client programs are not allowed to make. In other words, they are things that
> can change; the interface defines the things that cannot change (without simultaneous
> changes to both implementation and client). Obviously, it is easier to program and
> modify a system if its parts make fewer assumptions about each other. On the other
> hand, the system may not be easier to design—it's hard to design a good interface.

--

> One way to improve performance is to increase the number of assumptions that
> one part of a system makes about another; the additional assumptions often allow
> less work to be done, sometimes a lot less.

--

> When in doubt, use brute force. Especially as the cost of hardware declines,
> a straightforward, easily analyzed solution that requires a lot of special-purpose
> computing cycles is better than a complex, poorly characterized one that may work
> well if certain assumptions are satisfied.

--

Needless to say, I strongly recommend the paper.

