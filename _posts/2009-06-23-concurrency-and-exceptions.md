---
layout: post
title: Concurrency and exceptions
date: 2009-06-23 20:13:52.000000000 -07:00
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
I wrote this memo over 2 1/2 years ago about what to do with concurrent
exceptions in Parallel Extensions to .NET.  Since [Beta1 is now out](http://www.microsoft.com/downloads/details.aspx?FamilyID=ee2118cc-51cd-46ad-ab17-af6fff7538c9&displaylang=en),
I thought posting it may provide some insight into our design decisions.  I've
made only a few slight edits (like replacing code- and type-names), but it's mainly
in original form.  I still agree with much of what I wrote, although I'd definitely
write it differently today.  And in retrospect, I would have driven harder to
get deeper runtime integration.  Perhaps in the next release.

**~~~**

# Concurrency and Exceptions
October, 2006

Exceptions raised inside of concurrent workers must be dealt with in a deliberate
way.  Failures can happen concurrently, and yet often the programmer is working
with an API that appears to them as though it's sequential.  The basic question
is, then, how do we communicate failure?

## The problem

Fork/join concurrency, in which a single "master" thread forks and coordinates
with N separate parallel workers, is an incredibly common instance of one of these
sequential-looking concurrent operations.  The same callback is run by many
threads at once, and may fail zero, one, or multiple times.  The exception propagation
problem is inescapable here and comes with a lot of expectations, because the programmer
is presented a traditional stack-based function calling interface papered on top
of data or task parallelism underneath.

I am faced with the need for a solution to this problem for PLINQ right now and,
while I could invent a one-off solution, we owe it to our customers to come up with
a common platform-wide approach (or at least ManyCore-wide).  Any solution should
compose well across the stack, so that somebody invoking a PLINQ query from within
their TPL task that was spawned from a thread pool thread yields the expected and
consistent result.  And I would like for us to reach consensus for both managed
and native programming models.

Before moving on, there is one non-goal to call out.  Long-running tasks not
under the category of fork/join also deserve some attention, because of the ease
with which stack traces can be destroyed and the corresponding impact to debugging,
but I will ignore them for now.  The problem is not new, exists with the IAsyncResult
pattern, and PLINQ doesn't use this sort of singular asynchronous concurrency.
These cases can typically be trivially solved using existing mechanisms, like standard
exception marshaling.

## No errors, one error, many errors

To understand the core of the issue, imagine we have an API 'void ForAll(Action
a, T[] d)'.  It takes a delegate and an array, and for every element 'e'
in 'd' invokes the delegate, passing the element, i.e. 'a(e)'.  If multiple
processors are available, the implementation of ForAll may use some heuristic to
distribute work among several OS threads, for instance by partitioning the array,
probably running one partition on the caller's thread, and finally joining with
these threads before returning so that the caller knows that all of the work is complete
when the API returns.

ForAll is not fictitious, and is similar to a number of PLINQ APIs: Where, Select,
Join, Sort, etc.  It is also exposed directly by the TPL runtime's Parallel
class which intelligently forks and joins with workers.

'a' is a user-specified delegate and can do just about anything.  That includes,
of course, throwing an exception.  What's worse, because 'a' is run in
several threads concurrently, there may be more than one exception thrown.
In fact, there are three distinct possibilities:

1. No errors: No invocations of 'a' throw an exception.

2. One error: A single invocation of 'a' throws an exception.

3. Many errors: Concurrent invocations of 'a' on separate threads throw exceptions.

Clearly letting an exception crash whichever thread the problematic 'a(e)' happened
to be run on is problematic and confusing.  If for no other reason than the
IAsyncResult pattern has established precedent.  But realistically, the developer
would be forced to devise his or her own scheme to marshal the failure back to the
calling thread in order for any sort of chance at recovery.  They would get
it wrong and it would lead to incompatible and poorly composing silos over time.
A Byzantine model that fully prohibits exceptions passing fork/join barriers goes
against the simple, familiar, and understandable (albeit often deceptively so) model
of exceptions.

