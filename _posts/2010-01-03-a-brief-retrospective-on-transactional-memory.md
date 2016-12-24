---
layout: post
title: A (brief) retrospective on transactional memory
date: 2010-01-03 11:05:12.000000000 -08:00
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
Rewind the clock to mid-2004.  Around this time awareness about the looming
"concurrency sea change" was rapidly growing industry-wide, and indeed within
Microsoft an increasing number of people -- myself included -- began to focus on
how the .NET Framework, CLR, and Visual C++ environments could better accommodate
first class concurrent programming.  Of course, our colleagues in MSR and researchers
in the industry more generally had many years' head start on us, in some cases
dating back 3+decades.  It is safe to say that there was no shortage of prior
art to understand and learn from.

One piece of prior art was particularly influential on our thoughts: software transactional
memory.  (STM, or, in short just TM.)  In fact, right around that time,
Tim Harris's TM work grew in notoriety (my first exposure arriving by way of OOPSLA'03's
proceedings, which contained [the "Language Support for Lightweight Transactions"
paper](http://research.microsoft.com/en-us/um/people/tharris/papers/2003-oopsla.pdf)).
TM was immediately fascinating, and simultaneously promising.  For a number
of reasons:

- TM hid sophisticated synchronization mechanisms under a simple veil.

- It could be implemented using sophisticated (and scalable) techniques, again under
a simple veil.

- It built on decades of experience in building scalable and parallel transactional
databases.

- Among others.  But most of all, it was a bright shiny light in a sea of complexity.

- And how fortunate: Tim was a colleague in our neighboring MSR Cambridge offices
(and still is).

In a nutshell, TM offered declarative concurrency-safety.  You declare what
you'd like in as few simple words as possible, and you get what you want.
In this case, those simple words are 'atomic { S; }'.

Many people latched onto TM rapidly and simultaneously, both inside and outside of
Microsoft.  I hacked together a little prototype built atop SSCLI ("Rotor"),
and another architect on our team built an even more feature-rich prototype using
MSIL rewriting.  We compared notes, began jointly exploring the design space,
and talking more regularly with other colleagues like Tim in MSR.  Soon thereafter
we kicked off a small working group with about a dozen architects and researchers
from around the company, aiming to articulate what a real productized TM might look
like.  Fun times.

We were eventually given the OK for an official "incubation" project, and multiple
years' of exploration and hard work ensued.  In fact, the fruits of a team
of many's labor recently got released in the form of [a Community Technology Preview](http://msdn.microsoft.com/en-us/devlabs/ee334183.aspx)
-- a good conduit for experimentation, but with no commitment to add it to any of
Microsoft's products.  To be clear, I had only a small part to play in this
ambitious project, and mostly towards the start.  Partway through, I stepped
away to do [PLINQ and Parallel Extensions to .NET](http://msdn.microsoft.com/concurrency/),
both of which are now part of the .NET Framework 4.0.  Dozens of amazing people
played a significant role in the project over the years.  But I am getting way
ahead of myself…

I've been away from the nitty-gritty day-to-day details of TM for about 3 years
now, which feels sufficiently long to develop a healthy perspective on the project.
So here it is.  What follows is of course in no way Microsoft's "official
position" on the technology, but rather my own personal one.  I've interspersed
generalizations with specific details because that's just how my brain thinks about
TM.

**Towards the North Star**

A wondrous property of concurrent programming is the sheer number and diversity of
programming models developed over the years.  Actors, message-passing, data
parallel, auto-vectorization, ...; the titles roll off the tongue, and yet none dominates
and pervades.  In fact, concurrent programming is a multi-dimensional space
with a vast number of worthy points along its many axes.

This rich history is simultaneously a blessing and a daunting curse.  But in
any case can make for some very interesting multi-year-long immersion.  [My
UW talk](http://norfolk.cs.washington.edu/htbin-post/unrestricted/colloq/details.cgi?id=768)
from 1 1/2 years ago just barely touches on the sheer breadth.

TM's greatest virtue is the first word in its name: transactional.  It turns
out that, no matter your concurrent programming model du jour, three fundamental
concepts crop up again and again: isolation (of state), atomicity (of state transitions),
and consistency (of those atomic transitions).  We use locks in shared-memory
programming, coarse grained messages in message-passing, and functional programming
to achieve all of these things in different ways.  Transactions are another
such mechanism, sure, but more than that, transactions are an all-encompassing way
of thinking about how programs behave at their most fundamental core.  Transaction
is a religion.

Not everybody believes this, and of course why would they: it is an immensely subjective
and qualitative statement.  Some will claim that models like message passing
entirely avoid the likes of "race conditions," and such, but this is clearly
false: state transitions are made, complicated state invariants are erected amongst
a sea of smaller isolated states, and care must be taken, just as in shared memory.
Even Argus, a beautiful early incarnation of message-passing (via promises) demands
that messages are atomic in nature.  This property is not checked and, if done
improperly, leads to "races in the large."  Even Argus introduced the notion
of transactions and persistence in the form of guardians.

Of course, message passing helps push you in the right direction.  It is not,
however, a panacea.

I was reading my ICFP proceedings recently and was reminded of research done in the
context of Erlang that [supports this assertion](http://portal.acm.org/citation.cfm?id=1596550.1596574).
In it, they apply [CHESS](http://research.microsoft.com/en-us/projects/chess/)-like
techniques (with clever search space culling) to find race conditions.  Indeed
we use similar techniques very successfully for our message-passing programming models
on my team here at Microsoft.

Transactions are terrific because they are "automatic".  You declare the
boundaries, and the transactional machinery takes care of the rest.  This is
true of databases and also TM.  Countless developers in the wild write massively
concurrent programs by issuing operations against databases: they can do this so
easily because they grok the simple façade that transactions provide.  Numerous
server-side state-based applications use transactions to shield programmers from
the pitfalls of concurrency.  Behold MSDTC.  The bet we were making is
that similar models would scale down just as well "in the small".

The canonical syntactic footprint of TM is also beautiful and simple.  You say:

```
atomic {
    ... concurrency-safe code goes here ...
}
```

And everything in that block is magically concurrency-safe.  (Well, you still
need to ensure the consistency part, but isolation and atomicity are built-in.
Mix this with Eiffel- or [Spec#](http://research.microsoft.com/en-us/projects/specsharp/)-style
contracts and assertions like those in .NET 4.0, run at the end of each transaction,
and you're well on your way to verified consistency also.  The 'check E'
work [in Haskell](http://research.microsoft.com/en-us/um/people/simonpj/Papers/stm/stm-invariants.pdf)
was right along these lines.)  You can read and write memory locations, call
other methods, all without worrying about whether concurrency-safety will be at risk.

For example, consider three transactions running concurrently:

```
int x = 0, y = 0, z = 0;

atomic {    atomic {    atomic {
    x++;        y++;        z++;
}               x++;        y++;
            }               z++;
                        }
```

No matter the order in which these run, the end result will be x == 3, y == 2, z
== 1.

Contrast this elegant simplicity with the many pitfalls of locks:

- _Data races_.  Like forgetting to hold a lock when accessing a certain piece
of data.  And other flavors of data races, such as holding the wrong lock when
accessing a certain piece of data.  Not only do these issues not exist, but
the solution is not to add countless annotations associating locks with the data
they protect; instead, you declare the scope of atomicity, and the rest is automatic.

- _Reentrancy_.  Locks don't compose.  Reentrancy and true recursive
acquires are blurred together.  If a locked region expects reentrancy, usually
due to planned recursion, life is good; if it doesn't, life is bad.  This
often manifests as virtual calls that reenter the calling subsystem while invariants
remain broken due to a partial state transition.  At that point, you're hosed.

- _Performance_.  The tension between fine-grained locking (better scalability)
versus coarse-grained locking (simplicity and superior performance due to fewer lock
acquire/release calls) is ever-present.  This tension tugs on the cords of correctness,
because if a lock is not held for long enough, other threads may be able to access
data while invariants are still broken.  Scalability pulls you to engage in
a delicate tip-toe right up to the edge of the cliff.

- _Deadlocks_.  This one needs no explanation.

In a nutshell, locks are not declarative.  Not even close.  They are not
associated with the data protected by those locks, but rather the code that accesses
said data.  (For example: in the above code snippet, do we need three locks?
Or one?  Or …?  Imagine we choose three: one for each variable, x, y,
and z.  What if we increment z, release its associated lock, and some other
thread can now see the newly incremented z before the y and x get incremented.
Whether this is acceptable depends on the program.)  Sure, you can achieve atomicity
and isolation, but only by intimately reasoning about your code by understanding
the way they are implemented.  And if you care about performance, you are also
going to need to think about hardware esoterica such as CMPXCHG, spin waiting, cache
contention, optimistic techniques with version counters and memory models, ABA, and
so on.

The contrast is stark.  Atomic-block-style transactions provide automatic serializability
of whole regions of code, no matter what that code does, and the TM infrastructure
does the rest, choosing between: optimistic, pessimistic, coarse, fine, etc.
The linearization point of a transaction is clear: the end of the atomic block.
TM can even adjust strategies based on the surrounding environment: hardware, dynamic
program behavior, etc.  ("Policy".)  In comparison to locks, TM is
an order of magnitude simpler.  There have even been studies whose conclusions
[support this assertion](http://www.cs.uoregon.edu/events/icse2009/images/postConf/pankratius-TMStudy-Pankratius-ICSE2009.pdf).

(Transactions unfortunately do not address one other issue, which turns out to be
the most fundamental of all: sharing.  Indeed, TM is insufficient -- indeed,
even dangerous -- on its own because it makes it very easy to share data and
access it from multiple threads; first class isolation is far more important to achieve
than faux isolation.  This is perhaps one major difference between client and
server transactions.  Most server sessions are naturally isolated, and so transactions
only interfere around the edges.  I'm showing my cards too early, and will
return to this point much, much later in this essay.)

TM also has the attractive quality of automatic rollback of partial state updates.
(How did I get this far without discussing rollback?)  Concurrency aside, this
avoids needing to write backout code to run in the face of unhandled exceptions.
In retrospect this capability alone is almost enough to justify TM in limited quantities.
Reams of code "out there" contain brittle, untested, and, therefore, incorrect
error handling code.  We have seen such code lead to problems ranging in severity:
reliability issues leading to data loss, security exploits, etc.  Were we to
replace all those try/catch/rethrow blocks of code with transactions, we could do
away with this error prone spaghetti.  We'd also eliminate try/filter exploits
thanks to Windows/Win32 2-pass SEH.  Sometimes I wish we focused on this simple
step forward, forgot about concurrency-safety, and baby stepped our way forward.
Likely it wouldn't have been enough, but I still wonder to this day.

We also toyed with the ability to replace reliability-oriented CER blocks with transactions.
As you go through a transaction, there is a log of forward progress and how to undo
it.  So no matter the kind of failure, including OOM, you can rollback the partial
state updates with zero allocation required.

At some point we began describing an 'atomic' block as though the program used
a single global lock for all its concurrency operations.  This would be grossly
inefficient, of course, and fails to capture the precise isolation and rollback properties,
but nevertheless conveys the basic idea.  It also, as an aside, foreshadows
a few of the difficult problems that lie ahead, namely strong vs. weak atomicity.
Even though there is only one, if you forget to hold this one global lock while accessing
shared data, you've still got a data race on your hands.  This model won't
save you.  We will return to this later on.

**Tough Decisions: Life as a Starving Artist**

We faced some programming model decisions requiring artistic license early on.

One that we quickly decided was whether to automatically roll back a transaction
in response to an unhandled exception thrown from within.  Such as with this
code:

```
atomic {
    x++;

    if (p) {
        throw new Exception("Whoops");
    }
}
```

If p evaluates to true, and hence an unhandled exception thrown, should that x++
be rolled back?

Most on the team said "Yes" as a gut reaction, whereas some argued we should
require the programmer to catch-and-rollback by hand.  We settled on the automatic
approach because it seemed to do what you would expect in all the cases we looked
at.  Your transaction failed to complete normally and consistently.  We
also debated whether to support a unilateral "Transaction.Abort()" capability;
while we agreed a "Transaction.Commit()" would be silly -- the only way to commit
a transaction being to reach its end non-exceptionally -- the jury remained split
on unilateral abort.  We eventually found that, particularly when nesting is
involved, the ability to detect a dire problem with the universe and bail unilaterally
can be useful.

And we also hit some tough snags early on.  Some were trivial, like what happens
when an exception is thrown out of an atomic block.  Of course that exception
was likely constructed within the atomic block ('throw new SomeException()' being
the most common form of 'throw'), so we decided we probably need to smuggle at
least some of that exception's state out of the transaction.  Like its stack
trace.  And perhaps its message string.  I wrote the initial incarnation
of the CLR exception subsystem support, and stopped at shallow serialization across
the boundary.  But this was a slippery slope, and eventually the general problem
was seen, leading to more generalized nesting models (which I shall describe briefly
below).  Another snag, which was quite non-trivial, was the impact to the debugging
experience.  Depending on various implementation choices -- like in-place versus
buffered writes -- you may need to teach the debugger about TM intrinsically.
And some of the challenges were fundamental to building a first class TM implementation.
Clearly the GC needed to know about TM and its logging, because it needs to keep
both the "before" and "after" state of the transaction alive, in case it
needed to roll back.  The JIT compiler was very quickly splayed open and on
the surgery table.  And so on.

Throughout, it became abundantly clear that TM, much like generics, was a systemic
and platform-wide technology shift.  It didn't require type theory, but the
road ahead sure wasn't going to be easy.

So we knocked down many early snags, and kept plowing forward, eagerly and excitedly.
None of these challenges were insurmountable.  We remained hopeful and happy
(perhaps even blissful) to continue exploring the space of possible solutions.
More irksome snags lurked right around the corner, however.  And little did
we know that some decisions we were about to make would subject us to some of the
biggest such snags.  TM's greatest feature -- slap an atomic around a block
of code and it just gets better -- would turn out to be its greatest challenge…
but alas, I am again jumping ahead; more on that later.

**Turtles, but How Far Down?  Or, Bounded vs. Unbounded Transactions**

Not all transactions are equal.  There is a broad spectrum of TMs, ranging from
those that are bounded to updating, say, 4 memory locations or cache lines, to those
that are entirely unbounded.  Indeed TM blurs together with other hardware-accelerated
synchronization techniques, like speculative lock elision (SLE).  The more constrained
TM models are often hardware-hybrids, and the limitations imposed are typically due
to physical hardware constraints.  Models can be pulled along other axes, however,
such as whether memory locations must be tagged in order to be used in a transaction
or not, etc.  Haskell requires this tagging (via TVars) so that side-effects
are evident in the type system as with any other kind of monad.

We quickly settled on unbounded transactions.  Everything else looked like multi-word
CAS and, although we knew multi-word CAS would be immensely useful for developing
new lock-free algorithms, our aim was to build something radically new and with broader
appeal.  If we ended up with a hardware-hybrid, we would expect the software
to pick up the slack; you'd get nice acceleration within the hardware constraints,
and then "fall off the silent cliff" to software emulation thereafter.
Thus the unbounded approach was chosen.

In hindsight, this was a critical decision that had far-reaching implications.
And to be honest, I now frequently doubt that it was the right call.  We had
our hearts in the right places, and the entire industry was trekking down the same
path at the same time (with the notable exception of Haskell).  But with the
wisdom of age and hindsight, I do believe limited forms of TM could be wildly successful
at particular tasks and yet would have avoided many of the biggest challenges with
unbounded TM.

And believe me: many such challenges arose in the ensuing months.

An example of one challenge that didn't threaten the model of TM per se, but sure
did make our lives more difficult, is the compilation strategy we were forced to
adopt.  Transactions cost something.  To transact a read or write entails
a non-trivial amount of extra work; we spent a lot of time optimizing away redundant
work, and developing new optimizations that reduced the overhead of TM.  But
at the end of the day, the cost is not zero -- and in fact, the common case is far
from it.  Imagine you have an unbounded transaction model and are faced with
compiling a particular method from MSIL to native code.  A simple separate-module
-based compiler (i.e. not whole-program) will not necessarily know whether this method
will get called from a transaction, or from non-transactional code, such that in
the worst case the method must be prepared for transactional access.  There
are a variety of techniques to use to produce code that supports both: the two extremes
are (1) cloning, or (2) sharing w/ conditional dynamic checking.  Neither extreme
is particularly attractive, and this choice represents a classic space-time tradeoff
that entails finding a reasonable middle ground.  A JIT compiler can dynamically
produce the version that is needed at the moment, but offline compilers -- like
the CLR's NGEN -- do not have this luxury.  And within Microsoft at least,
and among shrink-wrap ISVs, offline compilation is of greater importance than JIT
compilation.  For better or for worse.

The model of unbounded transactions is the hard part.  You surround any arbitrary
code with 'atomic { … }' and everything just works.  It sounds beautiful.
But just think about what can happen within a transaction: memory operations, calls
to other methods, P/Invokes to Win32, COM Interop, allocation of finalizable objects,
I/O calls (disk, network, databases, console, …), GUI operations, lock acquisitions,
CAS operations, …, the list goes on and on.  Versus bounded transactions,
where we could say something like: if you do more than N things, the transaction
will fail to run -- deterministically.

Unbounded really was the golden nugget.   But we should not be shy about
what this decision implies.

**Implementing the Idea**

This leads me to a brief tangent on implementation.  Given that we didn't
implement TM with a single global lock, as the naïve mental model above suggests,
you may wonder how we actually did do it.  Three main approaches were seriously
considered:

- IL rewriting.  Use a tool that passes over the IL post-compilation to inject
transaction calls.

- Hook the (JIT) compiler.  The runtime itself would intrinsically know how
to inject such calls.

- Library-based.  All transactional operations would be explicit calls into
the TM infrastructure.

Approaches #1 and #2 would look similar, but the latter would be quite different.
Instead of:

```
atomic {
    x++;
}
```

Or:

```
Atomic.Run(() => {
    x++;
});
```

You might say something like:

```
Atomic.Run(() => {
    Atomic.Write(Atomic.Read(ref x) + 1);
});
```

With enough language work, we could have tried to desugar the latter into the former,
but when you start crossing method boundaries, everything gets more complicated.
(Do you create transactional clones of every method, and rewrite calls from ordinary
methods to the transactional clone?  This is easy to do with a rewriter or compiler,
but quite difficult with a pure library approach.)   We also knew we'd
need to do some very sophisticated compiler optimizations to get TM's performance
to the point of acceptable.  So we chose approach #2 for our "real" prototype,
and never looked back.

After this architectural approach was decided, a vast array of interesting implementation
choices remained.

We moved on to building the primitive library with all the TM APIs that the JIT would
introduce calls into.  We quickly settled an approach much like Harris's (and,
at the time, pretty much the industry/research standard): optimistic reads, in-place
pessimistic writes, and automatic retry.  That means reads do not acquire locks
of any sort, and instead, once the end of the transaction has been reached, all reads
are validated; if any locations read have been modified concurrently (or an uncommitted
value was read), the whole transaction is thrown away and reattempted from the start.
Writes work like locks.  This approach makes reads cheap: a single read consists
of reading the value, and a version number whose address is at a statically known
offset.  No interlockeds.  This is great since reads typically far outnumber
writes.  Down the line, we explored adding more sophisticated policy than this,
which I will detail in brief below.

So the compiler would inject hooks for the above code like so:

```
while (true) {
    TX tx = new TX();
    try {
        // x++;
        tx.OpenReadOptimistic(ref x);
        int tmp = x;
        tx.OpenWritePessimistic(ref x);
        x = (tmp + 1);

        if (!tx.Validate()) {
            continue;
        }

        tx.Commit();
    }
    catch {
        tx.Rollback();
        throw;
    }
}
```

Notice there are some obvious overheads in here:

- The atomic block becomes a loop (to support automated retry).

- A new transaction must be allocated and likely placed in TLS (if methods are called).

- A try/catch block is used to initiate rollback on unhandled exceptions.

- Each unique location read in a block requires at least one call to OpenReadOptimistic.

- Each unique location written requires at least one call to OpenWritePessimistic.

- Each location read must be validated (at Validate), and finally the transaction
is committed (at Commit).

Much of the work in the compiler was meant to reduce these overheads.  For example,
if the same location is read multiple times, there's no need to call OpenReadOptimistic
more than once.  If the compiler can statically detect this, it may elide some
of the calls.  If the same location is read and then written -- as in the above
example -- only the write lock must be acquired.  If no methods are called,
the transaction object can be enregistered, and we needn't add it to TLS so long
as the exception trap code knows how to move it from register to TLS on demand.
Et cetera.

There are other overheads that are not so obvious.  Optimistic reads mandate
that there is a version number for each location somewhere, and pessimistic writes
mandate that there is a lock for each location somewhere.

A straightforward technique is to use a hashing scheme to associate locations with
this auxiliary data: each address is hashed to index into a table of version numbers
and locks.  This leads to false sharing, of course, but reduces space overhead
and makes lookup fast.  Unfortunately, in a garbage collected environment, addresses
are not stable and therefore hashing becomes complicated.  You can use object
hash codes for this purpose, but .NET hash codes are overridable; and generating
them is not nearly as cheap as using the memory location's address, which by definition
is already in-hand.  Other alternatives of course exist.  You can associate
version numbers and locks with the objects themselves, just like monitors and object
headers/sync-blocks in the CLR: this provides object-granularity locking.  Ahh,
the age old tension of fine vs. coarse grained locking comes up again.

We eventually realized we'd want both optimistic and pessimistic reads, the latter
of which worked a lot like reader/writer locks.  We crammed all these into a
clever little word-sized data structure which worked a lot like Vista's SRWL data
structure.  Except that it also contained a version number.

It was always surprising to me what strange things in the runtime we bumped up against.
We realized a nice GC optimization: instead of keeping strong references to all intermediary
states in a transaction log, we could keep weak references to all but the "before"
and "after" state.  This is important when transacting synthetic situations
like this:

```
static BigHonkinFoo s_f;

...

atomic {
    for (int i = 0; i < 1000000; i++) {
        s_f = new BigHonkinFoo();
    }
}
```

Of course you wouldn't write that code exactly.  But there's no need to
keep alive all but the s\_f that existed prior to entering the atomic block and the
current one at any given time.  But this leads to particularly hairy finalization
issues.  If a finalizable object is allocated within a transaction (say BigHonkinFoo),
and is then reclaimed, its Finalize() method will be scheduled to run on a separate
thread.  Yet the transaction log may contain references to it.  Thus there
is a race between the transaction's final outcome and the invocation of the finalizer.
We came up with a clever solution for this, but there were countless other clever
solutions for various things not worth diving too deep into.

Hacking is fun.  However, it was not going to be what made or broke TM as a
model.

**Disillusionment Part I: the I/O Problem**

It wasn't long before we realized another sizeable, and more fundamental, challenge
with unbounded transactions.  Finalizers touched on this.  What do we do
with atomic blocks that do not simply consist of pure memory reads and writes?
(In other words, the majority of blocks of code written today.)  This was not
just a pesky question of how to compile a piece of code, but rather struck right
at the heart of the TM model.

You already saw the OpenReadOptimistic, OpenWritePessimistic, Validate, Commit, and
Rollback pseudo-TM infrastructure calls, each of which operated on memory locations.
But what about a read or write from a single block or entire file on the filesystem?
Or output to the console?  Or an entry in the Event Log?  What about a
web service call across the LAN?  Allocation of some native memory?  And
so on.  Ordinarily these kinds of operations will be composed with other memory
operations, with some interesting invariant relationship holding between the disparate
states.  A transaction comprised of a mixture still ought to remain atomic and
isolated.

The answer seemed clear.  At least in theory.  The transaction literature,
including [Reuter and Gray's classic](http://www.amazon.com/exec/obidos/ASIN/1558601902/bluebytesoftw-20),
had a simple answer for such things: on-commit and on-rollback actions, to perform
or compensate the logical action being performed, respectively.  (Around this
same time, the Haskell folks were creating just this capability in their STM, where
'onCommit' and 'onRollback' would take arbitrary lambdas to execute the said
operation at the proper time.)  Because we were working primarily in .NET --
with a side project targeting C++ -- we decided to use the new System.Transactions
technology in 2.0 to hook into inherently transactional resources, like transacted
NTFS, registry, and, of course, databases.

(Digging through my blog, I found [this article](http://www.bluebytesoftware.com/blog/2006/06/20/AVolatileTransactionResourceManagerForMemoryAllocationdeallocation.aspx)
written back in June 2006 about building a volatile resource manager for memory allocation/free
operations, just as an example.)

This worked, though we were quite obviously swimming upstream.  Numerous challenges
confronted us.

A significant problem was that not all operations are inherently transactional, so
in many cases we were faced with the need to add faux transactions on top of existing
non-transactional services.  (Already-transactional services were easy, like
databases.  Except that mixing fine-grain TM transactions with distributed DTC
transactions makes my skin crawl.)  For example, how would you undo a write
to the console?  Well, you can't, really.  So we decided maybe the right
default for Console.WriteLine was to use an on-commit action to perform the actual
write only once the transaction had committed.

But in even thinking this thought, we realized we were standing on shaky ground.
What if the WriteLine was followed by something like a ReadLine, for example, where
the program was meant to wait for the user to enter something into the console (likely
in response to the prompt output by WriteLine)?  (This example is a toy, of
course, but represents a more fundamental pattern common in networked programs.)
The basic problem was immediately clear.  Adding isolation to an existing non-isolated
operation is not always behavior-preserving, particularly when I/O is involved.
Sometimes it is necessary to step outside of the isolation that would otherwise get
poured on top by a simple transactional model.

This particular problem isn't specific to traditional I/O per se.

Foreign function interface calls through.NET's P/Invoke suffer from like problems.
A call to CreateEvent may be compensatable (via an on-rollback action) with a call
to CloseHandle.  But this is flawed.  Once that event's HANDLE is requested,
and/or it is passed to other Win32 APIs like MsgWaitForMultipleObjects, then the
isolation of the faux transaction is broken, and real state must be provided to the
Win32 APIs.  And if another thread were to look up that HANDLE -- perhaps through
a name given to it in the call to CreateEvent -- it may be able to see and interact
with that event before the enclosing transaction has been committed.  The abstraction
leaks.  And even if the abstraction is perfect, it is obvious there's quite
a bit of work to be had in order to transact all the touch points between .NET and
Win32, of which there are many.  And I mean many.

Other issues wait just around the corner.  For example, how would you treat
a lock block that was called from within a transaction?  (You might say "that's
just not supported", but when adding TM to an existing, large ecosystem of software,
you've got to draw the compatibility line somewhere.  If you draw it too carelessly,
large swaths of existing software will not work; and in this case, that often meant
that we claimed to provide unbounded transactions, and yet we would be placing bounds
on them such that a lot of existing software could not be composed with transactions.
Not good.)  A seemingly straightforward answer is to treat a lock block like
an atomic block.  So if you encounter:

```
atomic {
    lock (obj) { ... }
}
```

it is logically transformed into:

```
atomic {
    atomic { ... }
}
```

On the face of it, this looks okay.  (Forget problems like freeform use of Monitor.Enter/Exit
for now.)  We're strengthening the atomicity and isolation, so what could
go wrong?  Well, it turns out that examples like this can also suffer from the
"too much isolation" problem.  Adding transactions to a lock-block extends
the lifetime of the isolation of that particular block's effects, possibly leading
to lack of forward progress.  In fact, you don't need locks to illustrate
the problem.  Imagine a simple lock-free algorithm that communicates between
threads using shared variables:

```
volatile int flag = 0;

...

flag = 1;               while (flag != 1) ;
while (flag == 1) ;     flag = 2;
```

If you invoke this code from within a transaction (on each thread), you're apt
to lead to deadlock.  Both transactions' effects will be isolated from the
others', whereas we are quite obviously intending to publish the updates to the
flag variable immediately.

Anyway, the whole lock thing is a bit of a digression.  The simple fact is that
very little .NET code would actually run inside an atomic block but for things like
collections and pure computations due to the I/O problem.  You can develop one-off
solutions for each problem that arises -- and indeed we did so for many of them
-- and even hang those solutions underneath one general framework -- like System.Transactions
-- but you cannot help but eventually become overwhelmed by the totality of the
situation.  The team experimented with static checking to turn these dynamic
failures into static ones, but this only marginally improved matters.

I could go on and on about the I/O problem, its various incarnations, and what we
did about it.  Instead I will sum it up: this problem was, and still is, the
"elephant in the room" threatening unbounded TM's broader adoption.

The question ultimately boils down to this: is the world going to be transactional,
or is it not?

Whether unbounded transactions foist unto the world will succeed, I think, depends
intrinsically on the answer to this question.  It sure looked like the answer
was going to be "Yes" back when transactional NTFS and registry was added to
Vista.  But the momentum appears to have slowed dramatically.

**Nesting**

Let's get back to some fun, less depressing material.  There are more surprises
lurking ahead.

I already mentioned a great virtue of transactions is their ability to nest.
But I neglected to say how this works.  And in fact when we began, we only recognized
one form of nesting.  You're in one atomic block and then enter into another
one.  What happens if that inner transaction commits or rolls back, before the
fate of the outer transaction is known?  Intuition guided us to the following
answer:

- If the inner transaction rolls back, the outer transaction does not necessarily
do so.  However, no matter what the outer transaction does, the effects of the
inner will not be seen.

- If the inner transaction commits, the effects remain isolated in the outer transaction.
It "commits into" the outer transaction, we took to saying.  Only if the
outer transaction subsequently commits will the inner's effects be visible; if
it rolls back, they are not.

For example, consider this code:

```
void f() {                  void g() {
    atomic { // Tx0             atomic { // Tx1
        x++;                        y++;
        try {                       if (p1)
            g();                        throw new BarException();
        } catch {               }
            if (p0)         }
                throw;
        }

        if (p2)
            throw new FooException();
    }
}
```

Imagine x = y = 0 at the start, and we invoke f.  Many outcomes are possible.

- If p1 is true, g will throw an exception, aborting Tx1's write to y. There are
then two possibilities.  (1)If p0 is true, the exception is repropagated and
Tx0 will also abort, rolling back its write to x; this leaves x == y == 0.
(2) If p0 is false, the exception is swallowed, and Tx0 proceeds to committing its
write to x; this leaves x == 1, whereas y == 1.

- If p1 is false, on the other hand, g will not throw anything.  Tx1 will commit
its write to y "into" the outer transaction Tx0.  One of two outcomes will
now occur depending on the value of p2.  (1) If p2 is true, an exception is
thrown out of f, and Tx0 rolls back both the inner transaction Tx1's effects and
its own, leaving x == y == 0.  (2) Else, f completes ordinarily, and Tx0 commits
both Tx1's and its own effects, leading to x == y == 1.

We expected most peoples' intuition to match this behavior.

The canonical working example was a BankAccount class:

```
class BankAccount
{
    decimal m_balance;

    public void Deposit(decimal delta) {
        atomic { m_balance += delta; }
    }

    public static void Transfer(
            BankAccount a, BankAccount b, decimal delta) {
        atomic {
            a.Deposit(-delta);
            b.Deposit(delta);
        }
    }
}
```

This was an illustrative and beautiful example.  It made beautiful slide-ware.
We are composing the Deposit operations of two separate bank accounts into a single
Transfer method.  Of course doing the a.Deposit(-delta) and b.Deposit(delta)
must be made atomic, else a failure could either lead to missing money, and/or someone
could witness the world with the money in transit (and nowhere except for one a thread's
stack) rather than having been transferred atomically.  And building the same
thing with locks is frustratingly difficult: using fine-grained per-account locks
can lead to deadlock very quickly.

Intuitively we walked down many variants of this mode of nesting.  We reacquainted
ourselves with Moss's [great dissertation on the topic](http://portal.acm.org/citation.cfm?id=3529),
and remembered this intuitive nesting mode as closed nested transactions.  And
we shortly recognized the need for another mode: [open nested transactions](http://www.cs.utah.edu/wmpi/2006/final-version/wmpi-posters-1-Moss.pdf).

To motivate the need for open nesting, imagine we've got a hashtable whose physical
storage is independent from its logical storage.  Resizing the table of buckets,
for example, has little to do with whether a particular {key, value} pair exists
within those buckets.  The resizing operation, in fact, is logically idempotent
and isolated: the same set of keys will exist within the table both before and after
such an operation.  So we can actually commit the physical effects of such an
operation eagerly.  With a naïve TM implementation, two independent keys hashing
to the same bucket will conflict, and the reads and writes for such operations will
live as long as the enclosing user-level transactions.  Instead, we can serialize
logical operations with respect to one another at a "higher level" than physically
independent operations do, leading to greater concurrency.  Two transactions
will only conflict in long-running transactions if they truly operate on the same
keys, rather than just happening to hash to the same bucket.

Open nesting forced us to contemplate the sharing of state between outer and inner
transactions more deliberately, and gave us some troubles syntactically.  We
had wanted to say:

```
atomic { // ordinary closed nesting.
    Foo f = new Foo();
    atomic(open) { /// open nesting.
        ... f? ...
    }
}
```

But is it really legal for the inner transaction here to access the 'f', which
has been constructed and is presumably uncommitted in the outer transaction?
With closed nested transactions there is lock compatibility between the outer and
inner transactions.  An inner closed nested transaction can of course read a
memory location write-locked by the outer transaction, for example.  However,
the same must not true of open nesting, because an open nested transaction commits
"to the world" rather than into its outer transaction.  Allowing it to read
and then potentially publish uncommitted state would violate serializability.
It's possible that the inner open nested transaction will commit, whereas the outer
will roll back.  (The reverse situation is equally problematic.)  And yet
it's darn useful to pass state from an outer to an inner transaction -- and indeed,
often impossible to do anything otherwise -- yet what if the key itself were a complicated
object graph rather than value, and the key bleeds across transaction boundaries?

Many issues like this arose.  Our straightforward answer was that only pass-by-value
worked across such a boundary.  I don't think we ever found nirvana here.

We developed other transaction modes also.

As we added data parallel operations within a nested transaction, we realized that
we'd need something a lot like closed nesting but with special accommodation for
intra-transaction parallelism.  This led us to [parallel nested transactions](http://www.cs.rochester.edu/meetings/TRANSACT07/papers/agrawal.pdf),
enabling lock sharing from a parent to its many data parallel children.  These
children could not communicate with one another other than to "commit into" the
parent, and subsequently reforking, thereby ensuring non-interference between them.
Of course children could share read-locks amongst one another, just not write locks.

And we continued to reject the temptation of adding weakened serializability modes
a la relational databases (unrepeatable reads, etc).  Although we expected this
to arise out of necessity with time, it never did; the various nesting modes we provided
seemed to satisfy the typical needs.

**A Better Condition Variable**

Here's a brief aside on one of TM's bonus features.

Some TM variants also provide for "condition variable"-like facilities for coordination
among threads.  I think Haskell was the first such TM to provide a 'retry'
and 'orElse' capability.  When a 'retry' is encountered, the current
transaction is rolled back, and restarted once the condition being sought becomes
true.  How does the TM subsystem know when that might be?  This is an implementation
detail, but one obvious choice is to monitor the reads that occurred leading up to
the 'retry' -- those involved in the evaluation of the predicate -- and once
any of them changes, to reschedule that transaction to run.  Of course, it will
reevaluate the predicate and, if it has become false, the transaction will 'retry'
again.

A simple blocking queue could be written this way.  For example:

```
object TakeOne()
{
    atomic {
        if (Count == 0) {
            retry;
        }

        return Pop();
    }
}
```

If, upon entering the atomic block, Count is witnessed as being zero, we issue a
retry.  The transaction subsystem notices we read Count with a particular version
number, and then blocks the current transaction until Count's associated version
number changes.  The transaction is then rescheduled, and races to read Count
once again.  After Count is seen as non-zero, the Pop is attempted.  The
Pop, of course, may fail because of a race -- i.e. we read Count optimistically
without blocking out writers -- but the usual transaction automatic-reattempt logic
will kick in to mask the race in that case.

The 'orElse' feature is a bit less obvious, though still rather useful.
It enables choice among multiple transactions, each of which may end up issuing a
'retry'.  I don't think I've seen it in any TMs except for ours and
Haskell's.

To illustrate, imagine we've got 3 blocking queues like the one above.  Now
imagine we'd like to take from the first of those three that becomes non-empty.
'orElse' makes this simple:

```
BlockingQueue bq1 = ..., bq2 = ..., bq3 = ...;

atomic {
    object obj =
        orElse {
            bq1.TakeOne(),
            bq2.TakeOne(),
            bq3.TakeOne()
    };
}
```

While 'orElse' is perhaps an optional feature, you simply can't write certain
kinds of multithreaded algorithms without 'retry'.  Anything that requires
cross-thread communication would need to use spin variables.

**Deliberate Plans of Action: Policy**

I waved my hands a bit above perhaps without you even knowing it.  When I talk
about optimistic, pessimistic, and automatic retry, I am baking in a whole lot of
policy.  It turns out there is a wide array of techniques.  The simplest
question we faced early on was, when an optimistic read fails to validate at the
end of a transaction, when should we reattempt execution of that transaction?

The naïve answer is "immediately".  But obviously that would lead to livelock
under some conditions.  A more reasonable answer is "spin for N cycles and
then retry".  But this too can lead to livelock.  A better answer is
to either choose some random strategy, or to make an intelligent adaptive choice.
We experimented with many such variants, including random backoff, sophisticated
waiting and signaling based on the memory locations in question, among others.
We even played games like giving transactions karma points for cooperatively acquiescing
to other competing transactions, and allowing those transactions with the most karma
points to make more forward progress before interrupting them.

[A few good papers](http://lpd.epfl.ch/kapalka/files/robust-cm-scool05.pdf) supplied
useful (and entertaining) reading material on the topic, but to be honest, nobody
had a good answer at the time.  Thankfully these are all implementation details.
So we were free to experiment.

Deadlock breaking also requires policy.  Thankfully we can actually roll back
the effects of transactions engaged in a deadly embrace with TM, so we merely need
to know how often to run the deadlock detection algorithm.  There was a similar
problem when deciding to back off outer layers of nesting, and in fact this becomes
more complicated when deadlocks are involved.  Imagine:

```
atomic {        atomic {
    x++;            y++;
    atomic {        atomic {
        y++;            x++;
    }               }
}               }
```

This deadlock-prone example is tricky because rolling back the inner-most transactions
won't be sufficient to break the deadlock that may occur.  Instead the TM
policy manager needs to detect that multiple levels of nesting are involved and must
be blown away in order to unstick forward progress.

Another variant that went beyond deciding when to favor one transaction over another
was to upgrade to pessimistic locking if optimistic let us down.  The whole
justification behind optimistic is that, …well, we're optimistic that conflicts
won't happen.  So it seems reasonable that, if they do occur, we fall back
to something more, …well, pessimistic.  There is a dial here too.  Perhaps
you only want to fall back to pessimistic after failing optimistically N times in
a row, where N > 1.  As I mentioned above, our single-word lock associated with
each object supported both locking and versioning cheaply.

**Disillusionment Part II: Weak or Strong Atomicity?**

All along, we had this problem nipping at our heels.  What happens if code accesses
the same memory locations from inside and outside a transaction?  We certainly
expected this to happen over the life of a program: state surely transitions from
public and shared among threads to private to a single thread regularly.  But
if some location were to be accessed transactionally and non-transactionally concurrently,
at once, we'd (presumably) have a real mess on our hands.  A supposedly atomic,
isolated, etc. transaction would no longer be protected from the evils of racey code.

For example:

```
atomic { // Tx0     x++; // No-Tx
    x++;
}
```

Can we make any statements about the value of x after Tx0 commits (or rolls back)?
Not really.  It depends on the way the particular TM being used has been implemented.
An in-place model that rolls back could not only roll back Tx0's but also the unprotected
x++'s write.  And so on.

On one hand, this code is racey.  So you could explain away the undefined behavior
as being a race condition.  On the other hand, it was also troublesome.
All those problems with locks begin cropping up all over the place.  It would
have been ideal if we could notify developers that they made a mistake.  Then
we could have made the assertion that data races are simply not possible with TM.

(Except for consistency-related ones, of course.)

At the same time, many hardware models were being explored.  And of course in
hardware you've got the physical addresses that variables resolve to and needn't
worry about aliasing.  So it was actually possible to issue a fault if a location
was used transactionally and non-transactionally at once.  But given that our
solution was software-based, we were uncomfortable betting the farm on hardware support.

Another approach was static analysis.  We could require transactional locations
to be tagged, for example.  This had the unfortunate consequence of making reusable
data structures less, well, reusable.  Collections for example presumably need
to be usable from within and outside transactions alike.  After-the-fact analysis
could be applied without tagging, but false positives were common.  We never
really took a hard stance on this problem, but always assumed the combination of
static analysis, tooling, and, perhaps someday, hardware detection would make this
problem more diagnosable.  But I think we generally resolved ourselves to the
fact that our TM would suffer from weak atomicity problems.

We thought this was explainable.  Sadly it led to something that surely was
not.

**Disillusionment Part III: the Privatization Problem**

I still remember the day like it was yesterday.  A regular weekly team meeting,
to discuss our project's status, future, hard problems, and the like.  A summer
intern on board from a university doing pioneering work in TM, sipping his coffee.
Me, sipping my tea.  Then that same intern's casual statement pointing out
an Earth-shattering flaw that would threaten the kind of TM we (and most of the industry
at the time) were building.  We had been staring at the problem for over a year
without having seen it.  It is these kinds of moments that frighten me and make
me a believer in formal computer science.

Here it is in a nutshell:

```
bool itIsOwned = false;
MyObj x = new MyObj();

...

atomic { // Tx0                         atomic { // Tx1
    // Claim the state for my use:          if (!itIsOwned)
    itIsOwned = true;                           x.field += 42;
}                                       }

int z = x.field;
...
```

The Tx0 transaction changes itIsOwned to true, and then commits.  After it has
committed, it proceeds to using whatever state was claimed (in this case an object
referred to by variable x) outside of the purview of TM.  Meanwhile, another
transaction Tx1 has optimistically read itIsOwned as false, and has gone ahead to
use x.  An update in-place system will allow that transaction to freely change
the state of x.  Of course, it will roll back here, because isItOwned changed
to true.  But by then it is too late: the other thread using x outside
of a transaction will see constantly changing state -- torn reads even -- and
who knows what will happen from there.   A known flaw in any weakly atomic,
update in-place TM.

If this example appears contrived, it's not.  It shows up in many circumstances.
The first one in which we noticed it was when one transaction removes a node from
a linked list, while another transaction is traversing that same list.  If the
former thread believes it "owns" the removed element simply because it took it
out of the list, someone's going to be disappointed when its state continues to
change.

This, we realized, is just part and parcel of an optimistic TM system that does in-place
writes.  I don't know that we ever fully recovered from this blow.  It
was a tough pill to swallow.  After that meeting, everything changed: a somber
mood was present and I think we all needed a drink.  Nevertheless we plowed
forward.

We explored a number of alternatives.  And so did the industry at large, because
that intern in question published [a paper on the problem](http://portal.acm.org/citation.cfm?id=1281161).
One obvious solution is to have a transaction that commits a change to a particular
location wait until all transactions that have possibly read that location have completed
-- a technique we called quiescence.  We experimented with this approach, but
it was extraordinarily complicated, for obvious reasons.

We experimented with blends of pessimistic operations instead of optimistic, alternative
commit protocols, like using a "commit ticket" approach that serializes transaction
commits, each of which tended to sacrifice performance greatly.  Eventually
the team decided to do buffered writes instead of in-place writes, because any concurrent
modifications in a transaction will simply not modify the actual memory being used
outside of the transaction unless that transaction successfully commits.

This, however, led to still other problems, like the granular loss of atomicity problem.
Depending on the granularity of your buffered writes -- we chose object-level --
you can end up with false sharing of memory locations between transactional and non-transactional
code.  Imagine you update two separate fields of an object from within and outside
a transaction, respectively, concurrently.  Is this legal?  Perhaps not.
The transaction may bundle state updates to the whole object, rather than just one
field.

All these snags led to the realization that we direly needed a memory model for TM.

**Disillusionment Part IV: Where is the Killer App?**

Throughout all of this, we searched and searched for the killer TM app.  It's
unfair to pin this on TM, because the industry as a whole still searches for a killer
concurrency app.  But as we uncovered more successes in the latter, I became
less and less convinced that the killer concurrency apps we will see broadly deployed
in the next 5 years needed TM.  Most enjoyed natural isolation, like embarrassingly
parallel image processing apps.  If you had sharing, you were doing something
wrong.

**In Conclusion**

I eventually shifted focus to enforcing coarse-grained isolation through message-passing,
and fine-grained isolation through type system support a la Haskell's state monad.
This would help programmers to realize where they accidentally had sharing, I thought,
rather than merely masking this sharing and making it all work (albeit inefficiently).

I took this path not because I thought TM had no place in the concurrency ecosystem.
But rather because I believed it did have a place, but that several steps would be
needed before getting there.

I suspected that, just like with Argus, you'd want transactions around the boundaries.
And that you'd probably want something like open nesting for fine-grained scalable
data structures, like shared caches.  These are often choke points in a coarse-grained
locking system, and often cannot be fully isolated, at least in the small.
Ironically I am just now arriving there.  In the system I work on I see these
issues actually staring us in the face.

This is just my own personal view on TM.  You may also be interested in reading
the current STM.NET team's views also, available on [their MSDN blog](http://blogs.msdn.com/stmteam/).

For me the TM project was particularly enjoyable.  And it was a great learning
experience.  I worked with some amazing people, and it was a privilege.
You really had the sense that something big was right around the corner, and every
day was a rush of enjoyment.  Despite running as fast as we could, it seemed
like we could just barely keep pace with the research community.  Over time
more and more researchers turned to TM, and I distinctly recall reading at least
one new TM paper per week.

This was also the first time I realized that Microsoft, at its core, really does
operate like a collection of many startups.  Our TM work was a grassroots movement,
and there was no official sponsorship for our effort at the start.  It was just
a group of people independently getting together to discuss how TM might fit into
the direction the industry was headed.  Eventually TM started showing up on
slide decks in presentations to management, followed by dedicated TM reviews, and
even a BillG review.  I will never forget, a couple years after that review
-- during an overall concurrency review -- Bill standing up at the whiteboard,
drawing the code "atomic { … }" and asking something to the effect: "Why
can't you just use transactional memory for that?"  I guess the idea stuck
with him too.

Who knows.  Maybe in 10 years, the world will be transactional after all.

