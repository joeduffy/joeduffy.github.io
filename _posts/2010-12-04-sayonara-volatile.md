---
layout: post
title: Sayonara volatile
date: 2010-12-04 15:16:34.000000000 -08:00
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
After spending more time than I'd like to admit over the years researching memory
model literature (particularly Java's terrific JMM and related publications), subsequently
trying to "fix" the CLR memory model, reviewing proposals for new C++ memory
models, and beating my head against the wall for months developing a new memory model
that supports weakly ordered processors like the kind you'll find on ARM in a developer-friendly
yet power-efficient way, I have a conclusion to share.

# Volatile is evil

Why? Let me recount the reasons:

1. It doesn't mean what you think.
2. It used to have a very specific purpose — to enure memory operations with external
side-effects did not get reordered — and has since gotten bastardized and used
for many secondarily-related purposes.
3. Even if you think it does mean what you think, the annotation scheme is all wrong.
Volatile annotates a storage location, and yet what really matters is what happens
when accessing said storage locations. The fences occur when you access the variable,
not when you declare it. And yet from a readability perspective, they are completely
invisible and easy to miss.
4. And even if you don't care about readability, the meaning of volatile changes
wildly when you switch platforms. Today it's store / release, tomorrow it's write
/ read fences. Perhaps it's even sequentially consistent. And the label of "store
/ release" could actually be a white lie, as with the CLR's memory model thanks
to store buffer forwarding and the lack of fences in the CLR JIT's x64 stores.
5. Performance, man, performance! Sure sequential consistency as the default sounds
nice on the tin, but once you're running that mobile app on ARM, and sucking up
160 cycles for each write you perform, you're going to curse volatile like the
plague.

And so the moral of the story follows...

# Attempting to "fix" volatile is a waste of time

Instead, a new world order has arrived. We must take a two-pronged approach to solving
instruction-level interleaving bugs, neither prong having much to do with the traditional
definition of memory models or volatiles. We must:

1. Eliminate memory ordering from 99% of developers' purviews. This is already
the case with single-threaded programs, because code motion in compilers and processors
is limited to what only affects concurrent observations. So the answer is pretty
clear: developers must move towards single-threaded programming models connected
through message passing, optionally with provably race-free fine-grained parallelism
inside of those single-threaded worlds.
2. Leave the memory model esoterica to the Einsteins, and radically change its meaning.
Data dependence and transitive visibility of memory operations are in. Volatiles
on storage locations are out. Instead, we must throw fences into programmer's faces,
and force them to understand each and every one that occurs. And moreover, force
them to decide about each and every one that occurs. Specifically, hidden fences
thanks to volatile are no longer. Those who cannot take it should fall into the 99%
bucket already mentioned above, versus the 1% bucket.

Let's set #1 aside for now, since it's obviously a huge can of worms.

But what about #2? It is quite encouraging that the C++0x group is firmly on the
path of #2. See [http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2007/n2145.html](http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2007/n2145.html)
for more details. In a nutshell, each location that you'd have ordinarily tagged
volatile instead becomes a template atomic type. And then each read / write has the
opportunity to specify the desired kind of fence, whether that is acquire (for reads),
release (for writes), fully ordered, or relaxed (meaning no fence).

I do think it'd be worth them considering compiler-only fences too. So that relaxed
means fully-relaxed, and there is a fence in-between that merely prevents the compiler
from optimizing the memory operation. This pays homage to volatile's legacy in
C as merely a variable that mustn't be subject to optimizations, because operations
against these variables pertain to, say, memory-mapped device I/O.

Another nitpick of mine is that I'd have required each access to specify the fence,
whereas C++0x implicitly uses full fence if left unspecified at the callsite. It's
a minor convenience, but I like always having the fence spelled out very explicitly
in the code. Lock-free access to shared variables is sufficiently dangerous that
automatic sequential consistency is the least of your problems.

Nevertheless, the C++0x direction is a massive good step forward, and these are just
minor details.

My hope is that .NET follows suit. And the timing couldn't be more apropos as "now":
we are moving forward in a heavily mobile, distributed-system-on-a-chip, and heterogeneous
world, where processor memory models will necessarily continue to weaken. The overly
strong x86 memory model, kept alive primarily to ensure compatibility, has simply
grown too expensive to accommodate. The power benefits and architectural simplifications
are hard to argue with, and because compatibility becomes less of an issue as new
platforms arise (e.g. for mobile), the world moves to the cloud, and hence there
is legacy to worry about, I do hope that processor vendors seize the opportunity.
ARM certainly has. It is less about out-of-order execution as it is about coherency
costs. Truthfully, I'd be disappointed if anything else happened, even though the
risk to compatibility for shrink-wrapped software scares the hell out of me. But
this is most certainly the right way to go, long-term. As software platforms move
in the direction of #1 -- as I also foresee -- the need for fences dwindles. The
cost of supporting the current .NET memory model is too great and will become a liability
with time.

Thankfully, it is quite simple to build a veneer atop .NET that works a lot more
like atomic. For example, imagine that we had a new System.Threading.Volatile static
class, and that it offered the moral equivalent to atomic inner types for each atomic
primitive we can synchronize against:

```
namespace System.Threading
{
    public static class Volatile
    {
        public struct Int32 {..}
        public struct Int64 {..}
        …
        public struct Reference<T> where T : class {..}
        …
    }
}
```

Now instead of tagging a location as 'volatile', you would use one of these primitives.
For example, rather than:

```
static volatile MySingleton s_instance;
```

You would say:

```
static Volatile.Reference<MySingleton> s_instance;
```

Each class has a similar set of operations. For example:

```
namespace System.Threading
{
    public static class Volatile
    {
        public struct Int32
        {
            public Int32(int value);

            public int ReadAcquireFence();
            public int ReadFullFence();
            public int ReadCompilerOnlyFence();
            public int ReadUnfenced();

            public void WriteReleaseFence(int newValue);
            public void WriteFullFence(int newValue);
            public void WriteCompilerOnlyFence(int newValue);
            public void WriteUnfenced(int newValue);

            public int AtomicCompareExchange(int newValue, int comparand);
            public int AtomicExchange(int newValue);
            public int AtomicAdd(int delta);
            public int AtomicIncrement();
            public int AtomicDecrement();

            // Etc…, bitwise ops, other math ops, etc.
        }
    }
}
```

Of course, only the integer types would offer the increment, decrement, add, and
related operators. And it turns out that offering different kinds of fences on the
Atomic\* operations would be incredibly useful too, because processors like ARM do
not couple the fence to the compare-and-swap / load-locked-store-conditional as x86
processors do. Taking advantage of this can be huge if you are writing performance
critical code, like a concurrent garbage collector whose atomic swaps need not imply
ordering with the surrounding instruction stream. You can quibble over the details,
like whether these should use enums instead of the name to encode the fence-kind.
I did it this way to keep the implementations branch-free, although with a decent
inlining JIT compiler, it'd probably optimize those away thanks to constant propagation.

It's quite trivial to implement these APIs atop existing .NET primitives. I built
a little library that does so, but it was so boring and repetitive I decided not
to post it alongside this blog entry as originally intended.

With the above definition, we can very clearly see the fences involved in doing,
say, double-checked locking:

```
static Volatile.Reference<MySingleton> s_instance;

public static MySingleton Instance
{
    get
    {
        MySingleton instance = s_instance.ReadAcquireFence();
        if (instance == null) {
            instance = new MySingleton();
            instance = s_instance.AtomicCompareExchangeRelease(instance, null);
        }
        return instance;
    }
}
```

We see there are two fences. One is an acquire and, depending on what your memory
model says about data dependence, is probably unnecessary. Most sane memory models
guarantee that data dependent loads do not pass. So we needn't worry that we'll
see a non-null s\_instance whose contents haven't been initialized. (If we were
talking structs, it'd be another story.) Nevertheless, it's definitely required
that we use a release-only fence for the publication of the object. This guarantees
writes to fields within the MySingleton constructor have completed prior to the write
of the new object to the shared instance field. The point here is that you are forced
to think about the fences, and you actually see them.

Of course, most platforms need to provide the bare minimum of fencing to assure type
safety, particularly for languages like C#. My understanding is that C++0x has decided,
at least for now, not to offer type-safety in the face of multithreading. That means
you might publish an object and, if stores occur out-of-order, the reader could see
an object partially initialized with an invalid vtable pointer. In C# and Java, the
language designers have thankfully decided to shield programmers from this. The need
for fences also extends to unsafe code like strings, where -- were it possible for
a thread to read the non-zero length before the char\* pointer was valid -- writes
to random memory could occur and hence threaten type-safety. Thankfully, again, C#
and Java protect developers from this, mostly due to the automatic zero'ing of
memory as the GC allocates and hands out new segments.

There are costs to offering this type safety assurance. So you can understand why
the C++ designers want to keep fences out of object allocation. If you have #1 above,
however, the costs are dramatically lower and more acceptable. But the world is --
unfortunately -- still a freethreaded one, and we have several years to go before
we've reached the final destination. As a step forward, however, the death of volatile
is a welcomed one. Say it with me.

# "Sayonara volatile."

Here's hoping that .NET 5.0 takes this step forward too.

