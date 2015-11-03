---
layout: post
title: Boxed Nullables are now null
date: 2005-08-12 09:18:30.000000000 -07:00
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
Check out [Soma's
post](http://blogs.msdn.com/somasegar/archive/2005/08/11/450640.aspx) about the
Nullable<T> DCR we recently implemented...we referred to the project as
_nullbox _internally. This one kept me up at night on a few occassions, but was
a lot of fun. :)

The core change here is that the IL _box _instruction has been modified to
recognize Nullable<T>s. For non-Nullables, behavior remains the same; but upon
seeing one, it inspects its HasValue property. If HasValue is true, box peeks
inside the structure, extracts the T value, and boxes that instead; otherwise,
box simply leaves behind a null reference. Obviously, _unbox _has also been
changed to allow nulls to be unboxed back into Nullable<T> structures. This had
a rippling effect in the CLR codebase and also required changes to late-bound
semantics to mimic the static case.

The result is that given

> int? x = null; object y = x;

both expressions

> x == null y == null

evaluate to true. And furthermore, given

> bool F<T>(T t) { return t == null; }

the following expressions

> F(x) F(y)

also evaluate to true.

I intend to post a more detailed summary of the DCR over the coming week[s].

