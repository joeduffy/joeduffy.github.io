---
layout: post
title: Condition variables and lock recursion
date: 2007-09-12 00:03:11.000000000 -07:00
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
Lock recursion is usually a bad idea.  It can seem convenient (at first), but once
the slippery slope of making calls from critical regions into complex ecosystems
of code is embarked upon (which is usually a necessary pre-requisite to lock recursion,
except for some relatively simple cases), it's easy to accidentally fall right
off the edge.  This topic was part of the doc I wrote previously about [using
concurrency inside of reusable libraries](http://www.bluebytesoftware.com/blog/2006/10/26/ConcurrencyAndTheImpactOnReusableLibraries.aspx).
My opinions haven't changed much since then.

Lock recursion coupled with condition variables is even worse.  In fact, its
behavior might surprise you.

To motivate this, would you ever think of writing code that does something like this?

```
void BreakAtomicity()
{
    ... I assume somebody called me with a recursive lock on 'obj' ...
    Monitor.Exit(obj);
    Monitor.Exit(obj);
    ... Do something ...
    Monitor.Enter(obj);
    Monitor.Enter(obj);
}
```

I should certainly hope not!  Unless you're crazy or reeeeally know what you're
doing.  Who knows what state invariants are busted at the time the call to BreakAtomicity
was made?  Releasing the lock in this manner hoists these ticking timebombs
onto the other threads into the process that might want to inspect the shared state.
If you, the author of BreakAtomicity, have all-knowing omnipresent knowledge of the
entire program, perhaps you know precisely.  But, particularly in the case of
recursion, where it's all-too-common to engage in practices of sloppy composition,
this is actually quite unlikely.  Lock recursion is typically used for convenience,
not because of a really solid design that is based on clean algorithmic recursion.

What does this example have to do with condition variables anyway?  Glad you
asked!  It matters because of what happens when you wait on a monitor that
has been recursively acquired.  In such cases, Monitor.Wait will release _all
_recursive acquires as part of its waiting.  I.e. if it has been acquired 10
times, it is released 10 times before waiting.  It does this, of course, because
otherwise it would deadlock waiting for some other thread to make a call to Monitor.Pulse/PulseAll
(since a separate thread needs to first acquire the lock in order to do either).
This is symmetric, so once the thread has been awoken, it will reacquire the lock
as many times as needed before returning to attain the same level of recursion that
existed prior to the call.

Now, Monitor.Wait breaks atomicity anyway.  This is obvious.  It releases
and reacquires the lock internally, and so any conditions regarding shared state
that exist prior to the call cannot be assumed to exist after the call returns.
(Most) people understand this and tend to use Wait in fairly common and safe patterns,
such as guarded regions where some predicate is checked for validity at the very
front of a critical region before doing anything interesting with state.  But
the really nasty thing about recursive locks and the Wait behavior described above
is that this breaks atomicity for some unknowing number of nested critical regions
that have existed for some unknown amount of time leading up to the Wait.  This
is a recipe for pain.  My recommendation is probably predictable: just following
the broadly accepted advice that, because lock recursion is evil to begin with, it
is best avoided, and you will safely avoid the more complicated case outlined above.

It's worth pointing out that the new CONDITION\_VARIABLE in Vista, i.e. SleepConditionVariableCS
and SleepConditionVariableSRW, only release the lock once, despite recursive acquire
counts.  (SRWL doesn't officiailly support recursion, although it works for
shared locks since there is no affinity used and it is undetectable.)  Deadlocks
result instead.  From an editorial perspective, I prefer this behavior quite
a bit, since it's easier to debug.  (Admittedly, if Monitor's behavior is
what you want, it's less than straightforward to achieve, unless you know the recursion
counter somehow.  Although, I will also note that I am convinced very few real
people would want Monitor's current behavior...)  My preferred solution to
this would have been to throw an exception, since I do think issuing a Wait when
locks have been recursively acquired is in most cases a bug.  As a workaround,
we could have exposed a RecursionCount on Monitor so that a developer could manually
exit the lock RecursionCount-1 times before the call to Wait and then reacquire it
RecursionCount-1 times after the call returns.  (Actually no -- I would have made
Monitor non-recursive by default, like the new ReaderWriterLockSlim.)  Sadly,
I guess I'm only about 10 years too late...

