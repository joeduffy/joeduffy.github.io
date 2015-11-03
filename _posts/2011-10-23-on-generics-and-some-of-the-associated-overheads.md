---
layout: post
title: On generics and (some of) the associated overheads
date: 2011-10-23 15:26:02.000000000 -07:00
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
It's been unbelievably long since I last blogged.

The reason is simple. I've been ecstatic in my job and, every time I think to write
something, I quickly end up turning to work and soon find that hours (days? months?)
have passed. This is a wonderful problem to have, but not so good for keeping the
blog looking fresh and new. (I've also been writing [a fair bit of music](http://soundcloud.com/45nm_joeduffy/sets/current/)
lately.) Well, this weekend I managed to lock myself out of my VPN access, and decided
that this was a sign that I ought to dust off the cobwebs on a blog entry or two
that I've had in the works for quite some time.

The topic for today is generics, a feature many of us know and love. Specifically,
their impact on software performance, something I frequently see developers struggling
to understand and tame in the wild.

# The blessing; and, the curse

I absolutely love generics. I can hardly imagine writing code without them these
days. The code reuse, higher-order expressiveness, beautiful abstractions, and static
type-safety enabled by first class parametric polymorphism are all game-changing.
And being a language history wonk, I'm delighted to see many mainstream programming
languages stealing a page from ML and theoretical CS generally.

