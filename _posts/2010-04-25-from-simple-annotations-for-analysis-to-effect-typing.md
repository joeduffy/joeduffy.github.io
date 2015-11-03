---
layout: post
title: From Simple Annotations for Analysis to Effect Typing
date: 2010-04-25 09:35:15.000000000 -07:00
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
We use static analysis very heavily in my project here at Microsoft, as a way of
finding bugs and/or enforcing policies that would have otherwise gone unenforced.
Many of the analyses we rely on are in fact minor extensions to the CLR type system,
and verge on "effect typing", an intriguing branch of type systems research that
has matured significantly over the years.

Many of these annotations are done on methods, rather than types.  A few examples
include:

1. [MayBlock] indicates that a method is free to call methods that might block.

2. [NoAllocations] indicates that a method is neither allowed to allocate, nor call
another method that might allocate

3. [Throws(...)] indicates that a method is allowed to throw an exception of a type
in the set { … }, or call other methods that may throw exceptions in the set {
… }.

4. And so on.

It turns out there's a general way for handling these annotations.  And indeed,
you will quickly find that pursuing ad-hoc solutions to each independently leads
to troubles.  We shall briefly look at the generalization.

We must first observe that each falls into one of two categories: additive or subtractive.
MayBlock and Throws are additive.  They say what is permitted.  NoAllocations,
on the other hand, is subtractive, because the annotation declares what is not permitted.
This distinction, we shall see, is crucial.

First we can imagine that each distinct effect shown above has a distinct effect
type.

The types EMayBlock, ENoAllocations, and EThrows correspond to the annotations above.
This will permit us to model effects using subtyping polymorphism.  We will
use the usual notation, i.e. "S &lt;: T" means "S is a subtype of T", or "a
S is substitutable in place of a T".  For example, String &lt;: Object.
Throws is special, because it has a type hierarchy of its own beneath the root type.
As you might guess, this hierarchy is infinite in size and is comprised of each possible
permutation of exception types.

There are two special kinds of effects: the null effect (ENil), and a set of other
effects (EMany).  The latter permits us to create a new, unique effect type
merely by concatenating a list of other effect types.

Each method is then given an EMany effect type containing its full set of effect
types.  For example:

```
[MayBlock, Throws(typeof(FileNotFoundException)), NoAllocations]
void M() { ... }
```

Is given the distinct effect type EMany { EMayBlock, EThrows(typeof(FileNotFoundException)),
ENoAllocations }.

We should make one generalization before moving on.  ENil ~ EMany { }.
In other words, having no effects is equivalent to a list of no effects.  Furthermore,
EMany { } ~ EMany { ENil }.  In other words, having a list of no effects is
equivalent to having no effects.

Now we are ready to weave everything together.  The main question confronting
us is as follows: What is the subtyping relationship between the various effect types,
including the null and list types?

The easiest to do away with is the EMany type.  Given two EMany types E and
F, then E &lt;: F if, for all effects T in E's type set, there exists an effect type
U in F's type set such that T &lt;: U.  In simpler terms, a list is a subtype
of another list so long as all of its components are also subtypes of a component
of the other.  This is very abstract, but we shall see soon why it is useful.

Now we get to see why the additive and subtractive distinctions are so important:

- Given an additive effect type EAdditive, we say ENil &lt;: EAdditive.
- Given a subtractive effect type ESubtractive, we say ESubtractive &lt;: ENil.

The first statement says that a method with no effects is substitutable for a method
with additive effects, and the second says that a method with subtractive effects
is substitutable for a method with no effects.  The corollaries are perhaps
just as important.  A method with additive effects cannot take the place of
a method with no effects, whereas a method with subtractive effects can.

For the simple single-effect case, effects depicted in this way represent points
on a line, where ENil is zero, subtractive effects are negative integers, and additive
effects are positive integers.  The lattice obviously becomes rather complicated
as many effects accumulate.

Where does substitutability come up with respect to methods, anyway, you may ask?
The first is in determining which other methods can be called.  If a method
M with effects E is trying to call another method N with effects F, this is
permitted so long as F &lt;: E.  The next is in virtuals and overriding.
A virtual with effects E may be overridden by a method with effects F so long as
F &lt;: E.  The following example illustrates this idea, in addition to the composition
of the subtyping rules we have shown so far:

```
class C{
    public virtual void M() {}

    [MayBlock, NoAllocations]
    public virtual void N() {}
}

class D : C {
    [MayBlock, NoAllocations]
    public override void M() {}

    public override void N() {}
}
```

In this example, the four methods are given the following effect types:

- C::M gets EMany { ENil }, or just ENil.
- C::N gets EMany { MayBlock, NoAllocations }.
- D::M gets EMany { MayBlock, NoAllocations }.
- D::N gets EMany { ENil }, or just ENil.

What does all this gibberish mean?  Well it's straightforward and intuitive,
actually.

