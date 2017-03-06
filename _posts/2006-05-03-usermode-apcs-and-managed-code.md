---
layout: post
title: User-mode APCs and managed code
date: 2006-05-03 20:53:38.000000000 -07:00
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
Raymond's [recent
post](http://blogs.msdn.com/oldnewthing/archive/2006/05/03/589110.aspx) talks
about queueing user-mode APCs in Win32.

When you block in managed code, the CLR is responsible for figuring out the
correct style of wait. This ends up in a `CoWaitForMultipleHandles` (on Win2k+)
or `MsgWaitForMultipleObjectsEx` if you're executing in an STA; else, this ends
up in a non-pumping wait, such as
`WaitForSingleObjectEx`/`WaitForMultipleObjectsEx`. In any case, the wait is
alertable, meaning that user-mode APCs will have a chance to run. There are
various blocking calls hidden in Win32 and the CLR itself, so it's not
guaranteed that all waits are alertable; but any that originate from managed
code are, which we hope is a significant percentage.

This code illustrates a simple user-mode APC reentering as we do an alertable
wait (via `Thread.CurrentThread.Join(0)`):

    using System;
    using System.Runtime.InteropServices;
    using System.Threading;

    static class Program {
      static void Main() {
        QueueUserAPC(
          delegate { Console.WriteLine("APC fired"); },
          GetCurrentThread(), UIntPtr.Zero);

        Console.WriteLine("Doing join");
        Thread.CurrentThread.Join(0);
        Console.WriteLine("Finishing join");
      }

      delegate void APCProc(UIntPtr dwParam);

      [DllImport("kernel32.dll")]
      static extern uint QueueUserAPC(APCProc pfnAPC, IntPtr hThread, UIntPtr dwData);

      [DllImport("kernel32.dll")]
      static extern IntPtr GetCurrentThread();
    }

While this technique seems like an effective way to reuse a thread while it is
blocked -- for example, you might contemplate doing this for thread-pool
threads -- a little problem called thread affinity tends to arise. [I wrote
about this in terms of COM reentrancy
before](http://joeduffyblog.com/2005/07/22/pump-me-baby-one-more-time-and-break-my-invariants/).
An APC reentering doesn't perform a context transition, so even if we used a
logical context to store such state, the problem would still exist. The simple
fact is that user-mode APCs are good for system bookkeeping, but not for
running general purpose code that modifies arbitrary program state.

