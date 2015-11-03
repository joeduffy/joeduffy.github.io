---
layout: post
title: The 'premature optimization is evil' myth
date: 2010-09-06 11:38:49.000000000 -07:00
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
I can't tell you how many times I've heard the age-old adage echoed inappropriately
and out of context:

> "We should forget about small efficiencies, say about 97% of the time;
> premature optimization is the root of all evil"
> -- Donald E. Knuth, [Structured Programming with go to Statements](http://portal.acm.org/citation.cfm?id=356640)

I have heard the "premature optimization is the root of all evil" statement used
by programmers of varying experience at every stage of the software lifecycle, to
defend all sorts of choices, ranging from poor architectures, to gratuitous memory
allocations, to inappropriate choices of data structures and algorithms, to complete
disregard for variable latency in latency-sensitive situations, among others.

Mostly this quip is used defend sloppy decision-making, or to justify the indefinite
deferral of decision-making. In other words, laziness. It is safe to say that the
very mention of this oft-misquoted phrase causes an immediate visceral reaction to
commence within me... and it's not a pleasant one.

In this short article, we'll look at some important principles that are counter
to what many people erroneously believe this statement to be saying. To save you
time and suspense, I will summarize the main conclusions: I do not advocate contorting
oneself in order to achieve a perceived minor performance gain. Even the best performance
architects, when following their intuition, are wrong 9 times out of 10 about what
matters. (Or maybe 97 times out of 100, based on Knuth's numbers.) What I do advocate
is thoughtful and intentional performance tradeoffs being made as every line of code
is written. Always understand the order of magnitude that matters, why it matters,
and where it matters. And measure regularly! I am a big believer in statistics, so
if a programmer sitting in his or her office writing code thinks just a little bit
more about the performance implications of every line of code that is written, he
or she will save an entire team that time and then some down the road. Given the
choice between two ways of writing a line of code, both with similar readability,
writability, and maintainability properties, and yet interestingly different performance
profiles, don't be a bozo: choose the performant approach. Eschew redundant work,
and poorly written code. And lastly, avoid gratuitously abstract, generalized, and
allocation-heavy code, when slimmer, more precise code will do the trick.

Follow these suggestions and your code will just about always win in both maintainability
and performance.

# Understand the order of magnitude that matters

First and foremost, you really ought to understand what order of magnitude matters
for each line of code you write.

In other words, you need to have a budget; what can you afford, and where can you
afford it? The answer here changes dramatically depending on whether you're writing
a device driver, reusable framework library, UI control, highly-connected network
application, installation script, etc. No single answer fits all.

I am personally used to writing code where 100 CPU cycles matters. So invoking a
function that acquires a lock by way of a shared-memory interlocked instruction that
may take 100 cycles is something I am apt to think hard about; even more worrisome
is if that acquisition could block waiting for 100,000 cycles. Indeed this situation
could become disastrous under load. As you can tell, I write a lot of systems code.
If you're working on a network-intensive application, on the other hand, most of
the code you write is going to be impervious to 100 cycle blips, and more sensitive
to efficient network utilization, scalability, and end-to-end performance. And if
you're writing a little one-time script, or some testing or debugging program,
you may get away with ignoring performance altogether, even multi-million cycle network
round-trips.

To be successful at this, you'll need to know what things cost. If you don't
know what things cost, you're just flailing in the dark, hoping to get lucky. This
includes rule of thumb order of magnitudes for primitive operations -- e.g. reading
/ writing a register (nanoseconds, single-digit cycles), a cache hit (nanoseconds,
tens of cycles), a cache miss to main memory (nanoseconds, hundreds of cycles), a
disk access including page faults (micro- or milliseconds, millions of cycles), and
a network roundtrip (milliseconds or seconds, many millions of cycles) -- in addition
to peering beneath opaque abstractions provided by other programmers, to understand
their best, average, and worst case performance.

Clearly the concerns and situations you must work to avoid change quite substantially
depending on the class of code you are writing, and whether the main function of
your program is delivering a user experience (where usability reigns supreme), delivering
server-side throughput, etc. Thinking this through is crucial, because it helps avoid
true "premature optimization" traps where a programmer ends up writing complicated
and convoluted code to save 10 cycles, when he or she really needs to be thinking
about architecting the interaction with the network more thoughtfully to asynchronously
overlap round-trips. Understanding how performance impacts the main function of your
program drives all else.

Pay attention to interoperability between layers of separately authored software
that is composed together. The most common cause of hangs is that an API didn't
specify the expected performance, and so a UI programmer ended up using it in an
innocuous but inappropriate way, because they couldn't afford the range of order
of magnitude cost that the API's performance was expected to fall within. Hangs
aren't the only manifestation; O(N^2), or worse, performance can also result, if,
for example, a caller didn't realize the function called was going to enumerate
a list in order to generate its results.

It is also important to think about worst case situations. What happens if that lock
is held for longer than expected, because the system is under load and the scheduler
is overloaded? And what if the owning thread was preempted while holding the lock,
and now will not get to run again for quite some time? What happens if the network
is saturated because a big news event is underway, or worse, the phone network is
intermittently cutting out, the network cable has been unplugged, etc.? What about
the case where, because a user has launched far too many applications at once, your
memory-intensive operation that usually enjoys nice warmth and locality suddenly
begins waiting for the disk on the majority of its memory accesses, due to demand
paging? These things happen all the time.

In each of these situations, you can end up paying many more orders of magnitude
in cost than you expected under ordinary circumstances. The lock acquisition that
usually took 100 CPU cycles now takes several million cycles (as long as a network
roundtrip), and the network operation that is usually measured in milliseconds is
now measured in tens of seconds, as the software painfully waits for the operation
to time out. And your "non-blocking" memory-intensive algorithm on the UI thread
just caused a hang, because it's paging like crazy.

You've experienced these problems as a user of modern software, I am sure, and
it isn't fun. An hourglass, spinning donut, unresponsive button clicks, "(Not Responsive)"
title bars, and bleachy white screens. An important measurement of a programmer's
worth is how good the code they write operates under the extreme and rare circumstances.
Because, truth be told, when you have a large user-base, these circumstances aren't
that rare after all. This is more of a "performance in the large" thing, but it turns
out that the end result is delivered as a result of many "performance in the small"
decisions adding up. A developer wrote code meant to be used in a particular way,
but decided what order of magnitude was reasonable based on best case, … and gave
no thought to the worst case.

# Using the right data structure for the job

This is motherhood and apple pie, Computer Science 101, … bad clichés abound.
And yet so many programmers get this wrong, because they simply don't give it enough
thought.

One of my favorite books on the topic ("Programming Pearls") has this to say about
them:

> "Most programmers have seen them, and most good programmers realize they've written at least one.
> They are huge, messy, ugly programs that should have been short, clean, beautiful programs."

I'll add one adjective to the "short, clean, beautiful" list: fast.

Data structures drive storage and access behavior, both strongly affecting the size
and speed of algorithms and components that make use of them. Worst case really does
matter. This too is a case where the right choice will boost not only performance
but also the cleanliness of the program.

I'm actually not going to spend too much time on this; when I said this is CS101,
I meant it. However, it is crucial to be intentional and smart in this choice. Validate
assumptions, and measure.

Ironically, in my experience, many senior programmers can make frighteningly bad
data structure choices, often because they are more apt to choose a sophisticated
and yet woefully inappropriate one. They may choose a linked list, for example, because
they want zero-allocation element linking via an embedded next pointer. And yet they
then end up with many lists traversals throughout the program, where a dense array
representation would have been well worth the extra allocation. The naïve programmer
would have happily new'd up a List&lt;T&gt;, and avoided some common pitfalls; yet, here
the senior guy is working as hard as humanly possible to avoid a single extra allocation.
They over-optimized in one dimension, and ignored many others that mattered more.

This same class of programmer may choose a very complicated lock-free data structure
for sharing elements between threads, incurring many more object allocations (and
thus increased GC pressure), and a large number of expensive interlocked operations
scattered throughout the code. The sexy lure of lock-freedom tricked them into making
a bad choice. Perhaps they didn't quite understand that locks and lock-free data
structures share many costs in common. Or perhaps they just hoped to get lucky and
squeeze out out-of-this-world scalability thanks to lock-freedom, without actually
considering the access patterns necessary to lead to such scalability and whether
their program employed them.

These are often held up as examples of "premature optimization", but I hold them
up as examples of "careless optimization". The double kicker here is that the time
spent building the more complicated solution would have been better spent carefully
thinking and measuring, and ultimately deciding not to be overly clever in the first
place. This most often plagues the mid-range programmer, who is just smart enough
to know about a vast array of techniques, but not yet mature enough to know when
not to employ them.

# A different, better-performing approach

It's an all-too-common occurrence. I'll give code review feedback, asking "Why
didn't you take approach B? It seems to be just as clear, and yet obviously has
superior performance." Again, this is in a circumstance where I believe the difference
matters, given the order of magnitude that matters for the code in question. And
I'll get a response, "Premature optimization is the root of all evil." At which
point I want to smack this certain someone upside the head, because it's such a
lame answer.

The real answer is that the programmer didn't stop to carefully consider alternatives
before coding up solution A. (To be fair, sometimes good solutions evade the best
of us.) The reality is that the alternative approach should have been taken; it may
be true that it's "too late" because the implications of the original decision
were nontrivial and perhaps far-reaching, but that is too often an unfortunate consequence
of not taking the care and thought to do it right in the first place.

These kinds of "peanut butter" problems add up in a hard to identify way. Your performance
profiler may not obviously point out the effect of such a bad choice so that it's
staring you in your face. Rather than making one routine 1000% slower, you may have
made your entire program 3% slower. Make enough of these sorts of decisions, and
you will have dug yourself a hole deep enough to take a considerable percentage of
the original development time just digging out. I don't know about you, but I prefer
to clean my house incrementally and regularly rather than letting garbage pile up
to the ceilings, with flies buzzing around, before taking out the trash. Simply put,
all great software programmers I know are proactive in writing clear, clean, and
smart code. They pour love into the code they write.

In this day and age, where mobility and therefore power is king, instructions matter.
My boss is fond of saying "the most performant instruction is the one you didn't
have to execute." And it's true. The best way to save battery power on mobile phones
is to execute less code to get the same job done.

To take an example of a technology that I am quite supportive of, but that makes
writing inefficient code very easy, let's look at LINQ-to-Objects. Quick, how many
inefficiencies are introduced by this code?

```
int[] Scale(int[] inputs, int lo, int hi, int c) {
    var results = from x in inputs
                  where (x >= lo) && (x <= hi)
                  select (x * c);
    return results.ToArray();
}

```

It's hard to account for them all.

There are two delegate object allocations, one for the call to Enumerable.Where and
the other for the call to Enumerable.Select. These delegates point to potentially
two distinct closure objects, each of which has captured enclosing variables. These
closure objects are instances of new classes, which occupy nontrivial space in both
the binary and at runtime. (And of course, the arguments are now stored in two places,
must be copied to the closure objects, and then we must incur extra indirections
each time we access them.) In all likelihood, the Where and Select operators are
going to allocate new IEnumerable and new IEnumerator objects. For each element in
the input, the Where operator will make two interface method calls, one to IEnumerator.MoveNext
and the other to IEnumerator.get\_Current. It will then make a delegate call, which
is slightly more expensive than a virtual method call on the CLR. For each element
for which the Where delegate returns 'true', the Select operator will have likewise
made two interface method calls, in addition to another delegate invocation. Oh,
and the implementations of these likely use C# iterators, which produce relatively
fat code, and are implemented as state machines which will incur more overhead (switch
statements, state variables, etc.) than a hand-written implementation.

Wow. And we aren't even done yet. The ToArray method doesn't know the size of
the output, so it must make many allocations. It'll start with 4 elements, and
then keep doubling and copying elements as necessary. And we may end up with excess
storage. If we end up with 33,000 elements, for example, we will waste about 128KB
of dynamic storage (32,000 X 4-byte ints).

A programmer may have written this routine this way because he or she has recently
discovered LINQ, or has heard of the benefits of writing code declaratively. And/or
he or she may have decided to introduce a more general purpose implementation of
a Scale API versus doing something specific to the use in the particular program
that Scale will be immediately used in. This is a great example of why premature
generalization is often at odds with writing efficient code.

Imagine an alternative universe, on the other hand, where Scale will only get used
once and therefore we can take advantage of certain properties of its usage. Namely,
perhaps the input array need not be preserved, and instead we can update the elements
matching the criteria in place:

```
void ScaleInPlace(int[] inputs, int lo, int hi, int c) {
    for (int i = 0; i < inputs.Length; i++) {
        if ((inputs[i] >= lo) &*& (inputs[i] <= hi)) {
            inputs[i] *= c;
        }
    }
}
```

A quick-and-dirty benchmark shows this to be an order of magnitude faster. Again,
is it an order of magnitude that you care about? Perhaps not. See my earlier thoughts
on that particular topic. But if you care about costs in the 100s or 1000s of cycles
range, you probably want to pay heed.

Now, I'm not trying to take potshots at LINQ. It was just an example. In fact,
I spent 3 years running a team that delivered PLINQ, a parallel execution engine
for LINQ-to-Objects. LINQ is great where you can afford it, and/or where the alternatives
do not offer ridiculously better performance. For example, if you can't do in-place
updates, functionally producing new data is going to require allocations no matter
which way you slice it. But having watched people using PLINQ, I have witnessed numerous
occasions where an inordinately expensive query was made 8-times faster by parallelizing…
where the trivial refactoring into a slimmed down algorithm with proper data structures
would have speed the code up by 100-fold. Parallelizing a piggy piece of code to
make it faster merely uses more of the machine to get the same job done, and will
negatively impact power, resource management, and utilization.

Another view is that writing code in this declarative manner is better, because it'll
just get faster as the compiler and runtimes enjoy new optimizations. This sounds
nice, and seems like taking a high road of some sort. But what usually matters is
today: how does the code perform using the latest and greatest technology available
today. And if you scratch underneath the surface, it turns out that most of these
optimizations are what I call "science fiction" and unlikely to happen. If you write
redundant asserts at twenty adjacent layers of your program, well, you're probably
going to pay for them. If you allocate objects like they are cheap apples growing
on trees, you're going to pay for them. True, optimizations might make things faster
over time, but usually not in the way you expect and usually not by orders of magnitude
unless you are lucky.

A colleague of mine used to call C a WYWIWYG language—"what you write is what you
get"—wherein each line of code roughly mapped one-to-one, in a self-evident way,
with a corresponding handful of assembly instructions. This is a stark contrast to
C#, wherein a single line of code can allocate many objects and have an impact to
the surrounding code by introducing numerous silent indirections. For this reason
alone, understanding what things cost and paying attention to them is admittedly
more difficult -- and arguably more important -- in C# than it was back in the
good ole' C days. ILDASM is your friend … as is the disassembler. Yes, good systems
programmers regularly look at the assembly code generated by the .NET JIT. Don't
assume it generates the code you think it does.

# Gratuitous memory allocations

I love C#. I really do. I was reading my "Secure Coding in C and C++" book for fun
this weekend, and it reminded me how many of those security vulnerabilities are eliminated
by construction thanks to type- and memory-safety.

But the one thing I don't love is how easy and invisible it makes heap allocations.

The very fact that C++ memory management is painful means most C++ programmers are
overly-conscious about allocation and footprint. Having to opt-in to using pointers
means developers are conscious about indirections, rather than having them everywhere
by default. These are qualitative, hard-to-backup statements, but in my experience
they are quite true. It's also cultural.

Because they are so easy, it's doubly important to be on the lookout for allocations
in C#. Each one adds to a hard-to-quantify debt that must be repaid later on when
a GC subsequently scans the heap looking for garbage. An API may appear cheap to
invoke, but it may have allocated an inordinate amount of memory whose cost is only
paid for down the line. This is certainly not "paying it forward."

It's never been so easy to read a GB worth of data into memory and then haphazardly
leave it hanging around for the GC to take care of at some indeterminate point in
the future as it is in .NET. Or an entire list of said data. Too many times a .NET
program holds onto GBs of working set, when a more memory conscientious approach
would have been to devise an incremental loading strategy, employ a denser representation
of this data, or some combination of the two. But, hey, memory is plentiful and cheap!
And in the worst case, paging to disk is free! Right? Wrong. Think about the worst
case.

Depending on the size of the objects allocated, how long they remain live, and how
many processors are being used, the subsequent GCs necessary to clean up incessant
allocations may impact a program in a difficult to predict way. Allocating a bunch
of very large objects that live for long enough to make it out of the nursery, but
not forever, for instance, is one of the worst evils you can do. This is known as
mid-life crisis. You either want really short-lived objects or really long-lived
ones. But in any case, it really matters: the LINQ example earlier shows how easy
it is to allocate crap without seeing it in the code.

If I could do it all over again, I would make some changes to C#. I would try to
keep pointers, and merely not allow you to free them. Indirections would be explicit.
The reference type versus value type distinction would not exist; whether something
was a reference would work like C++, i.e. you get to decide. Things get tricky when
you start allocating things on the stack, because of the lifetime issues, so we'd
probably only support stack allocation for a subset of primitive types. (Or we'd
employ conservative escape analysis.) Anyway, the point here is to illustrate that
in such a world, you'd be more conscious about how data is laid out in memory,
encouraging dense representations over sparse and pointer rich data structures silently
spreading all over the place. We don't live in this world, so pretend as though we
do; each time you see a reference to an object, think "indirection!" to yourself
and react as you would in C++ when you see a pointer dereference.

Allocations are not always bad, of course. It's easy to become paranoid here. You
need to understand your memory manager to know for sure. Most GC-based systems, for
example, are heavily tuned to make successive small object allocations very fast.
So if you're programming in C#, you'll get less "bang for your buck" by fusing
a large number of contiguous object allocations into a small number of large object
allocations that ultimately occupy an equivalent amount of space, particularly if
those objects are short-lived. Lots of little garbage tends to be pretty painless,
at least relatively.

# Variable latency and asynchrony

There aren't many ways to introduce a multisecond delay into your program at a
moment's notice. But I/O can do just that.

Code with highly variable latency is dangerous, because it can have dramatically
different performance characteristics depending on numerous variables, many of which
are driven by environmental conditions outside of your program's control. As such
it is immensely important to document where such variable latency can occur, and
to program defensively against it happening.

For example, imagine a team of twenty programmers building some desktop application.
The team is just large enough that no one person can understand the full details
of how the entire system works. So you've got to compose many pieces together.
(As I mentioned earlier, composition can lead to hard-to-predict performance characteristics.)
Programmer Alice is responsible for serving up a list of fonts, and Programmer Bob
is consuming that list to paint it on the UI. Does Bob know what it takes to fetch
the list of fonts? Probably not. Does Alice know the full set of concerns that Bob
must think about to deliver a responsive UI, like incremental repaints, progress
reporting, and cancellation? Probably not. So Alice does the best she knows how to
do: she hits the cache, when the font cache is fully populated, and falls back to
fetching fonts from the printer otherwise. She returns a List<Font> object from her
API. Now Bob just calls the API and paints the results on the UI; the call appears
to be quite snappy in his testing. Unfortunately, when the cache is not populated,
the "quick" cache hit turns into a series of network roundtrips with the printer;
that hangs the UI, but only for a few milliseconds. Even worse, when the printer
is accidentally offline, perhaps due to a power outage, the UI freezes for twenty
seconds, because that's the hard-coded timeout. Ouch!

This situation happens all the time. It's one of the most common causes of UI hangs.

If you're programming in an environment where asynchrony is first class, Alice
could have advertised the fact that, under worst-case circumstances, fetching the
font list would take some time. If she were programming in .NET, for example, she'd
return a Task<List<Font>> rather than a List<Font>. The API would then be self-documenting,
and Bob would know that waiting for the task's result is dangerous business. He
knows, of course, that blocking the UI thread often leads to responsiveness problems.
So he would instead use the ContinueWith API to rendezvous with the results once
they become available. And Bob may now know he needs to go back and work more closely
with Alice on this interface: to ensure cancellation is wired up correctly, and to
design a richer interface that facilitates incremental painting and progress reporting.

Variable latency is not just problematic for responsiveness reasons. If I/O is expressed
synchronously, a program cannot efficiently overlap many of them. Imagine we must
make three network calls as part of completing an operation, and that each one will
take 25 milliseconds to complete. If we do synchronous I/O, the whole operation will
take at least 75 milliseconds. If we launch do asynchronous I/O, on the other hand,
the operation may take as few as 25 milliseconds to finish. That's huge.

If I had my druthers, all I/O would be asynchronous. But that's not where we are
today.

The concern is not limited to just I/O, of course. Compute- and memory-bound work
can quickly turn into variable latency work, particularly under stressful situations
like when an application is paging. So truthfully any abstraction doing "heavy lifting"
should offer an asynchronous alternative.

# Examples of "bad" optimizations

It is easy to take it too far. Even if you're shaving off cycles where each-and-every
cycle matters, you may be doing the wrong thing. If anything, I hope this article
has convinced you to be thoughtful, and to strive to strike a healthy balance between
beautiful code and performance.

Anytime the optimization sacrifices maintainability, it is highly suspect. Indeed,
many such optimizations are superficial and may not actually improve the resulting
code's performance.

The worst category of optimization is one that can lead to brittle and insecure code.

One example of this is heavy reliance on stack allocation. In C and C++, doing stack
allocation of buffers often leads to difficult choices, like fixing the buffer size
and writing to it in place. There is perhaps no single technique that, over the years,
has led to the most buffer overrun-based exploits. Not only that, but stack overflow
in Windows programs is quite catastrophic, and increases in likelihood the more stack
allocation that a program does. So doing \_alloca in C++ or stackalloc in C# is really
just playing with fire, particularly for dynamically sized and potentially big allocations.

Another example is using unsafe code in C#. I can't tell you how many times I've
seen programmers employ unsafe pointer arithmetic to avoid the automatic bounds checking
generated by the CLR JIT compiler. It is true that in some circumstances this can
be a win. But it is also true that most programmers who do this never bothered to
crack open the resulting assembly to see that the JIT compiler does a fairly decent
job at automatic bounds check hoisting. This is an example where the cost of the
optimization outweighs the benefits in most circumstances. The cost to pin memory,
the risk of heap corruption due to a failure to properly pin memory or an offset
error, and the complication in the code, are all just not worth it. Unless you really
have actually measured and found the routine to be a problem.

If it smells way too complicated, it probably is.

# In conclusion

I'm not saying Knuth didn't have a good point. He did. But the "premature optimization
is the root of all evil" pop-culture and witty statement is not a license to ignore
performance altogether. It's not justification to be sloppy about writing code.
Proactive attention to performance is priceless, especially for certain kinds of
product- and systems-level software.

My hope is that this article has helped to instill a better sense, or reinforce an
existing good sense, for what matters, where it matters, and why it matters when
it comes to performance. Before you write a line of code, you really need to have
a budget for what you can afford; and, as you write your code, you must know what
that code costs, and keep a constant mental tally of how much of that budget has
been spent. Don't exceed the budget, and most certainly do not ignore it and just
hope that wishful thinking will save your behind. Building up this debt will cost
you down the road, I promise. And ultimately, test-driven development works for performance
too; you will at least know right away once you have exceeded your budget.

Think about worst case performance. It's not the only thing that matters, but particularly
when the best and worst case differ by an order of magnitude, you will probably need
to think more holistically about the composition of caller and callee while building
a larger program out of constituent parts.

And lastly, the productivity and safety gains of managed code, thanks to nice abstractions,
type- and memory-safety, and automatic memory management, do not have to come at
the expense of performance. Indeed this is a stereotype that performance conscious
programmers are in a position to break down. All you need to do is slow down and
be thoughtful about each and every line of code you write. Remember, programming
is as much engineering as it is an art. Measure, measure, measure; and, of course,
be thoughtful, intentional, and responsible in crafting beautiful and performant
code.

