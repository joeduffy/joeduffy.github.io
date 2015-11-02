---
layout: post
title: Overdose on parallelism goodness in MSDN Magazine
date: 2008-10-01 21:25:50.000000000 -07:00
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
The October 2008 MSDN Magazine issue just went live with [5 articles on concurrency](http://msdn.microsoft.com/en-us/magazine/cc992993.aspx),
plus the [editor's note](http://msdn.microsoft.com/en-us/magazine/cc966710.aspx).
Four of the articles are written by members of the Parallel Computing team here at
Microsoft, including one by me:

- [**Paradigm Shift: Design Considerations for Parallel Programming**](http://msdn.microsoft.com/en-us/magazine/cc872852.aspx),
by David Callahan.  David is the dinstinguished engineer responsible for setting
the overall direction for the Parallel Computing team (a group of ~100 people) and
indeed the whole company vis-a-vis parallelism.

- [**Coding Tools: Improved Support for Parallelism In the Next Version of Visual
Studio**](http://msdn.microsoft.com/en-us/magazine/cc817396.aspx), by Stephen Toub
and Hazim Shafi.  Yes, we'll actually have IDE support for all of the cool new
stuff we're shipping.

- [**Concurrency Hazards: Solving 11 Likely Problems in Your Multithreaded Code**](http://msdn.microsoft.com/en-us/magazine/cc817398.aspx),
by yours truly.  Although we make things simpler in many regards, there are
still some gotchas to be aware of when writing parallel code.

- [**.NET Matters: False Sharing**](http://msdn.microsoft.com/en-us/magazine/cc872851.aspx),
by Stephen Toub, Igor Ostrovsky, and Huseyin Yildiz.  It's surprising sometimes
how much of a bottleneck the memory system can become in parallel programs,
and this article offers some insight and tips about how to deal with it.

Enjoy the text.  This edition was timed intentionally to coincide with the PDC.
I'm hoping to see you there: we have some exciting things to show, covering both
.NET and C++.  These articles are really just teasers.