(That said, marshaling leads to a crappy debugging experience.  An already attached
debugger will get a break-on-throw notification at the exception on the origin thread,
but since we catch, marshal, and (presumably) rethrow, the first and second chances
for unhandled exceptions won't happen until after the exception been marshaled.
This breaks the first pass, and by the time the debugger breaks in, or a crash dump
is taken, the stack associated with the origin thread is apt to have gone away, been
reused for another task (in the case of the thread pool), etc.  We generally
try to avoid breaking the first pass in the .NET Framework, but do it in plenty of
places: the BCL today already contains tons of try { … } catch { /\*cleanup \*/
throw; }-style exception handlers, for example.  For this reason I'm not terribly
distraught over the implications of doing it ourselves.  And sans deeper integration
with the exception subsystem -- something we ought to consider -- there aren't
many reasonable alternatives.)

What makes this problem really bad is that ForAll appears as though it's synchronous:

```
void f() {
    // do some stuff
    ForAll(..., ...);
    // do some more stuff, 'ForAll' is completely done
}
```

The method call to ForAll itself is synchronous, but of course its internal execution
is not.  But still, to the developer, the call to this function represents one
task, one logical piece of work, regardless of the fact that the implementation uses
multiple threads for execution.  As higher level APIs are built atop things
like ForAll, the low level parallel infrastructure problem becomes a higher level
library or application problem.  A Sort that is internally parallel must now
decide what exception(s) it will tell callers it may throw.

## Nondeterministic exception ordering

We assume the ForAll API stops calling 'a(e)' on any given thread when it first
encounters an exception.  That is, each thread just does something like this:

```
for (int i = start_idx; i < end_idx; i++) {
    a(d[i]);
}
```

The for loop terminates when any single iteration throws an exception.  Imagine
our array contains 2048 elements and that ForAll smears the data across 8 threads,
partitioning the array into 256-element sized chunks of contiguous elements.
So partition 0 gets elements [0…256), partition 1 gets [256…512), …, and partition
7 gets [1792…2048).  Now imagine that 'a' throws an exception whenever
fed a null element, and that every 256th element in 'd', starting at element
10, is null.  What can a developer reasonably expect to happen?

On one hand, if we're trying to preserve the illusion of sequential execution,
we would only want to surface the exception from the 10th element.  With a sequential
loop, this would have prevented the 266th, 522nd, and so on, elements from even being
passed to 'a'.  So we might simply say that the "left most" exception
(based on ordinal index) is the one that gets propagated.  The obvious problem
with this is there are races involved: subsequent iterations indeed may have actually
run.  Alternatively, we might consider only letting the "first" propagate.
Unfortunately, that doesn't work either, because we unfortunately can't necessarily
determine, for a set of concurrent exceptions, which got thrown first.  Even
if they have timestamps, they could occur in parallel at indistinguishably close
times.  Nor does this really matter, because it feels fundamentally wrong.

The reason is that we can't simply throw away failures without true recoverability
in the system, a la STM.  The execution of code leading up to the exception
did actually happen, after all, and there could be residual effects.  We might
be masking a terrible problem by throwing failures away, possibly leading to (more)
state corruption and (prolonged, perhaps unrecoverable) damage.  What if the
10th element was a simple ArgumentNullException that the caller chooses to tolerate,
but the 266th element's exception was in response to a catastrophic error from
which the application can't recover?  We can't choose to propagate the 10th
but swallow the 266th.  Broadly accepted exceptions best practices suggest that
app and library devs never catch and swallow exceptions they cannot reasonably handle.
We should do our best to follow the spirit of this guidance too.

## Re-propagation

We could employ an approach similar to the IAsyncResult pattern, with some slight
tweaks.

If each concurrent copy of ForAll caught any unhandled exceptions and marshaled them
to the forking thread, including any exceptions that happen on the forking thread
itself, we could then propagate all of them together after the join completes.
The question is then: what exactly do we propagate?

If there is just a single exception, it's tempting to just rethrow it.  But
I don't believe this is a good approach for two primary reasons:

1. This will destroy the stack trace of the original exception.  This means
no information about the actual source of the error inside 'a' is available.
With some help from the CLR team, we might be able to get a special type of 'rethrow'
that copied the original stack trace before recreating a new one.  This is already
done for remoted exceptions, and the Exception base class will prefix the original
remoted stack trace to the new stack trace.

2. This doesn't scale to handle multiple exceptions.  If we could solve #1,
it might be attractive because it appears as-if things happened sequentially, but
we can't escape #2, no matter what we do.  We could have different behavior
in these two cases, but I believe it's better to remain consistent instead.
Otherwise, developers will need to write their exception handles two ways: one way
to handle singular cases, and the other way to handle multiple cases, where the same
API may do either nondeterministically.

