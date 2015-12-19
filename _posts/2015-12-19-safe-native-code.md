---
layout: post
title: 'Safe Native Code'
date: 2015-12-19 13:03:00.000000000 -08:00
categories: []
tags: []
status: publish
type: post
published: true
author:
  display_name: joeduffy
  first_name: Joe
  last_name: Duffy
  email: joeduffy@acm.org
---
In my [first Midori post](http://joeduffyblog.com/2015/11/03/a-tale-of-three-safeties/), I described how safety was the
foundation of everything we did.  I mentioned that we built an operating system out of safe code, and yet stayed
competetive with operating systems like Windows and Linux written in C and C++.  In many ways, system architecture
played a key role, and I will continue discussing how in future posts.  But, at the foundation, an optimizing compiler
that often eeked out native code performance from otherwise "managed", type- and memory-safe code, was one of our most
important weapons.  In this post, I'll describe some key insights and techniques that were essential to our success.

# Overview

When people think of C#, Java, and related languages, they usually think of [Just-In-Time (JIT) compilation](
https://en.wikipedia.org/wiki/Just-in-time_compilation).  Especially back in the mid-2000s when Midori began.  But
Midori was different, using more C++-like [Ahead-Of-Time (AOT) compilation](
https://en.wikipedia.org/wiki/Ahead-of-time_compilation) from the outset.

AOT compiling managed, [garbage collected code](https://en.wikipedia.org/wiki/Garbage_collection_(computer_science))
presents some unique challenges compared to C and C++.  As a result, many AOT efforts don't achieve parity with their
native counterparts.  .NET's NGEN technology is a good example of this.  In fact, most efforts in .NET have exclusively
targeted startup time; this is clearly a key metric, but when you're building an operating system and everything on top,
startup time just barely scratches the surface.

Over the course of 8 years, we were able to significantly narrow the gap between our version of C# and classical C/C++
systems, to the point where basic code quality, in both size of speed dimensions, was seldom the deciding factor when
comparing Midori's performance to existing workloads.  In fact, something counter-intuitive happened.  The ability to
co-design the language, runtime, frameworks, operating system, and the compiler -- making tradeoffs in one area to gain
advantages in other areas -- gave the compiler far more symbolic information than it ever had before about the program's
semantics and, so, I dare say, was able to exceed C and C++ performance in a non-trivial number of situations.

Before diving deep, I have to put in a reminder.  The architectural decisions -- like [Async Everywhere](
http://joeduffyblog.com/2015/11/19/asynchronous-everything/) and Zero-Copy IO (coming soon) -- had more to do with us
narrowing the gap at a "whole system" level.  Especially the less GC-hungry way we wrote systems code.  But the
foundation of a highly optimizing compiler, that knew about and took advantage of safety, was essential to our results.

I would also be remiss if I didn't point out that the world has made considerable inroads in this area alongside us.
[Go](https://golang.org/) has straddled an elegant line between systems performance and safety.  [Rust](
http://rust-lang.org/) is just plain awesome.  The [.NET Native](
https://msdn.microsoft.com/en-us/vstudio/dotnetnative.aspx) and, related, [Android Runtime](
https://en.wikipedia.org/wiki/Android_Runtime) projects have brought a nice taste of AOT to C# and Java in a more
limited way, as a "silent" optimization technique to avoid mobile application lag caused by JITting.  Lately, we've
been working on bringing AOT to a broader .NET setting with the [CoreRT project](https://github.com/dotnet/corert).
Through that effort I hope we can bring some of the lessons learned below to a real-world setting.  Due to the
delicate balance around breaking changes it remains to be seen how far we can go.  It took us years to get
everything working harmoniously, measured in man-decades, however, so this transfer of knowledge will take time.

First thing's first.  Let's quickly recap: What's the difference between native and managed code, anyway?

## What's the same

I despise the false dichotomy "native and managed," so I must apologize for using it.  After reading this article, I
hope to have convinced you that it's a continuum.  C++ is [safer these days than ever before](
https://github.com/isocpp/CppCoreGuidelines), and likewise, C# performant.  It's amusing how many of these lessons apply
directly to the work my team is doing on Safe C++ these days.

So let's begin by considering what's the same.

All the basic [dragon book](https://en.wikipedia.org/wiki/Principles_of_Compiler_Design) topics apply to managed as
much as they do native code.

In general, compiling code is a balancing act between, on one hand emitting the most efficient instruction sequences
for the target architecture, to execute the program quickly; and on the other hand emitting the smallest encoding of
instructions for the target architecture, to store the program compactly and effectively use the memory system on the
target device.  Countless knobs exist on your favorite compiler to dial between the two based on your scenario.  On
mobile, you probably want smaller code, whereas on a multimedia workstation, you probably want the fastest.

The choice of managed code doesn't change any of this.  You still want the same flexibility.  And the techniques you'd
use to achieve this in a C or C++ compiler are by and large the same as what you use for a safe language.

You need a great [inliner](https://en.wikipedia.org/wiki/Inline_expansion).  You want [common subexpression
elimination (CSE)](https://en.wikipedia.org/wiki/Common_subexpression_elimination), [constant propagation and folding](
https://en.wikipedia.org/wiki/Constant_folding), [strength reduction](https://en.wikipedia.org/wiki/Strength_reduction),
and an excellent [loop optimizer](https://en.wikipedia.org/wiki/Loop_optimization).  These days, you probably want to
use [static single assignment form (SSA)](https://en.wikipedia.org/wiki/Static_single_assignment_form), and some unique
SSA optimizations like [global value numbering](https://en.wikipedia.org/wiki/Global_value_numbering) (although you need
to be careful about working set and compiler throughput when using SSA everywhere).  You will need specialized machine
dependent optimizers for the target architectures that are important to you, including [register allocators](
https://en.wikipedia.org/wiki/Register_allocation).  You'll eventually want a global analyzer that does interprocedural
optimizations, link-time code-generation to extend those interprocedural optimizations across passes, a [vectorizer](
https://en.wikipedia.org/wiki/Automatic_vectorization) for modern processors (SSE, NEON, AVX, etc.), and most definitely
[profile guided optimizations (PGO)](https://en.wikipedia.org/wiki/Profile-guided_optimization) to inform all of the
above based on real-world scenarios.

Although having a safe language can throw some interesting curveballs your way that are unique and interesting -- which
I'll cover below -- you'll need all of the standard optimizing compiler things.

I hate to say it, but doing great at all of these things is "table stakes."  Back in the mid-2000s, we had to write
everything by hand.  Thankfully, these days you can get an awesome off-the-shell optimizing compiler like [LLVM](
http://llvm.org) that has most of these things already battle tested, ready to go, and ready for you to help improve.

## What's different

But, of course, there are differences.  Many.  This article wouldn't be very interesting otherwise.

The differences are more about what "shapes" you can expect to be different in the code and data structures thrown at
the optimizer.  These shapes come in the form of different instruction sequences, logical operations in the code that
wouldn't exist in the C++ equivalent (like more bounds checking), data structure layout differences (like extra object
headers or interface tables), and, in most cases, a larger quantity of supporting runtime data structures.

Objects have "more to them" in most managed languages, compared to frugal data types in, say, C.  (Note that C++ data
structures are not nearly as frugal as you might imagine, and are probably closer to C# than your gut tells you.)  In
Java, every object has a vtable pointer in its header.  In C#, most do, although structs do not.  The GC can impose
extra layout restrictions, such as padding and a couple words to do its book-keeping.  Note that none of this is really
specific to managed languages -- C and C++ allocators can inject their own words too, and of course, many C++ objects
also carry vtables -- however it's fair to say that most C and C++ implementations tend to be more economical in these
areas.  In most cases, for cultural reasons more than hard technical ones.  Add up a few thousand objects in a heap,
especially when your system is built of many small processes with isolated heaps, like Midori, and it adds up quickly.

In Java, you've got a lot more virtual dispatch, because methods are virtual by default.  In C#, thankfully, methods
are non-virtual by default.  (We even made classes sealed by default.)  Too much virtual dispatch can totally screw
inlining which is a critical optimization to have for small functions.  In managed languages you tend to have more
small functions for two reasons: 1) properties, and 2) higher level programmers tend to over-use abstraction.

Although it's seldom described this formally, there's an "ABI" ([Application Binary Interface](
https://en.wikipedia.org/wiki/Application_binary_interface)) that governs interactions between code and the runtime.
The ABI is where the rubber meets the road.  It's where things like calling conventions, exception handling, and, most
notably, the GC manifest in machine code.  This is *not* unique to managed code!  C++ has a "runtime" and therfore an
ABI too.  It's just that it's primarily composed of headers, libraries like allocators, and so on, that are more
transparently linked into a program than with classical C# and Java virtual machines, where a runtime is non-negotiable
(and in the JIT case, fairly heavy-handed).  Thinking of it this way has been helpful to me, because the isomorphisms
with C+ suddenly become immediately apparent.

The real biggie is array bounds checks.  A traditional approach is to check that the index is within the bounds of an
array before accessing it, either for laoding or storing.  That's an extra field fetch, compare, and conditional
branch.  [Branch prediction](https://en.wikipedia.org/wiki/Branch_predictor) these days is quite good, however it's just
plain physics that if you do more work, you're going to pay for it.  Interestingly, the work we're doing with C++'s
`array_view<T>` incurs all these same costs.

Related to this, there can be null checks where they didn't exist in C++.  If you perform a method dispatch on a null
object pointer in C++, for example, you end up running the function anyway.  If that function tries to access `this`,
it's bound to [AV](https://en.wikipedia.org/wiki/Segmentation_fault), but in Java and .NET, the compiler is required
(per specification) to explicitly check and throw an exception in these cases, before the call even occurs.  These
little branches can add up too.  We eradicated such checks in favor of C++ semantics in optimized builds.

In Midori, we compiled with overflow checking on by default.  This is different from stock C#, where you must explicitly
pass the `/checked` flag for this behavior.  In our experience, the number of surprising overflows that were caught,
and unintended, was well worth the inconvenience and cost.  But it did mean that our compiler needed to get really good
at understanding how to eliminate unnecessary ones.

Static variables are very expensive in Java and .NET.  Way more than you'd expect.  They are mutable and so cannot be
stored in the readonly segment of an image where they are shared across processes.  And my goodness, the amount of
lazy-initialization checking that gets injected into the resulting source code is beyond belief.  Switching from
`preciseinit` to `beforefieldinit` semantics in .NET helps a little bit, since the checks needn't happen on every
access to a static member -- just accesses to the static variable in question -- but it's still disgusting compared to
a carefully crafted C program with a mixture of constant and intentional global initialization.

The final major area is specific to .NET: structs.  Although structs help to alleviate GC pressure and hence are a
good thing for most programs, they also carry some subtle problems.  The CLI specifies surprising behavior around their
initialization, for example.  Namely if an exception happens during construction, the struct slot must remain zero-
initialized.  The result is that most compilers make defensive copies.  Another example is that the compiler must
make a defensive copy anytime you call a function on a readonly struct.  It's pretty common for structs to be copied
all over the place which, when you're counting cycles, hurts, especially since it often means time spent in `memcpy`.
We had a lot of techniques for addressing this and, funny enough, I'm pretty sure when all was said and done, our
code quality here was *better* than C++'s, given all of its RAII, copy constructor, destructor, and so on, penalties.

# Compilation Architecture

Our architecture involved three major components:

* [C# Compiler](https://github.com/dotnet/roslyn): Performs lexing, parsing, and semantic analysis.  Ultimately
  translates from C# textual source code into a [CIL](https://en.wikipedia.org/wiki/Common_Intermediate_Language)-based
  [intermediate representation (IR)](https://en.wikipedia.org/wiki/Intermediate_language).
* [Bartok](https://en.wikipedia.org/wiki/Bartok_(compiler)): Takes in said IR, does high-level MSIL-based analysis,
  transformations, and optimizations, and finally lowers this IR to something a bit closer to a more concrete machine
  representation.  For example, generics are gone by the time Bartok is done with the IR.
* [Phoenix](https://en.wikipedia.org/wiki/Phoenix_(compiler_framework)): Takes in this lowered IR, and goes to town on
  it.  This is where the bulk of the "pedal to the metal" optimizations happen.  The output is machine code.

The similarities here with Swift's compiler design, particularly [SIL](
http://llvm.org/devmtg/2015-10/slides/GroffLattner-SILHighLevelIR.pdf), are evident.  The .NET Native project also
mirrors this architecture somewhat.  Frankly, most AOT compilers for high level languages do.

In most places, the compiler's internal representation leveraged [static single assignment form (SSA)](
https://en.wikipedia.org/wiki/Static_single_assignment_form).  SSA was preserved until very late in the compilation.
This facilitated and improved the use of many of the classical compiler optimizations mentioned earlier.

The goals of this architecture included:

* Facilitate rapid prototyping and experimentation.
* Produce high-quality machine code on par with commerical C/C++ compilers.
* Support debugging optimized machine code for improved productivity.
* Facilitate profile-guided optimizations based on sampling and/or instrumenting code.
* Suitable for self-host:
    - The resulting compiled compiler is fast enough.
    - It is fast enough that the compiler developers enjoy using it.
    - It is easy to debug problems when the compiler goes astray.

Finally, a brief warning.  We tried lots of stuff.  I can't remember it all.  Both Bartok and Phoenix existed for years
before I even got involved in them.  Bartok was a hotbed of research on managed languages -- ranging from optimizations
to GC to software transactional memory -- and Phoenix was meant to replace the shipping Visual C++ compiler.  So,
anyway, there's no way I can tell the full story.  But I'll do my best.

# Optimizations

Let's go deep on a few specific areas of classical compiler optimizations, extended to cover safe code.

## Bounds check elimination

C# arrays are bounds checked.  So were ours.  Although it is important to eliminate superfluous bounds checks in regular
C# code, it was even more so in our case, because even the lowest layers of the system used bounds checked arrays.  For
example, where in the bowels of the Windows or Linux kernel you'd see an `int*`, in Midori you'd see an `int[]`.

To see what a bounds check looks like, consider a simple example:

    var a = new int[100];
    for (int i = 0; i < 100; i++) {
        ... a[i] ...;
    }

Here's is an example of the resulting machine code for the inner loop array access, with a bounds check:

    ; First, put the array length into EAX:
    3B15: 8B 41 08        mov         eax,dword ptr [rcx+8]
    ; If EDX >= EAX, access is out of bounds; jump to error:
    3B18: 3B D0           cmp         edx,eax
    3B1A: 73 0C           jae         3B28
    ; Otherwise, access is OK; compute element's address, and assign:
    3B1C: 48 63 C2        movsxd      rax,edx
    3B1F: 8B 44 81 10     mov         dword ptr [rcx+rax*4+10h],r8d
    ; ...
    ; The error handler; just call a runtime helper that throws:
    3B28: E8 03 E5 FF FF  call        2030

If you're doing this bookkeeping on every loop iteration, you won't get very tight loop code.  And you're certianly not
going to have any hope of vectorizing it.  So, we spent a lot of time and energy trying to eliminate such checks.

In the above example, it's obvious to a human that no bounds checking is necessary.  To a compiler, however, the
analysis isn't quite so simple.  It needs to prove all sorts of facts about ranges.  It also needs to know that `a`
isn't aliased and somehow modified during the loop body.  It's surprising how hard this problem quickly becomes.

Our system had multiple layers of bounds check eliminations.

First it's important to note that CIL severely constraints an optimizer by being precise in certain areas.  For example,
accessing an array out of bounds throws an `IndexOutOfRangeException`, similar to Java's `ArrayOutOfBoundsException`.
And the CIL specifies that it shall do so at precisely the exception that threw it.  As we will see later on, our
error model was more relaxed.  It was based fail-fast and permitted code motion that led to inevitable failures
happening "sooner" than they would have otherwise.  Without this, our hands would have been tied for much of what I'm
about to discuss.

At the highest level, in Bartok, the IR is still relatively close to the program input.  So, some simple patterns could
be matched and eliminated.  Before lowering further, the [ABCD algorithm](
http://www.cs.virginia.edu/kim/courses/cs771/papers/bodik00abcd.pdf) -- a straightforward value range analysis based on
SSA -- then ran to eliminate even more common patterns using a more principled approach than pattern matching.  We were
also able to leverage ABCD in the global analysis phase too, thanks to inter-procedural length and control flow fact
propagation.

Next up, the Phoenix Loop Optimizer got its hands on things.  This layer did all sorts of loop optimizations and, most
relevant to this section, range analysis.  For example:

* Loop materialization: this analysis actually creates loops.  It recognizes repeated patterns of code that would be
  more ideally represented as loops, and, when profitable, rewrites them as such.  This includes unrolling hand-rolled
  loops so that a vectorizer can get its hands on them, even if they might be re-unrolled later on.
* Loop cloning, unrolling, and versioning: this analysis creates copies of loops for purposes of specialization.  That
  includes loop unrolling, creating architectural-specific versions of a vectorized loop, and so on.
* [Induction](https://en.wikipedia.org/wiki/Induction_variable) range optimization: this is the phase we are most
  concerned with in this section.  It uses induction range analysis to remove unnecessary checks, in addition to doing
  classical induction variable optimizations such as widening.  As a byproduct of this phase, bounds checks were
  eliminated and coalesced by hoisting them outside of loops.

This sort of principled analysis was more capable than what was shown earlier.  For example, there are ways to write
the earlier loop that can easily "trick" the more basic techniques discussed earlier:

    var a = new int[100];
    
    // Trick #1: use the length instead of constant.
    for (int i = 0; i < a.length; i++) {
        a[i] = i;
    }
    
    // Trick #2: start counting at 1.
    for (int i = 1; i <= a.length; i++) {
        a[i-1] = i-1;
    }
    
    // Trick #3: count backwards.
    for (int i = a.length - 1; i >= 0; i--) {
        a[i] = i;
    }
    
    // Trick #4: don't use a for loop at all.
    int i = 0;
    next:
    if (i < a.length) {
        a[i] = i;
        i++;
        goto next;
    }

You get the point.  Clearly at some point you can screw the optimizer's ability to do anything, especially if you
start doing virtual dispatch inside the loop body, where aliasing information is lost.  And obviously, things get more
difficult when the array length isn't known statically, as in the above example of `100`.  All is not lost, however,
if you can prove relationships between the loop bounds and the array.  Much of this analysis requires special knowledge
of the fact that array lengths in C# are immutable.

At the end of the day, doing a good job at optimizing here is the difference between this:

    ; Initialize induction variable to 0:
    3D45: 33 C0           xor         eax,eax
    ; Put bounds into EDX:
    3D58: 8B 51 08        mov         edx,dword ptr [rcx+8]
    ; Check that EAX is still within bounds; jump if not:
    3D5B: 3B C2           cmp         eax,edx
    3D5D: 73 13           jae         3D72
    ; Compute the element address and store into it:
    3D5F: 48 63 D0        movsxd      rdx,eax
    3D62: 89 44 91 10     mov         dword ptr [rcx+rdx*4+10h],eax
    ; Increment the loop induction variable:
    3D66: FF C0           inc         eax
    ; If still < 100, then jump back to the loop beginning:
    3D68: 83 F8 64        cmp         eax,64h
    3D6B: 7C EB           jl          3D58
    ; ...
    ; Error routine:
    3D72: E8 B9 E2 FF FF  call        2030

And the following, completely optimized, bounds check free, loop:

    ; Initialize induction variable to 0:
    3D95: 33 C0           xor         eax,eax
    ; Compute the element address and store into it:
    3D97: 48 63 D0        movsxd      rdx,eax
    3D9A: 89 04 91        mov         dword ptr [rcx+rdx*4],eax
    ; Increment the loop induction variable:
    3D9D: FF C0           inc         eax
    ; If still < 100, then jump back to the loop beginning:
    3D9F: 83 F8 64        cmp         eax,64h
    3DA2: 7C F3           jl          3D97

It's amusing that I'm now suffering deja vu as we go through this same exercise with C++'s new `array_view<T>` type.
Sometimes I joke with my ex-Midori colleagues that we're destined to repeat ourselves, slowly and patiently, over the
course of the next 10 years.  I know that sounds arrogant.  But I have this feeling on almost a daily basis.

## Overflow checking

As mentioned earlier, in Midori we compiled with checked arithmetic by default (by way of C#'s `/checked` flag).  This
eliminated classes of errors where developers didn't anticipate, and therefore code correctly for, overflows.  Of
course, we kept the explicit `checked` and `unchecked` scoping constructs, to override the defaults when appropriate,
but this was preferable because a programmer declared her intent.

Anyway, as you might expect, this can reduce code quality too.

For comparison, imagine we're adding two variables:

    int x = ...;
    int y = ...;
    int z = x + y;

Now imagine `x` is in `ECX` and `y` is in `EDX`.  Here is a standard unchecked add operation:

    03 C2              add         ecx,edx

Or, if you want to get fancy, one that uses the `LEA` instruction to also store the result in the `EAX` register using
a single instruction, as many modern compilers might do:

    8D 04 11           lea         eax,[rcx+rdx]

Well, here's the equivalent code with a bounds check inserted into it:

    3A65: 8B C1              mov         eax,ecx
    3A67: 03 C2              add         eax,edx
    3A69: 70 05              jo          3A70
    ; ...
    3A70: E8 B3 E5 FF FF     call        2028

More of those damn conditional jumps (`JO`) with error handling routines (`CALL 2028`).

It turns out a lot of the analysis mentioned earlier that goes into proving bounds checks redundant also apply to
proving that overflow checks are redundant.  It's all about proving facts about ranges.  For example, if you can prove
that some check is [dominated by some earlier check](https://en.wikipedia.org/wiki/Dominator_(graph_theory)), and that
furthermore that earlier check is a superset of the later check, then the later check is unnecessary.  If the opposite
is true -- that is, the earlier check is a subset of the later check, then if the subsequent block postdominates the
earlier one, you might move the stronger check to earlier in the program.

Another common pattern is that the same, or similar, arithmetic operation happens multiple times near one another:

    int p = r * 32 + 64;
    int q = r * 32 + 64 - 16;

It is obvious that, if the `p` assignment didn't overflow, then the `q` one won't either.

There's another magical phenomenon that happens in real world code a lot.  It's common to have bounds checks and
arithmetic checks in the same neighborhood.  Imagine some code that reads a bunch of values from an array:

    int data0 = data[dataOffset + (DATA_SIZE * 0)];
    int data1 = data[dataOffset + (DATA_SIZE * 1)];
    int data2 = data[dataOffset + (DATA_SIZE * 2)];
    int data3 = data[dataOffset + (DATA_SIZE * 3)];
    .. and so on ...

Well C# arrays cannot have negative bounds.  If a compiler knows that `DATA_SIZE` is sufficiently small that an
overflowed computation won't wrap around past `0`, then it can eliminate the range check in favor of the bounds check.

There are many other patterns and special cases you can cover.  But the above demonstrates the power of a really good
range optimizer that is integrated with loops optimization.  It can cover a wide array of scenarios, array bounds and
arithmetic operations included.  It takes a lot of work, but it's worth it in the end.

## Inlining

For the most part, [inlining](https://en.wikipedia.org/wiki/Inline_expansion) is the same as with true native code.  And
just as important.  Often more important, due to C# developers' tendency to write lots of little methods (like property
accessors).  Because of many of the topics throughout this article, getting small code can be more difficult than in
C++ -- more branches, more checks, etc. -- and so, in practice, most managed code compilers inline a lot less than
native code compilers, or at least need to be tuned very differently.  This can actually make or break performance.

There are also areas of habitual bloat.  The way lambdas are encoded in MSIL is unintelligable to a naive backend
compiler, unless it reverse engineers that fact.  For example, we had an optimization that took this code:

    void A(Action a) {
        a();
    }

    void B() {
        int x = 42;
        A(() => x++);
        ...
    }

and, after inlining, was able to turn B into just:

    void B() {
        int x = 43;
        ...
    }

That `Action` argument to `A` is a lambda and, if you know how the C# compiler encodes lambdas in MSIL, you'll
appreciate how difficult this trick was.  For example, here is the code for B:

    .method private hidebysig instance void
        B() cil managed
    {
        // Code size       36 (0x24)
        .maxstack  3
        .locals init (class P/'<>c__DisplayClass1' V_0)
        IL_0000:  newobj     instance void P/'<>c__DisplayClass1'::.ctor()
        IL_0005:  stloc.0
        IL_0006:  nop
        IL_0007:  ldloc.0
        IL_0008:  ldc.i4.s   42
        IL_000a:  stfld      int32 P/'<>c__DisplayClass1'::x
        IL_000f:  ldarg.0
        IL_0010:  ldloc.0
        IL_0011:  ldftn      instance void P/'<>c__DisplayClass1'::'<B>b__0'()
        IL_0017:  newobj     instance void [mscorlib]System.Action::.ctor(object,
                                                                      native int)
        IL_001c:  call       instance void P::A(class [mscorlib]System.Action)
        IL_0021:  nop
        IL_0022:  nop
        IL_0023:  ret
    }

To get the magic result required constant propagating the `ldftn`, recognizing how delegate construction works
(`IL_0017`), leveraging that information to inline `B` and eliminate the lambda/delegate altogether, and then, again
mostly through constant propagation, folding the arithmetic into the constant `42` initialization of `x`.  I always
found it elegant that this "fell out" of a natural composition of multiple optimizations with separate concerns.

As with native code, profile guided optimization made our inlining decisions far more effective.

## Structs

CLI structs are almost just like C structs.  Except they're not.  The CLI imposes some semantics that incur overheads.
These overheads almost always manifest as excessive copying.  Even worse, these copies are usually hidden from your
program.  It's worth noting, because of copy constructors and destructors, C++ also has some real issues here, often
even worse than what I'm about to describe.

Perhaps the most annoying is that initializing a struct the CLI way requires a defensive copy.  For example, consider
this program, where the initialzer for `S` throws an exception:

    class Program {
        static void Main() {
            S s = new S();
            try {
                s = new S(42);
            }
            catch {
                System.Console.WriteLine(s.value);
            }
        }
    }

    struct S {
        public int value;
        public S(int value) {
            this.value = value;
            throw new System.Exception("Boom");
        }
    }

The program behavior here has to be that the value `0` is written to the console.  In practice, that means that the
assignment operation `s = new S(42)` must first create a new `S`-typed slot on the stack, construct it, and *then* and
only then copy the value back over the `s` variable.  For single-`int` structs like this one, that's not a huge deal.
For large structs, that means resorting to `memcpy`.  In Midori, we knew what methods could throw, and which could not,
thanks to our error model (more later), which meant we could avoid this overhead in nearly all cases.

Another annoying one is the following:

    struct S {
        // ...
        public int Value { get { return this.value; } }
    }
    
    static readonly S s = new S();

Every single time we read from `s.Value`:

    int x = s.Value;

we are going to get a local copy.  This one's actually visible in the MSIL.  This is without `readonly`:

    ldsflda    valuetype S Program::s
    call       instance int32 S::get_Value()

And this is with it:

    ldsfld     valuetype S Program::s
    stloc.0
    ldloca.s   V_0
    call       instance int32 S::get_Value()

Notice that the compiler elected to use `ldsfld` followed by `lodloca.s`, rather than loading the address directly,
by way of `ldsflda` in the first example.  The resulting machine code is even nastier.  I also can't pass the struct
around by-reference which, as I mention later on, requires copying it and again can be problematic.

We solved this in Midori because our compiler knew about methods that didn't mutate members.  All statics were immutable
to begin with, so the above `s` wouldn't need defensive copies.  Alternatively, or in addition to this, the struct could
have beem declared as `immutable`, as follows:

    immutable struct S {
        // As above ...
    }

Or because all static values were immutable anyway.  Alternatively, the properties or methods in question could have
been annotated as `readable` meaning that they couldn't trigger mutations and hence didn't require defensive copies.

I mentioned by-reference passing.  In C++, developers know to pass large structures by-reference, either using `*` or
`&`, to avoid excessive copying.  We got in the habit of doing the same.  For example, we had `in` parameters, as so:

    void M(in ReallyBigStruct s) {
        // Read, but don't assign to, s ...
    }

I'll admit we probably took this to an extreme, to the point where our APIs suffered.  If I could do it all over again,
I'd go back and eliminate the fundamental distinction between `class` and `struct` in C#.  It turns out, pointers aren't
that bad after all, and for systems code you really do want to deeply understand the distinction between "near" (value)
and "far" (pointer).  We did implement what amounted to C++ references in C#, which helped, but not enough.  More on
this in my upcoming deep dive on our programming language.

## Code size

We pushed hard on code size.  Even more than some C++ compilers I know.

A generic instantiation is just a fancy copy-and-paste of code with some substitutions.  Quite simply, that means an
explosion of code for the compiler to process, compared to what the developer actually wrote.  [I've covered many of the
performance challenges with generics in the past.](
http://joeduffyblog.com/2011/10/23/on-generics-and-some-of-the-associated-overheads/)  A major problem there is the
transitive closure problem.  .NET's straightforward-looking `List<T>` class actually creates 28 types in its transitive
closure!  And that's not even speaking to all the methods in each type.  Generics are a quick way to explode code size.

We learned to be more thoughtful about our use of generics.  For example, types nested inside an outer generic are
usually not good ideas.  We also aggressively shared generic instantiations, even more than [what the CLR does](
http://blogs.msdn.com/b/joelpob/archive/2004/11/17/259224.aspx).  Namely, we shared value type generics, where the
GC pointers were at the same locations.  So, for example, given a struct S:

    struct S {
        int Field;
    }

we would share the same code representation of `List<int>` with `List<S>`.  And, similarly, given:

    struct S {
        object A;
        int B;
        object C;
    }

    struct T {
        object D;
        int E;
        object F;
    }

we would share instantiations between `List<S>` and `List<T>`.

You might not realize this, but C# emits IL that ensures `struct`s have `sequential` layout:

    .class private sequential ansi sealed beforefieldinit S
        extends [mscorlib]System.ValueType
    {
        ...
    }

As a result, we couldn't share `List<S>` and `List<T>` with some hypothetical `List<U>`:

    struct U {
        int G;
        object H;
        object I;
    }

For this, among other reasons -- like giving the compiler more flexibility around packing, cache alignment, and so on
-- we made `struct`s `auto` by default in our language.  Really, `sequential` only matters if you're doing unsafe code,
which, in our programming model, wasn't even legal.

We did not support reflection in Midori.  In principle, we had plans to do it eventually, as a purely opt-in feature.
In practice, we never needed it.  What we found is that code generation was always a more suitable solution.  We shaved
off at least 30% of the best case C# image size by doing this.  Significantly more if you factor in systems where the
full MSIL is retained, as is usually the case, even for NGen and .NET AOT solutions.

In fact, we removed significant pieces of `System.Type` too.  No `Assembly`, no `BaseType`, and yes, even no `FullTime`.
The .NET Framework's mscorlib.dll contains about 100KB of just type names.  Sure, names are useful, but our eventing
framework leveraged code generation to produce just those you actually needed to be around at runtime.

At some point, we realized 40% of our image sizes were [vtable](https://en.wikipedia.org/wiki/Virtual_method_table)s.
We kept pounding on this one relentlessly, and, after all of that, we still had plenty of headroom for improvements.

Each vtable consumes image space to hold pointers to the virtual functions used in dispatch, and of course has a runtime
representation.  Each object with a vtable also has a vtable pointer embedded within it.  So, if you care about size
(both image and runtime), you are going to care about vtables.

In C++, you only get a vtable if you use virtual inheritance.  In languages like C# and Java, you get them even if you
didn't want them.  In C#, at least, you can use a `struct` type to elide them.  I actually love this aspect of Go,
where you get a virtual dispatch-like thing, via interfaces, without needing to pay for vtables on every type; you only
pay for what you use, at the point of coercing something to an interface.

Another vtable problem in C# is that all objects inherit three virtuals from `System.Object`: `Equals`, `GetHashCode`,
and `ToString`.  Besides the point that these generally don't do the right thing in the right way anyways -- `Equals`
requires reflection to work on value types, `GetHashCode` is nondeterministic and stamps the object header (or sync-
block; more on that later), and `ToString` doesn't offer formatting and localization controls -- they also bloat every
vtable by three slots.  This may not sound like much, but it's certainly more than C++ which has no such overhead.

The main source of our remaining woes here was the assumption in C#, and frankly most OOP languages like C++ and Java,
that [RTTI](https://en.wikipedia.org/wiki/Run-time_type_information) is always available for downcasts.  This was
particularly painful with generics, for all of the above reasons.  Although we aggressively shared instantiations, we
could never quite fully fold together the type structures for these guys, even though disparate instantiations tended
to be identical, or at least extraordinarily similar.  If I could do it all over agan, I'd banish RTTI.  In 90% of the
cases, type discriminated unions or pattern matching are more appropriate solutions anyway.

## Profile guided optimizations (PGO)

I've mentioned [profile guided optimization](https://en.wikipedia.org/wiki/Profile-guided_optimization) (PGO) already.
This was a critical element to "go that last mile" after mostly everything else in this article had been made
competetive.  This gave our browser program boosts in the neighborhood of 30-40% on benchmarks like [SunSpider](
https://webkit.org/perf/sunspider/sunspider.html) and [Octane](https://developers.google.com/octane/).

Most of what went into PGO was similar to classical native profilers, with two big differences.

First, we tought PGO about many of the unique optimizations listed throughout this article, such as asynchronous stack
probing, generics instantiations, lambdas, and more.  As with many things, we could have gone on forever here.

Second, we experimented with sample profiling, in addition to the ordinary instrumented profiling.  This is much nicer
from a developer perspective -- they don't need two builds -- and also lets you collect counts from real, live running
systems in the data center.  A good example of what's possible is outlined in [this Google-Wide Profiling (GWP) paper](
http://static.googleusercontent.com/media/research.google.com/en/us/pubs/archive/36575.pdf).

# System Architecture

The basics described above were all important.  But a number of even more impactful areas required deeper architectural
co-design and co-evolution with the language, runtime, framework, and operating system itself.  I've written about [the
immense benefits of this sort of "whole system" approach before](
http://joeduffyblog.com/2014/09/10/software-leadership-7-codevelopment-is-a-powerful-thing/).  It was kind of magical.

## GC

Midori was garbage collected through-and-through.  This was a key element of our overall model's safety and
productivity.  In fact, at one point, we had 11 distinct collectors, each with its own unique characteristics.  (For
instance, see [this study](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.353.9594&rep=rep1&type=pdf).)  We
had some ways to combat the usual problems, like long pause times.  I'll go through those in a future post, however.
For now, let's stick to the realm of code quality.

The first top-level decision is: *conservative* or *precise*?  A conserative collector is easier to wedge into an
existing system, however it can cause troubles in certain areas.  It often needs to scan more of the heap to get the
same job done.  And it can falsely keep objects alive.  We felt both were unacceptable for a systems programming
environment.  It was an easy, quick decision: we sought precision.

Precision costs you something in the code generators, however.  A precise collector needs to get instructions where to
find its root set.  That root set includes field offsets in data structures in the heap, and also places on the stack
or, even in some cases, registers.  It needs to find these so that it doesn't miss an object and erroneously collect it
or fail to adjust a pointer during a relocation, both of which would lead to memory safety problems.  There was no magic
trick to making this efficient other than close integration between runtime and code generator, and being thoughtful.

This brings up the topic of *cooperative* versus *preemptive*, and the notion of GC safe-points.  A GC operating in
cooperative mode will only collect when threads have reached so-called "safe-points."  A GC operating in preemptive
mode, on the other hand, is free to stop threads in their tracks, through preemption and thread suspension, so that it
may force a collection.  In general, preemptive requires more bookkeeping, because the roots must be identifiable at
more places, including things that have spilled into registers.  It also makes certain low-level code difficult to
write, of the ilk you'll probably find in an operating system's kernel, because objects are subject to movement between
arbitrary instructions.  It's difficult to reason about.  (See [this file](
https://github.com/dotnet/coreclr/blob/master/src/vm/eecontract.h), and its associated uses in the CLR codebase, if you
don't believe me.)  As a result, we used cooperative mode as our default.  We experimented with automatic safe-point
probes inserted by the compiler, for example on loop back-edges, but opted to bank the code quality instead.  It did
mean GC "livelock" was possible, but in practice we seldom ran into this.

We used a *generational* collector.  This has the advantage of reducing pause times because less of the heap needs to be
inspected upon a given collection.  It does come with one disadvantage from the code generator's perspective, which is
the need to insert write barriers into the code.  If an older generation object ever points back at a younger generation
object, then the collector -- which would have normally preferred to limit its scope to younger generations -- must know
to look at the older ones too.  Otherwise, it might miss something.

Write barriers show up as extra instructions after certain writes; e.g., note the `call`:

    48 8D 49 08        lea         rcx,[rcx+8]
    E8 7A E5 FF FF     call        0000064488002028

That barrier simply updates an entry in the card table, so the GC knows to look at that segment the next time it scans
the heap.  Most of the time this ends up as inlined assembly code, however it depends on the particulars of the
situation.  See [this code](https://github.com/dotnet/coreclr/blob/master/src/vm/amd64/JitHelpers_Fast.asm#L462) for an
example of what this looks like for the CLR on x64.

It's difficult for the compiler to optimize these away because the need for write barriers is "temporal" in nature.  We
did aggressively eliminate them for stack allocated objects, however.  And it's possible to write, or transform code,
into less barrier hungry styles.  For example, consider two ways of writing the same API:

    bool Test(out object o);
    object Test(out bool b);

In the resulting `Test` method body, you will find a write barrier in the former, but not the latter.  Why?  Because the
former is writing a heap object reference (of type `object`), and the compiler has no idea, when analyzing this method
in isolation, whether that write is to another heap object.  It must be conservative in its analysis and assume the
worst.  The latter, of course, has no such problem, because a `bool` isn't something the GC needs to scan.

Another aspect of GC that impacts code quality is the optional presence of more heavyweight concurrent read and write
barriers, when using concurrent collection.  A concurrent GC does some collection activities concurrent with the user
program making forward progress.  This is often a good use of multicore processors and it can reduce pause times and
help user code make more forward progress over a given period of time.

There are many challenges with building a concurrent GC, however one is that the cost of the resulting barriers is high.
The original [concurrent GC by Henry Baker](
http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.23.5878&rep=rep1&type=pdf) was a copying GC and had the notion
of "old" versus "new" space.  All reads and writes had to be checked and, anything operation against the old space had
to be forwarded to the new space.  Subsequent research for the DEC Firefly used hardware memory protection to reduce the
cost, but the faulting cases were still exceedingly expensive.  And, worst of all, access times to the heap were
unpredictable.  There has been [a lot of good research into solving this problem](
http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.69.1875&rep=rep1&type=pdf), however we abandoned copying.

Instead, we used a concurrent mark-sweep compacting collector.  This means only write barriers are needed under normal
program execution, however some code was cloned so that read barriers were present when programs ran in the presence of
object movement.  Our primary GC guy's research was published (Steensgaard Coco), so you can read all about it.  The CLR
also has a concurrent collector.  It is slightly different.  It uses copying to collect the youngest generation,
mark-sweep for the older ones, and the mark phase is parallelized.  There are unfortunately a few conditions that can
lead to sequential pauses (think of this like a big "lock"), sometimes over 10 milliseconds: 1) all threads must be
halted and scanned, an operation that is bounded only by the number of threads and the size of their stacks; 2) copying
the youngest generation is bounded only by the size of that generation (thankfully, in normal configurations, this is
small); and 3) under worst case conditions, compaction and defragmentation, even of the oldest generation, can happen.

## Separate compilation

The basic model to start with is static linking.  In this model, you compile everything into a single executable.  The
benefits of this are obvious: it's simple, easy to comprehend, conceptually straightforward to service, and less work
for the entire compiler toolchain.  Honestly, given the move to Docker containers as the unit of servicing, this model
makes more and more sense by the day.  But at some point, for an entire operating system, you'll want separate
compilation.  Not just because compile times can get quite long when statically linking an entire operating system, but
also because the working set and footprint of the resulting processes will be bloated with significant duplication.

Separately compiling object oriented APIs is hard.  To be honest, few people have actually gotten it to work.  Problems
include the [fragile base class problem](https://en.wikipedia.org/wiki/Fragile_base_class), which is a real killer for
version resilient libraries.  As a result, most real systems use a dumbed down ["C ABI"](
https://en.wikipedia.org/wiki/Application_binary_interface) at the boundary between components.  This is why Windows,
for example, has historically used flat C Win32 APIs and, even in the shift to more object orientation via WinRT, uses
COM underneath it all.  At some runtime expense, the ObjectiveC runtime addressed this challenge.  As with most things
in computer science, virtually all problems can be solved with an extra level of indirection; [this one can be too](
http://www.sealiesoftware.com/blog/archive/2009/01/27/objc_explain_Non-fragile_ivars.html).

The design pivot we took in Midori was that whole processes were sealed.  There was no dynamic loading, so nothing that
looked like classical DLLs or SOs.  For those scenarios, we used the [Asynchronous Everything](
http://joeduffyblog.com/2015/11/19/asynchronous-everything/) programming model, which made it easy to dynamically
connect to and use separately compiled and versioned processes.

We did, however, want separately compiled binaries, purely as a developer productivity and code sharing (working set)
play.  Well, I lied.  What we ended up with was incrementally compiled binaries, where a change in a root node triggered
a cascading recompilation of its dependencies.  But for leaf nodes, such as applications, life was beautiful.  Over
time, we got smarter in the toolchain by understanding precisely which sorts of changes could trigger cascading
invaliation of images.  A function that was known to never have been inlined across modules, for example, could have its
implementation -- but not its signature -- changed, without needing to trigger a rebuild.  This is similar to the
distinction between headers and objects in a classical C/C++ compilation model.

Our compilation model was very similar to C++'s, in that there was static and dynamic linking.  The runtime model, of
course, was quite different.  We also had the notion of "library groups," which let us cluster multiple logically
distinct, but related, libraries into a single physical binary.  This let us do more aggressive inter-module
optimizations like inlining, devirtualization, async stack optimizations, and more.

## Parametric polymorphism (a.k.a., generics)

That brings me to generics.  They throw a wrench into everything.

The problem is, unless you implement an erasure model -- which stinks performance-wise due to boxing allocations,
indirections, or both -- there's no way for you to possible pre-instantiate all possible versions of the code.  For
example, say you're providing a `List<T>`.  How do you know whether folks using your library will want a `List<int>`,
`List<string>`, or `List<SomeStructYouveNeverHeardOf>`?

Solutions abound:

1. Do not specialize.  Erase everything.
2. Specialize only a subset of instantiations, and create an erased instantiation for the rest.
3. Specialize everything.  This gives the best performance, but at some complexity.

Java uses #1 (in fact, erasure is baked into the language).  Many ML compilers use #2.  As with everything in Midori,
we picked the hardest path, with the most upside, which meant #3.  Actually I'm being a little glib; we had several ML
compiler legends on the team, and #2 is fraught with peril; just dig a little into [some papers](
http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.98.2165&rep=rep1&type=pdf) on how hard this can get, since it's
difficult to know a priori which instantiations are going to be performance critical to a program.

Anyway, Midori's approach turned out to be harder than it sounded at first.

Imagine you have a diamond.  Library A exports a `List<T>` type, and libraries B and C both instantiate `List<int>`.  A
program D then consumes both B and C and maybe even passes `List<T>` objects returned from one to the other.  How do we
ensure that the versions of `List<int>` are compatible?

We called this problem the *potentially multiply instantiated*, or PMI for short, problem.

The CLR handles this problem by unifying the instantiations at runtime.  All RTTI data structures, vtables, and whatnot,
are built and/or aggressively patched at runtime.  In Midori, on the other hand, we wanted all such data structures to
be in readonly data segments and hence shareable across processes, wherever possible.

Again, everything can be solved with an indirection.  But unlike solution #2 above, solution #3 permits you to stick
instantiations only in the rare places where you need them.  And for purposes of this one, that meant RTTI and accessing
static variables of just those generic types that might have been subject to PMI.  First, that affected a vast subset of
code (versus #2 which generally affects even loading of instance fields).  Second, it could be optimized away for
instantiations that were known not to be PMI, by attaching state and operations to the existing generic dictionary that
was gets passed around as a hidden argument already.  And finally, because of all of this, it was pay for play.

But damn was it complex.

It's funny, but C++ RTTI for template instantiations actually suffers from many of the same problems.  In fact, the
Microsoft Visual C++ compiler resorts to a `strcmp` of the type names, to resolve diamond issues!  (Thankfully there are
well-known, more efficient ways to do this, which we are actively pursuing for the next release.)

## Virtual dispatch

Although I felt differently when first switching from Java to C#, Midori made me love that C# made methods non-virtual
by default.  I'm sure we would have had to change this otherwise.  In fact, we went even further and made classes
`sealed` by default, requiring that you explicitly mark them `virtual` if you wanted to facilitate subclasses.

Aggressive devirtualization, however, was key to good performance.  Each virtual means an indirection.  And more
impactfully, a lost opportunity to inline (which for small functions is essential).  We of course did global
intra-module analysis to devirtualize, but also extended this across modules, using whole program compilation, when
multiple binaries were grouped together into a library group.

Although our defaults were right, m experience with C# developers is that they go a little hog-wild with virtuals and
overly abstract code.  I think the ecosystem of APIs that exploded around highly polymorphic abstractions, like LINQ and
Reactive Extensions, encouraged this and instilled lots of bad behavior.  As you can guess, there wasn't very much of
that floating around our codebase.  A strong culture around identifying and trimming excessive fat helped keep this in
check, via code reviews, benchmarks, and aggressive static analysis checking.

Interfaces were a challenge.

There are just some poorly designed, inefficient patterns in the .NET Framework.  `IEnumerator<T>` requires *two*
interface dispatches simply to extract the next item!  Compare that to C++ iterators which can compile down a pointer
increment plus dereference.  Many of these problems could be addressed simply with better library designs.  (Our final
design for enumeration didn't even invole interfaces at all.)

Plus invoking a C# interface is tricky.  Existing systems do not use pointer adjustment like
C++ does so usually an interface dispatch requires a table search.  First a level of indirection to get to the vtable,
then another level to find the interface table for the interface in question.  Some systems attempt to do callsite
caching for monomorphic invocations; that is, caching the latest invocation in the hope that the same object kind passes
through that callsite time and time again.  This requires mutable stubs, however, not to mention an [incredibly complex
system of thunks and whatnot](https://github.com/dotnet/coreclr/blob/master/src/vm/virtualcallstub.cpp).  In Midori, we
never ever ever violated [W^X](https://en.wikipedia.org/wiki/W%5EX); and we avoided mutable runtime data structures,
because they inhibit sharing, both in terms of working set, but also amortizing TLB and data cache pressure.

Our solution took advantage of the memory ordering model earlier.  We used so-called "fat" interface pointers.  A fat
interface pointer was two words: the first, a pointer to the object itself; the second, a pointer to the interface
vtable for that object.  This made conversion to interfaces slightly slower -- because the interface vtable lookup had
to happen -- but for cases where you are invoking it one or more times, it came out a wash or ahead.  Usually,
significantly.  Go does something like this, but it's slightly different for two reasons.  First, they generate the
interface tables on the fly, because interfaces are duck typed.  Second, fat interface pointers are subject to tearing
and hence can violate memory safety in Go, unlike Midori thanks to our strong concurrency model.

The finally challenge in this category was *generic virtual methods*, or GVMs.  To cut to the chase, we banned them.
Even if you NGen an, image in .NET, all it takes is a call to the LINQ query `a.Where(...).Select(...)`, and you're
pulling in the JIT compiler.  Even in .NET Native, there is considerable runtime data structure creation, lazily, when
this happens.  In short, there is no known way to AOT compile GVMs in a way that is efficient at runtime.  So, we didn't
even bother offering them.  This was a slightly annoying limitation on the programming model but I'd have done it all
over again thanks to the efficiencies that it bought us.  It really is surprising how many GVMs are lurking in .NET.

## Statics

I was astonished the day I learned that 10% of our code size was spent on static initialization checks.

Many people probably don't realize that the [CLI specification](
http://www.ecma-international.org/publications/standards/Ecma-335.htm) offers two static initialization modes.  There
is the default mode and `beforefieldinit`.  The default mode is the same as Java's.  And it's horrible. The static
initializer will be run just prior to accessing any static field on that type, any static method on that type, any
instance or virtual method on that type (if it's a value type), or any constructor on that type.  The "when" part
doesn't matter as much as what it takes to make this happen; *all* of those places now need to be guarded with explicit
lazy initialization checks in the resulting machine code!

The `beforefieldinit` relaxation is weaker.  It guarantees the initializer will run sometime before actually accessing
a static field on that type.  This gives the compiler a lot of leeway in deciding on this placement.  Thankfully the
C# compiler will pick `beforefieldinit` automatically for you should you stick to using field initializers only.  Most
people don't realize the incredible cost of choosing instead to use a static constructor, however, especially for value
types where suddenly all method calls now incur initialization guards.  It's just the difference between:

    struct S {
        static int Field = 42;
    }

and:

    struct S {
        static int Field;
        static S() {
            Field = 42;
        }
    }

Now imagine the struct has a property:

    struct S {
        // As above...
        int InstanceField;
        public int Property { get { return InstanceField; } }
    }

Here's the machine code for `Property` if `S` has no static initializer, or uses `beforefieldinit` (automatically
injected by C# in the the field initializer example above):

    ; The struct is one word; move its value into EAX, and return it:
    8B C2                mov         eax,edx
    C3                   ret

And here's what happens if you add a class constructor:

    ; Big enough to get a frame:
    56                   push        rsi
    48 83 EC 20          sub         rsp,20h
    ; Load the field into ESI:
    8B F2                mov         esi,edx
    ; Load up the cctor's initialization state:
    48 8D 0D 02 D6 FF FF lea         rcx,[1560h]
    48 8B 09             mov         rcx,qword ptr [rcx]
    BA 03 00 00 00       mov         edx,3
    ; Invoke the conditional initialization helper:
    E8 DD E0 FF FF       call        2048
    ; Move the field from ESI into EAX, and return it:
    8B C6                mov         eax,esi
    48 83 C4 20          add         rsp,20h
    5E                   pop         rsi

On every property access!

Of course, all static members still incur these checks, even if `beforefieldinit` is applied.

Although C++ doesn't suffer this same problem, it does have mind-bending [initialization ordering semantics](
http://en.cppreference.com/w/cpp/language/initialization).  And, like C# statics, C++11 introduced thread-safe
initialization, by way of the ["magic statics" feature](
http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2008/n2660.htm).

We virtually eliminated this entire mess in Midori.

I mentioned offhandedly earlier that Midori had no mutable statics.  More accurately, we extended the notion of `const`
to cover any kind of object.  This meant that static values were evaluated at compile-time, written to the readonly
segment of the resulting binary image, and shared across all processes.  More importantly for code quality, all runtime
initialization checks were removed, and all static accesses simply replaced with a constant address.

There were still mutable statics at the core of the system -- in the kernel, for example -- but these did not make their
way up into user code.  And because they were few and far between, we did not rely on the classical C#-style lazy
initialization checks for them.  They were manually initialized on system startup.

As I said earlier, a 10% reduction in code size, and lots of speed improvements.  It's hard to know exactly how much
saved this was than a standard C# program because by the time we made the change, developers were well aware of the
problems and liberally applied our `[BeforeFieldInit]` attribute all over their types, to avoid some of the overheads.
So the 10% number is actually a lower bound on the savings we realized throughout this journey.

## Async model

I already wrote a lot about [our async model](http://joeduffyblog.com/2015/11/19/asynchronous-everything/).  I won't
rehash all of that here.  I will reiterate one point: the compiler was key to making linked stacks work.

In a linked stacks model, the compiler needs to insert probes into the code that check for available stack space.  In
the event there isn't enough to perform some operation -- make a function call, dynamically allocate on the stack, etc.
-- the compiler needs to arrange for a new link to get appended, and to switch to it.  Mostly this amounts to some
range checking, a conditional call to a runtime function, and patching up `RSP`.  A probe looked something like:

    ; Check amount of stack space:
        lea     rax, [rsp-250h]
        cmp     rax, qword ptr gs:[0]
        ja      prolog
    ; If insufficient stack, link a new segment:
        mov     eax, 10029h
        call    ?g_LinkNewStackTrampoline
    prolog:
    ; The real code goes here...

Needless to say, you want to probe as little as possible, for two reasons.  First, they incur runtime expense.  Second,
they chew up code size.  There are a few techniques we used to eliminate probes.

The compiler of course knew how to compute stack usage of functions.  As a result, it could be smart about the amount of
memory to probe for.  We incorporated this knowledge into our global analyzer.  We could coalesce checks after doing
code motion and inlining.  We hoisted checks out of loops.  For the most part, we optimized for eliminating checks,
sometimes at the expense of using a little more stack.

The most effective technique we used to eliminate probes was to run synchronous code on a classical stack, and to teach
our compiler to elide probes altogether for them.  This took advantage of our understanding of async in the type system.
Switching between the classical stack and back again again amounted to twiddling `RSP`:

    ; Switch to the classical stack:
    move    rsp, qword ptr gs:[10h]
    sub     rsp, 20h

    ; Do some work (like interop w/ native C/C++ code)...

    ; Now switch back:
    lea     rsp, [rbp-50h]

I know Go abandoned linked stacks because of these switches.  At first they were pretty bad for us, however after about
a man year or two of effort, the switching time faded away into the sub-0.5% noise.

## Memory ordering model

Midori's stance on [safe concurrency](http://joeduffyblog.com/2015/11/03/a-tale-of-three-safeties/) had truly one
amazing benefit: you get a [sequentially consistent](https://en.wikipedia.org/wiki/Sequential_consistency) memory
ordering model *for free*.  You may wish to read that again.  Incredible!

Why is this so?  First, Midori's [process model](http://joeduffyblog.com/2015/11/19/asynchronous-everything/) ensured
single-threaded execution by default.  Second, any fine-grained parallelism inside of a process was governed by a finite
number of APIs, all of which were race-free.  The lack of races meant we could inject a fence at fork and join points,
selectively, without a developer needing to care or know.

Obviously this had incredible benefits to developer productivity.  The fact that Midori programmers never got bitten by
memory reordering problems was certainly one of my proudest outcomes of the project.

But it also meant the compiler was free to make [more aggressive code motion optimizations](
https://www.cs.princeton.edu/courses/archive/fall10/cos597C/docs/memory-models.pdf), without any sacrifices to this
highly productive programming model.  In other words, we got the best of both worlds.

A select few kernel developers had to think about the memory ordering model of the underlying machine.  These were the
people implementing the async model itself.  For that, we eliminated C#'s notion of `volatile` -- which is [utterly
broken anyway](http://joeduffyblog.com/2010/12/04/sayonara-volatile/) -- in favor of something more like C++
[`atomic`s](http://en.cppreference.com/w/cpp/atomic).  That model is quite nice for two reasons.  First, what kind of
fence you need is explicit for every read and write, where it actually matters.  (ences affect the uses of a variable,
not its declaration.  Second, the explicit model tells the compiler more information about what optimizations can or
cannot take place, again at a specific uses, where it matters most.

## Error model

Our error model journey was a long one and will be the topic of a future post.  In a nutshell, however, we experimented
with two ends of the spectrum -- exceptions and return codes -- and lots of points in betweeen.

Here is what we found from a code quality perspective.

Return codes are nice because the type system tells you an error can happen.  A developer is thus forced to deal with
them (provided they don't ignore return values).  Return codes are also simple, and require far less "runtime magic"
than exceptions or related mechanisms like setjmp/longjmp.  So, lots to like here.

From a code quality persective, however, return codes suck.  They force you to execute instructions in hot paths that
wouldn't have otherwise been executed, including when errors aren't even happening.  You need to return a value from
your function -- occupying register and/or stack space -- and callers need to perform branches to check the results.
Granted, we hope that these are predicted correctly, but the reality is, you're just doing more work.

Untyped exceptions suck when you're trying to build a reliable system.  Operating systems need to be reliable.  Not
knowing that there's a hidden control flow path when you're calling a function is, quite simply, unacceptable.  They
also require heavier weight runtime support to unwind stacks, search for handlers, and so on.  It's also a bitch to
model exceptional control flow in the compiler.  (If you don't believe me, just read through [this mail exchange](
http://lists.llvm.org/pipermail/llvm-dev/2015-May/085843.html).  So, lots to hate here.

Typed exceptions -- I got used to not saying checked exceptions for fear of hitting Java nerves -- address some of these
shortcomings, but come with their own challenges.  Again, I'll save detailed analysis for my future post.

From a code quality perspective, exceptions can be nice.  First, you can organize code segments so that the "cold"
handlers aren't dirtying your ICACHE on successful pathways.  Second, you don't need to perform any extra work during
the normal calling convention.  There's no wrapping of values -- so no extra register or stack pressure -- and there's
no branching in callers.  There can be some downsides to exceptions, however.  In an untyped model, you must assume
every function can throw, which obviously inhibits your ability to move code around.

Our model ended up being a hybrid of two things:

* [Fail-fast](http://joeduffyblog.com/2014/10/13/if-youre-going-to-fail-do-it-fast/) for programming bugs.
* Typed exceptions for dynamically recoverable errors.

I'd say the ratio of fail-fast to typed exceptions usage ended up being 10:1.  Exceptions were generally used for I/O
and things that dealt with user data, like the shell and parsers.  Contracts were the biggest source of fail-fast.

The result was the best possible configuration of the above code quality attributes:

* No calling convention impact.
* No peanut butter associated with wrapping return values and caller branching.
* All throwing functions were known in the type system, enabling more flexible code motion.
* All throwing functions were known in the type system, giving us novel EH optimizations, like turning try/finally
  blocks into straightline code when the try could not throw.

A nice accident of our model was that we could have compiled it with either return codes or exceptions.  Thanks to this,
we actually did the experiment, to see what the impact was to our system's size and speed.  The exceptions-based system
ended up being roughly 7% smaller and 4% faster on some key benchmarks.

At the end, what we ended up with was the most robust error model I've ever used, and certainly the most performant one.

## Contracts

As implied above, Midori's programming language had first class contracts:

    void Push(T element)
        requires element != null
        ensures this.Count == old.Count + 1
    {
            ...
    }

The model was simple:

* By default, all contracts are checked at runtime.
* The compiler was free to prove contracts false, and issue compile-time errors.
* The compiler was free to prove contracts true, and remove these runtime checks.

We had conditional compilation modes, however I will skip these for now.  Look for an upcoming post on our language.

In the early days, we experimented with contract analyzers like MSR's [Clousot](
http://research.microsoft.com/pubs/138696/Main.pdf), to prove contracts.  For compile-time reasons, however, we had to
abandon this approach.  It turns out compilers are already very good at doing simple constraint solving and propagation.
So eventually we just modeled contracts as facts that the compiler knew about, and let it insert the checks wherever
necessary.

For example, the loop optimizer complete with range information above can already leverage checks like this:

    void M(int[] array, int index) {
        if (index >= 0 && index < array.Length) {
            int v = array[index];
            ...
        }
    }

to eliminate the redundant bounds check inside the guarded if statement.  So why not also do the same thing here?

    void M(int[] array, int index)
            requires index >= 0 && index < array.Length {
        int v = array[index];
        ...
    }

These facts were special, however, when it comes to separate compilation.  A contract is part of a method's signature,
and our system ensured proper [subtyping substitution](https://en.wikipedia.org/wiki/Liskov_substitution_principle),
letting the compiler do more aggressive optimizations at separately compiled boundaries.  And it could do these
optimizations faster because they didn't depend on global analysis.

## Objects and allocation

In a future post, I'll describe in great detail our war with the garbage collector.  One technique that helped us win,
however, was to aggressively reduce the size and quantity of objects a well-behaving program allocated on the heap.
This helped with overall working set and hence made programs smaller and faster.

The first technique here was to shrink object sizes.

In C# and most Java VMs, objects have headers.  A standard size is a single word, that is, 4 bytes on 32-bit
architectures and 8 bytes on 64-bit.  This is in addition to the vtable pointer.  It's typically used by the GC to mark
objects and, in .NET, is used for random stuff, like COM interop, locking, memozation of hash codes, and more.  (Even
[the source code calls it the "kitchen sink"](https://github.com/dotnet/coreclr/blob/master/src/vm/syncblk.h#L29).)

Well, we ditched both.

We didn't have COM interop.  There was no unsafe free-threading so there was no locking (and [locking on random objects
is a bad idea anyway](TODO)).  Our `Object` didn't define a `GetHashCode`.  Etc.  This saved a word per object with no
discernable loss in the programming model, which is nothing to shake a stick at.

At that point, the only overhead per object was the vtable pointer.  For structs, of course there wasn't one (unless
they were boxed), and we did our best to eliminate these too.  Sadly, due to RTTI, it was difficult to be aggressive.  I
think this is another area where I'd go back and entirely upend the C# type system, to follow a more C, C++, or even
maybe Go-like, model.  In the end, however, I think we did get to be fairly competetive with your average C++ program.

There were padding challenges.  Switching the `struct` layout from C#'s current default of `sequential`, to our
preferred default of `auto`, certainly helped.  As did optimizations like the well-known C++ [empty base optimization](
http://en.cppreference.com/w/cpp/language/ebo).

We also did aggressive escape analysis in order to more efficiently allocate objects.  If an object was found to be
stack-confined, it was allocated on the stack instead of the heap.  Our initial implementation of this moved somewhere
in the neighborhood of 10% static allocations from the heap to the stack, and let us be far more aggressive about
pruning back the size of objects, eliminating vtable pointers and entire unused fields.  Given how conservative this
analysis had to be, I was pretty happy with these results.

We offered a hybrid between C++ references and Rust borrowing if developers wanted to give the compiler a hint while at
the same time semantically enforcing some level of containment.  For example, say I wanted to allocate a little array to
share with a callee, but know for sure the callee does not remember a reference to it.  This was as simple as saying:

    void Caller() {
        Callee(new[] { 0, 1, ..., 9 });
    }

    void Callee(int[]& a) {
        ... guaranteed that `a` does not escape ...
    }

The compiler used the `int&` information to stack allocate the array and, often, eliminating the vtable for it entirely.
Coupled with the sophisticated elimination of bounds checking, this gave us something far closer to C performance.

Lambdas/delegates in our system were also structs, so did not require heap allocation.  The captured display frame was
subject to all of the above, so frequently we could stack allocate them.  As a result, the following code was heap
allocation-free; in fact, thanks to some early optimizations, if the callee was inlined, it ran as though the actual
lambda body was merely expanded as a sequence of instructions, with no call over head either!

    void Caller() {
        Callee(() => ... do something ... );
    }

    void Callee(Action& callback) {
        callback();
    }

In my opinion, this really was the killer use case for the borrowing system.  Developers avoided lambda-based APIs in
the early days before we had this feature for fear of allocations and inefficiency.  After doing this feature, on the
other hand, a vibrant ecosystem of expressive lambda-based APIs flourished.

# Throughput

All of the above have to do with code quality; that is, the size and speed of the resulting code.  Another important
dimension of compiler performance, however, is *throughput*; that is, how quickly you can compile the code.  Here too
a language like C# comes with some of its own challenges.

The biggest challenge we encountered has less to do with the inherently safe nature of a language, and more to do with
one very powerful feature: parametric polymorphism.  Or, said less pretentiously, generics.

I already mentioned earlier that generics are just a convenient copy-and-paste mechanism.  And I mentioned some
challenges this poses for code size.  It also poses a problem for throughput, however.  If a `List<T>` instantiation
creates 28 types, each with its own handful of methods, that's just more code for the compiler to deal with.  Separate
compilation helps, however as also noted earlier, generics often flow across module boundaries.  As a result, there's
likely to be a non-trivial impact to compile time.  Indeed, there was.

In fact, this is not very different from where most C++ compilers spend the bulk of their time.  In C++, it's templates.
More modern C++ code-bases have similar problems, due to heavy use of templated abstractions, like STL, smart pointers,
and the like.  Many C++ code-bases are still just "C with classes" and suffer this problem less.

As I mentioned earlier, I wish we had banished RTTI.  That would have lessened the generics problem.  But I would guess
generics still would have remained our biggest throughput challenge at the end of the day.

The funny thing -- in a not-so-funny kind of way -- is that you can try to do analysis to prune the set of generics and,
though it is effective, this analysis takes time.  The very thing you're trying to save.

A metric we got in the habit of tracking was how much slower AOT compiling a program was than simply C# compiling it.
This was a totally unfair comparison, because the C# compiler just needs to lower to MSIL whereas an AOT compler needs
to produce machine code.  It'd have been fairer to compare AOT compiling to JIT compiling.  But no matter, doing a great
job on throughput is especially important for a C# audience.  The expectation of productivity was quite high.  This was
therefore the key metric we felt customers would judge us on, and so we laser-focused on it.

In the early days, the number was ridiculously bad.  I remember it being 40x slower.  After about a year and half with
intense focus we got it down to *3x for debug builds* and *5x for optimized builds*.  I was very happy with this!

There was no one secret to achieving this.  Mostly it had to do with just making the compiler faster like you would any
program.  Since we built the compiler using Midori's toolchain, however -- and compiled it using itself -- often this
was done by first making Midori better, which then made the the compiler faster.  It was a nice virtuous loop.  We had
real problems with string allocations which informed what to do with strings in our programming model.  We found crazy
generics instantiation closures which forced us to eliminate them and build tools to help find them proactively.  Etc.

# Culture

A final word before wrapping up.  Culture was the most important aspect of what we did.  Without the culture, such an
amazing team wouldn't have self-selected, and wouldn't have relentlessly pursued all of the above achievements.  I'll
devote an entire post to this.  However, in the context of compilers, two things helped:

1. We measured everything in the lab.  "If it's not in the lab, it's dead to me."
2. We reviewed progress early and often.  Even in areas where no progress was made.  We were habitually self-critical.

Every sprint, we had a so-called "CQ Review" (where CQ stands for "code quality").  The compiler team prepared for a few
days, by reviewing every benchmark -- ranging from the lowest of microbenchmarks to compiling and booting all of Windows
-- and investigating any changes.  All expected wins were confirmed (we called this "confirming your kill"), any
unexpected regressions were root cause analyzed (and bugs filed), and any wins that didn't materialize were also
analyzed and reported on so that we could learn from it.  We even stared at numbers that didn't change, and asked
ourselves, why didn't they change.  Was it expected?  Do we feel bad about it and, if so, how will we change next
sprint?  We reviewed our competitors' latest compiler drops and monitored their rate of change.  And so on.

This process was enormously healthy.  Everyone was encouraged to be self-critical.  This was not a "witch hunt"; it was
an opportunity to learn as a team how to do better at achieving our goals.

I'm surprised at how contentious this can be with some folks.  They get threatened and worry their lack of progress
makes them look bad.  They say "the numbers aren't changing because that's not our focus right now," however in my
experience, so long as the code is changing, the numbers are changing.  It's best to keep your eye on them lest you get
caught with your pants around your ankles many months later when it suddenly matters most.

This process was as much our secret sauce as anything else was.

# Wrapping Up

Whew, that was a lot of ground to cover.  I hope at the very least it was interesting, and I hope for the incredible
team who built all of this that I did it at least a fraction of justice.  (I know I didn't.)

This journey took us over a decade, particularly if you account for the fact that both Bartok and Phoenix had existed
for many years even before Midori formed.  Merely AOT compiling C#, and doing it well, would have netted us many of the
benefits above.  But to truly achieve the magical native-like performance, and indeed even exceed it in certain areas,
required some key "whole system" architectural bets.  I hope that some day we can deliver safety into the world at this
level of performance.  Given the state of security all-up in the industry, the world at large seriously needs it.

I've now touched on our programming languages enough that I need to go deep on it.  Tune in next time!

