---
layout: post
title: 'Quiz: Should you call Close() and/or Dispose() on a Stream?'
date: 2004-12-10 22:04:53.000000000 -08:00
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
So you may or may not have noticed that `System.IO.Stream` both has a `Close()`
method _and_ implements `IDisposable`, meaning it has a `Dispose()` method, too.
(Note: it's explicitly implemented, meaning that to access it you'll need to
use an `IDisposable` typed reference in C#, e.g. as in
`((IDisposable)myStream).Dispose()`). `Stream` is an abstract base class, the most
common derivitive being FileStream.

Without consulting Reflector, ;) can you answer these questions?

- What does invoking `Close()` on an open `Stream` do?
- What does invoking `Dispose()` on an open `Stream` do?
- Should you call both at some point in a `Stream`'s lifecycle?
  - If so, when and in what order?
  - If not, why?
- Can you call only one without having to call the other?
- Is it weird that there is both a `Close()` and `Dispose()` on a single type, or
  does that seem natural? Based on your understanding of the pattern, do you
think we should continue to use it, or is there a better one?

I have a much lengthier post that I'm writing up regarding an internal design
debate we're currently involved in - responses will help to shape both the post
and the debate. :)

