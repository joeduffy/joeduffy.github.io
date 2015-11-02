---
layout: post
title: On partially-constructed objects
date: 2010-06-27 12:52:29.000000000 -07:00
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
Partially-constructed objects are a constant source of difficulty in object-oriented
systems. These are objects whose construction has not completed in its entirety prior
to another piece of code trying to use them. Such uses are often error-prone, because
the object in question is likely not in a consistent state. Because this situation
is comparatively rare in the wild, however, most people (safely) ignore or remain
ignorant of the problem. Until one day they get bitten.

Not only are partially-constructed objects a source of consternation for everyday
programmers, they are also a challenge for language designers wanting to provide
guarantees around invariants, immutability and concurrency-safety, and non-nullability.
We shall see examples below why this is true. The world would be better off if partially-constructed
objects did not exist. Thankfully there is some interesting prior art that moves
us in this direction from which to learn.

# Seeing such a beast in the wild

In what situations might you see a partially-constructed object? There are two common
ones in C++ and C#:

- 'this' is leaked out of a constructor to some code that assumes the object
has been initialized.
- A failure partway through an object's construction leads to its destructor or
finalizer running against a partially-constructed object.

In the first case, the rule of thumb is "don't do that." This is easier said
than done. The second case, on the other hand, is a fact of life, and the rule of
thumb is "tread with care, and be intentional." Let's examine both more closely.

## The evils of leaking 'this'

Leaking 'this' during construction to code that expects to see a fully-initialized
object is a terrible practice. Before moving on, it's important to remember initialization
order in C++ and C#: base constructors run first, and then more derived constructors.
If I have E subclasses D subclasses C, then constructing an instance of E will run
C's constructor, and then D's, and then lastly E's. Destructors in C++, of
course, run in the reverse order.

Member initializers, on the other hand, run in different orders in C++ versus C#.
In C#, they run from most derived first, to least derived. So in the above situation,
E's initializers run, and then D's, and then C's. This happens fully before
running the ad-hoc constructor code. In C++, however, member initializers run alongside
the ordinary construction process. C's member initializers run just before C's
ad-hoc construction code, and then D's, and then E's. Another difference is that
C#'s initializers cannot access 'this', whereas C++'s initializers can.

For example, this C# program will print E\_init, D\_init, C\_init, C\_ctor, D\_ctor,
and then E\_ctor:

```
using System;
    class C {
        int x = M();

        public C() {
            Console.WriteLine("C_ctor");
        }

        private static int M() {
            Console.WriteLine("C_init");
            return 42;
        }
    }

    class D : C {
        int x = M();

        public D() : base() {
            Console.WriteLine("D_ctor");
        }

        private static int M() {
            Console.WriteLine("D_init");
            return 42;
        }
    }

    class E : D {
        int x = M();

        public E() : base() {
            Console.WriteLine("E_ctor");
        }

        private static int M() {
            Console.WriteLine("E_init");
            return 42;
        }
    }

    class Program {
        public static void Main() {
            new E();
        }
    }
```

And this C++ program will print C\_init, C\_ctor, D\_init, D\_ctor, E\_init, E\_ctor,
~E, ~D, and finally ~C:

```
#include <iostream>
using namespace std;

struct C {
    int x;
    C() : x(M()) { cout << "C_ctor" << endl;   }
    ~C() { cout << "~C" << endl; }
    static int M() { cout << "C_init" << endl; return 42; }
};

struct D : C {
   int x;
    D(): x(M()) { cout << "D_ctor" << endl; }
    ~D() { cout << "~D" << endl; }
    static int M() { cout << "D_init" << endl; return 42; }
};

struct E : D {
   int x;
    E() : x(M()) { cout << "E_ctor" << endl; }
    ~E() { cout << "~E" << endl; }
    static int M() { cout << "E_init" << endl; return 42; }
};

static void main() {
    E e;
}
```

It's interesting to note that the CLR allows constructor chaining to happen in
any order. The C# compiler emits the calls to base as the first thing a constructor
does, but other languages can choose to do differently. The verifier ensures that
a call has occurred somewhere in the constructor body before returning.

This IL program, for example, will print E, D, and then C -- the reverse of what
C# gives us:

