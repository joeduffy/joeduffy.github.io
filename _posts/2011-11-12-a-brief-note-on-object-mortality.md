---
layout: post
title: A brief note on object mortality
date: 2011-11-12 14:03:13.000000000 -08:00
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
I often wish that .NET had erred on the side of offering postmortem instead of premortem
finalization.

The distinction here is when exactly the finalizer runs, i.e. _after_ or _before_
the GC has actually reclaimed an object. This governs whether a dying object is (a)
accessible from within its own finalizer, and therefore (b) eligible to become resurrected.
Postmortem finalization occurs after the object is long gone, and hence says "no"
to both of these questions; premortem finalization happens beforehand and hence says
"yes."

.NET chose the latter.

The primary downside of premortem finalization, setting aside the confusing nature
of resurrection, is that the object in question cannot be collected until _after_
its finalizer has run. This should be fairly obvious: it is only that second time
the object is found to be dead "again" that we know the finalizer has or has
not resurrected it.

This may seem like a small matter. But it matters quite a lot when building high
performance software. In a garbage collected system, relying on high rates of finalization
to keep up with demanding workloads almost never works. But in a premortem finalization
system, even moderate demands become cause for concern.

Premortem finalization leads to finalized objects getting promoted to the elder generations
before actually dying. If you check the value of GC.GetGeneration(this) within an
object's finalizer, for example, you will notice it is one greater than the generation
in which the object was found to be dead the first time. Say it was found dead in
Gen1; then GC.GetGeneration(this) will return '2'. Yet another collection must
happen, in Gen2 to boot, in order to actually reclaim this object. And, of course,
it's not just this object, but also the transitive closure of objects to which
it refers.

This approach penalizes the majority use case of finalizable objects. At least on
.NET, most objects merely invoke CloseHandle on an IntPtr in the finalizer. This
clearly needn't hold up freeing the managed state. And resurrection is a dubious
scenario anyway: such objects quickly end up in Gen2 where collections are expensive
and infrequent. If you're pooling via resurrection because you create expensive
objects at a high rate of birth and death, manual memory management (or a different
design altogether) is likely your only savior.

Although Java's finalizers are also premortem, the JDK offers the facilities necessary
to implement postmortem finalization on your own. It entails using WeakReference
and ReferenceQueue. See [this article](http://java.sun.com/developer/technicalArticles/javase/finalization/)
if you are curious.

.NET doesn't offer the notifications required to do the same. You can, however,
learn from postmortem finalization to write better premotem finalizers: prefer simple
finalizable objects that refer to only the state necessary to implement finalization
-- which ordinarily means no other managed objects. The SafeHandle abstraction is
a good example of this. Most implementations are comprised of a simple IntPtr. This
pattern will ensure that collateral promotion due to finalization is more contained.

After saying all of this, I hope it is just amusing trivia. I'm sure nobody is writing
finalizers these days anyway.

