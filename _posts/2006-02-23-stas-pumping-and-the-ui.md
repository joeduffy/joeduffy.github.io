---
layout: post
title: STAs, pumping, and the UI
date: 2006-02-23 12:37:08.000000000 -08:00
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
When you perform a wait on the CLR, we make sure it happens in an STA-friendly
manner. This entails using msg-waits, such as MsgWaitForMultipleObjectsEx
and/or CoWaitForMultipleHandles. Doing so ensures we pick up and dispatch
incoming RPC work mid-stack, while the STA isn't necessarily sitting in a
top-level message loop. In fact, an STA that doesn't pump temporarily can
easily lead to temporary and permanent hangs (i.e. deadlocks), especially in
common COM scenarios where reentrant calls across apartments are made (e.g.
MTA->STA->MTA->STA). Even where deadlock isn't possible, failing to pump can
have a ripple effect across your process, as components wait for other
components to complete intensive work.

I was recently writing about this fact for an article, and realized I had
leaped to an incorrect assumption. OLE creates special RPC windows for
processing these apartment transitions. I knew that. But I had assumed that we
blatently pump for messages for any windows. But in reality, we don't. We only
pump the special "WIN95 RPC Wmsg", "OleMainThreadWndClass", and
"OleObjectRpcWindow" RPC windows. Consider why.

If you were on a UI and you pumped your window's message queue, you could end
up dispatching new events before old events had completed. If you dispatched a
WM\_CLOSE message on the same stack you were doing some other UI processing,
you'd destroy the window before that other processing was done. Without the GUI
message loop taking this into account somehow, you'd crash. There are other
factors. Imagine you were processing a click event that required movement of
several UI elements. If some bit of infrastructure--or perhaps your code--ended
up pumping, UI invariants could be broken. (Lots of FX code pumps for RPC, by
the way.) At best, this could lead to strange visual artifacts, and at worst a
crash.

You'd also have to deal with the subtleties of reentrancy. [I've written about
this
before](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=1ca19b0e-ef5b-4efc-b614-48d8c913efb9).
Imagine a UI event had waited on an auto-reset event, did some work, and then
set the event. If another event--perhaps the same type--were dispatched while
it was doing "some work," it might try to wait on this same event. This would
be a deadlock. A pretty difficult one to track down too, especially if it only
occurred if the user clicked on certain elements at precise timings to get the
reentrancy to occur. This is already a problem with COM interop. But thankfully
we don't burden Windows Forms and WPF programming with it too.

