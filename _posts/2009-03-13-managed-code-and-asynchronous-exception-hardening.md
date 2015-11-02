---
layout: post
title: Managed code and asynchronous exception hardening
date: 2009-03-13 13:24:25.000000000 -07:00
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
Managed code generally is not hardened against asynchronous exceptions.

"Hardened" simply means "written to preserve state invariants in the face of
unexpected failure."  In other words, hardened code can tolerate an exception
and continue being called subsequently without a process or machine restart.
Conversely, code that is not hardened may react sporadically if continued use is
attempted: by corrupting state and subsequently behaving strangely and unpredictably.

Asynchronous exceptions are a foreign concept to native programmers, and arise because
there is a runtime underneath all managed code that is silently injecting code on
behalf of the original program.  The only truly asynchronous exception is ThreadAbortException,
but any in the set { OutOfMemoryException, TypeInitializationException, ThreadInterruptedException,
StackOverflowException } are often labeled as such.  While thread aborts can
happen at any line of code outside a delay-abort regions, these other exceptions
can be introduced by the CLR at surprising times; i.e., { memory allocations, static
member access, blocking calls, any function call }.  The effect is that, unlike
most exceptions, the points at which they may occur are not obvious.  OOMs,
for instance, can happen at any method call (due to failure to allocate memory in
which to JIT code), implicit boxing, etc.

(As of 2.0, StackOverflowException is no longer relevant because SO triggers a FailFast
of the process instead.  So saying that managed code is not hardened against
SO is an understatement.)

Also, because of the way COM reentrancy works, any blocking call can lead to any
arbitrary code dispatched through STA pumping.  And that arbitrary code, much
like an APC, can fail via any arbitrary exception.  These are a lot like asynchronous
exceptions.  So in truth, code that isn't written to respond to arbitrary
exceptions at all blocking points is technically not hardened either.

.NET doesn't provide checked exceptions, so the blunt reality is that very little
managed code is hardened properly to synchronous exceptions either.  I think
we do a better job in the framework of carefully engineering the code to resiliently
tolerate failure, usually by being very careful about argument validation, but we
aren't perfect.  Some things slip through.

If you stop to think about why hardening isn't done, it's probably obvious.
It's darn difficult.  Especially for asynchronous exceptions where nearly
every line of code must be considered.  In Win32 programming, most failure points
are indicated by return codes.  (Although C++ exceptions can sneak through the
cracks at surprising times.  Like the fact that EnterCriticalSection can throw.)
While error codes are cumbersome to program against (since every call needs to be
checked for a plethora of conditions, making it easy to miss something), at least
the response to failure is explicit.  You can decide to propagate and leave
state corrupt, fix up state and then propagate, rip the process, or ignore the failure,
as appropriate.  This becomes part of the API contract.  In managed code,
you need to know to wrap such calls in try/catch blocks.  Nobody does this.
It's insane to even consider doing that.  And because nobody does, you can't
even catch exceptions coming out of a single API call and know that, when faced with
an OOM (for example), that all code on the propagating callgraph has transitively
handled the failure in a controlled manner.  The very fact that the lock{} statement
auto-unlocks without rolling back corrupt state should be indication enough of the
current state of affairs.

An instance of any of the aforementioned exceptions means the AppDomain is toast.

