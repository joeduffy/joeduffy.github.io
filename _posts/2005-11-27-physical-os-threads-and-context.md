---
layout: post
title: Physical OS threads and context
date: 2005-11-27 21:50:32.000000000 -08:00
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
Each Windows thread has a Thread Environment Block (i.e. TEB) which is a block
of user-mode memory pointed at and reserved for use by the Windows kernel
Thread data structure (KTHREAD). In addition to basic OS information like the
active SEH filter chain, stack base and limit, and owned critical sections,
applications can easily stash data into and retrieve data out of the Thread
Local Storage (TLS) area of the TEB. This is done using the Win32 TlsAlloc,
TlsGetValue, TlsSetValue, and TlsFree functions. You can view the TEB via the
kernel debugger's !thread command.

(The CLR of course offers TLS functionality too, i.e. using ThreadStatics and
the System.Threading.Thread's AllocateDataSlot, SetData, and GetData functions.
This information does go into the TEB, but it is managed by the CLR. A call to
SetData does not translate directly to a call to TlsSetValue.)

Win32--and Windows in general--makes liberal use of thread-local memory. I
noted a few uses above (e.g. exception handlers) which are pervasive. Such
usage creates an implicit affinity between the workload running on the thread
and the physical OS thread itself. What do I mean by affinity? Simply that the
work executing on a thread must continue executing on that exact physical
thread for it to remain correct. This affinity isn't documented consistently
nor is it easy to detect. You might be able to weasel around it by chance. But
it makes it extraordinarily difficult to transfer logical work from one
physical thread to another.

Imagine what would happen if we made a call to some Win32 function and then
decided to swap out the logical work so that we could install new work.
SetLastError might have been used to communicate a failure in a function called
on either the thread the work is being swapped out of, or the destination once
it gets rescheduled. But SetLastError installs the error information into the
TEB. GetLastError will then either fail to retrieve information or, more
likely, will retrieve somebody else's information, either of which would lead
to all sorts of serious problems. Similar issues can happen if we (foolishly)
tried to swap out a thread that owned a critical section, or some other
thread-specific resource (like a mutex).

This is one major reason why fibers are still problematic as a general task
scheduling solution for Windows. And it's a challenge if you even want to
consider user-mode scheduling a la continuations. You just can't get around the
platform's hidden thread affinity. We've done much better in managed code. Over
time we are trying to use ExecutionContext as the currency for logical context
information, which can be easily captured and restored by the runtime. But
there are examples where we violate this (e.g. monitors), where we use the
physical OS thread as the context (be fair: we do notify hosts of such
situations via Thread.Begin/EndThreadAffinity).

But you can't escape the fact that the runtime itself is built right on top of
Win32.

