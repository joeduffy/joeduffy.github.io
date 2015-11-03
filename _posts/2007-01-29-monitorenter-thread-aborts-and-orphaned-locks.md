---
layout: post
title: Monitor.Enter, thread aborts, and orphaned locks
date: 2007-01-29 19:07:48.000000000 -08:00
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
I [previously mentioned](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641)
the X86 JIT contains a "hack" to ensure that thread aborts can't sneak in between
a _Monitor.Enter(o)_ and the subsequent try-block.  This ensures that a lock
won't be leaked due to a thread abort occurring in the middle of a _lock(o)
{ S1; }_ block.  In the following example, that means an abort can't be triggered
at _S0_:

```
Monitor.Enter(o);
S0;
try {
    S1;
}
finally {
    Monitor.Exit(o);
}
```

If an abort could happen at _S0_, it'd be possible for a thread to acquire lock _o_,
but before entering the try block, be asynchronously aborted, and then not run
the finally block to release the lock on _o_.  This would lead to an orphaned
lock, and probable deadlocks later on during execution.  Debugging an instance
of such a deadlock would of course be rather difficult because it depends on a very
subtle race condition that must occur within the tiny window of a single
instruction.  On a single-processor machine, this would require a precariously
placed context switch, but as more and more cores are added to the machines that
this software runs on, the probability simply increases.

Characterizing this as a "hack" was a little harsh.  It's really just a byproduct
of the way that the X86 JIT generates code.

For an asynchronous thread abort to be thrown in a thread, that thread must be either:
(1) polling for the abort in the EE or (2) running inside of managed code.
And even if the thread is in managed code, we may not be able to abort it, as is
the case if the thread is currently executing a finally block, inside a constrained
execution region, etc.  The C# code generation for the lock statement ensures
there are no IL instructions between the CALL to _Monitor.Enter_ and the instruction
marked as the start of the try block.  The JIT correspondingly will not insert
any machine instructions in between the two.  And since any attempted thread
aborts in _Monitor.Enter_ are not polled for after the lock has been acquired and
before returning, the soonest subsequent point at which an abort can happen
is the first instruction following the call to _Monitor.Enter_.  And at that
point, the IP will already be _inside_ the try block (the return from _Monitor.Enter
_returns to the CALL+1), thereby ensuring that the finally block will always run
if the lock was acquired.

This might seem like an implementation detail, but the reality is that we can never
change it.  Too many people depend on this guarantee.

It turns out that Whidbey's X64 JIT does not guarantee this behavior.
(I suspect IA64 doesn't either, but don't know for sure.)  In fact there's a
high probability that this won't work: there is always a NOP instruction before the
CALL and the instruction marking the try block in the JITted code.  This is
done to make it easier to identify try/catch scopes during stack unwind.
This means that, yes indeed, an abort can happen at _S0_ on 64-bit.

This will likely be fixed for the next runtime release, but I can't say for sure.

**Update 4/17/08**: _This was indeed fixed for the X64 JIT in Visual Studio
2008.  Note that when compiling C# code targeting both X86 and X64, if you do
not use the /o+ switch, this problem can still occur due to extra explicit NOPs inserted
before the try._

The framework implements a method _Monitor.ReliableEnter_, by the way, that could
be used to avoid orphaning locks in the face of thread aborts, but it's internal
to mscorlib.dll.  It sets an out parameter within a region of code that cannot
be interrupted by a thread abort, which the caller can then check inside the finally
block.  The acquisition then gets moved inside so that, if the CALL is
reached, the finally block is guaranteed to always run.  You'd then write
this instead:

```
bool taken;
try {
    Monitor.ReliableEnter(o, out taken);
    S1;
}
finally {
    if (taken)
        Monitor.Exit(o);
}
```

It's also possible the CLR team would expose this API in the future.  We wanted
to in Whidbey, but didn't have enough time.  If 64-bit code generation was changed
so that it doesn't emit a NOP before the try block, however, we probably wouldn't
need _ReliableEnter_ after all.

