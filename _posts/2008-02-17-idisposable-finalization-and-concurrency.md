---
layout: post
title: IDisposable, finalization, and concurrency
date: 2008-02-17 20:29:07.000000000 -08:00
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
A long time ago, I wrote that you'd [never need to write another finalizer again](http://www.bluebytesoftware.com/blog/2005/12/27/NeverWriteAFinalizerAgainWellAlmostNever.aspx).
I'm sorry to say, my friends, that I may have (unintentionally) lied.
In my defense, the blog title where I proclaimed this fact _did_ end with "well,
almost never."

Finalizers have historically been used to ensure reclamation of resources that are
finite or outside of the purview of the CLR's GC.  Native memory and Windows
kernel HANDLEs immediately come to mind.  Without a finalizer, resources would
leak; server apps would die, client apps would page like crazy, and life would be
a mess.  For such resources, properly authored frameworks also provide IDisposable
implementations to eagerly and deterministically reclaim the resources when they
are definitely done.  Three years ago, I wrote [a lengthy treatise](http://www.bluebytesoftware.com/blog/2005/04/08/DGUpdateDisposeFinalizationAndResourceManagement.aspx)
on the subject.

The finalizer is there as a backstop.  It is often meant to clean up after bugs
, such as when a developer forgets to call Dispose in the first place, tried to but
failed due to some runtime execution path skipping it (often exceptions-related),
or a framework or library author hasn't respect the transitive IDisposable rule,
meaning that eager reclamation isn't even possible.  It also avoids tricky
ref-counting situations as are prevalent in native code:  since the GC handles
tracking references, you, the programmer, can avoid needing to worry about such low-level
mechanics.  In all honesty, the finalizer's main purpose is probably that
we wanted to facilitate a RAD and VB-like development experience on .NET, where programmers
don't need to think about resource management _at all_, unlike C++ where it's
in your face.  While one could reasonable argue that IDisposable is all you
need (the C++ argument), that would have gone against this goal.

Concurrency changes things a little bit.  A thread is just another resource
outside of the purview of the CLR's GC, and is actually backed by a kernel object
and associated resources like non-pageable memory for the kernel stack, some data
for the TEB and TLS, and 1MB of user-mode stack, to name a few.  They also add
pressure to the thread scheduler.  Threads are fairly expensive to keep around,
and "user" code is responsible for creating and destroying them.

Now, it's true that we are moving towards a world where threads and logical tasks
are not one and the same.  This is a ThreadPool model.  But it's also
true that a task that is running on a thread is effectively keeping that thread alive,
and perhaps more concerning, preventing other tasks from running on it.  _Use
_of a resource is a kind of _actual _resource itself, although more difficult to
quantify.

So, what does all of this have to do with finalization?

If some object kicks off a bunch of asynchronous work and then becomes garbage—i.e.
the consumer of that object no longer needs to access it's information—then it's
possible (or even likely) that any outstanding asynchronous operations ought to be
killed as soon as possible.  Otherwise they will continue to use up system resources
(like threads, the CPU, IO, system locks, virtual memory, and so on), all in the
name of producing results that will never be needed.  The only reason this task
stays alive is because the scheduler itself has a reference to it.

Just as with everything discussed above pertaining to non-GC resources, we'd like
it to be the case that such a component would offer two methods of cleanup:

1. Dispose: to get rid of associated asynchronous computations immediately when the
caller knows they no longer need the object.

2. Finalization: to get rid of associated resources that are still outstanding when
the GC collects the root object that is responsible for managing those asynchronous
computations.

You'll notice that we support cancelation in a first class and deeply-ingrained
way in the Task Parallel Library.  While not exposed in PLINQ (yet), there is
actually cancelation support built-in (though not as fundamental as we'd like (yet)).
This is a useful hook to allow us to build support for both resource reclamation
models.  In this sense, cancelation as a pattern of stopping expensive
things from happening is quite similar to resource cleanup.  Clearly they aren't
identical, but we will need to figure out the specific deltas.

I should also point out that we will prefer and push structured parallelism for many
reasons.  Parallel.For is an example, where the API looks synchronous but is
internally highly parallel.  One reason we like this model is that the point
at which concurrency begins and ends is very specific.  The call won't return
until all work is accounted for and completed.  It's only when you bleed computations
into the background after a call returns that everything stated above becomes an
issue.  This is obviously nice for failures (e.g. you are forced to deal with
them right away), but also because it alleviates this problem nicely.

I don't think we're at a point where we can recommend definite tried-and-true
best practices for cancelation of asynchronous work and how it pertains to resource
management.  I do think we need to get there by the time we ship Parallel Extensions
V1.0.  And I think we will.  Here's a snapshot summary of my current
thinking, however, and I would love to get feedback on it:

1. We should tell people to implement IDisposable and to Cancel tasks inside Dispose,
when their classes own unstructured asynchronous computations.

2. We may or may not want people to implement a finalizer to do the same.  I
currently believe we will.

3. I am undecided about whether these cancelations should be synchronous.  In
some sense, they should be since you'd like to know that all resources have definitely
been reclaimed.  But this would mean blocking (possibly indefinitely) on the
finalizer thread.  That's a definite no-no.  Blocking in Dispose would
mean blocking (possibly indefinitely) inside a finally block.  That's also
a no-no, although it's less severe of one than the finalizer.  It just means
hosts can't take over threads as easily when they need to abort them.  Thankfully
we offer the Task.Cancel method which is non-blocking.  Possibly we should suggest
synchronous cancelation inside of Dispose, and asynchronous inside of the finalizer.

4. If we did do synchronous anywhere, presumably with Task.CancelAndWait, we'd
need to recommend a practice for communicating failures.  Throwing from Dispose
is discouraged, but so is swallowing failures.  The kind of code usually run
inside of Dispose is much less likely to generate exceptions than running arbitrary
tasks full of user code.  Catch-22.

5. There are some cases we can do the cancelation thing ourselves.  Whether
we do or not is subject to debate, but I believe we should.  If we ensured the
scheduler's references are weak, then once all other code in the process drops
the reference, we would not schedule it.  This implies that tasks are seldom
executed "for effect", which is certainly a judgment call.  It might be
worth exposing an option that allows "for effect" tasks to be created not subject
to this rule.

6. The trickiest case is when a task is already running.  For short-running
tasks, this may not be a huge concern, but a lot of such tasks do recursively queue
up additional ones.  It would be nice if the fact that its results are no longer
needed somehow flowed automatically to the task, perhaps through cancelation.
This also means waking tasks from blocking calls.

It's interesting to point out that 5 and 6 were part of the original motivation
for the inventors of the future abstraction.  They noted that representing computations
as futures, and allowing the GC to collect them before they run once they've become
unreachable, effectively makes computations garbage-collectable.  This, I think,
is a neat idea, particularly if your program uses futures pervasively.

In any case, I wanted to point these subtleties out, and hear any feedback folks
out there might have.  What I find particularly interesting about concurrency,
as we move forward on things like Parallel Extensions, is that there are a lot of
subtle implications to the way programs are written.  This includes fundamental
things like exceptions and resource management.  There are other subtle impacts,
like whether the ordering of results coming out of a computation matters.  PLINQ
surfaced this early on, and I didn't expect the pervasive nature of the issue.
Debugging and profiling are also extraordinarily different.  I suspect we'll
continue running into many such things throughout the evolution to highly parallel
software.