Given that we need to propagate multiple exceptions, we should wrap them in an aggregate
exception object, and propagate that instead.  At least this way, the original
exceptions will be preserved, stack trace and all.  Of course the original exceptions
themselves might be other aggregates, handling arbitrary composition.

For sake of discussion, call this aggregate exception System.AggregateException,
which of course derives from System.Exception.  It exposes the raw Exception
objects thrown by the threads, via an 'Exception[] InnerExceptions' property,
and additional meta-data about each exception: from which thread it was thrown, and
any API specific information about the concurrent operation itself.  This last
part is just to help debuggability.  For instance, we might tell the developer
that the ArgumentNullException was thrown from a thread pool thread with ID 1011,
and that it occurred while invoking the 266th element 'e' of array 'd'.
We might also guarantee the exceptions will be stored in the order in which they
were marshaled back to the forking thread, just to help the developer (as much as
we can) piece together the sequence of events leading to failures.

> _(Editor's note: we decided against storing this meta-data information for various
reasons.)_

Now the dev can do whatever he or she wishes in response to the exception.
Previously they might have written:

```
try {
    ForEach(a, d);
} catch (FileNotFoundException fex) {
    // Handler(fex);
}
```

And now they would have to instead write:

```
try {
    ForAll(a, d);
} catch (AggregateException pex) {
    List unhandled = new List();
    foreach (Exception e in pex.InnerExceptions) {
        FileNotFoundException fex = e as FileNotFoundException;
        if (fex == null) {
            unhandled.Add(fex);
        } else {
            // Handler(fex);
        }
    }

    if (unhandled.Count > 0)
        throw new AggregateException(unhandled);
}
```

In other words, they would catch the AggregateException, enumerate over the inner
exceptions, and react to any FileNotFoundExceptions as they would have normally.
(Taking into consideration that there might have been multiple.)  At the end,
if there are any non-FileNotFoundExceptions left over, we propagate a new AggregateException
with the handled FileNotFoundExceptions removed.  If there was only one remaining,
we could, I suppose, try to rethrow just that, but this has the same nondeterminism
problems mentioned above.

Very few people will write this code.  But one of the most vocal arguments against
it is: just throw one singular exception, such as ForAllException, and let it crash,
because no developer will handle it.  Well, that scheme is no better than throwing
the AggregateException.  At least the aggregation model lets people write backout
and recovery code if they have the patience to deal with the reality that multiple
exceptions occurred.

To make this slightly easier, we could expose an API, 'void Handle(Func a) where
T : Exception', that effectively encapsulates the same logic as shown above, repropagating
the exception at the end if all the exceptions weren't handled (i.e. some weren't
of type T):

```
try {
    ForAll(a, d);
} catch (AggregateException pex) {
    pex.Handle(delegate(Exception ex) {
        FileNotFoundException fex = ex as FileNotFoundException;
        if (fex != null) {
            // Handle(fex);
            return true;
        }

        return false;
    });
}
```

(One problem with this approach is that the 'throw' inside of Handle will destroy
the original stack trace for 'pex'.  An alternative might be for Handle
to modify the AggregateException in place, keeping the stack trace intact, returning
a bool that the caller switches on and does a 'throw' if it returns false; this
is unattractive because it's error prone and could lead to accidentally swallowing,
but in the end might help debuggability.)

If we cared about eliminating unnecessary catch/rethrows, we could use 1st pass filters
instead, but this would only be available to VB and C++/CLI programmers, as C# doesn't
expose filters.  For example, in pseudo-code:

```
try {
    ForAll(a, d);
} catch (fex.InnerExceptions.Contains<FileNotFoundException>()) {
    // Handle ...
}
```

Although interesting, we're trying to move away from our two pass model.
So let's forget about this for now.

This approach suffers when composing with non-aggregate exception aware code.
For it to work well, everybody on the call stack needs to be looking inside the aggregate
for "their" exception, handling it, and possibly repropagating.  If we want
existing BCL APIs to start using data parallelism internally, we would have to be
careful here, not to break AppCompat because we start throwing AggregateExceptions
instead of the originals.