```
.assembly extern mscorlib { }
.assembly ctor { }

.class C {
  .method public specialname rtspecialname instance void .ctor() cil managed {
    ldstr      "C"
    call       void [mscorlib]System.Console::WriteLine(string)
    ldarg.0
    call       instance void [mscorlib]System.Object::.ctor()
    ret
  }
}

.class D extends C {
  .method public specialname rtspecialname instance void .ctor() cil managed {
    ldstr      "D"
    call       void [mscorlib]System.Console::WriteLine(string)
    ldarg.0
    call       instance void C::.ctor()
    ret
  }
}

.class E extends D {
  .method public specialname rtspecialname instance void .ctor() cil managed {
    ldstr      "E"
    call       void [mscorlib]System.Console::WriteLine(string)
    ldarg.0
    call       instance void D::.ctor()
    ret
  }
}

.class Program {
  .method public static void Main() cil managed {
    .entrypoint
    newobj     instance void E::.ctor()
    pop
    ret
  }
}
```

So why is leaking 'this' bad, anyway?

Say you've decided in the implementation of D's constructor that you would like
to stick 'this' into a global hash-map. Doing this sadly means other code could
grab the pointer and begin accessing it before E's constructor has even run. That
is a race at-best and a ticking time-bomb in all likelihood. For example:

```
class C {
    public static Dictionary s_globalLookup;
    private readonly int m_key;
    public C(int key) {
        m_key = key;
        s_globalLookup.Add(key, this);
    }
}
```

Even though we have taken great care to initialize our readonly field m\_key before
sticking 'this' into a dictionary, any subclasses will not have been initialized
at this point. Only if C is sealed can we be assured of this. Another piece of code
that grabs the element out of the hashtable and begins calling virtual methods on
it, for example, is in a race with the completion of the initialization code for
subclasses.

Leaking 'this' isn't always such an explicit act. Merely invoking a virtual
method within the constructor may dispatch a more derived class's override before
the more derived class's constructor has run. And therefore its state is most likely
not in a place conducive to correct execution of that override. It is fairly common
knowledge that invoking virtual methods during construction is an extraordinarily
poor practice, and best avoided.

## Failure to construct

