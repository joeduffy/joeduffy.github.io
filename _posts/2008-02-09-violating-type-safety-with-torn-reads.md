---
layout: post
title: Violating type safety with torn reads
date: 2008-02-09 23:32:23.000000000 -08:00
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
[Torn reads](http://www.bluebytesoftware.com/blog/2006/02/08/ThreadsafetyTornReadsAndTheLike.aspx)
are possible whenever you read a shared value without synchronization that is either
misaligned and/or which spans an addressible pointer-sized region of memory.  This
can lead to crashes and data corruption due to bogus values being seen.  If
not careful, torn reads can also violate type safety.  If you have a static
variable that points to an object of type T, and your program only ever writes references
to objects of type T into it, you may still end up accessing a memory location that
isn't actually a T.  How could this be?

You guessed it.  Torn reads apply to pointer values just as much as they do
to ordinary values.  So a thread reading a pointer in-flux could see bits of
its value in separate pieces, blending the state before and after the update.
Dereferencing this mutant pointer would lead you off into an unknown place in the
address space, and most certainly not to an instance of T, breaking type safety.
Since VC++ aligns pointer fields automatically, you'd have to go out of your way
with \_\_declspec(align(N)) or an unaligned allocator to create this situation.
Similarly with .NET's StructLayoutAttribute.  Moreover, it turns out that .NET
guards against this problem in its type loader, by rejecting any types containing
improperly aligned object references.  This is good news, because otherwise
a plethora of security vulnerabilities would be possible.  But VC++ doesn't
offer any such guarantees.

This is another example where trying to program in a lock-free manner can lead to
difficulties that aren't present when you stick to ordinary locking.

