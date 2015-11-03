---
layout: post
title: Concurrency-oriented code reviews
date: 2008-03-28 10:04:50.000000000 -07:00
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
We take code reviews very seriously in our group.  No checkin is ever made without
a peer developer taking a close look.  (Incubation projects are often treated
differently than product work, because the loss of agility is intolerable.)
A lot of this is done over email, but if there's anything that is unclear from
just looking at the code, a face to face review is done.  Feedback ranges from
consistency (with guidelines and surrounding code), finding errors or overlooked
conditions, providing suggestions on how to more clearly write something, comments,
etc.; this ensures that our codebase is always of super high quality.

Concurrency adds some complexity to development, and requires special consideration
during code reviews.  I thought I'd put some thoughts on paper about what
I look for during concurrency-oriented code reviews, in hopes that it will be useful
to anybody starting to sink their teeth into concurrency; it may also help you devise
your own internal review guidelines.  Most of this advice just comes down to
knowing a laundry list of best practices, but a lot of it is also knowing what to
look for and where to spend your time during a review.

(A couple years ago I wrote a lengthy "Concurrency and its impact on reusable libraries"
essay which provides a lot of the motivation behind what I look for.  It's
up on my blog, [http://www.bluebytesoftware.com/blog/2006/10/26/ConcurrencyAndTheImpactOnReusableLibraries.aspx](http://www.bluebytesoftware.com/blog/2006/10/26/ConcurrencyAndTheImpactOnReusableLibraries.aspx),
and (though slightly out of date) I'm revising it for an Appendix in [my upcoming
book](http://www.bluebytesoftware.com/books/winconc/winconc_book_resources.html).
If you question why I believe something, chances are that this document will explain
my rationale.  And it's far more complete than this short essay; I've only
hit the high points here.)

**Getting started**

I first review the code in a traditional sequential code review fashion.  When
doing this, I earmark all state that I see as either "private" (aka isolated)
or "shared".  I then go back and closely review all state that is shared
(accessible from many threads) with a fine-tooth comb.  Sometimes I'll do
this during my first pass through, but I usually find it helpful to understand the
algorithmic structure of the changes first before fully developing an understanding
of the concurrency parts.

Changes to existing code should be reviewed just as carefully (if not more carefully)
as new code.  Concurrency behavior is subtle, and it's very easy to accidentally
violate some unchecked assumption the code was previously making.  Liberal use
of asserts is therefore very important.  Sadly many of the conditions code assumes
are simply unassertable (like "object X isn't shared").
I easily spend about 2x the amount of time reviewing the concurrency aspects of the
code than usual sequential aspects.  Perhaps more.  This extra time is
OK, because the concurrency portion is far smaller (in lines of code) than the sequential
portion in most of the code I review.  There are obvious exceptions to this
rule, especially since I'm on a team building low-level primitive data types whose
sole purpose in life is to be used in concurrent apps.

**Shared state and synchronization**

Some state, although shared, is immutable (read-only) and can be safely shared and
read from concurrently.  Often this is by construction (e.g. immutable value
types) but sometimes this is by loose convention (e.g. a data structure is immutable
for some period of time, simply by virtue of no threads actively writing to it).
Both should be clearly documented in the code.
Once mutable shared state is identified, I look for two major things:

1. When does it become shared, i.e. publicized, and what is the protocol for the
transfer of ownership?  Is it done cleanly?  And is it well documented?

2. When does it once again become private again, if ever?  And is this documented
too?

Ideally all shared state would have clean ownership transitions.  Any state
that is disposable necessarily must have a point at the end of its life where it
has a single owner, so it can be safely disposed of (unless ref-counting is used).
But for most state the line will be extremely blurry and unenforced.  Comments
should be used to clarify, in gory detail.  I also tend to prefix names of variables
that refer to shared objects with the word 'shared' itself, so that they jump
out.

Many, many bugs arise from some code publicizing some state, sometimes by accident,
and then continuing to treat it as though it is private.  It is also sometimes
tricky to determine this precisely, since sharing can be modal.  A list data
structure may be shared in some contexts but not others.  Knowing what its sharing
policy is requires transitive knowledge of callers.  Building up this level
of global understanding can involve a fair bit of simply sitting back and reading
and rereading the code over and over again.

Once the policy around sharing a piece of state is known, it is crucial to understand
the intended synchronization policy for that data.  Is it protected by a fine-grained
monitor?  Is it manipulated and read in a lock-free way?  And so on.
And once the intended policy is known, is the actual policy implemented what was
intended?

While this part is extremely important, by the way, I have to admit that I feel this
aspect tends to overshadow other things in conversation.  This is probably because
it's the most obvious thing to look for.  Sadly the world of concurrency is
far more subtle than this.  I've honestly found more bugs resulting from failing
to identify shared state properly than resulting from failing to implement the synchronization
logic itself properly.  Your mileage will of course vary.

**Locks**

I treat lock-based code and lock-free as two entirely separate beasts.  I spend
about 5x the time reviewing lock-free code when compared to lock-based code.
There is a tax to having lock-free code in any codebase, so as you are reviewing
it, also ask yourself: is there a better (or almost-as-good) way that this could
have been done using locks?  Often the answer is no, due to the benefits lock-freedom
brings (no thread can indefinitely starve another).

But if the answer is yes, that the code could be written more clearly using locks,
you could save your team a lot of time by convincing the author to change his or
her mind.  Not only is lock-free code far more difficult to write and test,
it carries a large tax during long stress hauls and end-game bug-fixing, an important
and time-sensitive period in the development lifecycle of any commercial software
product.  Maintaining lock-free code also carries an extra long-term cost, particularly
when ramping up new hires on it.  All of this risks interfering with your ability
to work on cool new features at some point.  Don't feel bad about pushing
back on this one.  Hard.

Carefully review what happens inside of a lock region.  Look at every single
line with scrutiny.

- Lock hold times should be as short as possible.  Hold times should be counted
in dozens or hundreds of cycles, not thousands (unless absolutely unavoidable).

- If lock hold times are in the dozens, you can consider using a spin-lock.

- Recursive lock acquisitions are strongly discouraged.  If it can happen, did
the developer clearly intend it to happen?  Or is this possibility accidental?
Point it out to them.  Also, are there any unexpected points at which reentrancy
can occur?  E.g. any APC or message-pumping waits?  If yes, is there a
way to avoid that by simple restructuring of the code?

- Dynamic method calls via delegates or virtual methods while a lock is held should
be as rare as possible.  Method calls under a lock to user-supplied code should
only ever happen if the concurrency behavior is clearly documented and specified
for the user, and when invariants hold.  All of these cases can lead to reentrancy.
Often this requires special code to detect the reentrancy and respond intelligently.

- Lock regions should usually not span multiple methods: for example, acquiring the
lock in one method, returning, and having the caller release it in another method
is bad form.  It is very easy to screw up the control flow and deadlock your
library.

- CERs can only use spin-locks currently (because Monitor.ReliableEnter is currently
unavailable), if you care about orphaning locks at least (which most CER-cost does).
If you see somebody trying to write a CER using a CLR Monitor, their code is probably
busted.  Thankfully CERs are pretty rare to encounter in practice.

Races that break code are always must-fix bugs, no matter how obscure.  If they
happen with low frequency on the quad-cores of today, they will probably break with
regularity on the 16-cores of tomorrow.  The kinds of code my team writes needs
to remains correct and scale well into the distant future; presumably if you're
writing concurrent code already, yours does too.  If you find such a race, the
code should not even be checked in until it's fixed.  "But it only happens
once in a while" is an inexcusable answer.  Benign races are OK but should
be clearly documented.

**Events**

When I see any event-based code (either Monitor Wait/Pulse/PulseAll condition variables
or some event type, like AutoResetEvent or ManualResetEvent), the first thing I do
is build up a global understanding of all the conditions under which events are set,
reset, and waited on.  This is to understand the coordination and flow of threads
top-down, rather than bottom-up.  Because I've already reviewed the sequential
parts of the algorithm, I typically already know the important state transitions
events are guarding before I even get to this point.

Next, there are some simple aspects to specific usage of events that I look for:

- Understanding the relationship between mutual exclusion, the state, and the events
is important and subtle.  Comments should be used ideally to explain that.

- Does the setting of the event happen in a wake-one (Pulse, Auto-Reset) or wake-all
(PulseAll, Manual-Reset) manner?  If it's wake-one, are all waiters homogeneous?
Is it always strictly true that waking-one is sufficient and won't lead to missed
wake-ups?

- Waiters that release the lock and then wait should be viewed with suspicion.
There's a race between the release and wait that notoriously causes deadlocks.

- Concurrent code should never use timeouts as a way to work around sloppiness in
the way threads wait and signal.  A missed wake-up is a bug in the code that
must be fixed.

**Lock-freedom and volatiles**

If you're looking at lock-free code, you need to have a firm grasp on the CLR's
memory model.  See [http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx](http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx)
for an overview.  Don't think about the machine, think about the logical abstraction
provided by the memory model.  You also need a firm grasp on the invariants
of the data structures involved.  Specifically you are looking to see if the
structure could ever move into a state, visible by another thread, where one of these
invariants doesn't hold.  I explicitly permute (often on a whiteboard or in
notepad) the sections of the code that involve shared loads and stores, using knowledge
of the legal reorderings given our memory model, to see if the code breaks.

