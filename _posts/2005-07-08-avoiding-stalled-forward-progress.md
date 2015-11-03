---
layout: post
title: Avoiding stalled forward progress
date: 2005-07-08 16:55:10.000000000 -07:00
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
When access to a location in memory is shared among multiple tasks executing in
parallel, some form of serialization is necessary in order to guarantee
consistent and predictable logic. Furthermore, in many situations, a number of
such reads and writes to shared memory are expected to happen "all at once," in
other words atomically. Serializability and atomicity are both often
implemented using mutual exclusion locks. This is bread and butter stuff.

An important concept in concurrent programming is forward progress. This is the
idea that the largest number of parallel tasks should make the most amount of
progress towards their goal as possible for every given time unit of execution.
If you can manage to divvy up the work such that all tasks can execute
completely logically independently from each other—called linear
parallelization, something that is actually difficult to achieve in
practice—then sharing resources such as memory can quickly bog down your
theoretical linear speedup in practice. Shared memory prevents each task from
making forward progress because there are points of execution where access to
resources must be serialized. That means code has to wait in line in order to
execute. That's generally bad.

What an ambitious introduction. Unfortunately, I must constrain the rest of
this particular article to some very precise, more manageable topics… Else I
would never complete it, and might end up with a book on my hands. And
furthermore, I am going to constrain my conversation to the CLR, with a focus
on the Monitor APIs. I intend to write a series of these articles over the
coming months, since I've been writing a lot about the topic in general lately.

**Eliminating deadlocks**

Deadlocks are well documented out there, and are simple to understand. Thus I
will start with them. Deadlocks are by far the #1 forward progress inhibitors.
While contention over shared memory can prevent all but one parallel unit from
making forward progress (in the extreme case, where all tasks request access to
the same resource simultaneously), deadlocks prevent all units involved in the
access from making forward progress. Without detection and correction logic,
your program is likely to come to a grinding halt.

For example, consider two bits of code running in parallel:

