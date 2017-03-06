---
layout: post
title: Boxing Nullable and verification
date: 2005-10-05 13:47:58.000000000 -07:00
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
Our verifier has knowledge of statically typed boxed value types. Such things
are never surfaced to user code, not even through reflection. In user code, the
type of a statically typed boxed value can only be referred to as `object`,
both statically and dynamically. This is one of the nice properties of a
nominal type system; if you can't name it, you can't refer to it.

We use boxed types for type tracking in the verifier. This is why it's legal to
make virtual method calls against boxed value types, for example, and similar
reasons apply to the formation of delegates over boxed value types. Using the
box instruction's type token argument, we can easily calculate the resulting
boxed type. We say the result of boxing a value of type `T` is an item on the
stack of type `boxed<T>`.

Well, most of the time...

### nullbox Rears its Head

Life was simple before [the nullbox
DCR](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=104175ad-2448-4607-bd12-4b02f877fe29).
In the good ole' days, when you boxed a value of type `T`, you got back a
`boxed<T>`. Always. But now things change ever-so-slightly. If `T` is a
`Nullable<U>`, the static type of the item left on the stack is a `boxed<U>`;
all other cases are still typed as `boxed<T>`. Given that you can only refer to
these things as `object`, perhaps this isn't concerning to you.

But from the verifier's perspective, it changes the user-observable semantics.
It means you can't verifiably form a delegate over a `Nullable<U>` _ever_. The
only way to produce something of type `boxed<T>` is through the use of a `box`
instruction; and we've established `box<Nullable<U>>` is a `boxed<U>`. There
should be no way to produce a `boxed<Nullable<U>>`. It similarly means that you
can't call virtual methods on a `Nullable<U>` because, by definition, you must
box value types in order to callvirt them.

(This statement doesn't apply to all virtual method dispatch. If you use
constrained calls--as the C# compiler does--they do the magic to determine if
there's a suitable implementation on the target type and, if so, avoids boxing.
They operate on the raw unboxed item as 'this'. This applies when you call
`ToString` on a `Nullable`, for example, because `Nullable` overrides it.)

Notice also that this is the very magic that permits you to make interface
calls on a `Nullable<T>` for interfaces that `T` supports. It gets boxed and the
type tracking permits you to perform the operation.

### Type Hole?

A type hole is a situation where the dynamic type of something doesn't match
what the static verifier said it would be. This is very bad. By definition,
something which is verifiably type safe should not be able to corrupt data at
runtime as a result of such type mismatches. A sound type system has no holes.
The change associated with `nullbox`, however, introduces one specific cause for
concern. We call it a "wart" but won't go so far as to call it a "type hole."

Consider what happens if a box instruction were to operate using a type token
which was parameterized by some generic parameter in the scope. In other words,
the thing being boxed was of some type `T` (perhaps declared on the enclosing
method) that wasn't known at verification time. Our verification rules state
that the result of box `T` is always `boxed<T>`. But as we've seen already,
if this scope were instantiated with `Nullable<U>` as the argument for the type
parameter `T`, this would be a lie. The dynamic type is actually a `boxed<U>`,
yet we said it was a `boxed<Nullable<U>>` (indirectly).

Unfortunately, because the verifier operates on abstract type forms, not
precise generic instantiations, fixing this isn't quite as simple as you might
imagine. Verification at JIT-time could actually determine this, but our model
does not surface such lazy verification. In other words, the verifier does not
have the information it needs at verification time to determine whether it is
lying.

Why isn't this a type hole? If there was a property of an item statically typed
as `boxed<Nullable<U>>` that you could verifiably make use of, but that wasn't
also a property of `boxed<U>`, this would precisely the definition of a type
hole stated aboved. We'd discover the problem at runtime. Right?

### \*Whew!\*

It turns out you can't do any such things.

First of all, you cannot do anything to an unconstrained type parameter `T`
except perform operations statically verifiable against `object`. A `boxed<U>`
(the dynamic type of a static `boxed<Nullable<U>>`) is obviously a derivative
of `object`, so this is OK. You couldn't verifiably form a delegate over a
`boxed<Nullable<_U_>>`, for example, because of the _verifier_ not the absence of
Nullable's methods at runtime.

Next, you can also constrain type parameters to things that implement specific
interfaces. So if `Nullable<U>` implemented an interface that its inner `U`
didn't support, you could legally make interface calls which would cause holes
at runtime. But (thankfully) `Nullable<U>` doesn't implement any interfaces.
(Notice we removed `INullableValue` from Whidbey altogether. :P)

Furthermore, `Nullable<U>`'s type parameter is constrained to value types, so
even if you could represent a constraint that allowed only value type values
for `T` (which you can't, you can only use the 'valuetype' constraint which
omits `Nullable` directly) you couldn't do anything dangerous.

### Summary?

Move along. Nothing to see here. I just typed up a brief summary because we
were discussing this at great lengths during ECMA specification. It sparked a
lot of interesting discussion. And it's a little bit of trivia to impress your
friends with.

I personally get a tad queasy when I think about proving the soundness of a
type system through the use of members of that type system, but that's a
separate topic...

