---
layout: post
title: Musing on messages and blocking
date: 2010-01-08 00:11:39.000000000 -08:00
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
Sometimes you need to wait for something before proceeding with a computation.

Perhaps you need to know the value of some integer that is being computed concurrently.
Maybe you need to wait for the bytes to flush to disk before telling another process
the file is consistent and ready to read.  Or you need to get that next row
back from the database before painting it on the UI.  It could be that you need
to wait for the missile to leave the bay before closing the bay door.  And so
on.

And sometimes there's simply nothing better to do while waiting for these things
to happen other than to let the CPU halt (or let other processes on the machine run).
You need to twiddle your thumbs a bit, and exhibit a little patience.  Or at
least your program does.  This is simply an unfortunate fact of life.

This manifests numerous ways in our programming models:

1. Waiting on an event.
2. Waiting to acquire an already-held lock.
3. Finding that the GUI message queue is empty and doing a MsgWaitForMultipleObjectsEx.
4. Finding that the COM RPC queue is empty and doing a CoWaitForMultipleHandles.
5. Issuing an Ada rendezvous 'accept' and finding that no messages await you, thus blocking.
6. Issuing an Erlang 'receive' and finding that no messages await you, thus blocking.
7. Waiting on a .NET 4.0 task.
8. Issuing a ContinueWith on a .NET 4.0 task.
9. And so on.

There are three big distinctions to make about the characteristic nature
of this waiting: namely, (1) what condition's establishment is being sought
-- i.e. the reason for the wait, (2) whether multiple such conditions of interest
may be waited on simultaneously, and, related, (3) whether waiting for said condition(s)
necessarily means that the processing of some other conditions that may arise elsewhere,
but require the blocked context to run, cannot occur.

I will be the first to admit that this statement is rather abstract.  But it
really does matter.

For example, MsgWaitForMultipleObjectsEx is a pumping wait.  Not only do you
wait for the occurrence of one of several events to get set, but the arrival
of a new top-level message at the message queue (either GUI or COM RPC-related) causes
immediate processing of that message, presuming the thread is blocked at that call
at the time.  Although you can be deeply nested in some complicated code, you
"jump" to the event loop to run the message handling code.  Vanilla WaitForMultipleObjectsEx
works in a similar way vis-à-vis APCs, provided the wait is alertable.  This
is quite different from a fully blocking non-pumping wait, which only waits for one
or more very specific events, but does not dispatch messages simultaneously.

Win32 esoterica aside, the concepts appear elsewhere.  The moral equivalent
in Ada or Erlang is to do a selective-accept or -receive, intentionally not dispatching
certain messages that might arrive in the meantime.  (To be fair, you can also
do this in COM with message filters.)  This often happens when you nest accepts
and receives.  You may be capable of processing messages A-Z at the top-level
tail recursive loop; but if that nested accept only knows about message kinds M and
N, then there are 24 other kinds that will not be picked up in the meantime.

Not pumping for messages is dangerous.  And it can lead to deadlock if you pump
for the wrong ones.  Like if you're accepting M or N, yet the triggering of
M or N depends on first processing some message K waiting in the queue.  COM
RPCs with cycles run face first into this.  And/or not pumping can lead to responsiveness
and scalability problems.  Perhaps M or N eventually does arrive, yet little
old K needs to wait an indeterminate amount of time before it is seen.  Whereas
we could have overlapped its processing.  This is why most STAs pump while waiting,
and, similarly, why many Erlang processes consist of a main loop that is prepared
to handle any message the process accepts at that top level loop.  They may
seem very different but they are strikingly not.

Yet paradoxically pumping for messages is also dangerous.  You must predict
all the kinds of messages that may reentrantly get executed, and your state at the
point of the blocking call must be consistent enough to tolerate them.  (At
least those that will actually happen.)  In COM STAs, this can be wholly unpredictable
and indeed because the CLR auto-pumps on STAs the blocking points can be hidden.
Overly aggressively admitting messages may seem like the right thing to do, until
you've wedged yourself into some unforeseen inconsistent state.  You can avoid
this by making each message handler atomic; see Argus.  But if you can't or
don't have the discipline to do that, or aren't quite sure, you must not pump.
You either avoid pumping altogether or you selectively pump messages that do
not touch the state encapsulated by the pump.  Or you lock access to state with
a non-recursive lock and run the risk of deadlock.

I have found it clarifying to think about blocking in event loop concurrency
and state machine terms, advancing from one state to the next in between waits.
It's a slippery model, but particularly when working in message passing systems
that employ event loops, it can help to identify all the familiar problems with shared
memory, blocking, and consistency.

Indeed it is interesting how blocking and non-blocking systems can rapidly approach
each other.  Starting from either extreme tempts you to tiptoe closer and closer
to the middle.  The familiarity of the other extreme tempts you.  Until,
alas, you just might meet in the middle.

