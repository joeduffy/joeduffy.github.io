---
layout: post
title: Never write a finalizer again (well, almost never)
date: 2005-12-27 10:47:45.000000000 -08:00
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
Some fundamental changes were made in the .NET Framework 2.0 that just about
obviate the need to ever write a traditional finalizer. A lot of [the guidance
written
here](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=88e62cdf-5919-4ac7-bc33-20c06ae539ae)
is now obsolete, not because it is incorrect, but rather because there is one
important new consideration to make (hosting) and a set of new tools to aid you
in the task. [Jeff Richter](http://wintellect.com/) pointed this out to all of
us a few months back.

As [Stephen Toub](http://blogs.msdn.com/toub/) discusses in depth in [his
recent MSDN Magazine article on CLR
reliability](http://msdn.microsoft.com/msdnmag/issues/05/10/Reliability/),
resources not under the protection of _critical finalizers_ are doomed for
leakage when run inside of sophisticated hosts. SQL Server uses AppDomains as
the unit of code isolation, much like Windows' use of processes. When it tears
one down, it expects there to be no resulting residual build-up over time. But
if the best you've got are ordinary finalizers to clean up resources, a rude
AppDomain unload can bypass execution of them entirely, leading to leaks over
time. This might happen if a finalizer in the queue with you takes too long to
complete, perhaps by [deadlocking on entry to a non-pumping
STA](http://blogs.msdn.com/cbrumme/archive/2004/02/02/66219.aspx), causing the
host to escalate to a rude unload.

### Critical finalizers

During a rude unload, normal finalizers are skipped, `finally` blocks aren't run,
and only critical finalizers get a chance to make the world sane again. Thus we
can immediately form a guiding principle:

> _Any resource whose natural lifetime outlasts an AppDomain must be protected
> by a critical finalizer to avoid leaks._

Notice that I say "lifetime spans an AppDomain." This is important. Finalizers
are often used for process-wide resources, such as file HANDLEs and Semaphores.
But a resource whose lifetime is limited to the enclosing process's surely
outlasts any single AppDomain; a finalizer is not good enough. Another piece of
code in the same process might be denied access to the file handle because the
(now-dead) AppDomain orphaned an exclusively-opened handle to it. Windows
ensures this HANDLE will get released when the process shuts down, but our goal
with critical finalization is to do this at AppDomain unload time (avoiding
cross-AppDomain interference). In the worst case, not doing so can actually
lead to state corruption; a process crash is then likely to ensue, taking down
a host like SQL Server with it. Imagine if two AppDomains—perhaps even
multiple processes—communicate via memory mapped I/O inside of a shared
address space. If an AppDomain gets interrupted by an unload mid-way through a
[paired
operation](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641)
and intends to clean up state in its finalizer, failure to execute the
finalizer might lead to chaos. A critical finalizer should have been used. (And
use of `BeginDelayAbort`, e.g. via a CER. But that's digging a little too deep
for now.)

Critical finalizers are somewhat easier to write when compared to ordinary
finalizers, due to the out-of-the-box plumbing that you get. But they impose
_additional_ constraints on what you can actually do at finalization time. To
implement a critical finalizer, simply subclass the
`System.Runtime.ConstrainedExecution.CriticalFinalizerObject` (CFO) type, provide
a way for users to acquire a resource (e.g. in the constructor), and override
its `Finalize` method to perform cleanup. When instantiated, your object will be
placed onto the critical-finalization object queue. CFOs can be suppressed as
usual with the `GC.SuppressFinalize` method, and can be re-registered onto the
critical-finalization queue with the `GC.ReRegisterForFinalize` method. The CLR
then ensures your object is finalized should a rude unload occur; obviously, it
also runs them in the same cases ordinary finalizers are run too: i.e. standard
GC finalization, managed shut-down, ordinary AppDomain unload, etc. There is a
weak guarantee that CFOs are finalized after other finalizable objects,
specifically to accomodate relationships like how the `FileStream` must flush its
buffer before its underlying `SafeHandle` has been released.

As noted, writing a CFO `Finalize` method is trickier than a standard finalizer
due to additional constraints. This is because it can be called from inside of
a CER if the host escalates to a rude unload. It must guarantee that state will
not be corrupted as a result of its execution and that it will never fail (i.e.
by leaking an exception). And of course you can only call non-virtual methods
that make similar guarantees. This means your code has to be written to succeed
in the most hostile of situations, for instance in situations where any attempt
to allocate memory dynamically will be rejected via an `OutOfMemoryException`. If
you let that exception leak, you've violated the contract and can expect the
host to respond in any number of ways, including crashing the process
immediately. CERs perform eager preparation to statically ensure your code can
execute, jitting the transitive closure of methods you invoke, but it's easy to
make a misstep here due to the massive number of hidden allocations in the
runtime. A box instruction allocates memory; unbox does, too, but only if
you're unboxing a `Nullable<T>`; throw has to manufacture a
`RuntimeWrappedException` if you're throwing a non-Exception object; and so
forth. And unfortunately there aren't any tools to prove that you've written
your CER correctly. Thankfully most developers write bug free code on their
first attempt. ;)

### Critical- and safe-handles

Using the base CFO type directly has a couple drawbacks. First, it doesn't
fully implement the `IDisposable` pattern. There are two convenient Framework CFO
abstract classes that do, both in the System.Runtime.InteropServices namespace:
`CriticalHandle` and `SafeHandle`.

The `CriticalHandle` type is sufficient to get critical finalization semantics:
you simply override its protected constructor and `ReleaseHandle` methods,
performing open and close operations inside of them respectively. Your
`ReleaseHandle` implementation can be called from inside of a critical
finalization CER, so as with writing CFOs by hand you must make the same
guarantees outlined above. This type provides a cleanly factored and
encapsulated interface to your users.

But more concerning is the fact that both CFO and `CriticalHandle` are still
prone to security problems that you might need to worry about if you're
building any sort of reusable Framework. BrianGru [outlines this situation
here](http://blogs.msdn.com/bclteam/archive/2005/03/16/396900.aspx). To tackle
those issues, you need `SafeHandle`. Implementing `SafeHandle` is much like
`CriticalHandle`, in that you override the protected constructor and
`ReleaseHandle` methods, and abide by CER rules inside of `ReleaseHandle`. One
additional piece is necessary, however: you must implement the abstract
`IsInvalid` property getter and return `true` or `false` to indicate whether the
`SafeHandle` refers to an invalid handle. (The `SafeHandleMinusOneIsInvalid` and
`SafeHandleZeroOrMinusOneIsInvalid` types in the `Microsoft.Win32.SafeHandles`
namespace are there to help out here, returning `true` if the handle is the value
-1 in the first case and true if the handle is the value -1 or 0 in the latter
case. A PVOID with a value of 0 (i.e. NULL), for example, would be invalid for
a handle to a memory address; `SafeHandleZeroOrMinusOneIsInvalid` would be
perfect for this.) ShawnFa [discusses implementing SafeHandle in more detail on
his blog](http://blogs.msdn.com/shawnfa/archive/2004/08/12/213808.aspx).

Your `CriticalHandle` and `SafeHandle` types should never take on additional
business-logic responsibility; make them as light-weight as possible, doing
just enough to allocate and free resources. You'll probably have a number of
other functional classes that make use of these handles. The Framework's `Stream`
types are a classic example. Such types should implement the `IDisposable`
interface and invoke `Dispose` on the underlying handle, providing an eager way
to dispose of the resource. They should furthermore take care to never publicly
expose the underlying handle, as doing so could be used to erroneously suppress
finalization on a handle, leading to resource leaks.

### Did you really mean never?

Almost. There are still several situations in which people must still write
complex finalizers. The tax they must pay for stepping outside of the simple
allocate/deallocate pattern is understanding intimately [the big mess outlined
here](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=88e62cdf-5919-4ac7-bc33-20c06ae539ae).
Most people should consider factoring their real cleanup code to use a
`SafeHandle`, and only then layering specialized code on top of that inside of a
normal finalizer.

After a brief email thread with Chris Brumme, a number of legitimate cases of
alternative finalizer patterns were identified, including:

1. Sophisticated APIs can use finalizers to return expensive objects—like
   large buffers or database connections—back to a pool, amortizing the cost
   of creating and destroying them over the life of the application.
   `System.EnterpriseServices` does this. This is one of the only cases where
   resurrection is an acceptable practice. Critical finalization should only be
   used here if resources are pooled across an entire process. Most resources are
   AppDomain-local, and thus do not qualify for CFO status.

2. Calling `GC.RemoveMemoryPressure` to compensate for a previous
   `GC.AddMemoryPressure`, used to communicate to the GC that the pressure
   associated with an object's resources is no longer a factor (because it's been
   cleaned up). This should be protected by a CFO if the resource whose pressure
   it tracks is also allocated/deallocated under a CFO. It's unfortunate that the
   `RemoveMemoryPressure` API doesn't make reliability guarantees (e.g. with
   `ReliabilityContractAttribute`). If it attempts to allocate memory—I can't
   imagine that it would—you could end up crashing the process due to an
   unhandled `OutOfMemoryException`. You could consider swallowing such exceptions,
   at the risk of violating the corruption contract. This is a crappy situation,
   but if a large quantity of pressure were leaked after an AppDomain unload, a
   skew could build up over time, affecting all parties in the process, precisely
   what we're trying to avoid by using CFOs. You need to make an intelligent
   tradeoff. We should fix this in a later release.

3. Incrementing or decrementing a performance counter or lighter-weight counter
   like a static field. This is often used to monitor the rate of
   creation/destruction of objects, and is often turned off in retail builds.
   Assuming imprecise counting is OK—e.g. if it's used only for testing
   purposes—this should not use a CFO. If you do use a CFO, you have you follow
   the guidelines above. For light-weight counters this is easy (i++ and i--
   traditionally don't allocate memory); but for performance counters it is not.

4. Asserting to find cases where an object should have been, but was not,
   eagerly cleaned up using the `IDisposable` pattern. Properly written eager
   disposal is supposed to call `GC.SuppressFinalization` to eliminate the assert.
   It would be inappropriate to use CFOs for this purpose. Finally blocks will not
   run under a rude unload (which includes Dispose methods), and thus under any
   rude unload situation your CFO will fire.

5. Some external resources have elaborate rules for sequencing cleanup. The COM
   ADO APIs (not ADO.NET) require that fields are cleaned up before rows, which
   must precede tables, which must precede connections. If objects are cleaned up
   in a free-threaded manner or in the wrong order, memory corruption will occur.
   In other words, they violate the standard COM pUnk AddRef/Release rules.
   Outlook exposes COM APIs with similar sequencing rules. This is traditionally
   addressed by writing elaborate finalization code that walks the graph on the
   managed side and initiates the sequenced cleanup. This is the trickiest of all.
   If you can guarantee you follow the CFO rules outlined above, this probably
   belongs in a critical finalizer. But it's quite easy to make a misstep...you're
   basically playing with dynamite at this point.

If you decide you must write a finalizer, it's still important to follow [the
pattern described
here](http://joeduffyblog.com/2005/04/08/dg-update-dispose-finalization-and-resource-management/),
or the condensed version in the _ [.NET Framework Design
Guidelines](http://www.amazon.com/exec/obidos/redirect?link_code=ur2&camp=1789&tag=bluebytesoftw-20&creative=9325&path=tg/detail/-/0321246756/qid=1123679961/sr=8-1/ref=sr_8_xs_ap_i1_xgl14?v=glance%26s=books%26n=507846)_
book. This facilitates seamless integration with VC++ 2005's new destructor,
Dispose, and finalization unification features.

### Summary

At first glance, it appears that the world is simpler with CFOs. But when you
consider that you have to abide by the same rules for normal finalizers plus
the new ornery CER rules, life still isn't very simple at all.
`CriticalFinalizerObject` makes sure your resources don't leak during hostile
takeovers, and `SafeHandle` makes life more secure and a little easier in that
the plumbing required to get `IDisposable` hooked up is all built for you, but
one thing remains the same: Interoperating with unmanaged code is tricky stuff.
But thankfully [the world will be written in nothing but managed code sometime
in the near future](http://channel9.msdn.com/Showpost.aspx?postid=141858). Then
we can get rid of all of this hairy finalization code once and for all.