This is probably where there's an opportunity for better CLR and tool integration.
For instance, you could imagine a world where the CLR automatically unravels the
parallel failures, matching and running handlers for specific exceptions inside the
aggregate as it goes, but repropagating if all exceptions weren't handled.
This is very hand-wavy and fundamentally changes the way exceptions work, so it would
require a lot more thought.  A catch block that swallows an exception (today)
is just about guaranteed—asynchronous exceptions aside—that the IP will soon
reach the next instruction after the try/catch block.  This is a pretty basic
invariant.  With this proposal, that wouldn't be the case, and would be bound
to break large swaths of code.  Sticking with the library approach (with all
its imperfections) seems like the best plan of attack for now.

## Waiting for the "join" to finish

There was something implicit in the design mentioned above.  The ForAll API,
and others like it, wouldn't actually propagate exceptions until the fate of all
threads was known.

Imagine we have the scenario described earlier (2048 elements, 8 threads), but slightly
different: the 0th element causes an exception, but no other.  It turns out
this is probably a common case, i.e. that only a subset of the partitions will yield
an exception.  In this case, we would still have to wait for 7\*256 = 1,792
elements to be run through 'a' before this exception is propagated.  Imagine
a slightly different case.  The 0th element throws a catastrophic exception,
and the application is going to terminate as soon as it propagates.  'a'
simply can't be run any more, and will keep reporting back this same exception.
But it will take 8 of these exceptions to actually stop the application, i.e. by
calling 'a' on the 0th, 256th, 512th, etc. elements, if we wait for all tasks
to complete.  If each exception corresponds to some failed attempt at forward
progress, one that possibly corrupts state, then the damage is O(N) times "worse"
(for some measurement) than in the sequential program, where N is the number of concurrent
tasks.

Instead of waiting helplessly, we could try to aggressively shut down these concurrent
workers.

At first, you might be tempted to employ CLR asynchronous thread aborts, but this
is fraught with peril.  Almost all .NET Framework code today is taught that
thread abort == AppDomain unload, and reacts accordingly.  State corruption
stemming from libraries as fundamental as the BCL would be just about guaranteed.
Changing this state of mind and the state of our software would be quite the undertaking.

Instead, we can have the concurrent API itself periodically check an 'abort'
flag shared among all workers.  The first thread to propagate an exception would
set this flag.  And whenever a worker has seen that it has been set, it voluntarily
returns instead of finishing processing data:

```
for (int i = start_idx; i < end_idx; i++) {
    a(d[i]);
}
```

This increases the responsiveness of exception propagation, but clearly isn't foolproof.
There will still be a delay for long-running callbacks.  Thankfully, with PLINQ,
TPL, and I hope most of our parallel libraries, the units of work will be individually
fine-grained, and therefore this technique should suffice.

If a concurrent worker is blocked, there's not a whole lot we can do.  Much
like thread aborts, you might be tempted to use Thread.Interrupt to remove it from
the wait condition.  Unfortunately this will leave state corruption in its wake,
because plenty of code does things like WaitHandle.WaitOne(Timeout.Infinite) without
checking the return value or expecting a ThreadInterruptionException.  The same
argument applies to, say, user-mode APCs.  Eventually you might also be tempted
to use IO cancellation in Windows Vista to cancel errant, runaway network or disk
IO requests.  This would be great.  But this also generally has the same
problem as interruption, so until we find a general solution to that, we can't
do any of this.

> _(Editor's note: We eventually solved this problem by coming up with a [unified
cancellation framework](http://blogs.msdn.com/pfxteam/archive/2009/06/22/9791840.aspx).)_

## One last note

This path forward seems best for now, but it leaves me wanting more.

In the end, this feels like a more fundamental problem.  An API like ForAll
gives the illusion of an ordinary, old sequential caller/callee relationship.
But the callee doesn't use a stack-based calling approach: instead, it distributes
work among many concurrent workers, turning the linear stack into a sort of dynamically
unfolding cactus stack (or tree).  And SEH exceptions are fundamentally linear
stack-based creatures.

In this world, it's just a simple fact that data all over the place can become
corrupt simultaneously.  Many things can fail at once because many things are
happening at once.  It's inescapable.  Recovery is disastrously difficult,
so most failures will end in crashes.  STM's promise for automatic recovery
offers a glimmer of hope, but without it, I worry that papering a sequential "feel"
on top of data/task parallelism is a dangerous game to play.

