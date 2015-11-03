---
layout: post
title: Announcing the Axum programming language
date: 2009-05-08 12:05:04.000000000 -07:00
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
The parallel computing team just shipped an early release [Axum](http://msdn.microsoft.com/en-us/devlabs/dd795202.aspx)(fka
Maestro), an [actor](http://portal.acm.org/citation.cfm?id=36162) based programming
language with message passing and strong isolation.

I'm personally very excited to see what comes of Axum.  It's one step on the
long road towards limited automatic parallelism.  Although I can't claim credit
for writing any code, I did design the fine grained isolation model Axum is built
atop (something I call "Taming Side Effects" (TSE)).  It's a blend of functional
programming with imperative programming enabled by using the concepts of Haskell's
[state monad](http://portal.acm.org/citation.cfm?id=158524) in a more familiar way.
I'll try to blog a bit more about it in coming weeks.  It turns out I've recently
shifted my focus to a [new project](http://blogs.msdn.com/cbrumme/archive/2006/09/15/756709.aspx)
with the aim of applying these ideas very broadly for a whole new platform.

Doing incubation work at Microsoft is tough work, because it takes a strong vision
and drive to keep pushing forward.  You need to take stances that are unconventional,
risky, and often just plain unpopular, and drive against all odds.  Usually
you aren't going to make any money off the ideas for years at a time, so it also
takes a supportive management team who is willing to give you creative freedom and
cut you checks.  Most such efforts fail in a vaccuum.  But hats off to
the team for pushing hard, and going out early to ask what developers think.
This is a huge milestone.

