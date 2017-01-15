---
layout: post
title: Atomicity and asynchronous exception failures
date: 2005-03-18 16:26:34.000000000 -07:00
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
I recently sent this out to an internal audience. I saw no reason not to share
it with external folks, too... Although most of it probably won't be of
interest, maybe somebody out there will get something useful from it.

## Atomicity & Asynchronous Exception Failures

We often get asked how Framework developers should write atomic paired
operations that are reliable in the face of asynchronous exceptions, the
canonical example being thread aborts. These operations might be the
acquisition and release of a lock or the allocation and deallocation of some
unmanaged resource, for example. Not dealing with the risk that an exception
might interrupt these (hence breaking atomicity) might cause undesirable
reliability, or possibly even security, problems for you. A lot of people
wonder how paranoid they should be when coding defensively against these
scenarios.

This email is intended to clarify today's state of affairs (as of Whidbey
Beta2), provide guidance to those writing reusable managed code, and to shed a
little insight into our thinking around where we might go in the future. To be
entirely transparent, the top priority is first to convince you that, in almost
all cases, you don't need to and shouldn't be writing the paranoid code
necessary to deal with such problems. Only after that's out of the way will we
discuss how to do what you originally might have thought you wanted to do
(although, hopefully by then you'll have been convinced otherwise).

This is meant to compliment Chris Brumme's recent email "Exceptions, Security &
Frameworks," available here. In particular, the thread abort section #9. A lot
of this will make its way into the Design Guidelines document in a more easily
consumable form over the coming weeks.

## A quick overview

We consider it the responsibility of Framework code to guarantee cleanup of
state which spans AppDomains. It is also the responsibility of Framework code
to block threads in a manner in which the CLR can take control of them. (For
instance, use `WaitHandle.WaitOne` rather than a P/Invoke to
`WaitForSingleObject`). And it is also the responsibility of Framework code to
tolerate AppDomain unloads. This includes tolerating a certain level of
inconsistency, as seen by `Finalize` methods and `AppDomain.DomainUnload` events
during an unload. There are some things Framework code isn't responsible for,
though. It is entirely up to the host to deal with and contain possible
inconsistent or corrupt state inside an AD that occurs as a result of raising
asynchronous exceptions on some opaque executing thread. Further, it is the
responsibility of code which consumes an API to recover deterministically as
needed from operations that might fail, not that of the API itself. This last
paragraph is dense and perhaps the core message of this email, so you might
want to go back and reread it.

Let's examine some implications of this, using thread aborts as a running
example. Asynchronous thread aborts that are part of an AD unload are
acceptable, and Framework code needs to tolerate them. Random aborts that have
nothing to do with an unload are not fine, and the Framework generally need not
remain consistent when they occur. The host is making a decision that the risk
of inconsistency is less than the value of injecting these kinds of aborts and
then continuing to run. SQL Server can make this decision because it monitors
whether the threads it aborts are modifying shared state at the same time.

Asynchronous exceptions are tricky since they manifest as exceptions
originating at seemingly any instruction in code running on a thread,
essentially introducing nondeterministic races all over the place. By
asynchronous, this just means that the target of a thread abort is different
than the thread actually asking for the abort, either through the
`Thread.Abort()` API or as part of the `AppDomain` unload process. Although saying
"any instruction" is a bit of an overstatement. We don't process thread aborts
if you're executing inside a Constrained Execution Region (CER), finally block,
catch block, .cctor, or while running inside unmanaged code. If an abort is
requested while inside one of these regions, we process it as soon as you exit
(assuming you're not nested inside another).

Synchronous thread aborts (e.g. `Thread.CurrentThread.Abort()`) aren't a concern
at all since the result is analogous to manually throwing a new
`ThreadAbortException` exception (with the exception that they get re-raised
after catch blocks). This is completely deterministic and happens at well
defined points in your code; thus, it doesn't carry the same risk of corruption
as asynchronous aborts and won't be discussed further.

## Atomic pairs

If you have a piece of code that introduces a state change, makes some side
effect, or acquires or allocates a resource, for example, there will usually be
a paired operation intended to roll back the operation. One normally has a
desire to make these two things atomic. That is, if one occurs, the other is
also guaranteed to occur. If you open a file, you normally need to make sure
you close it. After you acquire a lock on an object, you probably want to
release it when you're done so that you avoid deadlocks. And further, the
soonest you can do this the better. Deterministic (or eager) action is usually
preferable to nondeterministic (or late). While these things are reasonably
simple to achieve about 99.x% of the time, achieving that extra 0.(1-0.x)% is
extraordinarily difficult, and indeed seldom justifies the complexity and
difficulty of trying to become resilient.

As a simple example, all of this means that given trivial code like this:

    using (Foo x = new Foo()) 
    { 
      // … 
    }

It can fail in nontrivial ways. For example, if a `ThreadAbortException` were
raised sometime between the invocation of Foo's constructor and the assignment
to `x`, then `Dispose()` will never get called on the instance that got created.
This is because at the end of the scope, `x` is still null (since it was never
assigned a value). Assuming some resources got allocated in `Foo`'s constructor,
it's the responsibility of `Foo`'s finalizer to clean up after itself at this
point. It should also be noted this problem can also occur if `Foo`'s constructor
throws an exception, which is a particularly good reason to avoid throwing
exceptions from constructors and to instead prefer acquisition of resources
inside discrete methods.

Now, hopefully `Foo` was written to have a finalizer that will eventually clean
up such resources. Indeed, if `Foo` has a public constructor, then the author of
`Foo` can have no guarantees that `Foo` is only used in the context of a `using`
statement. In other words, Foo would have no guarantees that its `IDisposable`
interface is ever called on any of its instances. If we're talking about
publicly constructable objects, the only guarantees worth considering are the
guarantees made to the client code.

While this does mean that whatever `Foo` introduced might take a little while to
roll back, since we're processing a thread abort it's safe for Framework code
to assume that we are unloading an `AppDomain` and therefore will be executing
finalizers shortly anyhow, which means this is perfectly acceptable most of the
time. (We talk about why this is so further below.) Here's where the paranoia
starts. What if surrounding code assumes that `Foo` will always have been
disposed of once control escapes the `using` statement? In this case, this
assumption doesn't hold. If the surrounding code is privy to the internal
details of what state `Foo` changes and how (such as knowing it creates a
particular file on disk and cleans it up during `Dispose`, for example), it might
be written against a false set of invariants. This might cause failures to
ripple up the call stack.

Thankfully, as is the case with infrastructure exceptions like thread abort,
the exception will be forced to re-raise at the tail end of any catch blocks.
So long as catch blocks are written without such assumptions, at least
non-catch code won't execute and see surprising state. And so long as any state
which spans a single `AppDomain` is cleaned up in finalizers, such failures don't
seem quite so bad.

## Some simple dos and don'ts

There are some simple things you can do to make your code more robust without
stepping over the paranoia threshold. As I stated above, most people writing
Framework code shouldn't even care about most of what appears after this
section.

**1. We don't expect most of the Framework to be willing or able to recover
fully from asynchronous exception.** In fact, the sole responsibility of code
executing during a thread abort or an AD unload is to fix up corruption to
state that spans AppDomains. By span, this just means that the management and
lifetime of that state is orthogonal to that of the `AppDomain` executing code
which is manipulating it. It's safe to assume that, if code is subject to a
thread abort, it will be shortly followed by an AD unload. Your goal should be
to make "shortly" as short as possible, namely by reducing the amount of work
you do as a result of these events. This includes finally blocks, finalization,
and AD unload event handlers.

This guidance immediately rules out having to worry about protecting state
which is entirely isolated inside an AD, such as managed object monitors, for
example. This is true, of course, unless doing so would subject your code to
possible security holes, in which case you might have to worry at least a
little about this. A malicious person who knows you end up violating a bunch of
invariants because you didn't write code to deal with a thread abort might use
this knowledge to find new and interesting exploits. If you're doing thread
impersonation or some other scary security elevation, you likely want to
guarantee (via `ExecutionContext.Run`) that it gets reverted before passing
control back up the stack, even in the face of thread aborts. Fortunately,
aborting a thread does demand privileges not granted to most partial trust
callers, but this does not rule out some bug exposing a reproducible way to
provoke aborts. Not likely, but not impossible either.

**2. Most of the time, you can (and should) rely on lazy cleanup to prevent
leaks.** Eager cleanup is useful, but you should always use a finalizer to
guarantee that important state gets rolled back and that resources get
reclaimed. Better yet, use
[SafeHandle](http://blogs.msdn.com/bclteam/archive/2005/03/16/396900.aspx),
especially for cross-AD state. `SafeHandle` uses critical finalization to ensure
execution even in the face of rude thread aborts and unloads. Regular
finalizers won't get a chance to run in such situations. True, lazy cleanup can
lead to undesirable intermediary situations, namely while the abort is getting
propagated and other cleanup code executed, but it's certainly better than
letting a leak past the AD unload entirely. The benefit of forcing eager
cleanup in the face of the rare occurrences described in this paper is not
worth the significant cost you would have to incur. Try not to write code that
depends too intimately on eager cleanup having taken place, especially inside
other cleanup code.

**3. Don't use finally blocks to intentionally delay asynchronous exceptions.**
While a clever observation, writing your code entirely inside finally blocks to
avoid an asynchronous from being injected between a block of paired operations
is a horribly bad practice. This is especially true of long running sections of
code, especially those which have a blocking operation thrown into the mix.
Doing this holds up processing of thread aborts and can hang AD unloads. This
will result in a poor application experience for those who rely on your code.

For example, consider this snippet:

    ReaderWriterLock rwl = /*…*/; 
    bool taken = false; 
    try 
    { 
      try {} 
      finally 
      {
        rwl.AcquireWriterLock(-1); 
        taken = true; 
      } 
      // do some work 
    } 
    finally 
    { 
      if (taken) 
        rwl.ReleaseWriterLock(); 
    }

Yes, this prevents a normal asynchronous thread abort from occurring between
the lock acquisition and entrance into the try block, but it also introduces
the significant unintended consequences cited above. Moreover, if your code
blocks upon trying to acquire a resource, we wouldn't be able to abort it until
it unblocks itself. If it's in a deadlock or long-running acquisition, this
would be pretty horrible.

**4. Start paired operations inside a try block when possible.** This might
deviate from guidance given in the past, but nonetheless helps to eliminate the
window between an acquisition and entrance into the try block. While this
window can seem tiny (e.g. acquiring a lock right before entering a try), the
JIT is free to inject as much code inside of it as it sees fit. This will
undoubtedly be a small quantity, but nonetheless increases the window's
duration and hence likelihood of being interrupted. With the window eliminated
entirely, however, it means that you can be assured your finally block will run
during an abort. It does complicate matters slightly, as now you can't be
certain whether the operation succeeded or not, and therefore whether you have
any state rollback to perform in your finally.

There are a few ways to deal with this, but in general your finally block
should be resilient to failure. This might mean trying an operation and
swallowing a resulting exception (like releasing a lock that never got
successfully acquired), or using an out parameter in the acquisition method.
Unless you use a CER or finally block to do the acquisition, you can't be
assured that you ever completed an assignment or operation fully. But in
(hopefully) most cases, you won't need to know. And this is usually more
attractive than worrying whether your finally block will get a chance to run.

**5. Always use the 'using' and 'lock' statements in C# as appropriate.** If
you're familiar with the code that gets generated for these, you might notice a
discrepancy between #4 and #5. This is true. Both of these constructs expand to
code which does the acquisition right before entering the try block, which as
we established in the opening section, could lead to missed deterministic
cleanup. But as we've also already established, most of this shouldn't be a
concern to you by now. In fact, the `lock` statement has a hack to ensure that,
at least in the absence of a rude abort or rude AD unload, the unlock will
always occur. (Unfortunately, because it's a JIT hack, it's not guaranteed to
happen across all platforms.) By using these constructs, we can optimize your
code for free in the future if and when we reassess how better to make the code
they emit (or how the JIT responds to such code, as in the case of `lock`) more
reliable in the face of asynchronous failures.

**6. Never initiate asynchronous thread aborts in the Framework.** This is
perhaps too strongly worded, but most code should never try to abort an opaque
thread. Only sophisticated hosts who are prepared to deal with the ensuring
corruption and inconsistent state inside an AD should ever attempt to do this,
and even then I emphasize the word "attempt." If you're doing this, know that
we are recommending Framework code to be written with the assumption that an
abort will be followed shortly by an unload. If you don't abide by this policy,
code probably won't react as you might have hoped. There's an MDA in Whidbey
that catches this. We expect people writing applications to make this mistake,
but please, please, please just don't do it from Framework code.

**7. Use CERs sparingly.** CERs can be used to patch up known problems and to
protect state that spans ADs, but unless you know for sure that one of these
applies to you, don't even consider using one. You need to execute under
particularly bad circumstances, and truthfully doing it right is rocket
science. Low level infrastructure code will use CERs more and more in the
future, but for most of the code that builds on top of this infrastructure,
CERs aren't necessary.

## Stress failures, complexities

The picture of the world depicted above is a bit naive. For example, it
suggests that orphaning an object lock is acceptable during an AD unload. While
in theory this is a fine thing to live with, there's a set of code which will
run during an unload that might make assumptions about what invariants have or
have not been kept in place. This is one of the reasons why it's so important
to reduce the complexity and quantity of code that runs in such situations, and
in particular to reduce as many inter-dependencies as possible. And if an
asynchronous exception was raised and the AD isn't actually being unloaded,
then certainly a whole host of things are sure to be wrong within the AD's
boundaries afterwards. Most of these problems become magnified when examined
under high stress loads.

Orphaned monitors are an example of a perfectly isolated resource that can
still cause problems. If an AD is getting unloaded and a) this involves
multiple threads and b) their cleanup paths attempt any lock acquisition
whatsoever, there is a real risk of deadlock due to a lock that never got
released. But again, this is by and large an application problem, not one for
the Framework to be concerned about. Most of the Framework is written not to be
thread-safe... at least not to access precise shared locks across thread
boundaries anyhow. The criticality of a deadlock, however, is precisely why we
added special code to recognize the 'lock' pattern—this guarantees lock
release in the face of asynchronous exceptions (although not during rude aborts
and rude unloads).

It's likely that inside hosts which aggressively perturb code with thread
aborts, such as ASP.NET for example, innocent Framework code might fail in new
and interesting ways. We're not suggesting that we shouldn't evolve to deal
with these situations as they arise, simply that the cases are so sporadic and
difficult to predict that developers shouldn't proactively seek to fix problems
that might not exist. Aggressive stress testing should uncover most of these
problems.

## Future direction

Of course, this section is highly speculative. The topics raised in this paper
are something that we (the CLR team) intend to look very closely at in the
Orcas timeframe. It's likely that we'll dream up some great new solutions. It's
also likely that any such solutions will require a combination of runtime,
language, and Framework support to get right.

For example, we've begun to adopt the pattern of providing out parameters to
confirm acquisition of a resource, where the acquisition occurs inside a
protected region. This is mostly to avoid the difficulties explained in #3 and
#4 above. For example, the `Monitor.ReliableEnter` method does just this (which
is only internally available, so you're out of luck if you're not shipping
inside mscorlib). It executes inside a CER and sets a bit to indicate that
you've successfully taken the lock. This alleviates concern about #4 above
causing problems. For example, one could imagine the C# `lock` keyword emitted
code like this in the future:

    bool took = false;
    try
    {
      Monitor.ReliableEnter(foo, out took); // code inside synchronized block
    }
    finally
    {
      if (took)
        Monitor.Exit(foo);
    }

So long as you abide by rule #5 above, you will get the benefits of whatever
innovation we do for free, and this doesn't rely on any JIT hackery. We will
certainly look for more places to introduce such a pattern—and even make it
public, too.

`Dispose` is unfortunately more difficult to solve. The goal here would be to
first make sure the construction of an object and assignment to a local
variable is atomic, and second to ensure there's no window between the
assignment and entrance into the try block. Without running constructors inside
a protected region, however, there's no obvious great solution. We certainly
wouldn't advise anybody to execute constructors inside a finally block, for
example. But at the same time, we know we need to figure this one out. Doing
resource allocations inside a protected factory method is one option, for
instance, but only one that makes sense in a situation where you'd feel
comfortable holding up an AD unload in order to protect state.

_This guidance was created mostly in response to constant feedback and
questions we receive on the topic. A lot of this will make its way into the
Design Guidelines in the form of more prescriptive guidance. This paper was
largely an exploratory exercise resulting from conversations and meetings on
the topic. In particular, I'd like to thank Chris Brumme, WeiWen Liu, Brian
Grunkemeyer, Anthony Moore, and Dave Fetterman for their helpful feedback and
suggestions, and indeed pushing the direction of the core message and points in
the above text._

