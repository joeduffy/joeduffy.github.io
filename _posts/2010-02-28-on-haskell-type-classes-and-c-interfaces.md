---
layout: post
title: On (Haskell) Type Classes and (C#) Interfaces
date: 2010-02-28 20:52:59.000000000 -08:00
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
Simon Peyton Jones was in town a couple weeks back to deliver a repeat of his ECOOP'09
keynote, ["Classes, Jim, but not as we know them. Type classes in Haskell: what,
why, and whither"](http://research.microsoft.com/en-us/um/people/simonpj/papers/haskell-retrospective/),
to a group of internal Microsoft language folks. It was a fantastic talk, and pulled
together multiple strains of thought that I've been pondering lately, most notably
the common thread amongst them: interfface abstraction.

In the talk, he compared polymorphism in Java-like languages (including C# which
I will switch to referring to over Java hereforth) with ML and Haskell. In other
words, how does a programmer commonly write code in each language that is maximally
reusable? Of course, C# programmers primarily achieve this through subclassing, whereas
functional programmers rely on type parameterization. Over the years, however, the
former group has begun to borrow a great deal from the latter; as evidence, witness
the growingly-pervasive use of generics in both Java and C# over the past decade.
The talk was given mainly through the lens of this evolution, which appears to approach
an interesting limit if projected far enough into the future.

Type classes came on the scene towards the end of the 1980's, and immediately became
a fertile seed for research and exploration in the relationship between subclass
and parametric polymorphism. Type classes are much closer to subclass-based polymorphism
than Haskell's borrowed ML-style, which is to say parametric polymorphism. This
is most intriguing because Haskell does not rely on subclassing, and so the mixture
of two breeds new patterns.

I thought that it might be interesting to compare the mixture of subclass and parametric
polymorphism in Haskell vis-à-vis type classes with the same in C# vis-à-vis a
mixture of interfaces, generics, and generic constraints. Hence this post. We shall
proceed by examining some basic type classes in Haskell with their equals in C#.
Though similar, the dissimilarities are as stark as the similarities. And the lack
of higher kinds -- particularly when combined with type classes -- means that some
Haskell patterns simply are not expressible in C#.

**The Simple Case: Equality (or Lack Thereof)**

The most basic type class of all is Eq, which allows the comparison of two like-typed
pieces of data. This may seem like a commodity if you ordinarily write code in languages
like Java and C# which have a strong notion of object identity. In Haskell, however,
equality is value equality over algebraic data types rather than objects, so polymorphism
over equality operators is quite a bit more important. Indeed, as we shall see, Haskell's
approach is more powerful than == in Java-like languages. (Witness the neverending
disagreements about reference and value equality when it comes to Object.Equals in C#.) But
alas, let us proceed by crawling in a series of logical steps, rather than leaping
to the conclusions.

Haskell's Eq type class is defined as such:

```
class Eq a where
        (==), (/=) :: a -> a -> Bool

        x /= y = not (x == y)
        x == y = not (x /= y)
```

As you see, Eq provides two operators: == and /=. Default implementations of each
define == as the inverse of /= and /= as the inverse of ==. Not only is this a convenience,
but it also specifies the desired contract implementations ought to abide by. Other
types may become members of the Eq class by mapping the one or both operators to
type-specific functionality. You will immediately recognize the similarity to virtual
methods in OOP languages, where the operators can be overridden by subclasses.

Of course all of the primitive data types already implement Eq, so you get value
equality over numbers, strings, etc. Imagine we declared a new Coords type -- comprised
of two integers -- and want to make it a member of Eq also -- wherein equality
is determined by a pairwise comparison of each's members:

```
data Coords = Coords { fst :: Integer, snd :: Integer }
```

We make Coords a member of the Eq type class, and thereby define equality over instance,
through the 'instance Eq Coords where' construct. This maps type class functions
to real implementation functions. The example here defines them inline, though you
may of course refer to existing functions instead:

```
instance Eq Coords where
      (Coords fst1 snd1) == (Coords fst2 snd2) =
            (fst1 == fs2) && (snd1 == snd2)
```

Now we can take a '[Coords]' and ask whether a particular 'Coords' exists
within it.

A function may constrain a type variable to a certain class, and thereby access members
of that class. For example, the following 'isin' function tests whether an instance
of some type 'a' is contained within a list of type '[a]'. To do this, it
demands that 'a' is a member of Eq using the syntax "Eq a =>":

```
isin :: Eq a => a -> [a] -> Bool
      x `isin` [] = False
      x `isin` (y:ys) = x == y || (x `isin` ys)
```

The moral equivalent to the Eq type class in C# is not so easy to decide. The most
obvious first guess is
the built-in == and != operators. However, we will quickly find that this is not
quite right, because these operators are not polymorphic in C#. To illustrate this
point, let's try to write the 'isin' method in C#, using generics and the ==
operator, for example:

```
bool IsIn<T>(T x, T[] ys)
{
    foreach (T y in ys) {
        if (x == y)
            return true;
    }
}
```

This function will not compile. The reason is that == and != in C# are not defined
over all types (specifically not for value types). You can get IsIn to compile by
restricting the T to a reference type:

```
bool IsIn<T>(T x, T[] ys) where T : class
{
    … same as above …
}
```

Although this code is deceptively similar to the Haskell example, it is actually
quite different. The == used to compare two instances compiles into the MSIL CEQ
operator, effectively hard-coding an object identity comparison. Even if an overloaded
== operator for a particular instantiated T is available, the compiler will not bind
to it. Why? Because it is overloading and specifically \*not\* overriding. For example,
say we had a MyData type and an overloaded == operator for comparing two instances:

```
class MyClass
{
    public static bool operator ==(MyClass a, MyClass b) { return true; }
    public static bool operator !=(MyClass a, MyClass b) { return false; }
}
```

According to this, all MyClass objects are equal. However, the following call yields
the answer 'false':

```
IsIn<MyClass>(new MyClass(), new MyClass[] { new MyClass() });
```

The same problem arises should instances of MyClass get referred to by Object references.
== and != do not perform any kind of virtual dispatch; the selection of implementation
is chosen statically.

Perhaps it is the Equals method inherited from System.Object, then? This, at least,
is virtual. And indeed, this gets much closer to Eq. Any type may override Equals,
and a generic definition defined in terms of it dispatches virtually and allows subclasses
to change behavior on a type-by-type basis:

```
bool IsIn<T>(T x, T[] ys)
{
    foreach (T y in ys) {
        if (x == y || (x != null && x.Equals(y)))
            return true;
    }
    return false;
}
```

(Even this is slightly different, because it assumes a certain type-agnostic behavior
about nulls.)

This is cheating, however. We've taken advantage of the fact that someone thought
to put an Equals method on System.Object, thereby giving all Ts such a method. There
are clearly limits to how many crosscutting things can be added to System.Object
before it becomes overwhelmed with concepts, not to mention the size (e.g. v-tables).
Moreover, Equals on Object is weakly typed; a better solution is to use interfaces,
like the IEquatable&lt;T&gt; interface that introduces a strongly typed Equals method:

```
public interface IEquatable<T>
{
    bool Equals(T other);
}
```

And to use a generic type constraint on IsIn's T, much more akin to what 'isin'
in Haskell above did:

```
bool IsIn<T>(T x, T[] ys)
      where T : IEquatable<T>
{
    foreach (T y in ys) {
        if (x == y || (x != null && x.Equals(y)))
            return true;
    }
    return false;
}
```

This is cheating a little less, because we can implement an interface after-the-fact
without impacting a class's type hierarchy. This, in fact, looks remarkably similar
to the Haskell 'isin' shown earlier, using type classes and parametric polymorphism,
where here we have used interfaces in place of type classes.

We might be tempted to define a default NotEquals method over all IEquatable&lt;T&gt; instances,
just like Haskell does by implementing the defaults for == and /= as the inverse
of each other:

```
public static class Equatable
{
    public static bool NotEquals<T>(this IEquatable<T> @this, IEquatable<T> other)
    {
        return !this.Equals(other);
    }
}
```

This is not perfect. It is not polymorphic; see my previous post for [an extensive
discussion](http://www.bluebytesoftware.com/blog/2010/02/10/ExtensionMethodsAsDefaultInterfaceMethodImplementations.aspx)
of this and related points. And what about nulls? If '@this' is null, the default
implementation is going to AV. We'd need to bake in type-agnostic knowledge of
null again. Sigh!

Sadly, it turns out this whole approach in general isn't quite right anyway. For
two reasons:

- First, we still infect the type in question with the interface being implemented;
it cannot be done completely outside of the type's definition, as with type classes.

- Second, type classes in Haskell do not actually require a value of the type in
question to dispatch against the class's functions, whereas we clearly do in the
above example: we need to virtually dispatch against the object, and rely on this
virtual dispatch to execute different code for each type. This will come up as we
look at the numeric classes, but it is a critical difference.

A closer analogy is to use IEqualityComparer&lt;T&gt;:

```
public interface IEqualityComparer<T>
{
    bool Equals(T x, T y);
}
```

(IEqualityComparer<T> in .NET also has a GetHashCode method on it. Let's ignore
that for now.)

Unfortunately, if our IsIn method were to use IEqualityComparer&lt;T&gt; to do its job,
callers would be required to pass an instance explicitly; we cannot infer a "default"
comparer based solely on the T:

```
bool IsIn<T>(T x, T[] ys, IEqualityComparer<T> eq)
{
    foreach (T y in ys) {
        if (eq.Equals(x, y))
            return true;
    }
    return false;
}
```

Type classes actually function rather similarly, with two major differences:

1. The interface object -- called a dictionary -- is passed and used implicitly.

2. The mapping from types to dictionaries is done implicitly, whereas in .NET you'll
need to find an instance of the interface in question through other means.

This second difference is solved by a little hack in .NET. If you take a look at
the EqualityComparer&lt;T&gt;.Default property, you shall see a lot of slightly gross reflection
code to return an instance of IEqualityComparer&lt;T&gt; for any arbitrary T. The code
checks some well-known types and conditions, and ultimately falls back to the aforementioned
interfaces and default Equals method for the most general case. It's not pretty,
but it's a beautiful hack given the tools at our disposal in C#.

**A Harder Case: Polymorphic Numbers, on Output Parameters**

The Eq type class is easy. The functions it defines are polymorphic on their inputs,
but not on their outputs; both == and /= return Bool values. Once we transition to
polymorphic output parameters or return values, we encounter a pattern quite different
from that which is found in most .NET interfaces.

Let's illustrate these differences by looking at Haskell's Num type class:

```
class (Eq a, Show a) => Num a where
      (+), (-), (*) :: a -> a -> a
      negate        :: a -> a
      abs, signum   :: a -> a
      fromInteger   :: Integer -> a
```

Here we see another feature of Haskell type classes: inheritance. Num derives from
both Eq and Show -- indicated by "(Eq a, Show a) => Num a" -- the latter class
of which we have not yet shown but is the moral equivalent to .NET's Object.ToString
method. It enables pretty printing of values, clearly something that would be expected
to be common among all numeric data types. Haskell's numeric class hierarchy is
quite elegant, enabling highly polymorphic computations. A nice little tutorial of
can be found here: [http://www.haskell.org/tutorial/numbers.html](http://www.haskell.org/tutorial/numbers.html).

But the question at hand is what the C# equivalent would be.

Our first approach would be to mimic the IEquatable&lt;T&gt; solution above:

```
interface INumeric<T>
{
    T Add(T d);
    T Subtract(T d);
    T Multiply(T d);
    T Absolute();
    T FromInteger(int x);
}
```

This works fine, and primitive types in .NET could presumably implement it:

```
struct int : INumeric<int> { .. }
struct float : INumeric<float> { .. }
struct double : INumeric<double> { .. }
...
```

This enables polymorphic code, like a Sum method, through the use of generic type
constraints:

```
public static T Sum<T>(params T[] values)
      where T : INumeric<T>
  {
      T accum = default(T);
      foreach (T v in values)
          accum = v.Add(accum);
      return accum;
  }
```

This example works great. Why then, you might wonder, doesn't LINQ use this instead
of providing special-case overloads of Average, Min, Max, Sum, etc. for all well-known
primitive data types?

The primary reason is the performance hit taken to perform addition through O(N)
interface calls versus O(N) MSIL ADD instructions. It is just a basic fact of life
that today's leading edge separate compilation techniques will not achieve parity
with the hand specialized variants. While it is true that the JIT compiler \*could\*
specialize the code for specific Ts and specific interfaces to emit more efficient
instructions, like int, float, etc. over INumeric&lt;T&gt; calls, it will not do so today.
This reduces the ability to share code -- which admittedly is what we want here
-- and is tangled up in a judgment call based on heuristics. But I digress.

There is a larger problem that arises with other examples, at least from a language
expressiveness point-of-view: the need to have an instance in hand to invoke interface
methods. FromInteger, for example, is rather awkward to write. In fact, we cannot
write a method with INumeric&lt;T&gt; like we could in Haskell:

```
public static T MakeT<T>(int value)
      where T : INumeric<T>
{
    ... ? ...
}
```

How do we invoke FromInteger, given that no T is available at the time of MakeT's
invocation? You can't; you need to arrange for an instance to be available. There
are ways out of this corner. One solution is to mandate that T has a default constructor:

```
public static T MakeT<T>(int value)
      where T : INumeric<T>, new()
{
    return new T().FromInteger(value);
}
```

That is always acceptable for structs, since they always have such a constructor;
but this practice requires that classes be designed to possibly not hold invariants
at all times, and so is not always acceptable or at the very least requires design
accommodation.

The alternative is probably obvious. Use a similar approach to IEqualityComparer&lt;T&gt;:

```
interface INumericProvider<T>
{
    T Add(T x, T y);
    T Subtract(T x, T y);
    T Multiply(T x, T y);
    T Absolute(T x);
    T FromInteger(int x);
}
```

And now, of course, each method that does polymorphic number crunching must accept
an instance of INumericProvider&lt;T&gt;. That's particularly cumbersome, so it's more
likely that .NET developers would prefer the aforementioned approach, where the type
must provide a default constructor.

Admittedly, I seldom run into this particular problem in practice; but when I do,
I really wish I had something like Haskell type classes to help me out.

Before moving on, it is worth pointing out one Haskell type class problem that explicit
interface object passing in .NET helps to avoid. Should you need multiple implementations
of a given class for the same type, as is relatively common with equality comparisons,
you must disambiguate in Haskell by separation by module and being careful about
what you import. This is similar to C#'s extension methods. With explicitly passed
interface objects, however, it is trivial to manage and pass separate objects if
you'd like.

**Close, but No Cigar: Higher Kinds**

There is one last feature that Haskell provides -- a pretty big one, I might add
-- that C# simply cannot do: higher kinded types, or polymorphism over constructed
types. This feature is orthogonal to type classes, but gets used pervasively in conjunction
with them. An example will make this stunningly clear:

```
class Monad m where
      (>>=)  :: m a -> (a -> m b) -> m b
      (>>)   :: m a -> m b -> m b
      return :: a -> m a
      fail   :: String -> m a

      m >> k  = m >>= \_ -> k
      fail s  = error s
```

Let's try to transcribe the core of this class in C#, renaming >>= to Bind, and
omitting the >> and 'fail s' operators because they have default implementations:

```
public interface IMonad<M, A>
{
    M<B> Bind<B>(M<A> m, Func k);
    M<A> Return(A a);
    M<A> Fail(string s);
}
```

This approach is tantalizingly close. It suffers from the already-admitted problem
that, for any M&lt;A&gt; instance, you will need to pass the appropriate IMonad&lt;A&gt; provider
object -- just as with the IEqualityComparer&lt;T&gt; and INumericProvider&lt;T&gt; examples
above.

But the code of course won't \*actually\* compile, because the type variable M
cannot be constructed as shown here. We find references to M&lt;A&gt; and M&lt;B&gt;, which are
complete nonsense to C#. M is just a plain type variable. M is required to be what
Haskell calls a type constructor (\* -> \*), which is a generic type that must be
instantiated before it is a terminal type. [I've written about this before](http://www.bluebytesoftware.com/blog/2008/11/04/LongingForHigherkindedC.aspx).
Although it seems like a trivial omission in C#'s language definition, it strikes
at the heart of the type system.

A fictitious syntax for expressing this in C# might be:

```
public interface IMonad
      where M : <>
{
    ...
}
```

And if, say, M were expected to be a two- or three-parametered type, we would find,
respectively:

```
... where M : <,>
... where M : <,,>

```

And so on.

This could in theory work. But C# -- and more worrisome .NET and the CLR -- do not
support this presently, and, to be quite honest, likely never will. It is immensely
powerful, however. Life without monads is a life destined to continuous repetition.
The "LINQ Pattern", for example, is one example case in .NET where, for each
'source' type, we must create a "copy" of the original System.Linq.Enumerable
variant. And shame on those who wish to write polymorphic code that will work for
any LINQ provider.

**Winding Down**

I hope to have shown some of the similarities and dissimilarities between type classes
and interfaces, and some patterns that arise when these things are mixed with parametric
polymorphism. The mix of inheritance for type classes, but not for implementation
types, in Haskell is unique. C#, of course, allows inheritance both amongst interfaces
and implementations which is both a blessing and a curse.

I do think both camps have something to teach one another. For example, having a
default interface lookup mechanism for arbitrary types in C# would be wonderful,
and indeed might provide a replacement for extension methods that has more longevity.
I'm sure much of this will happen with time; either "in place" as the respective
languages evolve, or as new languages are created with time.

But most importantly, I hope that the blog post was educational and fun. Enjoy.