By toast, I mean that it's soon going to be unusable, and hopefully actively being
unloaded.  Code in the framework assumes this, and you should too.  All
it does is try to get out of the way by not crashing or hanging the ensuing unload.
A small fraction of code that deals with process-wide state comprised of resources
not under the purview of the CLR GC needs to worry about running and avoiding leaks.
This is where things like [CERs](http://blogs.msdn.com/bclteam/archive/2005/06/14/429181.aspx),
[CriticalFinalizerObjects](http://www.bluebytesoftware.com/blog/2005/12/27/NeverWriteAFinalizerAgainWellAlmostNever.aspx),
and [paired operations stuck in finally blocks](http://www.bluebytesoftware.com/blog/2005/03/19/AtomicityAndAsynchronousExceptionFailures.aspx)
come into play.  They ensure cross-process state is freed, and that asynchronous
exceptions cannot occur in places that would crash or hang a clean unload.

Unfortunately, it's not always the case that the AppDomain is unloading when such
an exception occurs:

- Somebody can call Thread.Abort directly, without killing the AppDomain.  They
can either call ResetAbort and keep it around, or let it return to the ThreadPool
which catches and swallows aborts.  In fact, we tell people that synchronous
aborts a la Thread.CurrentThread.Abort is "always safe", whereas we tell people
asynchronous aborts are dangerous and best avoided.

- Some framework infrastructure, most notably ASP.NET, even aborts individual threads
routinely without unloading the domain.  They backstop the ThreadAbortExceptions,
call ResetAbort on the thread and reuse it or return it to the CLR ThreadPool.
That means any code running in ASP.NET is apt to be corrupted when websites are recycled
and AppDomain isolation is not being used.

- Assume AppDomain B is being unloaded.  If some thread has called from A to
B to C, the thread will immediately suffer an abort.  The result is that C will
see a thread unwinding with a ThreadAbortException, back into B, and then back to
A, at which point the exception turns into a deniable AppDomainUnloadedException
that can be caught.  But C has seen an in-flight abort and yet it is not being
unloaded.  The result is that C's state may be completely corrupt.  I
believe this should be considered a bug in the CLR.

- We can't differentiate between soft- and hard-OOMs today.  The former are
caused by requests to allocate large blocks memory.  Often a failure here isn't
indicative of a disaster.  It may be due to a need to allocate 1GB of contiguous
memory, and perhaps there is fragmentation.  Hard OOMs are often caused by running
up against the edge of the machine where no pagefile space is available, and may
indicate a failure to JIT some important method, among other things.  But because
we don't differentiate, any managed code can catch-and-ignore any kind of OOM,
including hard ones.

- Thread interruptions are often used as a form of inter-thread communication.
For example, they can be used as a poor man's cancellation.  (This is inappropriate,
and cooperative techniques should always be used.  But it is widespread.)
But because they are used as a means of communication, they are almost always caught
and handled in some controlled manner.  This is one place where we screwed up
by not hardening the frameworks against interrupted blocking calls and reacting intelligently.
Checked exceptions would have saved us.

What does all of this mean?  Quite simply, the .NET Framework cannot be trusted
when any of the aforementioned exceptions are thrown.  Ideally the process will
come tumbling down shortly thereafter, but improperly written code can catch them
and continue trying to limp along.  In fact, as I mentioned above, some wildly
popular & successful application models do (notably, ASP.NET and WinForms).

This state of affairs is admittedly unfortunate.  We don't properly separate
out the truly fatal exceptions from those that we can gracefully recover from.
In an ideal world, I'd love to see us do that.  For example:

1. At some point, we really ought to consider FailFast instead of continuing to run
code under failures we know are fatal and dangerous to attempt to recover from, much
like we do with SO.  At least these failures should be undeniable like thread
aborts are.  But this is a fairly Byzantine response and is not for the faint
of heart.  Given that we still live in a world where WinForms wraps the top-most
frame of the GUI thread in a catch-all, presents a dialog box, and allows a user
to click "Ignore & Continue", I seriously doubt we'll get there anytime soon.

2. Never expose a ThreadAbortException to code in an AppDomain unless we can guarantee
the AppDomain is being unloaded.  That means getting rid of the Abort API, and
thus indirectly disallowing code from catching and calling ResetAbort.  It also
means the A calls B calls C case would not allow B to unload until the thread voluntarily
unwinds out of C.

3. Allow OOMs to be caught only when they are soft.  That means a call to 'new',
and it means the catch much occur inside the same stack frame as the call to 'new'.
Such exceptions can be tolerated if code is properly written, and we will tell developed
to be mindful of them.  Once such an OOM propagates past the calling stack frame,
they will escalate to hard.

4. All other OOMs are hard and fatal.  This includes failure to allocate memory
to JIT code and failure to allocate 20 bytes to box an int.  Hard OOMs are thus
undeniable.

5. Get rid of ThreadInterruptedExceptions.  We screwed this up from Day One,
and it's probably too late to fix this.  We added cooperative cancellation
in .NET 4.0 for a reason.

6. TypeInitializationExceptions can probably stay, but we should allow rerunning
the cctor upon subsequent accesses.  Today, once a class C throws from its cctor,
the class can never be constructed.  So on the current plan, it only makes sense
to FailFast.

I'm sure there are many other things we could do to improve things.  But these
6 general themes would be a great start.

I'm just spitballing here.  There are no concrete plans to do any of these
6 things as far as I know.  And at the end of the day, hardening only improves
the statistics of the situation, so it tends to be very difficult to argue for one
change over another, particularly if taking the change would make existing programs
break.  But I really would like to see the base level of reliability in managed
code improve with time.  Especially with the exciting work going on around [contract-checking
in the BCL](http://blogs.msdn.com/bclteam/archive/2009/02/23/preview-of-code-contract-tools-now-available-melitta-andersen.aspx) in
Visual Studio 10, I hope these topics become top-of-mind for folks again in the near
future.