> #1:                        #2 lock (a)                   lock (b) {
> { lock (b)                   lock (a) {                          { // atomic
> code             // more atomic code }                          } }
> }

As written, these can easily get into a so called deadly embrace. Because they
acquire and release locks in the opposite order, it's not a difficult stretch
to imagine #1 acquiring a, #2 acquiring b, and then #1 trying to acquire b
(blocking forever), and #2 trying to acquire a (also blocking forever). The
result is often a hung application or background worker thread. The result is a
frustrated user having to open up Task Manager so they can slam the End Task
button tens of times… and then waiting for dumprep.exe to get done with its
jazz.

The solution to this problem is often "acquire and release locks in the same
order," but that's seldom achievable in practice. It's more likely that a and b
are acquired in entirely separate functions, deep in some complex call-stack,
which can moreover alter the flow of control at runtime. It's not always a
statically detectable situation. Another solution is to write your code so that
it can back off of lock acquisitions if it suspects a deadlock has occurred.
With the new Monitor.TryEnter API, this is relatively trivial to do (in the
simple case).

Regardless of how ridiculously simplified this scenario is, let's start here.
It's easier to understand and solve.

**A quick note on SQL Server**

Through the CLR's hosting APIs, you can actually hook all blocking points,
including Monitor.Enter calls. SQL Server (and possible other sophisticated
hosts) use this to detect deadlocks and prevent them from occurring.
Unfortunately, I don't know their policy for handling, but presumably it is a
fair one whereby a victim is chosen at random and killed. This is consistent
with the way SQL Server handles deadlocks pertaining to data transactional
deadlocks. [Chris Brumme's weblog entry on
Hosting](http://blogs.msdn.com/cbrumme/archive/2004/02/21/77595.aspx) has a
plethora of related information.

**Lock ordering and optimistic deadlock back-off**

An old fashioned solution to this problem is to mentally tag all locks in your
program, and ensure that you acquire them in a consistent manner. You could use
a simple algorithm, such as "sort by variable name." This works so long as you
never alias a memory location. Oh, and so long as you don't make a mistake when
you're writing the code (and anybody else who is touching your program). But
this would be error prone and laborious. We can do better.

We could, for example, write a function that accepts a list of objects and does
a few things in the process of locking on them:

- Sorts the objects in identity order to ensure consistent lock acquisition
  ordering;

- Uses a simple back-off strategy in case there are other lockers not using our
  ordered locking scheme.

The code might look like this:

> static int deadlockWait = 15;
>
>
>
> static bool EnterLocks(params object[] locks) { return EnterLocks(-1, locks);
> }
>
>
>
> static bool EnterLocks(int retryCount, params object[] locks) { // Clone and
> sort our locks by object identity.  object[] locksCopy =
> (object[])locks.Clone(); Array.Sort<object>(locksCopy, delegate(object x,
> object y) { int hx = x == null ? 0 : RuntimeHelpers.GetHashCode(x); int hy =
> y == null ? 0 : RuntimeHelpers.GetHashCode(y); return hx.CompareTo(hy); });
>
>
>
>     // Now begin the lock acquisition process.  bool successful = false; for
>     (int i = 0; !successful && (retryCount == -1 || i < retryCount); i++) {
>     successful = true; for (int j = 0; j < locksCopy.Length; j++) { try { if
>     (!Monitor.TryEnter(locksCopy[j], deadlockWait)) { // We couldn't acquire
>     this lock, ensure we back off.  successful = false; break; } } catch { //
>     An exception occurred--we don't know whether we got the last lock // or
>     not. Assume we did. We indicate that by incrementing the counter.  j++;
>     successful = false; throw; } finally { if (!successful) { for (int k = 0;
>     k < j; k++) { try { Monitor.Exit(locksCopy[k]); } catch
>     (SynchronizationLockException) { /\* eat it \*/ } } Thread.Sleep(0); //
>     Might increase chances that a thread will steal a lock (good).  } } } }
>
>
>
>     return successful; }

This method is actually sufficiently complex that it warrants a bit of
discussion. Most of the complexity stems from our paranoia about orphaning
locks coupled with the back-off algorithm. Notice that we first sort the list
of locks, using the System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode
method for comparisons (this function returns a unique hash code based on an
object's identity). We then use a loop to try acquisition of the locks. If an
acquisition fails, we begin the back-off logic by unraveling any locks we had
acquired previously, yielding the thread to increase the chance that another
possibly deadlocked thread is able to make forward progress, and starting over
again.

Of course, a real function would probably offer a timeout variant. The timout
for the Monitor.TryEnter isn't configurable, the retry Count is near
meaningless to the user, and the routine is still subject to denial of service
attacks whereby somebody grabs a lock and holds on to it forever. In that case,
we'll loop forever (unless an explicit retryCount is provided, it defaults to
-1 which means infinite). We also need a similar, although much simpler,
ExitLocks mechanism. I've omitted these implementations for brevity. Lastly, in
the face of asynchronous aborts, this code falls on its face. Nevertheless, it
demonstrates the concepts (I hope).

**Cross call-stack ordering and back-off**

Again, this strategy works only if you know all of your locks up front. With
deep call-stacks, this may not be the case. For example, consider:

> void f(bool b) { if (b) { lock (a) { g(!b); } } else { lock (b) { g(!b); } }
> }
>
>
>
> void g(bool b) { if (b) { lock (a) { // some atomic function } } else { lock
> (b) { // some other atomic function } } }

If these were called from two parallel tasks, one task run as f(true) the other
as f(false), you'd have a similar, although much more complex and difficult to
follow, deadlock scenario. We might be able to (almost) solve this, too,
however, with some really ugly hacks that I wouldn't suggest anybody uses in
real code. With that caveat, let's take a look at them…

We could learn a thing or two from
[STM](http://research.microsoft.com/%7Esimonpj/papers/stm/index.htm). If we
performed only idempotent and reversible operations inside the atomic (lock
protected block), you could imagine a more complex back-off strategy that
spanned multiple levels of a call-stack. This requires you to make a lot of
assumptions, use exceptions for control flow, and quite truthfully some
unorthodox strategies (including polluting your thread with state). Moreover,
without some form of transactional memory, rollback in the case of failure has
to be done manually. These are in general bad practices, but the result seems
to exhibit some redeeming qualities.

Here's a big steaming pile of code that attempts to demonstrate a possible
implementation:

> static LocalDataStoreSlot atomicSlot; static Par() { atomicSlot =
> Thread.AllocateNamedDataSlot("AtomicContext"); }
>
>
>
> internal class AtomicFailedException : Exception { public
> AtomicFailedException() {} }
>
>
>
> internal class AtomicContext { internal AtomicContext parent; internal
> List<object> toLock = new List<object>(); }
>
>
>
> static bool DoAtomically(Action<object> action, params object[] locks) {
> return DoAtomically(action, null, locks); }
>
>
>
> static bool DoAtomically(Action<object> action, Action<object> cleanup,
> params object[] locks) { return DoAtomically(action, cleanup, 10, locks); }
>
>
>
> static bool DoAtomically(Action<object> action, Action<object> cleanup, int
> retryCount, params object[] locks) { bool entered = false;
>
>
>
>     // We have to maintain our context so that we can unravel the parent
>     correctly.  AtomicContext ctx = new AtomicContext();
>     ctx.toLock.AddRange(locks); ctx.parent =
>     (AtomicContext)Thread.GetData(atomicSlot); Thread.SetData(atomicSlot,
>     ctx); try { for (int i = 0; !entered && i < retryCount; i++) { if
>     (entered = EnterLocks(10, ctx.toLock.ToArray())) { bool retryRequested =
>     false; try { action(null); } catch (AtomicFailedException) { if (cleanup
>     != null) cleanup(null); retryRequested = true; } finally { if (entered)
>     ExitLocks(locks); if (retryRequested) entered = false; } } } } finally {
>     // Reset the context to what it was before we polluted it.  AtomicContext
>     cctx = (AtomicContext)Thread.GetData(atomicSlot);
>     Thread.SetData(atomicSlot, cctx.parent); if (!entered && cctx.parent !=
>     null) { cctx.parent.toLock.AddRange(cctx.toLock); throw new
>     AtomicFailedException(); } }
>
>
>
>     return entered; }

The last overload is obviously the most complex, and the meat of the
implementation. DoAtomically uses a back-off strategy not unlike the first
EnterLocks function. In fact, it uses EnterLocks for lock acquisition.
DoAtomically maintains a context of the locks that must be acquired, and can be
chained such that there is a parent/child relationship between two contexts
(representing multiple DoAtomically calls in a single call stack).

The function then goes ahead and attempts to acquire each object that much be
locked. If it succeeds, it calls the delegate that was supplied as an argument.
This delegate can likewise make DoAtomically calls which will recursively
detect deadlocks and perform escalation if they occur. Note: there is some
noise here. Because of the small timeout we use, a function that holds a lock
for an extended period of time can give the impression of a deadlock. This
number could probably use some tuning. Further, I haven't tested the
interaction between this code and non-DoAtomically code. Presumably, it would
be more succeptable to livelock, but wouldn't actually fail or deadlock
(assuming the other code doesn't mount a denial of service).

The escalation policy we use is to perform cleanup logic (since we tried to
execute the action, there could be broken invariants that must be restored),
mutate the parent context so that it will attempt to acquire the locks the
child tried to acquire (and failed), and essentially unravel the stack to the
parent (using an exception—ugh—I think continuations would make this a much
prettier situation). The parent then tries to acquire its own locks in addition
to the child locks that got escalated. This can be an arbitrarily nested
call-stack, so a parent could end up with more than just a single child's locks
to acquire. But this ensures an entire call stack's worth of locks are acquired
in an ordered fashion, and furthermore backed off of all at once. The obvious
downside to this approach is that you end up taking a coarser grained lock than
necessary, but with the benefit of avoiding deadlocks.

Assuming all of the back off and retry succeeds, it will return a true
indicating success. If it doesn't, and it's exhausted all of its retries and
escalation space, the topmost atomic block will simply return false to indicate
failure. Honestly, an exception in this case might be more appropriate.

**An overly simple example**

A small test function that uses this (sorry, I didn't have time to write up a
more complex one), is as follows:

> static int i = 0; static object x = new object(); static object y = new
> object();
>
>
>
> static void Main() { List<Thread> ts = new List<Thread>(); for (int j = 0; j
> < 20; j++) { Thread t = new Thread(new ThreadStart(delegate {
> DoAtomically(delegate { i++; Console.WriteLine("{0}, {1}",
> Thread.CurrentThread.ManagedThreadId, i); i--; }, x, y); })); ts.Add(t); }
>
>
>
>     ts.ForEach(delegate (Thread t) { t.Start(); }); ts.ForEach(delegate
>     (Thread t) { t.Join(); }); }

Of course, all threads should print out the number 1.

**A brief word on livelock**

A quick word on livelock with the above design. With an escalation policy as
defined above—your standard back-off, yield, and retry—it is highly
susceptible to live-lock. This is a situation where code is trying to make
progress, but chasing its own tail, or continually hitting conflicts. Consider
what happens if a very long block and a very short block are competing in a
deadlock fashion for the same resources.

The policy defined above will always back-off and retry, meaning that a short
transaction has less work to do in order to perform its task. If the larger
block is higher priority than the smaller one, we're unfairly favoring the
small block simply due to its size. But similarly, a long running block could
acquire a lot of resources, and the smaller block could quickly try (and retry)
to acquire locks, fail, and give up.

Lock leveling or some more intelligent queuing system might help out here. But
I've written enough already.

**Future topics**

If you're interested in a particular concurrency-related topic, let me know!

I'd like to spend more time in the future on:

- Events and signaling;

- Managing large groups of complex parallel tasks;

- Implicit parallelism, e.g. using compiler code generation and IL rewriting;

- STA, COM and UI programming, reentrancy;

- More on livelock—it happens in a lot of contexts—and some ideas on how to
  solve them;

- Lock free programming, and why you should avoid it.

Feedback will help me write about things you want to know about.

Happy hacking!