Let's move on to the second issue. Imagine we suffer an exception during construction
of an object. Perhaps this is due to a failure to allocate resources, or maybe even
due to argument validation. It is clear that a leaked 'this' object in such cases
will be a problem, because the object will have escaped into the wild even though
its initialization failed. Subsequent attempts to use the object will obviously pose
problems. What is more subtle is that if the class in question declares a destructor
(in C++) or finalizer (in C#), a problem may now be lurking.

Let's say we have the original situation shown above: C derives from D derives
from E. Now say an exception happens within D's constructor. At this point in time,
C's constructor has run to completion, D's constructor has run partially up to
the point of failure, and E's has not run at all. (And, of course, in the case
of C#, all member-initializers for all classes have actually run.) What happens to
the cleanup code?

In C++, only constructors that have run will have their corresponding destructors
executed. In the above situation, where C, D, and E each declares a destructor, only
C's will be run during stack unwind. It is imperative, therefore, that D handles
failure within its constructor rather than relying on the destructor. For example:

```
class D : C {
    int* m_pBuf1;
    int* m_pBuf2;
public:
    D() {
        m_pBuf1 = ... alloc ...;
        m_pBuf2 = ... alloc ...;
    }
    ~D() {
        if (m_pBuf2) ... free ...;
        if (m_pBuf1) ... free ...;
    }
}
```

If the allocation destined for m\_pBuf2 fails by throwing an exception, the destructor
for D will not run, and therefore m\_pBuf1 will leak. The C++ solution to this particular
example is to use smart pointers and member initializers for the allocations, because
successfully initialized members do get destructed, even when the constructor (or
indeed one of the member initializers) subsequently fails. This means that destructors
for a particular class do not have to tolerate that class's state not having been
fully constructed, because those destructors will never run.

In C#, finalizers will run, regardless of whether an object's constructor ran fully,
partway through, or not at all. If the object is allocated -- and so long as GC.SuppressFinalize
isn't called on it -- the finalizer runs. This distinctly means that C# finalizers
must always be resilient to partially-constructed objects (unlike C++ destructors).
Thankfully finalizers are a rare bird, and therefore this issue is seldom even noticed
by .NET programmers.

This issue does not arise in the case of .NET's IDisposable pattern. If a constructor
throws, the assignment to the target local variable does not occur. And therefore
the variable enclosed in, say, a using statement remains null. This means that there
is no way to possibly invoke Dispose on the object. Moreover, the allocation in using
occurs prior to entering the try/finally block. Hence, you really had better be writing
constructors that don't throw and/or protecting such resources with smart-pointer-like
things with finalizers, a la SafeHandle.

# Impediments to language support

As if these weren't sufficient cause for concern, I also mentioned earlier --
and somewhat vaguely -- that partially-constructed objects interfere with language
designers' efforts to add invariants, immutability and concurrency-safety, and
non-nullability to the language. And all of these are important properties to consider
in our present age of complexity and concurrency, so this point is worth understanding
more deeply. Let's look at each in-order.

## Invariants and safe-points

A partially-constructed object obviously may have broken invariants. By definition,
invariants are meant to hold at the end of construction, and so if construction never
completes, the rules of engagement are being broken.

Imagine, for example:

```
class C {
    int m_x;
    int m_y;
    invariant m_x < m_y;
    public C(int a) {
        m_x = a;
        m_y = a + 1;
    }
}
```

It is ordinarily very difficult to ensure that each instruction atomically transitions
the state of an object from one invariant safe-point to another. A common technique
is to define well-defined points at which invariants must hold. We might model each
failure point as one such technique. But even in C#, the above program does not satisfy
this constraint, because an overflow exception may be generated at the 'm\_y =
a + 1' line. Or a thread-abort exception may be generated right in the middle of
those two functions. Or, if addition were implemented as a JIT helper, an out-of-memory
exception could get generated due to failure to JIT the helper function.

In such cases, we'd like to say that the object does not exist. But the sad fact
is that the object \*does\* exist, and if the object has acquired physical resources
at the time of failure to construct, we must compensate and reclaim them. The ideal
world looks a lot like object construction as transactions, where the end of construction
is the commit-point. The state-of-the-art is very different from this, however, and
so any static verification and theorem proving that depends on invariants on an object
holding, well, invariantly, is subject to being broken by partially-constructed objects.

## Immutability… or not

Immutability is also threatened by partially-constructed objects. Immutability is
a one of many first class techniques for solving concurrency-safety in the language,
so this one is quite unfortunate.

In C#, for example, we might be tempted to say that a shallowly immutable type is
one whose fields are all marked readonly. (And a deeply immutable type is one whose
fields are all readonly, and also refer to types that are immutable.) A readonly
field cannot be written to after construction has completed. Unfortunately, if the
'this' leaks out during construction, we may see those readonly fields in an
uninitialized or even changing state:

```
class C {
    public static C s_c;
    readonly int m_x;
    public C() {
        m_x = 42;
        s_c = this;
        while (true) {
            ++m_x;
        }
    }
}
```

This is quite evidently a terrible and malicious program. C appears to be immutable,
because it only contains readonly fields, but is quite clearly not, because the value
of m\_x is assigned to multiple times. If we had a guarantee that all readonly fields
were definitely assigned once-and-only-once before 'this' can escape, then we'd
be close to a solution. But of course we have no such guarantee. In C#, at least.

A related issue is co-initialization of objects. This is interesting and relevant,
because in such cases we actually want to leak out partially-constructed objects.
Imagine we'd like to build a cyclic graph comprised of two nodes, A and B, each
referring to the other. With a naïve approach to immutability, we simply cannot
make this work. Either A must first refer to B, in which case A refers to a partially-constructed
B; or B must first refer to A, in which case B refers to a partially-constructed
A. Both are equally as bad. The two assignments are not atomic.

Cyclic data structures are a commonly cited weakness of immutability, and an argument
in favor of supporting partially-instantiated objects in a first class way, although
there are approaches that can work. One example is to separate edges from nodes,
and represent them with different data structures. We can then build the nodes A
and B, and then build the edges A->B and B->A without needing to use cycles.

## It's not-null, or at least it wasn't supposed to be

Tony Hoare called it his billion-dollar mistake: the introduction of nulls into a
programming language. I think he sells himself short, however, because the absence
of nulls in an imperative programming language -- however worthy a pursuit -- is
actually a notoriously difficult to attain.

Spec# is one example of a C-style language with non-nullability, in which T! represents
a "non-null T", for any T. Although this is done in a pleasant way conducive
to C#-compatibility -- a significant goal of Spec# -- I'd personally prefer to
see the polarity switched: T would mean "non-null T" and T? would mean "nullable
T", for any T, reference- and value-types included. This is much more like Haskell's
Maybe monad, and is the syntax I'll use below for illustration purposes. But I
digress.

Non-nullability is a wonderful invention, because it is common for 75% or more of
the contracts and assertions in modern programs to be about a pointer being non-null
prior to dereferencing it, both in C# and in C++. Relying on the type-system to prove
the absence of nulls is one big step towards creating programs that are robust and
correct out-of-the-gate, particularly for systems software where such degrees of
reliability are important. And it cuts down on all those boilerplate contracts sprinkled
throughout a program. Instead of:

```
void M(C c, D d, E e)
    requires c != null, d != null, e != null
{
    ... use(c, d, e) ...
}
```

You simply say:

```
void M(C c, D d, E e)
{
    ... use (c, d, e) ...
}
```

No opportunity to miss one, and no need for runtime checks. It's beautiful.

A problem quickly arises, however, having to do with partially-constructed objects.
All of an object's fields cannot possibly be non-null while the constructor is
executing, because the object has been zero'd out and the assignments to its fields
have not yet been made. Clearly constructor code needs to be treated "differently"
somehow. We cannot simply live with the fact that 'this' escaping leads to a
partially-constructed object leaking out into the program, because that could lead
to serious errors. These serious errors include potential security holes, if unsafe
code is manipulating the supposedly non-null pointer. One advantage to adding non-nullability
is that runtime null checks can be omitted, because the type system guarantees the
absence of nulls in certain places. In this situation, partially-constructed objects
lead to holes in our nice type system support. Either the dynamic non-null checks
are required as back-stop, or we'll need some other coping technique.

There are related issues with non-nullability, like with partially-populated arrays.
Imagine we'd like to allocate an array of 1M elements of type T, and we will proceed
to populate those elements following the array's allocation. There's clearly
a window of time during which the array contains 1M nulls, and then 1M-1 nulls, …,
and if we finish 1M-1M nulls, i.e. 0 nulls. It is only at that last transition that
the array can be considered to contain non-null T's. The standard technique is
to use an explicit dynamic conversion check, or to force the creation of the list
to supply all of the elements of the array at construction time.

# Coping techniques

There are, thankfully, some interesting ways to cope with partially-constructed objects.
There is, in fact, a spectrum of techniques, ranging from escape analysis in various
forms, to limitations around how objects are constructed such that a partially-constructed
one can never leak, to automatic insertion of dynamic checks to prevent the use of
partially-constructed objects, to static annotations that treat partially-constructed
instances as first class things in the type system. And of course there's always
the technique of "deal with it", which is the one that most C++-style languages
have chosen, including our beloved C#.

## The F# approach: restrictions and dynamic checks

F#, it turns out, does a very good job in preventing partially-initialized objects.
A first important step is that fields in F# are readonly by-default, unless you opt-in
to mutability using the mutable keyword. Therefore data structures are mostly immutable.
And the construction rules are meant to make it very unlikely that you'll expose
a partially-constructed object during construction. How so? It's simple: such fields
must be initialized prior to running ad-hoc construction code, and if you attempt
to initialize them multiple times, the compiler supplies an error. In other words,
you really have to work hard to screw yourself, unlike C++ and C# where it's very
easy.

It's of course possible to do some dirty tricks to publish or access a partially-initialized
object, despite needing to work very hard at it. There is, however, a nice surprise
awaiting us when we try. For example:

```
type C() =
    abstract member virt : unit -> unit
    default this.virt() = ()

type D() as this =
    inherit C()
    do this.virt()

type E =
    inherit D
    val x : int
    new() = { x = 42; }
    override this.virt() = printf "x: %d" this.x

let e = new E()
```

This example attempts to perform a virtual invocation from C before the more derived
class has been fully initialized. This overridden virtual simply (attempts to) prints
out the value of x. If we compile and run this program, however, we will notice that
we get an exception: "InvalidOperationException: the initialization of an object
or value resulted in an object or value being accessed recursively before it was
fully initialized."

Pretty neat. The compiler will stick in the checks necessary when 'this' is being
accessed, to dynamically verify that an object is not being leaked before having
been fully initialized. The F# approach can be summed up as trying to make things
airtight as possible statically at compile-time, but admitting that there are holes
-- primarily due to inheritance -- and dealing with them by inserting dynamic runtime
checks. This tradeoff clearly makes sense for F#, because it is attempting to attain
a robust level of reliability around immutability.

F# also adds non-nullability for the most part. Like Haskell's Maybe monad, F#
adds an option type that can store a single None value which lies outside of the
underlying type's domain to effectively represent null. Because F# is a .NET language
it of course also needs to worry about nulls at interop boundaries with other languages
like C# and VB. This is a great step forward; first class CLI support would be a
nice next step.

A slight variant of the F# idea is to initialize data up the whole class hierarchy
in one pass, and then run ad-hoc construction code in a second pass in the usual
way. So long as readonly data can be initialized without running the ad-hoc construction
code, this helps to statistically cut down on the chances for accidental leaking
of 'this'.

## Type system: T versus notconstructed-T

We can model two kinds of T in the type-system: T and notconstructed-T. The constructor
for any type T would then see the 'this' pointer as an notconstructed-T, and
everything else -- by default -- sees ordinary T's.

What good does this distinction do? It enables us to add verification and restrictions
around the use of notconstructed-T's and limitations to the conversion between
the two types. See [this paper by Manuel Fahndrich and Rustan Leino](http://portal.acm.org/citation.cfm?id=949305.949332)
for an example of how this approach was taken in Spec#'s non-nullability work.

For example, we can prohibit conversion between T and notconstructed-T altogether,
thereby disallowing escaping 'this' references altogether. If the type of 'this'
within a constructor is different than all other references to type T, and they are
not convertible, we've successfully walled the problem off in the type system.
This protects against erroneous method calls, so that a constructor could not call
any of its own methods, because these methods expect an ordinary T whereas the constructor
only has a notconstructed-T. And because you cannot state notconstructed-T in the
language, you cannot let one leak by storing it into a field.

We could add more sophisticated support, by allowing a programmer to explicitly tag
certain non-field references as T-notconstructed. This makes the concept first-class
in the language, and allows one to explicitly declare the fact that code is interacting
with a partially-constructed T:

```
class C
{
    int m_x;
    public C() {
        m_x = V();
    }
    protected virtual int V() notconstructed {
        ... I know to be careful ...
    }
}
```

In this example, the programmer has annotated V with 'notconstructed'. This enables
the call from the constructor because the method's 'this' is an uninitialized-T,
and serves as a warning to the programmer that he or she should take care, much like
the code written inside a constructor.

We must also decide whether fields are offlimits via notconstructed-T's. If yes,
we can add F#-style dynamic checks for initialization, but only for attempted accesses
against notconstructed object's fields. This is nice because it means the scope
of dynamic checks are limited, and used in a pay-for-play manner. And we could even
enable a programmer to sidestep the error by stating at the use-site that they understand
a particular field access may be to uninitialized memory, like Field.ReadMaybeUninitialized(&m\_field).

To be honest, the reason this approach has likely not yet seen widespread use is
that the cost is not commensurate with the benefit. At least, in my opinion. To make
something like partially-constructed objects a first-class concept in a programming
language, programmers would need to want to know where they are dealing with them.
For systems programmers, this makes sense. For many other programmers, it would be
useless ceremony with no perceived value. And yet the initial approach where nothing
new needed to be stated, but yet escaping 'this' was prevented, blocks certain
patterns of legal use. This is where theory and practice run up against one another.
There is, however, presumably a nice middle ground awaiting discovery.

# Winding down

I meant for this to be a short post. But the topic really is fascinating, and has
been coming up time and time again as we do language work here at Microsoft. But
it is truly fascinating mainly because, like nulls, the problem is widespread yet
tolerable, and most C++ and C# programmers learn the rules and make do. Partially-constructed
objects are a major blemish, but not a crisis that threatens the complete abandonment
of imperative programming.

I do believe language trends indicate that more will move away from C++-style object
initialization and related issues, and more towards immutability and treating data
and its initialization separately from imperative ad-hoc initialization code. Haskell,
F#, and Clojure, for example, show us some promising paths forward. There are a plethora
of other attempts at solving related problems, and I unfortunately could only scratch
the surface.

Although these techniques are not new, the primary question -- to me -- is how
close to "the metal" in systems programming these concepts can be made to work.
Typically for those situations, you need to rely on a mixture of static verification
and complete freedom, because the dynamic checking is too costly and the code to
work around overly-limiting static verification also adds too much cost. But as soon
as you add complete freedom into the picture, you run into partially-constructed
objects as a consequence, and all the issues I've mentioned above.

Anyway, I hope it was interesting.

