---
layout: post
title: Concurrency and the impact on reusable libraries
date: 2006-10-26 13:05:12.000000000 -07:00
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
The meat of this article is in section II, where a set of best practices are listed.
If you're not interested in the up-front background and high level direction—or
you've heard it all before—I suggest skipping ahead right to it.

As has been widely publicized recently, mainstream computer architectures in the
future will rely on concurrency as a way to improve performance.  This is in
contrast to what we've grown accustomed to over the past 30+ years (see [Olukotun,
05](http://acmqueue.com/modules.php?name=Content&pa=showpage&pid=326) and [Sutter,
05](http://acmqueue.com/modules.php?name=Content&pa=showpage&pid=332)): a constant
increase in clock frequency and advances in superscalar execution techniques.
In order for software to be successful in this brave new world, we must transition
to a fundamentally different way of approaching software development and performance
work.  Simply reducing the number of cycles an algorithm requires to compute
an answer won't necessarily translate into the fastest possible algorithm that
scales well as new processors are adopted.  This applies to client & server
workloads alike.  Dual-core is already widely available—Intel Core Duo is
standard on the latest Apples and Dells, among others—with quad-core imminent (in
early 2007), and predictions of as many as 32-cores in the 2010-12 timeframe.
Each core could eventually carry up to 4 hardware threads to mask memory latencies,
equating to 128 threads on that same 32-core processor.  This trend will continue
into the foreseeable future, with the number of cores doubling every 2 years or so.

If we want apps to get faster as new hardware is purchased, then app developers need
to slowly get onto the concurrency bandwagon.  Moreover, there is a category
of interesting apps and algorithms that only become feasible with the amount of compute
power this transition will bring—what would you do with a 100 GHz processor?—ranging
from rich immersive experiences complete with vision and speech integration to deeper
semantic analysis, understanding, and mining of information.  If you're a
library developer and want your libraries to fuel those new-age apps, then you also
need to hop onto the concurrency bandwagon.  There is a catch-22 here that we
must desperately overcome:  developers probably can't build the next generation
of concurrent apps until libraries help them, but yet we typically wouldn't decide
to do large-scale proactive architectural and design work for app developers until
they were clamoring for it.

Although it may sound rather glamorous & revolutionary at first, this transformation
won't be easy and it certainly won't happen overnight.  Our libraries will
slowly and carefully evolve over time to better support this new approach to software
development.  We've done a lot of work laying the foundation over the .NET
Framework's first 3 major releases, but this direction in hardware really does
represent a fundamental shift in how software will have to be written.

This document exposes some issues, articulates a general direction for fixing them,
and, hopefully, will stimulate a slow evolution of our libraries.  App developers
will want to take incremental advantage of these new architectures as soon as possible,
ramping up over time.  The practices in here are based on experience.
My hope is that many of them (among others) are eventually integrated into libraries,
tools, and standard testing methodologies over time.  Nobody in their right
mind can keep all these rules in their head.

## I. The 20,000 Foot View

There are several major themes library developers must focus on in their design and
implementation in order to prepare for multi-core:

* A. The level of reliability users demand of apps built on the .NET Framework
    and CLR is increasing over time.  Being brought in-process with SQL Server made
    the CLR team seriously face this fact in Whidbey.  At the same time, with the
    introduction of more concurrency, subtle timing bugs—like races and deadlocks—will
    actually occur with an increasing probability.  Those rare races that would
    have required an obscure 5-step sequence of context switches at very specific lines
    of code on a uni-processor, for example, will start surfacing regularly for apps
    running on 8-core desktop machines.  Library authors have gotten better over
    time at finding and fixing these types of bugs during long stress hauls before shipping
    a product, but nobody catches them all.  Fixing this will require intense testing
    focus on these types of bugs, hopefully new tools, and the wide-scale adoption of
    best practices that statistically reduce the risk, as outlined in this doc.

* B. Nobody has seriously worked out the scheduling mechanisms for massively
    concurrent programs in detail, but it will likely involve some form of user-mode
    scheduling that keeps logical work separate from physical OS threads.  Unfortunately,
    many libraries assume that the identity of the OS thread remains constant over time
    in a number of places—something called thread affinity—preventing two important
    things from happening: (1) multiple pieces of work can't share the same OS thread,
    i.e. it has become polluted, and (2) a user-mode scheduler can no longer move work
    between OS threads as needed.  Windows's GUI APIs are notorious for this,
    including the Shell APIs, in addition to the reams of COM STA code written and thriving
    in the wild.  Fibers are the "official" mechanism on Windows today for user-mode
    scheduling, and—although there are several problems today—the CLR and SQL Server
    teams have experience trying to make serious use of them.  Regardless of the
    solution, thread affinity will remain a problem.

* C. Scalability via concurrency will become just as important -- if not more
    important (eventually, for some categories of problems) -- than sequential performance.
    If you assume that most users will try using your library in their now-concurrent
    programs, you also have to assume they will notice when you take an overly coarse
    grained lock, block the thread unexpectedly, or pollute the physical thread such
    that work can't remain agile.  Moreover, a compute-intensive sequential algorithm
    lurking in a reusable library and exposed by a coarse-grained API will eventually
    lead to scalability bottlenecks in customer code.  Faced with such issues, developers
    will have no recourse other than to refactor, rewrite, and/or avoid the use of certain
    APIs.  And even worse, they'll learn all of this through trial & error.

* D. It's not always clear what APIs will lead to synchronization and variable
    latency blocking.  If a customer is trying to build a scalable piece of code,
    it's very important to avoid blocking.  And of course GUI developers must
    avoid blocking to maintain good responsiveness (see [Duffy, 06c](http://www.ddj.com/dept/windows/192700235)).
    But if blocking is inevitable, either because of an API design or architectural issue,
    developers would rather know about it and choose to use an alternative asynchronous
    version of the API—such as is used by the System.IO.Stream class—or take the
    extra steps to "hide" this latency by transferring the wait to a spare thread
    and then joining with it once the wait is done.  Libraries need to get much
    better at informing users about the performance characteristics of APIs, particularly
    when it comes to blocking.  And everybody needs to get better at exposing the
    power of Windows asynchronous IO through APIs that use file and network IO internally.

These are all fairly dense and complex issues, and are all intertwined in some way.
Many of them can be teased apart and mitigated by following a set of best practices.
This is not to say they are all easy to follow.  These guidelines should evolve
as we as a community learn more, so please let me know if you have specific suggestions,
or ideas about how we can make this list more useful.  I seriously hope these
are reinforced with library and tool support over time.

## II. The Details

### Locking Models

#### Static state must be thread-safe.

Any library code that accesses shared state must be done thread-safely.  For
most managed code-bases this means that all accesses to objects reachable through
a static variable (i.e. that the library itself places there) must be protected by
a lock.  The lock has to be held over the entire invariant under protection—e.g.
for multi-step operations—to ensure other threads don't witness state inconsistencies
in between the updates.  Protecting multi-step invariants requires that the
granularity of your lock is big enough, but not so big that it leads to scalability
problems.  Read-modify-write bugs are also a common mishap here; e.g. if you're
updating a lightweight counter held in a static variable, it must be done with an
Interlocked.Increment operation, under a lock, or some other synchronization mechanism.

Reads and writes to statics whose data types are not assigned atomically (&gt;32 bits
on 32-bit, &gt;64 bits on 64-bit) also need to happen under a lock or with the appropriate
Interlocked method.  If they are not, threads can observe "torn values";
for example, while one thread writes a 64-bit value, 0xdeadbeefcafebabe to a field—which
actually involves two individual 32-bit writes in the object code—another thread
may run concurrently and see a garbage value, say, 0xdeadbeef00000000, because the
high 32-bit word was written first.  Similar problems can happen to GUID fields
on all architectures, for instance, because GUIDs are 128 bits wide.  Longs
on 32-bit machines also fall into this category, as do value types built out of said
data types.

This responsibility doesn't extend to accesses to instance fields or static fields
for objects that library users explicitly share themselves.  In other words,
only if the library makes state accessible through a static variable does it need
to protect it with synchronization.  In some cases, a library author may choose
to make a stronger guarantee—and clearly document it—but it should certainly
be the exception rather than the default choice, for instance with libraries specific
to the concurrency domain.

#### Instance state doesn't need to be thread-safe.  In most cases it should not be.

Protecting instance state with locks introduces performance overhead that is often
ill-justified.  The granularity of these locks is typically too small to protect
any operation of interesting size in the app.  And if the granularity might
be wrong you need to expose implementation locking details or it was a waste of time.
Claiming an object performs thread-safe reads/writes to instance fields can even
give users a false sense of safety because they might not understand the subtleties
around locking granularity.

In V1.0 the .NET Framework shipped synchronizable collections with SyncRoots, for
example, which in retrospect turned out to be a bad idea:  customers were frequently
bitten by races they didn't understand; and, for those who kept a collection private
to a single thread or used higher level synchronization rather than the collection's
lock, the performance overhead was substantial and prohibitive.  Thankfully
we left that part of the V1.0 design out of our new V2.0 generic collections.
We still have numerous types that claim "This type is thread-safe" in the MSDN
docs, but this is typically limited to simple, immutable value types.

#### Use isolation & immutability where possible to eliminate races.

If you don't share and mutate data, it doesn't need lock protection.
CLR strings and many value types, for example, are immutable.  Isolation can
be used to hide intermediate state transitions, although typically also requires
that multiple copies are maintained and periodically synchronized with a central
version to eliminate staleness.  Sometimes this approach can be used to improve
scalability particularly for highly shared state.  Many CRT malloc/free implementations
will use a per-thread pool of memory and occasionally rendezvous with a central process-wide
pool to eliminate contention, for example.

#### Document your locking model.

Most library code has a simple locking model:  code that manipulates statics
is thread-safe and everything else is not (see #1 and #2 above).  If your internal
locking schemes are more complex, you should document those using asserts (see below),
good comments, and by writing detailed dev design docs with information about what
locks protect what data to help others understand the synchronization rules.
If any of these subtleties are surfaced to users of your class then those must also
be explained in product documentation and, preferably, reinforced with some form
of tools & analysis support.  COM/GUI STAs, for example, are one such esoteric
scheme, where the locking model leaks directly into the programming model.
As a community, we would be best served if new instances of such specialized models
are few and far between; I for one would be interested in hearing of and understanding
any such cases.

### Using Locks

#### Use the C# 'lock' and VB 'SyncLock' statements for all synchronized regions.

Following this guidance ensures that locks will be released even in the face of
asynchronous thread aborts, leading to fewer deadlocks statistically.  The code
generated by these statements is such that our finally block will always run and
execute the Monitor.Exit if the lock was acquired.  This still doesn't protect
code from rude AppDomain unloads—but this is not something most library developers
have to worry about, except for reliability-sensitive code that maintains complex
process-wide memory invariants, such as code that interops heavily with native code.
(See [Duffy, 05](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641)
for more details.)

If you decide to violate this guidance, it should be for one of two reasons: (1)
you need to use a CER to absolutely guarantee the lock is released in rude AppDomain
unload cases—perhaps because a lock will be used during AppDomain tear-down and
you'd like to avoid deadlocks—or (2) you have some more sophisticated Enter/Exit
pattern that is not lexical.  For (1) I would recommend talking to somebody
at Microsoft so we can understand these scenarios better; if there are enough people
who need to do this, we may conceivably consider adding better Framework support
in the future.  For (2) you should first try to avoid this pattern.  If
it's unavoidable, you must use finalizers to ensure that locks are not orphaned
if the expected releasing thread is aborted and never reaches the Exit.  As
with (1), you may or may not need to use a critical finalizer based on your reliability
requirements.

#### Avoid making calls to someone else's code while you hold a lock.

This applies to most virtual, interface, and delegate calls while a lock is held—as
well as ordinary statically dispatched calls—into subsystems with which you aren't
familiar.  The more you know about the code being run when you hold a lock,
the better off you will be.  If you follow this approach, you'll encounter
far fewer deadlocks, hard-to-reproduce reentrancy bugs, and surprising dynamic composition
problems, all of which can lead to hangs when your API is used on the UI thread,
reliability problems, and frustration for your customer.  Locks simply don't
compose very well; ignoring this and attempting to compose them in this way is fraught
with peril.

#### Avoid blocking while you hold a lock.

Admittedly sometimes violating this advice is unavoidable.  Trying to acquire
a lock is itself an operation that can block under contention.  But blocking
on high or variable latency operations such as IO will effectively serialize any
other thread trying to acquire that lock "behind" your IO request.  If that
other thread trying to acquire the lock is on the UI thread, you may have just helped
to cause a user-visible hang.  The app developer may not understand the cause
of this hang if the lock is buried inside of your library, and it may be tricky and
error-prone to work around.

Aside from having scalability impacts, blocking while a lock is held can lead to
deadlocks and invariants being broken.  Any time you block on an STA thread,
the CLR uses it as a chance to run the message loop.  When run on pre-Windows
2000 we use custom MsgWaitForMultipleObjects pumping code, and post-Windows 2000
we use OLE's CoWaitForMultipleHandles.  While this style of pumping processes
only a tiny subset of UI messages, it can dispatch arbitrary COM-to-CLR interop calls.
These calls include cross-thread/apartment SendMessages, such as an MTA-to-STA call
through a proxy.  If this happens while a lock is held, that newly dispatched
work also runs under the protection of the lock.  If the same object is accessed,
this can lead to surprising bugs where invariants are still broken inside the lock.
(Note that COM offers ways to exit the SynchronizationContext when blocking in this
fashion, but this is outside of the scope of this doc.)

Try to refactor your code so the time you hold a lock is minimal, and any communication
across threads, processes, or to/from devices happens at the edges of those lock
acquisition/releases.  All libraries really should minimize all synchronization
to leaf-level code.

#### Assert lock ownership.

Races often result when some leaf-level code assumes a lock has been taken at a
higher level on the call-stack, but the caller has forgotten to acquire it.
Or maybe the owner of that code recently refactored it and didn't realize the implicit
pre-condition that was accidentally broken.  This may go undetected in test
suites unless the race actually happens.  I personally hope we add a Monitor.IsHeld
API in the future which you could wrap in a call to Debug.Assert (or whatever your
assert infrastructure happens to be).  Sans that, you can build this today by
wrapping calls to Monitor.Enter/Exit and maintaining recursion state yourself.
It'd be great if somebody developed some type of annotations in the future to make
such assertions easier to write and maintain.

Note that the IsHeld functionality should never be used to dynamically influence
lock acquisition and release at runtime, e.g. avoiding recursion and taking or releasing
based on its value.  This indicates poorly factored code.  In fact, the
only use we would encourage is SomeAssertAPI(Monitor.IsHeld(foo)).

#### Avoid lock recursion in your design.  Use a non-recursive lock where possible.

Recursion typically indicates an over-simplification in your synchronization design
that often leads to less reliable code.  Some designs use lock recursion as
a way to avoid splitting functions into those that take locks and those that assume
locks are already taken.  This can admittedly lead to a reduction in code size
and therefore a shorter time-to-write, but results in a more brittle design in the
end.

It is always a better idea to factor code into public entry-points that take non-recursive
locks, and internal worker functions that assert a lock is held.  Recursive
lock calls are redundant work that contributes to raw performance overhead.
But worse, depending on recursion can make it more difficult to understand the synchronization
behavior of your program, in particular at what boundaries invariants are supposed
to hold.  Usually we'd like to say that the first line after a lock acquisition
represents an invariant "safe point" for an object, but as soon as recursion
is introduced this statement can no longer be made confidently.  This in turn
makes it more difficult to ensure correct and reliable behavior when dynamically
composed.

As a community, we should transition to non-recursive locks as soon as possible.
Most locks that you have in your toolkit today—including Win32 CRITICAL\_SECTIONs
and the CLR Monitor—screwed this up.  Java realized this and now ships non-recursive
variants of their locks.  Using a non-recursive design requires more discipline,
and therefore we expect some scenarios to continue using recursive locks for some
time to come.  Over time, however, we'd like to wean developers off of lock
recursion completely.

#### Don't build your own lock.

Most locks are built out of simple principles at the core.  There's a state
variable, a few interlocked instructions (exposed to managed code through the Interlocked
class), with some form of spinning and possibly waiting on an event when contention
is detected.  Given this, it may look straightforward to build your own.
This is deceivingly difficult.

The CLR locks have to coordinate with hosts so that they can perform deadlock detection
and sophisticated user-mode scheduling for hosted customer-authored code.  Some
of our locks (Monitor) make higher reliability guarantees so that we can safely use
them during AppDomain teardown.  We have tuned our Monitor implementation to
use an ideal mixture of spinning & waiting across many OS SKUs, CPU architectures,
and cache hierarchy arrangements.  We make sure we work correctly with Intel
HyperThreading.  We mark critical regions of code manipulating the lock data
structure itself so that would-be thread aborts will be processed correctly while
sensitive shared state manipulation is underway.  And last but not least, the
C# and VB languages offer the 'lock' and 'SyncLock' keywords whose code-generation
pattern ensures that our Framework and our customer's code doesn't orphan locks
in the face of asynchronous thread aborts.  To get all of this right requires
a lot of hard work, time, and testing.

With that said, we may not have every lock you could ever want in the Framework
today.  Spin locks are a popular request that can help scalability of highly
concurrent and leaf-level code.  Thankfully, Jeff Richter wrote an article and
supplied a suitable spin lock on MSDN some time ago.  In Orcas, we are tentatively
going to supply a new ReaderWriterLockSlim type that offers much better performance
and scalability than our current ReaderWriterLock (watch those CTPs).  If there's
still some interesting lock you need but we don't currently offer, please drop
me a line and let me know.  If you need it, chances are somebody else does too.

#### Don't call Monitor.Enter on AppDomain-agile objects (e.g. Types and strings).

Instances of some Type objects are shared across AppDomains.  The most notable
are Type objects for domain neutral assemblies (like mscorlib) and cross-assembly
interned strings.  While it may look innocuous, locks taken on these things
are visible across all AppDomains in the process.  As an example, two AppDomains
executing this same code will stop all over each other:

```
lock (typeof(System.String)) { ... }
```

This can cause severe reliability problems should a lock get orphaned in an add-in
or hosted scenario, possibly causing deadlocks from deep within your library that
seemingly inexplicably span multiple AppDomains.  The resulting code also exhibits
false conflicts between code running in multiple domains and therefore can impact
scalability in a way that is difficult for customers (and library authors!) to reason
about.

#### Don't use a machine- or process-wide synchronization primitive when AppDomain-wide would suffice.

The Mutex and Semaphore types in the .NET Framework should only ever be used for
legacy, interop, cross-AppDomain, and cross-process reasons.  They very heavy-weight—several
orders of magnitude slower than a CLR Monitor actually—and they also introduce
additional reliability and affinity problems: they can be orphaned, process-external
DOS attacks can be mounted, and they can introduce synchronization bottlenecks that
contribute to scalability blockers.  Moreover, they are associated with the
OS thread, and therefore impose thread affinity.  As already noted, this is
a bad thing.

#### A race condition or deadlock in library code is always a bug.

Race conditions and deadlocks can be very difficult to fix.  Sometimes it
requires refactoring a bunch of code to work around a seemingly corner case & obscure
sequence of events.  It's tempting to rearrange things to narrow the window
of the race or reduce the likelihood of a deadlock.  But please don't lose
sight of the fact that this still represents a correctness problem in the library
itself, no matter how narrow the race is made.  Sometimes fixing the bug would
require breaking changes.  Sometimes you simply don't have enough time to
fix the bug in time for product ship.  In either case, this is something that
should be measured and decided based on the quality bar for the product at the time
the bug is found.  Remember that as higher degrees of concurrency are used in
the hardware, the probability of these bugs resurfacing becomes higher.  A murky
won't fix race condition in 2008 that repros only once in a while on high end machines
could become a costly servicing fix by 2010 that repros routinely on middle-of-the-line
hardware.  That jump from 32 to 64 cores is a rather substantial one, at least
in terms of change to program timing.

### Reliability

#### Every lock acquisition might throw an exception.  Be prepared for it.

Most locks lazily allocate an event if a lock acquisition encounters contention,
including CLR monitors.  This allocation can fail during low resource conditions,
causing OOMs originating from the entrance to the lock.  (Note that a typical
non-blocking spin lock cannot fail with OOM, which allows it to be used in some resource
constrained scenarios such as inside a CER.)  Similarly, a host like SQL Server
can perform deadlock detection and even break those deadlocks by generating exceptions
that originate from the Enter statement, manifesting as a System.Runtime.InteropServices.COMException.

Often there isn't much that can be done in response to such an exception.
But reliability- and security-sensitive code that must deal with failure robustly
should consider this case.  We would have liked it to be the case that host
deadlocks can be responded to intelligently, but most library code can't intelligently
unwind to a safe point on the stack so that it can back-off and retry the operation.
There is simply too much cross-library intermixing on a typical stack.  This
is why timeout-based Monitor acquisitions with TryEnter are typically a bad idea
for deadlock prevention.

#### Lock leveling should be used to avoid deadlocks.

Lock leveling (a.k.a. lock hierarchy) is a scheme in which a relative number is
assigned to all locks, and lock acquisition is restricted such that only locks at
monotonically decreasing levels than those already held by the current thread can
be acquired.  Strictly following this discipline guarantees a deadlock free
system, and is described in more detail in [Duffy, 06b](http://msdn.microsoft.com/msdnmag/issues/06/04/Deadlocks/).
Without this, libraries are subject to dynamic composition- and reentrancy-induced
deadlocks, which causes users trying to write even moderately reliable code a lot
of pain and frustration.  This pain will only become worse as more of them try
to compose our libraries into highly concurrent applications.  An alternative
to true lock leveling which doesn't require new BCL types is to stick to non-recursive
locks and to ensure that multiple lock acquisitions are done at once, in some well-defined
order.

There are two big problems that will surely get in the way of adopting lock leveling
today.

First, we don't have a standard leveled lock type in the .NET Framework today.
While the article I referenced contains a sample, the simple fact is that the lion's
share of library developers and customers will not start lock leveling in any serious
way without official support.  There is also a question of whether programmers
can be wildly successful building apps and libraries with lock leveling without good
tool and deeper programming model support.

Second, lock leveling is a very onerous discipline.  We've used it in the
CLR code base for the parts of the system that are relatively closed.  (I'm
fine saying this since I'm basing this off of the Rotor code-base.)  Lock
leveling doesn't typically compose well with other libraries because the levels
are represented using arbitrary numbering schemes.  You might want to extend
it to prevent certain cross-assembly calls, interop calls that might acquire Win32
critical sections, or calls into other parts of the system that acquire locks outside
of the current hierarchy.  These are all features that have to be built on top
of the base lock leveling scheme; again, without a standard library for this, it's
unlikely everybody will want to build it all themselves.
Lock leveling is not a silver bullet, but it's probably the best thing we have
for avoiding deadlocks with today's multithreading primitives.

#### Restore sensitive invariants in the face of an exception before the 1st pass executes up the stack.

This is in part a security concern as well as a reliability one.  The CLR
exception model is a 2-pass model which we inherit from Windows SEH.  The 1st
pass runs before finally blocks execute, meaning that the locks held by the thread
are held when up-stack filters are run and get a chance to catch the exception.
VB and VC++ expose filters in the language, while C# doesn't.   Code
inside of filters can see inside possibly broken invariants because the locks are
still held.

Thankfully CAS asserts and impersonation cannot leak in this way, but this can
still cause some surprising failures.  You can stop the 1st pass and ensure
your lock is released by wrapping a try/catch around the sensitive operation and
re-throwing the exception from your catch:

```
try {
    lock (foo) {
        // (Break invariants...)
        // Possibly throw an exception...

        // (Restore invariants...)
    }
}
catch {
    throw;
}
```

This is only something you should consider if security and reliability requirements
dictate it.

####  If class constructors are required to have run for code inside of a lock...

Consider eagerly running the constructor with a call to RuntimeHelpers.RunClassConstructor.

Reentrancy deadlocks and broken invariants involving cctors are difficult to reason
about because behavior is based on program history and timing, often in a nondeterministic
way.  The problem specific to locks is that running a cctor effectively introduces
possibly reentrant points into your code anywhere statics are accessed for a type
with a cctor.  If running the cctor causes an exception or attempts to access
some data structure which the current thread has already locked and placed into an
inconsistent state, you may encounter bugs related to these broken invariants.
If using a non-recursive lock, this can lead to deadlocks.  Calling Runtime.RunClassConstructor
hoists potential problems such as this to a well-defined point in your code.
It is not perfect, as other locks may be held higher up on the call-stack, but it
can statistically reduce the chance of problems in your users' code.

#### Don't use Windows Asynchronous Procedure Calls (APCs) in managed code.

We recently considered adding APC-based file IO completion to the BCL file APIs.
Several Win32 IO APIs offer this, and some use it for scalable IO that doesn't
need to use an event or an IO Completion thread.  After considering it briefly,
we realized how bad of an idea adding similar support to managed code would have
been.  APCs pollute the OS thread to which they are tied, and are a strange
form of thread affinity (more on that later).  They can fire at arbitrary alertable
blocking points in the code, including after a thread pool thread has been returned
back to the pool, after the finalizer thread has gone on to Finalize other objects
in the process, or even at some random blocking point deep within the EE (perhaps
while we aren't ready for it).  If an APC raises an exception, the state of
affairs at the time of the crash is likely to be quite confusing.  The stack
certainly will be.  Not only do APCs represent possible security threats, but
they can also introduce many of the subtle reliability problems already outlined.
They have been avoided almost entirely in three major releases of the .NET Framework,
and we ought to continue avoiding them.

#### Don't change a thread's priority.

This could fall into the rules below about "Scheduling & Threads," because
it is semantically tied to the notion of an OS thread, were it not for the large
reliability risk inherent in it.  Priority changes can cause subtle scalability
problems due to priority inversion, including preventing the CLR's finalizer thread
(which runs at high priority) from making forward progress.  The OS has support
for anti-starvation of threads—including a balance set manager which boosts the
priority of a thread waiting for a lock for certain OS synchronization primitives—but
this actually doesn't extend to CLR locks.  Testing in isolation will tend
not to find priority-related bugs.  Instead, app developers trying to compose
libraries into their programs will discover them.  Users may decide to go ahead
and change priorities themselves, but then the onus for breaking a best practice
is on them, not us.

#### Always test & retest a wait condition inside of a lock.

A common mistake when writing cross-thread synchronization code is to either forget
to retest a condition each time a thread wakes up or to test this condition outside
of a lock.  If you're using an EventWaitHandle or Monitor.Wait/Pulse/PulseAll,
for example, to put one thread to sleep while another produces some state transition
of interest, you typically need to double-check that that state is in the expected
condition when waking.  This is especially true of single-producer/multi-consumer
scenarios, where multiple threads frequently race with one another.  For example:

```
void Put(T obj) {
    lock (myLock) {
        S1; // enqueue it
        Monitor.PulseAll(myLock);
    }
}

T Get() {
    lock (myLock) {
        while (empty) {
            Monitor.Wait(myLock);

        }
        S2; // dequeue and return the item
    }
}
```

Notice that Get loops around testing the 'empty' variable to decide when to
wait for a new item, and it does so while holding the lock.  Whenever this consumer
is woken up, it must retest the variable.  If it doesn't, multiple threads
may wake up due to a single new item becoming available only for all but one of them
to find that the queue actually became empty by the time it reached S2.  This
is generally easier to do with Monitors because they combine the lock with the condition
variable.  Missteps with Win32 events are easier because the lock must be separately
managed.

### Scheduling & Threads

####  Don't write code that depends on the OS thread ID or HANDLE.

Use Thread.Current or Thread.Current.ManagedThreadId instead.

When code depends on the identity of the actual OS thread, the logical task running
that code is bound to the thread.  This is a major piece of the thread affinity
problem mentioned earlier on.  If running on a system where threads are migrated
between OS threads using some form of user-mode scheduling—such as fibers—this
can break if user-mode switches happen at certain points in the code.  If this
dependency is enforced (using Thread.BeginThreadAffinity and EndThreadAffinity),
at least the system remains correct, but this still limits the ability of the scheduler
to maintain overall system forward progress.

Unfortunately, many Win32 and Framework APIs may imply thread affinity when used.
Several GUI APIs require that they are called from a thread which owns the message
queue for the GUI element in question.  Historically, some Microsoft components
like the Shell, MSHTML.DLL, and Office COM APIs have also abused this practice.
The situation on the server is much better, but it still isn't perfect.  Some
APIs we design with the client in mind end up being used on the server, often with
less than desirable results.  My hope is that the whole platform moves away
from these problems in the future.

#### Mark regions of code that do depend on the OS thread identity with Thread.BeginThreadAffinity/EndThreadAffinity.

The corollary to the previous rule is that, if you must have code that depends
on the OS identity, you must tell the CLR (and potential host) about it.  That's
what the Thread.BeginThreadAffinity and EndThreadAffinity methods do, new to V2.0.
Marking these regions prevent OS thread migration altogether.  This is a crappy
practice, but is less crappy than allowing thread migration to happen anyway, causing
things to break in unexpected and unpredictable ways.

#### Always access TLS through the .NET Framework mechanisms.

That's ThreadStaticAttribute or Thread.GetData/SetData and related members.

The implementation of these APIs abstract away the dependency on the OS thread
allowing you to store state associated with the logical piece of work.  Although
they sound very thread-specific, these actually store state based on whatever user-mode
scheduling mechanism is being used, and therefore you don't actually take thread
affinity when you use them.  For example, we can (in theory) store information
into Fiber Local Storage (FLS) or manually move data across fibers rather than using
the underlying Windows Thread Local Storage (TLS) mechanisms if a host has decided
to use fibers.  While it's tempting to say "Who cares?" for this one,
particularly since Whidbey decided not to support fiber mode before shipping, I believe
it's premature: we haven't seen the death of fibers just yet.

#### Always access the security/impersonation tokens or locale information through the Thread object.

As with the previous item, we abstract away the storage of this information on
the Thread object, via the Thread.CurrentCulture, Thread.CurrentUICulture, and Thread.CurrentPrincipal
properties.  We flow this information across logical async points as required,
and therefore using them doesn't imply any sort of hard OS thread affinity.

#### Always access the "last error" after an interop call via Marshal.GetLastWin32Error.

If you mark a P/Invoke signature with [DllImportAttribute(…, SetLastError=true)],
then the CLR will store the Win32 last error on the logical CLR thread.  This
ensures that, even if a fiber switch happens before you can check this value, your
last error will be preserved across the physical OS threads.  The Win32 APIs
kernel32!GetLastError and kernel32!SetLastError, on the other hand, store this information
in the TEB.  Therefore, if you are P/Invoking to get at the last error information,
you are apt to be quite surprised if you are running in an environment that permits
thread migration.  You can avoid this by always using the safe Marshal.GetLastWin32Error
function.

#### Avoid P/Invoking to other Win32 APIs that access data in the Thread Environment Block (TEB).

Security and locale information is something Win32 stores in the TEB that we already
expose in the Framework APIs, so it's rather easy to follow the advice here.
Unfortunately, many Win32 APIs access data from the TEB without necessarily saying
so, or look for & possible lazily create a window message queue (i.e. in USER32),
all of which creates a sort of silent thread affinity.  In other words, a disaster
waiting to happen.  I wish I had a big laundry list of black-listed APIs,
but I don't.

### Scalability & Performance

#### Consider using a reader/writer lock for read-only synchronization.

A lot of concurrent code has a high read-to-write ratio.  Given this, using
exclusive synchronization (like CLR monitors) can hurt scalability in situations
with a large numbers of concurrent readers.  While starting off with a reader/writer
lock could be viewed as a premature optimization, the reality is that many situations
warrant using one due to the inherent properties of the problem.  If you know
you'll have more concurrent readers than writers, you can probably do some quick
back-of-the-napkin math and come to the conclusion that a reader/writer lock is a
good first approach.  For other cases, refactoring existing code to use one
can be a fairly straightforward translation.  If you do this, obviously you
need to be careful that the read-lock-protected code actually only performs reads
to maintain the correctness of your system.

There has been a lot of negative press about the BCL's ReaderWriterLock.
In particular, the performance is at about 8x of that of successful Monitor for acquires.
Unfortunately, this has (in the past) prevented many library developers from using
reader/writer locks altogether.  This is the primary motivation we are tentatively
supplying a new lock implementation, ReaderWriterLockSlim, in Orcas.  The BCL's
synchronization primitives ought not to get in the way of optimal synchronization
for your data structures.

#### Avoid lock free code at all costs for all but the most critical perf reasons.

Compilers and processors reorder reads and writes to get better perf, but in doing
so make it harder to code that is sensitive to the read/write orderings between multiple
threads.  The CLR memory model gives a base level of guarantees that we preserve
across all hardware platforms.  With that said, any sort of dependence on the
CLR memory model is advised against; we did that work in 2.0 to strengthen the memory
model to eliminate object-publish-before-initialization and double-checked locking
bugs that were found throughout the .NET Framework, not to encourage you to write
more lock free code.

The reason?  Lock free code is impossible to write, maintain, and debug for
most developers, even those who have been doing it for years.  This is the type
of code whose proliferation will lead to poor reliability across the board for managed
libraries, longer stress lock downs on multi-core and MP machines, and is best avoided.
Use of volatile reads and writes and Thread.MemoryBarrier should be viewed with great
suspicion, as it probably means somebody is trying to be more clever than is required.

With all of that said, there are a couple "blessed" techniques that can be
considered when informed by scalability and perf testing (see [Morrison, 2005](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/)):

(a) The simple double checked locking pattern can be used when you need
to prevent multiple instances from being created and you don't want to use a cctor
(because the state may not be needed by all users of your class).  This pattern
takes the form:

```
static State s_state;
static object s_stateLock = new object();
static T GetState() {
    if (s_state == null) {
        lock (s_stateLock) {
            if (s_state == null) {
                s_state = new State();
            }
        }
    }
    return s_state;
}
```

Note that simple variants of this pattern don't work, such as keeping
a separate 'bool initialized' variable, due to read reordering (see [Duffy, 06](http://www.bluebytesoftware.com/blog/PermaLink,guid,543d89ad-8d57-4a51-b7c9-a821e3992bf6.aspx)).

(b) Optimistic/non-blocking concurrency.  In some cases, you can safely
use Interlocked operations to avoid a heavyweight lock, such as doing a one-time
allocation of data, incrementing counters, or inserting into a list.  In other
areas, you might use a variable to determine when a ready has become dirty, and retry
it, typically done via a version number incremented on each update.

Again, you should only pursue these approaches if you've measured or done the
thought exercise to determine it will pay off.  There are additional tricks
you can play if you really need to, but most library code should not go any further
than what is listed here.

#### Avoid hand-coded spin waits.  If you must use one, do it right.

Sometimes it is tempting to put a busy wait in very tightly synchronized regions
of code.  For instance, when one part of a two-part update is observed then
you may know that the second part will be published imminently; instead of giving
up the time-slice, it may look appealing to enter a while loop on an MP machine,
continuously re-reading whatever state it is waiting to be updated, and then proceed
once it sees it.  Unless written properly, however, this technique won't work
well on single-CPU and Intel HyperThreaded systems.  It's often simpler to
use locks or events (such as Monitor.Wait/Pulse/PulseAll) for this type of cross-thread
communication.  These employ some reasonable amount of spinning versus waiting
for you.

Spin waits can actually improve scalability for profiled bottlenecks or when your
scalability goals make it necessary.  Note that this is NOT a complete replacement
for a good spin lock.  If you decide to use a spin wait, follow these guidelines.
The worst type of spin wait is a 'while (!cond) ;' statement.  A properly
written wait must yield the thread in the case of a single-CPU system, or issue a
Thread.SpinWait with some reasonably small argument (25 is a good starting point,
tune from there) on every loop iteration otherwise.  This last point ensures
good perf on Intel HyperThreading.  E.g.:

```
{
    uint iters = 0;
    while (!cond) {
        if ((++iters % 50) == 0) {
            // Every so often we sleep with a 1ms timeout (see #30 for justification).
            Thread.Sleep(1);
        }
        else if (Environment.ProcessorCount == 1) {
            // On a single-CPU machine we yield the thread.
            Thread.Sleep(0);
        }
        else {
            // Issue YIELD instructions to let the other hardware thread move.
            Thread.SpinWait(25);
        }
    }
}
```

The spin count of '25' is fairly arbitrary and should be tuned on the architectures
you care about.  And you may want to consider backing off or adding some randomization
to avoid regular contention patterns.  Except for very specialized scenarios,
most spin waits will have to fall back to waiting on an event after so many iterations.
Remember, spinning is just a waste of CPU time if it happens too frequently or for
too long, and can result in an angry customer.  A hung app is generally preferable
to a machine who's CPUs are spiked at 100% for minutes at a time.

#### When yielding the current thread's time slice, use Thread.Sleep(1) (eventually).

Calling Thread.Sleep(0) doesn't let lower priority threads run.  If a user
has lowered the priority of their thread and uses it to call your API, this can lead
to nasty priority inversion situations.  Eventually issuing a Thread.Sleep(1)
is the best way to avoid this problem, perhaps starting with a 0-timeout and falling
back to the 1ms-timeout after a few tries.  Particularly if you come from a
Win32 background, it might be tempting to P/Invoke to kernel32!SwitchToThread—it
is cheaper than issuing a kernel32!SleepEx (which is what Thread.Sleep does).
This is because SleepEx is called in alertable mode, which incurs somewhat expensive
checks for APCs.  Unfortunately, P/Invoking to SwitchToThread bypasses important
thread scheduling hooks that call out to a would-be host.  Therefore, you should
continue to use Thread.Sleep until if and when the .NET Framework offers an official
Yield API.

#### Consider using spin-locks for high traffic leaf-level regions of code.

A spin-lock avoids giving up the time-slice on MP systems, and can lead to more
scalable code when used correctly.  Context switches in Windows are anything
but cheap, ranging from 4,000 to 8,000 cycles on average, and even more on some popular
CPU architectures.  Giving up the time-slice also means that you're possibly
giving up data in the cache, depending on the data intensiveness of the work that
is scheduled as a replacement on the processor.  And any time you have cross
thread causality, it can cause a rippling effect across many threads, effectively
stalling a pipeline of parallel work.  As usual, using a spin-lock should always
be done in response to a measured problem, not to look clever to your friends.

#### You must understand every instruction executed while a spin lock is held.

Spin locks are powerful but very dangerous.  You must ensure the time the
lock is held is very small, and that the entire set of instructions run is completely
under your control.  Virtual method calls and blocking operations are completely
out of the question.  Because a spin-lock spins rather than blocking under contention,
a deadlock will manifest as a spiked CPU and system-wide performance degradation,
and therefore is a much more serious bug than a typical hang.

Whenever you use a spin lock you are making a bold statement about your code and
thread interactions:  it is more profitable for other contending threads to
possibly waste CPU cycles than to wait and let other work make forward progress.
If this statement turns out to be wrong, a large number of cycles will frequently
get thrown away due to spinning, and the overall throughput of the system will suffer.
On servers the result could be catastrophic and you may cost your customers money
due to an impact to the achievable throughput.  Each cycle you waste in a loop
waiting for a spin lock to become available is one that could have been used to make
forward progress in the app.

#### Consider a low-lock data structure for hot queues and stacks.

Windows has a set of 'S-List' APIs that provide a way to do "lock free"
pushes and pops from a stack data structure.  This can lead to highly scalable,
non-blocking algorithms, much in the same way that spin-locks do.  Unfortunately
it is not a simple matter to use 'S-Lists' from managed code, due to the requirements
for memory pinning among other things.  It's very easy to build a lock-free
stack out of CAS operations which is suitable for these situations.  The algorithm
goes something like this:

```
class LockFreeStack<T> {
    class Node {
        T m_obj;
        Node m_next;
    }

    private Node m_head;

    void Push(T obj) {
        Node n = new Node(obj);
        Node h;
        do {
          h = m_head;
           n.m_next = h;
       } while (Interlocked.CompareExchange(ref m_head, n, h) != h);
    }

    T Pop() {
        Node h;
        Node nh;
        do {
            h = m_head;
            nh = h.m_next;
        } while (Interlocked.CompareExchange(ref m_head, nh, h) != h);
        return h.m_obj;
    }
}
```

This sample implementation carefully avoids the well-known ABA problem as a result
of two things: (1) it assumes a GC, ensuring memory isn't reclaimed and reused
so long as at least one thread has a reference to it; and (2) we don't make any
attempt to pool nodes. A more efficient solution might pool nodes so that each Push
doesn't have to allocate one, but then would have to also implement an ABA-safe
algorithm. This is typically done by widening the target of the CAS so that it can
contain a version number in addition to the "next node" reference.

There are other permutations of this lock-free data structure pattern which can
be useful.  Lock-free queues can be built (see [Michael, 96](http://www.cs.rochester.edu/u/michael/PODC96.html)
for an example algorithm), permitting concurrent access to both ends of the data
structure.  All of the same caveats explained with the earlier lock free item
apply.

#### Always use the CLR thread pool or IO Completion mechanisms to introduce concurrency.

The CLR's thread pool is optimized to ensure good scalability across an entire
process.  If we end up with multiple custom pools in a process, they will compete
for CPUs, over-create threads, and generally lead to scalability degradation.
We already (unfortunately) have this situation with the OS's thread pool competing
with the CLR's.  We'd prefer not to have three or more.  If you will
be in the same process as the CLR, you should use our thread pool too.  We're
doing a lot of work over the next couple releases to improve scalability and introduce
new features—including substantially improved throughput (available in the last
Orcas CTP)—so if it still doesn't suit your purposes we would certainly like
to hear from you.

### Blocking

#### Document latency expectations for your users.

We haven't yet come up with a consistent way to describe the performance characteristics
of managed APIs.  When writing concurrent software, however, it's frequently
very important for developers to understand and reason about the performance of the
dependencies they choose to take.  This includes things like knowing the probability
of blocking—and therefore whether to try and mask latency by transferring work
to a separate thread, overlapping IO, and so on—as well as the compute and memory
intensiveness of the internal operations.  Please make an effort to document
such things.  Incremental and steady improvements are important in this area.

#### Use the Asynchronous Programming Model (APM) to supply async versions of blocking APIs.

Particularly if you are building a feature that mimics existing Win32 IO APIs or
uses such APIs heavily, you should also consider exposing the built-in asynchronous
nature of IO on Windows.  For example, file and network IO is highly asynchronous
in the OS; if you know your API will spend any measurable portion of its execution
time blocked waiting for IO, the same customers who use asynchronous file IO APIs
will want some way to turn that into asynchronous IO.  The only way they can
do that is if you go the extra step and provide an Asynchronous Programming Model
(APM) version of your API.

Details on precisely how to implement the APM are available in Cwalina, 05.
It involves adding 'IAsyncResult BeginXX(params, AsyncCallback, object)' and
'rettype EndXX(IAsyncResult) APIs for your 'rettype XX(params)' method.
As an example, consider System.IO.Stream:

```
int Read(byte[] buffer, int offset, int count);
IAsyncResult BeginRead(byte[] buffer, int offset, int count,

AsyncCallback callback, object state);
int EndRead(IAsyncResult asyncResult);
```

A good hard-and-fast rule is that if you use an API that offers an asynchronous
version, then you too should offer an asynchronous version (and so on, recursively
up the call stack).

This is very important to many app developers who need to tightly control the amount
of concurrency on the machine.  Having lots of IO happening asynchronously can
permit operations to overlap in ways they couldn't otherwise, therefore improving
the throughput at which the work is retired.  IO Completion Ports, for example,
allow highly scalable asynchronous IO without having to introduce additional threads.
There is simply no way to build a robust and scalable server program without them.
If the library doesn't expose this capability, customers are left with a clumsy
design: they have to manually marshal work to a thread pool thread—or one of their
own—to mask the latency, and then rendezvous with it later on.  And this doesn't
work at all for massive numbers of in-flight IO requests.  Or even worse, users
are forced to create, maintain, and use their own incarnations of existing library
APIs.

#### Always block using one of the existing framework APIs.

That's lock acquisition, WaitHandle.WaitOne, WaitAny, WaitAll, Thread.Sleep,
or Thread.Join.

The CLR doesn't block in a straightforward manner.  As noted earlier, we
use blocking as an opportunity to run the message loop on STA threads.  We also
call out to the host to give it a chance to switch fibers or perform any other sort
of book-keeping.  This is required to ensure good CPU utilization and to achieve
the goal of having all CPUs constantly busy on a MP machine, instead of the alternative
of wasting potential execution time by letting threads block.  P/Invoking or
COM interoping to a blocking API completely bypasses this machinery, and we are then
at the mercy of that API's implementation.  Aside from the thread switching
problems, if this API blocks but doesn't pump messages on an STA, for instance,
we may end up in a cross-apartment deadlock, among other problems.

## III. References

* [Brumme, 03]  Brumme, C.  [AppDomains ("application domains").]
    (http://blogs.msdn.com/cbrumme/archive/2003/06/01/51466.aspx) Blog article.  June 2003.
* [Cwalina, 05]  Cwalina, K., Abrams, B.  Framework design guidelines:
    Conventions, idioms, and patterns for reusable .NET libraries.  Addison-Wesley Professional.
    September 2005.
* [Duffy, 05]  Duffy, J.  [Atomicity and asynchronous exceptions]
    (http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641).
    Blog article.  March 2005.
* [Duffy, 06]  Duffy, J.  [Broken variants of double-checked locking]
    (http://www.bluebytesoftware.com/blog/PermaLink,guid,543d89ad-8d57-4a51-b7c9-a821e3992bf6.aspx).
    Blog article.  January 2006.
* [Duffy, 06b]  Duffy, J.  [No more hangs: Advanced techniques to avoid and
    detect deadlocks in .NET apps](http://msdn.microsoft.com/msdnmag/issues/06/04/Deadlocks/).
    MSDN Magazine.  April 2006.
* [Duffy, 06c]  Duffy. J.  [Application responsiveness: Using concurrency
    to enhance user experiences](http://www.ddj.com/dept/windows/192700235).  Dr.
    Dobb's Journal.  September 2006.
* [Michael, 96]  Michael, M., Scott, M.  [Simple, Fast, and Practical Non-blocking
    and Blocking Concurrent Queue Algorithms](http://www.cs.rochester.edu/u/michael/PODC96.html).
    PODC'06.
* [Morrison, 05]  Morrison, V.  [Understand the impact of low-lock techniques
    in multithreaded apps](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/).
    MSDN Magazine.  October 2005.
* [Olukotun, 05]  Olukotun, K., Hammond, L.  [The future of microprocessors]
    (http://acmqueue.com/modules.php?name=Content&pa=showpage&pid=326).
    ACM queue, vol. 3, no. 7.  September 2005.
* [Sutter, 05]  Sutter, H., Larus, J.  [Software and the concurrency revolution]
    (http://acmqueue.com/modules.php?name=Content&pa=showpage&pid=332).
    ACM queue, vol. 3, no. 7.  September 2005.