Any variable marked as volatile should be a red flag to carefully review all use
of that variable.  For every single read and every single write of that variable,
you must look at it and convince yourself of why volatile is necessary.  If
you can't, ask the person who wrote the code.  Sometimes volatile is used
because most (but not all) call sites need it; that's often acceptable.  Leaving
the variable as non-volatile and selectively using Thread.VolatileRead for the reads
that need it is typically too costly.  Anyway, comments should always be used
to explain why each load and store is volatile, even if it doesn't strictly need
the volatile semantics.

Conversely, any variable that is apparently shared, but not marked volatile, should
be an even redder flag.  It's very likely that this is a mistake.  Recall
that writes happen in-order with the CLR's memory model, but that reads do not.
Anytime there is a relationship between multiple shared variables that are written
and read together (without the protection of a lock), they typically both need to
be volatile.

Any reads of shared variables used in a tight loop must be marked volatile.
Otherwise the compiler may decide to hoist them, causing an infinite loop.
Even if they are retrieved via simple method calls like property accessors (due to
inlining).

Thread.MemoryBarrier should typically only occur to deal with store (release) followed
by load (acquire) reordering problems.  And it's usually a better idea to
use an InterlockedExchange for the store instead, since it implies a full barrier
but combines the write.  Sometimes a fence can be used to flush write buffers—like
when releasing a spin-lock to avoid giving the calling thread the unfair ability
to turn right around and reacquire it—but this is extremely rare, and often an
indication that somebody has an inaccurate mental model of what the fence is meant
to do.

Custom spin waiting should be used rarely.  If you see it used, the person may
not be aware that spin waits [need special attention](http://www.bluebytesoftware.com/blog/2006/08/23/PriorityinducedStarvationWhySleep1IsBetterThanSleep0AndTheWindowsBalanceSetManager.aspx): to
work well on HT machines, yield properly to all runnable threads with appropriate
amortized costs, to spin only for a reasonable amount of time (in other words, less
than the duration of a context switch), and so on.  Thread.SpinWait does not
do what most people expect, since it only covers the first.  Kindly let them
know about these things.  If any spin waiting is used in a codebase, it's
far better to consolidate all usage into a single primitive that does it all.

**Wrapping up**

At the end of each review, ask yourself whether all of the concurrency-oriented parts
of the code were clearly explained in the design doc for the feature.  Did this
carry over to clearly written comments in the implementation?  These are some
really hard issues to get your head around, so the time spent reviewing the code
should not be lost.  Somebody, someday down the road, will need to understand
the code again (perhaps so that they can maintain it, test it, etc.), and it is your
responsibility as a member of the team—regardless of whether you wrote the code—to
do your part in making that feasible.  You should explicitly go back to the
design doc and suggest areas for clarification.

