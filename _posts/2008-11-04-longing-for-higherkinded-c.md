---
layout: post
title: Longing for higher-kinded C#
date: 2008-11-04 12:55:52.000000000 -08:00
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
Type classes, kinds, and higher-order polymorphism represent some of Haskell's
most unique and important contributions to the world of programming languages.
They are all related, and began life as type classes in Wadler and Blott's 1988
paper, [How to make ad-hoc polymorphism less ad hoc](http://portal.acm.org/citation.cfm?id=75277.75283).
Eventually, Jones introduced the (then separate) concept of constructor classes,
in his 1993 paper, [A system of constructor classes: overloading and implicit higher-order
polymorphism](http://portal.acm.org/citation.cfm?id=165180.165190).  Eventually
these two ideas were unified into a beautiful single set of features (namely, type
constructors and kinds) in Haskell.

In this short essay, I'll explain what these things are and why I'm sad that
we don't have them in C#.

To take the simplest motivating example, say we want to define a generic square function:

```
square x = x * x
```

Given a Hindley-Milney type system (with type inference), how should the compiler
type this function?  The challenge that immediately arises is that, to know
the type of x and the function's return value, we must know something about the
function \* being called within the body of square.  But to know something about
that function, we'd need to know the type of x.  We've entered into a cycle,
and have hit a wall.  Clearly the type will be something generic, but polymorphic
on what?

Imagine that we could infer the type of the * function as follows:

```
(*) :: a -> a -> b
```

In other words, \* is a function that takes two values, both of type a, and produces
some value of another type b.  We know its two arguments must be of the same
type because in square we pass the same value x to it twice.  Given this typing
for \*, we could then type square similarly as:

```
square :: a -> b
```

In other words, square takes a single value of type a and produces a value of type
b.  The constraint on the type a here is, of course, that some function \* is
available that is typed as taking an a as input.  There's no obvious way to
capture this in the type system, though we might conceive of something like:

```
square :: (* :: a -> a -> b) => a -> b
```

In other words, given a type a for which some function \* is defined, which takes
two a's and returns a single b, the type of square thus takes an a and produces
a b.  You can't say that in Haskell, although we'll see a bit later that
type classes allow similar constraints (with "=>") to be written.

While this hypothetical typing is extremely general purpose, it would produce considerable
challenges in its implementation.  Standard ML throws up its hands and infers
all mathematical operators (like \*) as working with floats, meaning that all of
the types above (both a and b) will be inferred under the type of float.  (\*)
is of type float -> float -> float, and square is of type float -> float.  Similarly,
F# assumes you're working with ints.  Both Standard ML and F# have amazingly
rich type inference systems, but this begins to run right up against the limits of
what they can do.  We'll see some harder examples shortly.

You can probably guess that Haskell's solution to this conundrum is to use higher
order polymorphism with a feature of its type system called type classes.  They
allow us to classify types much in the same way types ordinarily classify objects.
We can classify the set of numeric types as follows, for instance:

```
class Num a where
    (*) :: a -> a -> a
    ...other numeric operations...
```

And then we can go ahead and provide concrete mappings for integers and floating
point numbers:

```
instance Num Int where
    (*) = addInt
    ...

instance Num Float where
    (*) = addFloat
    ...
```

Each instance of the type class (in this case, Num) is a bit like a dictionary mapping
the named functions (in this case, just \*) to other functions that are defined for
the concrete type (in this case, supplied in a's stead).  With this information
defined, the Haskell compiler can now infer the type of square as:

```
square :: Num a => a -> a
```

This inference really just says that the function square is defined for all types
a that are in the type class Num.  The "Num a =>" part is a bit like a C#
generic type constraint, in that it restricts what kinds of a's can be supplied.
Given what has been stated thus far, that's just Int and Float.  So we can
only call the square function with types on which multiplication is properly defined,
which is exactly what we want.

At this point, we might want to try defining a similar thing in C# using generics.
(And for this simplistic example, and others like Haskell's Eq a type class, we
will succeed.)  There are two basic ways we could achieve this.  The first
is to define an INum&lt;T&gt; interface (or abstract class), and give
it an instance method to multiply the target with another number:

```
interface INum<T> {
    T Mult(T x);
}
```

We would then have the basic numeric data types like Int32 and Float implement INum&lt;T&gt;:

```
struct Int32 : INum<Int32> {
    public Int32 Mult(Int32 x) { return value * x; }
    ...
}

struct Float : INum<Float> {
    public Float Mult(Float x) { return value * x; }
    ...
}
```

Given these definitions, it would be a breeze to write a Square method that only
operates on INum&lt;T&gt;s:

```
T Square<T>(T x) where T : INum<T> { return x.Mult(x); }
```

Thankfully, we can recursively reference the T from within the generic type constraint.

Now, of course, there's no way the C# compiler would infer the necessary INum&lt;T&gt;
constraint.  But given that we don't have rich type inference (aside from
for local variables) in C#, this doesn't pose any new problems.  Another slight
annoyance is that you need to modify the source type to declare support for INum&lt;T&gt;,
when a perfectly reasonable implementation could have been provided "from the outside,"
but you'll find that this will only occasionally get under your skin.

The second way we might go about this is to take an approach similar to .NET's
EqualityComparer&lt;T&gt; class, where we have an abstract base class that represents the
ability to do something with instances of Ts.  And then we only provide implementations
on concrete Ts for which that ability makes sense.  For example, we could have
a Multiplier&lt;T&gt; that looks a lot like INum&lt;T&gt;:

```
abstract class Multiplier<T> {
    public abstract T Mult(T x, T y);
}
```

Multiplier&lt;T&gt; on its own isn't usable.  But we can provide implementations
for Int32 and Float:

```
class Int32Multiplier : Multiplier<Int32> {
    public override Int32 Mult(Int32 x, Int32 y) { return x * y;
}

class FloatMultiplier : Multiplier<Float> {
    public override Float Mult(Float x, Float y) { return x * y;
}

// And so on ...
```

Now we can write a slightly different Square method that takes a Multiplier&lt;T&gt;
as an extra argument:

```
T Square<T>(T x, Multiplier<T> m) { return m.Mult(x, x); }
```

Now there isn't any kind of generic type constraint on Square's T, but of course
we can only call it if we have a concrete instance of Multiplier&lt;T&gt; in hand.
And by definition that means there is a Mult method defined that we can call.
(This isn't wholeheartedly true.  You can of course call Square&lt;U&gt; for any
U, passing in null as the second argument.  But presumably the method would
check for null and throw.  This is a real limitation, however, which would likely
push us back in the direction of the original interface solution.  If we had
non-null types, we could get closer to a fully statically verifiable solution.)

Aside from a lot more typing, and the lack of rich type inference, we seem to have
reached parity.  The simple examples provided in the literature and Haskell's
Standard Prelude can be implemented in such a fashion.  But we are kidding ourselves
if we think these are the same thing.

The main problem is that C# doesn't support higher-kinded type parameters.
We haven't yet seen a type class in Haskell that fully exploits this capability,
but there are several.  The simplest one I know about in the Haskell Standard
Prelude is the Functor type.  (Monad is also a great example, but is a bit more
complicated (and sufficiently frightening) that this will be a topic for another
day.)  Functor's definition is:

```
class Functor f where
    fmap :: (a -> b) -> f a -> f b
```

The Functor type class offers a single function, fmap.   It takes two things -- a
function that transforms a value of type a into a value of type b and some functor
value of type f -- and returns some new functor value of type f b.  This looks
like an ordinary type class, except for one funny (and subtle) aspect.  Functor
abstracts over type f, but notice that we're using f in fmap's second argument
and return type by actually constructing it with two other types a and b!  In
case you're having a hard time thinking in Haskell, it's as though we tried to
write this in C# using our interface trick from earlier:

```
interface IFunctor<T> {
    T<B> FMap<A, B>(Func<A, B> f, T<A> a);
}
```

This won't compile.  We can't refer to T in the typing of FMap as T&lt;B&gt; and
T&lt;A&gt;: it's not expressible in C# and .NET's type system.  Let's pretend
for a moment, however, that we could.  What is an example of class that might
implement this?  How about something that deals in terms of Nullable&lt;T&gt; instances?

```
class NullableFunctor<T> : IFunctor<Nullable<>> {
    Nullable<B> FMap<A, B>(Func<A, B> f, Nullable<A> a) {
        return new Nullable<B>(f(a.Value));
    }
}
```

All you need to do is take a close look at a 1997 paper by Simon Peyton Jones, Mark
Jones, and Erik Meijer, entitled [Type classes: an exploration of the design
space](http://research.microsoft.com/~simonpj/papers/type-class-design-space/),
and you will find a plethora of even more complicated (and useful) examples that
use an innocent-sounding aspect of Haskell's type system called multi-parameter
type classes.  All of the types are higher-order and are merely moved around
and manipulated like abstract (higher-order) symbols.  The type system gracefully
gets out of the way and allows you to drop abstract type parameters into any holes
they fit in, without mandating that you say too much.  The secret sauce -- as
noted earlier -- is kinds.

Kinds are used in the implementation of Haskell's type system, and you won't
mention a whole lot about them anywhere.  They basically categorize what kind
of types can appear anywhere a type is expected.  A great overview (with plenty
of context) can be found in Mark P. Jones's [Functional Programming with Overloading
and Higher-Order Polymorphism](http://portal.acm.org/citation.cfm?id=647698.734150)
paper and, of course, the [Haskell 98 Report](http://www.haskell.org/onlinereport/).

Here's a quick rundown.  Kinds appear in one of two forms:

1. the symbol \* represents a concrete type (a.k.a. a monotype), and,

2. if k1 and k2 are kinds, then k1 -> k2 is the kind of types that take a type of
kind k1 and return a type of kind k2.

Kinds are formed in many ways: the primitive types (such as Char, Int, Float, Double,
etc.) are an example of the former, and are of kind \*.  They "bottom out."
Type constructors, however, like Functor are an example of the latter, and are of
kind \* -> \*.  That is, they take a kind k1 (the first \*) and produce another
kind k2 (the second \*).  By giving some concrete type T (\*) to Functor, we
get back a Functor T (also \*).  The latter is therefore a bit like a function
mapping one kind to another.  Functions have a kind of \* -> \* -> \*, because
a function has two types: the type of arguments (the first \*) and the type of its
return value (the second \*).  These compose, so that you might have (\* ->
\*) -> \* -> \*.  And so on.  Thinking about kinds can take a bit of getting
used to.

But the really useful thing here is that kinds allow you to write higher order type
constructors like those we have begun to explore above, like Functors and Monads.
I.e., given a type t1 of kind k1 -> k2, and a type t2 of kind k1, then t1 t2 is a
type expression of kind k2.  This can be applied to the occurrences of f a and
f b in Functor's fmap function.  In the type Functor f they are of kind \*
-> \* -> \*.  When a concrete Functor instance is specified, e.g., by substituting
T for f, this turns fmap's T a and T b arguments to kind \* -> \*.  That is,
they still both expect another kind before bottoming out.  And therefore we
can substitute some concrete U and V types for a and b, to reduce them from kind
\* -> \* to kind \*.

Now we're done.  And, as if by magic, it all works.

