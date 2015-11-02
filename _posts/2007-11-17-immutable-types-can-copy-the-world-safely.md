---
layout: post
title: Immutable types can copy the world… safely!
date: 2007-11-17 08:18:11.000000000 -08:00
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
I [recently described](http://www.bluebytesoftware.com/blog/2007/11/11/ImmutableTypesForC.aspx)
an approach to adding immutability to existing, mutability-oriented programming languages
such as C#.  When motivating such a feature, I alluded to the fact that immutability
can make concurrent programming simpler.  This seems obvious: a major difficulty
in building concurrent systems today is dealing with the ever-changing state of "the
world," requiring synchronization mechanisms to control concurrent reads and writes.
This synchronization leads to inefficiencies in the end product, complexity in the
design process, and, if not done correctly, bugs: race conditions, deadlocks due
to the lack of composability of traditional locking mechanisms, and so forth.

Lock-free algorithms simplify matters (in some ways) by compressing state transitions
into single, atomic writes.  For instance, a lock-free stack has a single head
node; pushing requires swapping the current head with the new node to be enqueued,
and popping entails swapping the current head with its current next pointer.
I mentioned some of the benefits of lock-freedom [here](http://www.bluebytesoftware.com/blog/2007/11/10/TheSlipperySlopeOfLockfreedom.aspx).
Sadly these lock-free techniques do not really compose.  For instance, if I
want to pop from a lock-free stack and push onto another, in an atomic fashion, single-word
compare-and-swap is insufficient.  We'll return to this later in the context
of immutability.

I will draw an analogy between lock-free algorithms and synchronization involving
immutable objects.  Imagine an immutable type represents "the world" in
a concurrent system.  Threads are constantly interacting with the world, by
reading its state, and sometimes changing it.  Because the world is immutable,
we must copy it and publish an entire new one any time we wish our changes to become
visible.  This is key!  It enables optimistic concurrency and synchronization
protocols more similar to lock-free algorithms than lock-based algorithms.

Because individual components inside the world can't change, the entire world can
be read from without synchronization.  Moreover, the creation of the new world
needn't use synchronization either, so long as we are willing to tolerate the possibility
of wasted work, as is always the case with optimistic concurrency: we are being optimistic
that the work will indeed not have been wasted, because writes are infrequent.
That's the basic premise of most concurrency algorithms, e.g. reader/writer locks.
What requires synchronization is merely the publication of the new world.

```
internal static World s_theWorld = new World(...); // The initial world.

internal void ReadTheWorld()
{
    World w = s_theWorld; // This copy never changes!
    // Read state from the world ...
}

internal void ChangeTheWorld()
{
    World oldWorld;
    World newWorld;
    do {
        oldWorld = s_theWorld; // Read the world.
        // Read state to compute the new world ...
        newWorld = new World(...);
    }
    while (Interlocked.CompareExchange(
        ref s_theWorld, newWorld, oldWorld) != oldWorld);
}
```

In this scheme, there will always be inherent races between threads trying to call
ReadTheWorld and threads trying to call ChangeTheWorld.  This is a basic characteristic
of the system.  But it is more functional.  If ReadTheWorld produces correct
answers for any world sequentially, then it will also produce correct answers in
a parallel program too, since worlds cannot change.  And because writes are
guaranteed to retire in order on the [CLR 2.0 memory model](http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx),
we can be assured that ReadTheWorld will not be subject to memory reordering bugs.

This is a very powerful technique, making code that reads from and changes the world
much simpler to write, understand, and debug.  How many times have you longed
for a programming technique where code can be tested in a sequential context and
still be guaranteed to produce the right answers in a parallel context?

With all that said, it's sadly not applicable to every synchronization problem.
Some of the problems that arise can be worked around, and others are more difficult.
I will outline the most difficult of them.

**As with most lock-free algorithms, livelock is a distinct possibility.**

Livelock occurs because many threads may attempt to compute a new world simultaneously.
If they both read the same old world, only one will succeed at publishing their copy
of the new world.  The other thread will have to go back 'round the loop,
re-read the current world, compute a new one, and try again.  Computing a new
world may take some time which, coupled with high arrival times, may lead to unfair
forward progress and wasted work due to spinning.  We hope, however, that in
most cases the frequency of writes is small enough to make this a less pressing issue.
Also note that the algorithm shown above is truly wait-free: the failure of one thread
indicates that another thread has succeeded in publishing a new world.  So forward
progress of our system is not compromised by this problem.

**ChangeTheWorld may need to perform impure, irreversible side effects.**

A nasty issue in today's programming languages is the reliance on side-effects.
(OK, that's unfair.  This is a nasty issue in today's conventional programming
techniques and styles, and the languages we use simply accommodate these techniques.
This is mostly because, if we didn't, developers would find a way to circumvent
the system, prefer to use alternative languages, and so on.)  But if, corresponding
with the update of the world, another side effect must be made, this technique doesn't
accommodate that.  We could work around that with other synchronization techniques
but it is likely to be cumbersome.  In some cases, there is no harm in performing
a side effect, so long as it does not "undo" the side effect associated with
a newer world.

For instance, say we needed to update a GUI with the results of the new world computation.
We would want to ensure the GUI was refreshed with the most recent update. Thankfully
we don't need to worry about the world changing itself, so we may do something
like this:

```
internal void ChangeTheWorld()
{
    ... as before ...
    myGuiControl.BeginInvoke(delegate {
        if (s_theWorld == newWorld)
            // Update the GUI with newWorld.
    });
}
```

This ensures we only update the GUI with the latest world.  Imagine the sequence:
world A is published, world B is published, we refresh the GUI with world B, we receive
the BeginInvoke associated with world A now (out of order, which is perfectly reasonable).
We must make sure that the graphical depiction of world A doesn't overwrite world
A.  Thankfully the automatic mutual exclusion inherent in GUI programming ensures
that our dirty check s\_theWorld == newWorld is sufficient to prevent this from occurring.
Clearly this technique can't always apply.

**This technique doesn't expand to support multiple immutable fields.**

This is a fundamental flaw with techniques that rely on a single, atomic compare-and-swap.
Processor vendors have recently published papers for technologies like transactional
memory and multi-word compare-and-swap (and in fact, there is [plenty of research](http://portal.acm.org/citation.cfm?id=1233307.1233309)
into pure software implementations of both), which would allow us to fix this problem.

The title of this article, by the way, is a play on Wadler's paper ['Linear types
can change the world!'](http://citeseer.ist.psu.edu/28024.html)  I highly
recommend that paper to anybody interested in immutability, isolation, and purity.
This paper demonstrates type system support for linearity which, in essence, enables
safe reading and mutual exclusion via the type system instead of locking.  There
is only one world, after all, the paper argues, so the traditional functional programming
approach of disallowing mutability is actually a bit unrealistic.

In summary, immutable types add a lot of simultaneous power and simplicity to parallel
programming.  They are certainly not a panacea, since they require shifting
to a more functional style of programming, where side-effects are discouraged and
state is updated by making altered copies.  This is often non-trviial.
But this is one of many steps in what I consider to be the right direction.
A direction that will enable us to tolerate large amounts of parallelism...
without causing all of us to die of race-condition-induced anxiety attacks before
the age of 30.