We are attempting to add the MayBlock and NoAllocations effects to the overridden
M method which has none.  Because MayBlock is additive, this is illegal (someone
might call C::M thinking the code will not block), whereas it is OK for NoAllocations
(calls through D::M are assured no allocations will happen, even though calls through
C::M are guaranteed no such thing).  Similarly, we are attempting to remove
both effects from the overridden N method.  Because MayBlock is additive, this
is OK (M isn't required to block, even though calls through C::M may suspect it
of doing so), whereas it is decidedly not OK for NoAllocations (calls through C::M
will reasonable assume allocations do not happen, whereas D::M would be free to perform
them).  It may take some thought to convince yourself that this is correct,
but I hope that you find that it is.  All of this works because of the subtyping
of effect types.

All of this works similarly with delegates.  The source delegate signature is
akin to the base class in the above example, whereas the target method being bound
to is like the override.

Things get a little more complicated when considering the EThrows effect.  It
is additive, so it is of course true that ENil &lt;: EThrows(\*).  However, what
if we have two different EThrows, and wish to inquire about substitutability of one
in place of the other?  We can come up with a simple rule that is general purpose
for all set-of-type kinds of effects.  Namely, consider two instances A and
B of the same effect type:

- Given an additive effect type EAdditive, then A &lt;: B if, for all types T in A's
set-of-types, there exists a type U in B's set-of-types such that T &lt;: U.
- Given a subtractive effect type ESubtractive, then A &lt;: B if, for all types T in
A's set-of-types, there exists a type U in B's set-of-types such that U &lt;: T.

These sound quite similar, except that they end differently (i.e. T &lt;: U vs. U
&lt;: T).  We may illustrate the additive case with EThrows; to illustrate the
subtractive case, let us imagine we can declare a ENoAllocations effect type that
specifies which precise types may not be allocated:

```
class A {}

class B : A{}

class C{
    [Throws(typeof(Exception)), NoAllocations(typeof(A))]
    public virtual void M() {}

    [Throws(typeof(FileNotFoundException)), NoAllocations(typeof(B))]
    public virtual void N() {}
}

class D : C {
    [Throws(typeof(FileNotFoundException)), NoAllocations(typeof(B))]
    public override void M() {}

    [Throws(typeof(Exception)), NoAllocations(typeof(A))]
    public override void N() {}
}
```

The results should not be surprising.  D::M overrides C::M's exception list,
by being more specific and declaring that FileNotFoundException is thrown instead
of just Exception.  This is OK.  Whereas D::N overrides C::N's list by
being more general purpose, specifying Exception instead of FileNotFoundException.
This is clearly not OK.  The NoAllocations type works in exactly the reverse.
D::M attempts to prohibit allocations of B, but this is merely one possible subtype
of the base method C::M's declaration of A, and therefore this is illegal.
Whereas D::N ensures no instances of A are allocated, which of course subsumes the
base method C::N's declaration that no B's are allocated.

Everything gets a little more interesting when you consider generics.  For example,
how would we type a general purpose Map method?  (This pattern arises quite
frequently.)  We would presumably want it to somehow "acquire" the effects
of the delegate it invokes on all elements in a list.  For example:

```
U[] Map<T, U>(T[] input, Func<T, U> func);
```

This declaration is stronger than necessary.  The Func<T, U> class -- prepackaged
with the .NET Framework -- does not have any effects on it.  So it may not,
for example, bind to a method that has any additive effects like Throws on it.
This is rather unfortunate.

To solve this we could imagine treating effects with parametric polymorphism:

```
[Effects(E)]U Func<T, U, [EffectParameter] E>(T x);
```

This fictitious syntax merely says that Func can be instantiated with an effect type
E, and that the Func "method" itself acquires the effect E.  (Admittedly
I should stop using faux-attribute syntax for illustrations since we've reached
this level of language integration.)  Now Map can be declared as such:

```
[Effects(E)]U[] Map<T, U, [EffectParameter] E>(T[] input, Func<T, U, E> func);
```

This says that Map has the same effects as the Func that is supplied as an argument.
It turns out that we may want to extend this further, by enabling symbolic manipulation
of effects.  We may wish, for example, to specify that the Func is not allowed
to block, by stating it does not have [MayBlock] in it.  You could imagine using
something very similar to generic constraints to achieve this.  It is also interesting
to allow concatenation of multiple effect types, both through partial and full specialization.
For example, Map above may clearly have effects of its own.  You also tend to
want generic constraints like, 'where E : F', which of course just depends on the
aforementioned subtyping rules.  And of course C# 4.0's co- and contravariance
can be applied to effects too.

Anyway, I have probably gone beyond most readers' interest level in this subject.
Things sure do get very interesting when you allow symbolic manipulation of effects.
They get even more interesting when you begin to think of types as having "permissible
effects" attached to them.  However, the main thing I wanted to point out
with this brief article is that this pattern arises quite frequently.  And despite
everyone struggling through what seem to be odd corner cases as they develop ad-hoc
solutions, there really is a sound generalization behind it all.  Many languages
have first class effect typing, and I have found it liberating to think of many of
these type system annotations through that lens.  Perhaps you shall too.

