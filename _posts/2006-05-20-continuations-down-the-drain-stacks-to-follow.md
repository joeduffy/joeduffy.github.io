---
layout: post
title: Continuations down the drain. Stacks to follow?
date: 2006-05-20 12:24:31.000000000 -07:00
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
Via [DBox](http://pluralsight.com/blogs/dbox/archive/2006/05/20/24599.aspx) and 
[TBray](http://www.tbray.org/ongoing/When/200x/2006/05/19/Continuations-and-GUIs), 
I stumbled upon [Will Continuations 
Continue?](http://blogs.sun.com/roller/page/gbracha?entry=will_continuations_continue), 
a great essay about why continuation support in modern VMs is _not_ a good idea 
after all:

> "By far he most compelling use case for continuations are continuation-based 
> web servers. ... Rather than relying on the server's stack to keep track of 
> what location we're looking at, the [UI] will be a view on a model ... When 
> you pressed "Buy", it would pass all the information necessary to complete the 
> transaction onto the server. Consequently, we'll have no more of a pressing 
> need for continuations than traditional applications have today."

I couldn't agree more, although I arrive at the conclusion via a different line 
of thought.

Just over a year ago now, I was [working on 
continuations](http://www.bluebytesoftware.com/blog/PermaLink,guid,d608d408-9c74-44c7-b8e8-ab24edb3e006.aspx) 
for my Scheme interpreter and compiler, Sencha. I managed to create something 
that "worked" -- in the sense that the stack could be captured, passed around, 
and restored; and it even still reported locals as roots to the GC -- but there 
are so many facets of a modern runtime to consider that true product support 
would be a massive undertaking. I thought continuations were a good idea. Why? 
To be honest, the main reason was my simple goal of having a full-fidelity 
Scheme runtime. But I also admired their power.

In retrospect, I now realize something important: the stack is evil. It's a 
wasteful representation of state, especially for web applications.

The stack is unnecessarily bound to an OS thread, and munges control flow with 
the "state" of the program. The fact that return addresses for function calls 
lives on it has been the source of many security problems and counter-measures 
(/GS). When a thread blocks, the entire stack is wasted, even if there is 
logical work on it that could progress if it weren't for the arbitrary physical 
association. There's so much crap on it that to summarize the state of your 
entire program often requires pausing threads and walking their stacks. How 
dirty and impolite! Freak-of-nature abominations have twisted what the stack was 
meant for, e.g. COM and GUI reentrancy and APCs, completely disassociating 
logical and physical representations. You have to reserve a contiguous chunk of 
the thing per thread (often 1MB), wasting virtual memory space, because Windows 
doesn't support linked stack regions (not as big a deal on 64-bit as on 32-bit, 
sure), which also leads to the CLR ripping the process if you ever exceed it 
(overflow).

So many problems we encounter with parallel programming (among other domains) 
would go away with a more structured representation of the program as a state 
machine.

[Dharma](http://www.dharmashukla.com/) and the rest of the WF team are 
delivering [just that](http://msdn.microsoft.com/workflow/) (in the large). [C# 
2.0's iterator feature](http://msdn.microsoft.com/msdnmag/issues/04/05/C20/) 
supplies a similar capability (in the small). The [Concurrency and Coordination 
Runtime](http://channel9.msdn.com/ShowPost.aspx?PostID=143582) (CCR) eschews 
stack in favor of orchestration and message passing. We'll converge at some 
point. And it won't be around _serializing_ stacks, it will be around getting 
rid of the damned things.