Generics, however, are not free. And in some circumstances, they are, dare I say,
rather expensive. Few language features surpass generics in the ability to write
a concise and elegant bit of code, which then translates into reams of ugly assembly
code out the rear end of the compiler. I am of course speaking mainly to models in
which compilation leads to code specialization (like .NET's), versus erasure (like
Java's).

Most developers coming from a C++ background understand code expansion deeply, because
they program with templates. Unlike templates, however, there is ample runtime type
information (RTTI) associated with generic instantiations… such that the costs
associated with generics frequently -- and perhaps surprisingly -- are a superset
of those costs normally associated with C++ templates. At the same time, because
the compiler understands parametric polymorphism, it can sometimes do a better job
optimizing, e.g. with techniques like code sharing.

Basically, with templates and erasure, the equation for predicting code expansion
is super simple. You get it all (in the former) or you get none of it (in the latter),
but with specialized generics this equation is quite complex.

Paradoxically, these same costs are the main value that generics bring to the table!
Write a little type-agnostic code and then "instantiate" that same code over multiple
types without repeating yourself. But, generics are not magic; did you ever stop
to wonder things like: What machine code is generated for these types? Does the compiler
need to specialize the actual code that runs on the processor for unique instantiations,
or is it all the same? And if it does need to specialize, where, how, and why? And
perhaps most importantly, what hidden costs are there, and how should I think about
them while writing code?

Before reading further, paranoia need not ensue. The point of this article is merely
to raise your awareness. All programmers should know what the abstractions they use
cost, and make conscious tradeoffs when writing code with them. The aforementioned
benefits of generics really are often "worth it," both in the elegance and reusability
of abstractions, and in developer productivity. In my experience, however, the associated
costs are so subtle and ill-documented that even people who write highly generic
code typically remain unaware of them. Even more subtly, these costs are somewhat
different in nature when pre-compiling your code, such as with .NET's NGen technology.

This brief essay will walk through a few such costs in the context of the .NET Framework
and CLR's implementation of generics. This is in no way an exhaustive study of generic
compilation, and your mileage will vary from one platform to the next. Although the
studies presented would apply to other implementations of generics, the reality is
that if you're writing code in, say, Java -- where type erasure is employed rather
than code specialization -- then all of this is going to be less relevant to you.

With no further delay, let's get started.

# Code, RTTI, oh my

When considering costs, we must always think about both size and speed.

There is at least as much assembly code created for an instantiation as the code
you've written for the generic abstraction in C# or MSIL. A simple mental model --
that thankfully turns out isn't entirely accurate, thanks to some sharing optimizations
described below -- is that for each instantiation of a generic type or method you
get a new copy of that code specialized to the type in question. Obviously, this
increases code size. And just as obviously, it will add some runtime cost to JIT
compile the code (if you aren't using ahead of time compilation), as well as putting
more pressure on I-cache and TLB.

Another source of significant cost is the runtime data structures needed for RTTI
and Reflection, like vtables and other metadata. Quite simply, the runtime needs
to know the identity of each generic instantiation, to prevent things like casting
a List&lt;Int16&gt; to a List&lt;String&gt;, and even List&lt;Object&gt; to List&lt;String&gt;;
and given  that there is often distinct code generated for unique instantiations, the vtable
contents for those different List&lt;T&gt; instantiations are going to look quite different.

And of course, there are statics. Each generic instantiation gets its own set, requiring
extra storage and another level of indirection when fetching them. Unique statics
means D-cache and TLB pressure. It turns out that code shared across AppDomains,
like mscorlib.dll, already need such things. But I have found that it's surprisingly
common for a developer to throw a static field (or nested class!) onto an outer generic
type, without actually needing it to be replicated for each unique instantiation.

In addition to the immediate effects, generic types often refer to other generic
types which refer to other generic types … and so on. Instantiating a root type
is akin to instantiating the full transitive closure.

To make our discussion friendly and familiar, we shall use the .NET Framework's List&lt;T&gt;
type -- presumably one of the most commonly used generic types on the planet --
to illustrate many of these costs. And unfortunately, you'll also see that many of
the common performance pitfalls plague this type too. (So, really, you need not feel
bad if your own code is guilty of them too.)

# Why the distinct code, anyway?

There is only one copy of List&lt;T&gt;'s code in mscorlib's MSIL. It is essentially just
a blueprint for the list class.

When I create a List&lt;Int16&gt; in my program and use it, however, there clearly needs
to be some assembly code created in order to execute List&lt;T&gt;'s associated functionality,
just with any T's used by List&lt;T&gt;'s code replaced by actual 2-byte short integers.
And similarly, if I were to instantiate a List&lt;String&gt;, all those T's need to be
replaced by pointer-sized object references, either 4- or 8-bytes depending on machine
architecture, that are reported live to the garbage collector.

This is what leads to our simple mental model above, in which each instantiation
gets its own copy of the code. In this case, both List&lt;Int16&gt; and List&lt;String&gt; would
be entirely independent types at runtime, with wholly separate copies of the machine
code.

Certainly if I manually went about creating my own Int16List and StringList types,
they would be distinct types with distinct machine code generated. Being a prudent
developer, however, I'd probably try to arrange to share as much of the implementation
as possible between the two types, perhaps using implementation inheritance. But
alas, there's no way I could share it all: any code specific to Int16 or String,
for example, would surely differ, both in MSIL and in the native code.

Generics basically give you the ability to do this same thing, without you needing
to do the factoring of type-independent and type-specific code yourself. The compiler
does that for you.

Why might the code be different? As stated above, Int16 values are 2 bytes and String
pointers are native word sized (4 bytes on 32-bit, 8 bytes on 64-bit). All the code
that passes values of type T on the stack, either as arguments or return values,
moves instances into and out of memory locations (like the T[] backing array), and
so on, needs to be specialized based on the size of T. This wouldn't be true of a
generics implementation that used type erasure, like Java's, but then you'd need
to box the value types on the heap so that everything is a pointer. If T is a Float,
we will likely emit code that uses floating point math instead of general purpose
registers. Any tables that report GC roots are likely to be different, since object
references can be embedded inside struct values that get laid out on the stack. And
so on. Some day you might want to compare the machine code for a simple generic Echo&lt;T&gt;
method for different kinds of T's; it is really easy to do, and is quite illustrative.

A naïve wish might go as follows. Imagine that I had written my own dedicated Int16List
and StringList types, and that we diffed the resulting machine code between the distinct
list types; we'd presumably find a fair bit of duplication for all the reasons stated
above. It would be a nice property if, when we used the generic List&lt;Int16&lt; and List&lt;String&t;
types, and similarly diffed the resulting assembly, the amount of specialized code
would be no greater than the amount of specialized code between our best hand-written
Int16List and StringList types. I.e., only parts that need to be different are different.

We could go even further with our wish. Imagine I had a List&lt;DateTime&gt; and List&lt;Int64&gt;.
Both are 8-byte values, and do not contain any GC references. If I were writing a
specialized 8ByteValueList in C++ and had immense performance constraints, I would,
again being a prudent developer, probably use some type unsafe code, with nasty reinterpret\_casts,
so that I could use the same list type to store any kind of 8-byte value. (Except
in C++ I could even store pointers!) It would also be a nice property if generics
did some of this for us, while still retaining the type safety we love about generics.

It turns out we will get neither of our wishes exactly, although we will get something
close to the spirit of our wishes.

# Code sharing

Indeed, the CLR does arrange to share many generic instantiations. The rule is simple,
although it is subject to change in the future (being an optimization and all): instantiations
over reference types are shared among all reference type instantiations for that
generic type/method, whereas instantiations over value types get their own full copy
of the code. In other words, List&lt;String&gt; and List&lt;Object&gt; are backed by the same
code, but List&lt;DateTime> and List&lt;Int64&gt; get their own.

It is true that, in theory, List&lt;DateTime&gt; and List&lt;Int64&gt; could use the same shared
code, because they are of identical size and have GC roots in the same locations
(trivially, because neither has one). But there are additional restrictions on generated
code that makes this problematic, for example if we were talking about Double and
Int64. In short, the CLR doesn't actually share value type instantiations as of the
4.0 runtime, although clearly it could in certain situations (value types of the
same size with GC roots in the same locations).

As you might guess, this extends to multi-parameter generics in obvious ways. A Dictionary&lt;Object,
Object&gt; is shared with a Dictionary&lt;String, String&gt;, etc., and a Dictionary&lt;Int64,
Object&gt; is shared with a Dictionary&lt;Int64, String&gt;. A Dictionary&lt;DateTime, DateTime&gt;
is not, however, shared with a Dictionary&lt;Int64, Int64&gt; instantiation, as per the
above.

My pal [Joel Pobar](http://callvirt.net/blog/) wrote [a post eons ago describing
how code sharing works](http://blogs.msdn.com/b/joelpob/archive/2004/11/17/259224.aspx)
in great detail, which I do not intend to rehash. Please refer to his post for an
excellent overview of how code sharing works.

An important thing to remember, however, is that no matter how much code sharing
happens, you still need distinct RTTI data structures. So although List&lt;Object&gt; and
List&lt;String&gt; share the same machine code, they have distinct vtables; sure, each
table is full of pointers to the same code functions, but you are still paying for
the runtime data structures. A distinct instantiation, therefore, is never actually
free!

# Transitive closures

Why am I making such a big deal about code sharing, anyway?

Another surprising aspect of generics is the transitive closure problem. Particularly
when doing pre-compilation of generics, each unique instantiation doesn't simply
lead to a specialized version of the code associated with the type being directly
instantiated. The whole transitive closure of types, starting with that root type,
will also be compiled. This can be a surprisingly huge number of types! JIT is much
more pay-for-play, such that you get one level of explosion at a time, but once there
is code that calls a particular type's method, even if that code is lazily compiled,
creation of the type is forced.

To illustrate this, let's take our friend List&lt;T&gt;. Before examining the list, how
many generic types would you expect that a single new List&lt;T&gt; instantiation instantiates?

What if I told you that a single List&lt;int&gt; instantiation creates (at least) 28 types?
And that, say, five unique instantiations of List&lt;T&gt; might cost you 300K of disk
space and 70K of working set? Well, of course, if you are writing a script, or something
with fairly loose performance requirements, this might not matter much. But if topics
like download time, mobile footprint, and cache performance are important to you,
then you probably want to pay attention to this. To a first approximation, size _is_
speed.

Yes, you heard me right: 28 types. Holy smokes... How can this be?!

Nested types are one obvious answer, and indeed List&lt;T&gt; has two: an Enumerator class
(which is reasonable), and one to support the legacy synchronized collections pattern
(which we presumably wish we didn't have to pay for). The larger answer here, however,
is functionality. Yes, functionality! This is a great example where the cost of generics
explodes as you add more features. Start simple, keep adding stuff, as has happened
to List&lt;T&gt; over the years, and you will soon find that a series of elegant abstractions
adds up to a gut-wrenching bucket of bytes.

Here's a quick sketch of the transitive closure of generic types used by List&lt;T&gt;:

```
List<T>
	T[] type
	IList<T> type
		ICollection<T> type
			IEnumerable<T> type
				IEnumerator<T> type
	ReadOnlyCollection<T> type (AsReadOnly)
		(Nothing more than List<T>)
	IComparer<T> type (BinarySearch, Sort)
	{Array.BinarySearch<T> method (BinarySearch)}
		ArraySortHelper<T> type
			IArraySortHelper<T> type
			GenericArraySortHelper<T> type
	EqualityComparer<T> type (Contains)
		IEqualityComparer<T> type
		IEquatable<T> type
		NullableEqualityComparer<T> type
			Nullable<T> type
		EnumEqualityComparer<T> type
			{JitHelpers.UnsafeEnumCast<T> method}
		ObjectEqualityComparer<T> type
	Predicate<T> delegate type (Find*)
	Action<T> delegate type (ForEach)
	{Array.LastIndexOf<T> method (LastIndexOf)}
	Comparison<T> delegate type (Sort)
	Array.FunctorComparer<T> type (Sort)
		Comparer<T> type
		GenericComparer<T> type
		NullableComparer<T> type
		ObjectComparer<T> type
	{Array.Sort<T> method (Sort)}
		ArraySortHelper<T> type (see earlier)
	Enumerator inner type
	SynchronizedList<T> inner type
		IList<T> interface (see earlier)
		ICollection<T> interface (see earlier)
		IEnumerable<T> interface (see earlier)
	{Interlocked.CompareExchange<Object> method (SyncRoot)}
	{_emptyArray T[] static field}
```

I'm not trying to pick on List&lt;T&gt;. This class is only unique in this regard in that
it offers a large transitive closure of (mostly useful!) functionality. And it's
not the only guilty party. We recently shaved off 100K's of code size on my team,
for example, that were being lost simply because all the LINQ methods were declared
as instance methods on the base collection class, rather than being extension methods
as in .NET. We found nested enumerator and iterator types, cached static lambdas
as static fields, and huge transitive closures of other generic types, all allocated
when you just touched any collection type. Any collections library is apt to be full
of this stuff, since they are highly generic. But collection libraries are certainly
not the only places to go sniffing for such problems.

As an aside, it turns out that extension methods are a great way to make generic
abstractions more pay-for-play.

# Adding it up

Let's see what the above adds up to. I ran some programs through NGen as a quick
and dirty experiment, and inspected the on-disk sizes and also the runtime working
set sizes. I ensured clrjit.dll was not loaded into the process. Here's what I found.
Take these numbers with a grain of salt, as they will change from release to release;
they are simply rules of thumb. When in doubt, crank up NGen, DumpBin, and/or start
trawling the heap with VADump yourself!

One empty type with no methods in CLR 4.0 seems to cost roughly 0.2K bytes of on-disk
metadata, and about 0.7K in x64 working set. (This is a good rule of thumb irrespective
of generics… in terms of order of magnitude, you can think "one empty type means
1K of memory.") A single List&lt;S&gt; instantiation, where S is an empty struct, is in
the neighborhood of 60K on-disk metadata, and 14K of x64 working set. A single List&lt;C&gt;
instantiation, however, where C is an empty class, is only -- surprise -- about
7K on-disk and 4K in-memory. Why the large discrepancy? Well, it just so happens
that mscorlib.dll already includes an instantiation or two of List&lt;T&gt; over reference
types, so this 4K is the incremental cost on top of reusing what is there; remember,
there are still unique vtables and data structures still required for RTTI.

Rico did [a similar analysis a few years back](http://blogs.msdn.com/b/ricom/archive/2005/08/26/performance-quiz-7-generics-improvements-and-costs-solution.aspx),
and concluded that each unique List, where E was an enum type, cost 8K. Why the increase
to 14K over the years? x64 and ever-increasing functionality on the basic collections
classes, presumably. Remember, it's not just List&lt;T&gt; that has grown, it's also everything
that List&lt;T&gt; uses internally as an implementation detail.

# Dynamic specialization with dictionaries

Some specialization in behavior can be accomplished with dynamic runtime behavior,
rather than static code specialization. A prime example is the following:

```
class C
{
    public static void M<T>()
    {
        System.Console.WriteLine(typeof(T).Name);
    }
}
```

Where does the program get the value of typeof(T) from? If you look at the MSIL,
you will see that C# has emitted a ldtoken MSIL instruction. For some struct type,
we can compile that as a constant in the code, because it is getting its own copy
of the code. What occurs when two instantiations share code, like M<String> and M<Object>,
however? As you might guess, there is an indirection.

The thing we usually use for such indirections -- the vtable -- is nowhere to be
found in this particular example, because M is a static method. To deal with this,
the compiler inserts an extra "hidden" argument, frequently called a generic dictionary,
from which the emitted assembly code can fetch the type token. The cost here typically
isn't bad, because many of the operations that pull in the dictionary are already
RTTI or Reflection-based, and would require an indirection already (e.g., through
a vtable).

The operations which require a dictionary of some kind include anything that has
to do with RTTI and yet no vtable is readily accessible: typeof, casts, is and as
operators, etc. And as you might guess, if instantiations aren't shared (such as
with value types on the CLR), no dictionary is needed, because the code is fully
specialized. There are also multiple kinds of dictionaries used by the runtime, depending
on whether you are using a generic type, method, or some combination of both.

# JITting when you didn't mean to

There are two primary ways in which you will JIT compile when using generics, even
if you were good doobie and used NGen to reduce startup time.

One way is if you instantiate a new generic type exported from mscorlib.dll with
a type argument also defined in mscorlib.dll, that wasn't already instantiated inside
mscorlib.dll. (See my old [Generics and Performance](http://www.bluebytesoftware.com/blog/2005/03/23/DGUpdateGenericsAndPerformance.aspx)
blog entry for more details.) You can very easily see this happening by using an
instantiation like Dictionary<DateTime, DateTime>, and watching the clrjit.dll module
getting loaded.

The other way is generic virtual methods (GVMs). It turns out that GVMs pose incredible
difficulty for ahead of time separate compilation, because the compiler cannot know
statically which slot in the vtable points at the particular implementation you are
about to call. (Unless you use whole program compilation, something not offered by
.NET at present time.) For each such method, there's an unbounded set of possible
specialized instantiations a slot might point to, and so the vtable cannot be laid
out in a traditional manner. C++ doesn't allow templated virtual methods for this
very reason.

Thankfully, GVMs are somewhat rare. However, it only took 5 minutes of poking around
to find one that is quite front-and-center in .NET: in the implementation of LINQ,
there is an Iterator&lt;T&gt; type that has a method declared as follows:

```
public abstract IEnumerable<TResult> Select<TResult>(Func<TSource, TResult> selector);
```

All we need to do is figure out how to tickle that method, and we're guaranteed to
JIT. As it turns out, sure enough, the following code does the trick and forces clrjit.dll
to get loaded in .NET 4.0:

```
int[] xs = …;
int[] ys = xs.Where(x => true).Select(x => x).ToArray();
```

The Iterator&lt;T&gt; type is used for back-to-back Where and Select operators, as a performance
optimization that avoids excess allocations and interface dispatch. But because it
depends on a GVM, it does incur an initial penalty for using it, even if you have
used NGen to avoid runtime code generation.

# In conclusion

The moral of the story here is _not_ that you should fear generics. Beautiful things
can be built with them.

Instead, it's to use generics thoughtfully. Nothing in life is free, and generics
are no exception to this rule. If code size is important to you, then you will want
to have performance gates measuring your numbers against your goals; if you are working
in a codebase that uses generics heavily, and you end up spending any significant
time on code size optimizations, you will want to try to track down large transitive
closures. As I stated above, you could really be throwing away 100K's of code here.

And as to the surprise JITting, I've seen teams compiling with NGen and having a
functional gate that fails any new code that causes clrjit.dll to get loaded at runtime.
Although tracking down the root cause might be tricky when that gate fails, at least
you won't let the camel's nose under the tent.

Investing in tools here is a very good idea.

When it comes down to it, really thinking about what code must be executed by the
process is helpful. Step back and imagine you were writing this all in C++, with
the associated performance concerns front-and-center: consider how you'd arrange
to reuse as much implementation as you can, manage memory efficiently, perhaps employ
unsafe tricks that would have violated type safety and so are offlimits in .NET,
and all that jazz. Then step back and be grateful that you have a type- and memory-safe
environment to help you write more robust code, but also be realistic about what
you are paying in exchange.

I hope you've learned a useful thing or two in this article. If you'd like to learn
more, here are a few other good resources:

1. An MSR paper on the original implementation of .NET generics: [http://research.microsoft.com/pubs/64031/designandimplementationofgenerics.pdf](http://research.microsoft.com/pubs/64031/designandimplementationofgenerics.pdf)
2. Rico's "Six Questions About Generics and Performance" blog entry: [http://blogs.msdn.com/b/ricom/archive/2004/09/13/229025.aspx](http://blogs.msdn.com/b/ricom/archive/2004/09/13/229025.aspx)
3. Joel Pobar's "Generics and Code Sharing" blog post: [http://blogs.msdn.com/b/joelpob/archive/2004/11/17/259224.aspx](http://blogs.msdn.com/b/joelpob/archive/2004/11/17/259224.aspx)
4. My "Generics and Performance" blog entry: [http://www.bluebytesoftware.com/blog/2005/03/23/DGUpdateGenericsAndPerformance.aspx](http://www.bluebytesoftware.com/blog/2005/03/23/DGUpdateGenericsAndPerformance.aspx)

Cheers.

