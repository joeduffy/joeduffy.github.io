---
layout: post
title: 'Mostly functional (but not purely so): just what the doctor ordered'
date: 2009-02-22 23:34:10.000000000 -08:00
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
A few weeks back I recorded a discussion with the infamous [Erik Meijer](http://research.microsoft.com/en-us/um/people/emeijer/ErikMeijer.html)
and Charles from [Channel9](channel9.msdn.com).

Perspectives on Concurrent Programming and Parallelism
 [http://channel9.msdn.com/shows/Going+Deep/Joe-Duffy-Perspectives-on-Concurrent-Programming-and-Parallelism/](http://channel9.msdn.com/shows/Going+Deep/Joe-Duffy-Perspectives-on-Concurrent-Programming-and-Parallelism/)

In it, I show my cards a bit more than intuition says I should.  I'm not good
at poker.

To summarize:

- Mostly functional (purity + immutability) is a great default.

- Safe, determinstic mutability (a la runST) is a must-have for cognitive familiarity.

- Isolation is key to achieve the former; type systems can help (a lot).

- Actors, agents, forkIO, <what have you> is a good model, but not the only one.
Isolation is (far) more general.

- Transactions can help around the edges.

I'm working on a few papers for public consumption this year where I espouse these
ideas.  Keep watching for more detail.

