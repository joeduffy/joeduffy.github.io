---
layout: post
title: Static calls to virtual methods and verifiability
date: 2005-09-22 13:37:52.000000000 -07:00
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
We made a change in Whidbey recently that impacts the verification of **call**
s to virtual methods.

**Invoking Virtual Methods Statically**

Valid IL could previously invoke a precise implementation of a virtual method
with a **call** instruction instead of a **callvirt**. The target type's exact
method token could be specified, bypassing all dynamic dispatch altogether. For
example, given two classes A and B

> class A { public virtual void f() { Console.WriteLine("A::f"); } }
>
>
>
> class B : A { public override void f() { Console.WriteLine("B::f"); } }

a consumer would ordinarily emit IL to perform a virtual dispatch, looking
something like this in IL

> newobj instance void B::.ctor() callvirt instance void A::f()

The result is of course a properly dispatched virtual call which resolves to
B's override and prints out "B::f". But somebody could do this instead

> newobj instance void B::.ctor() call instance void A::f()

The result of which is an ordinary statically dispatched call to A's
implementation of f, printing out "A::f".

Some consider this a violation of _privacy through inheritence_. Lots of code
is written under the assumption that overriding a virtual method is sufficient
to guarantee  custom logic within gets called. Intuitively, this makes sense,
and C# lulls you into this sense of security because it always emits calls to
virtual methods as **callvirt** s. C++ offers language syntax to do precisely
this, however, e.g.

> B b; b.A::f();

I don't know of any other language that support this type of call directly, but
presumably somebody else followed in C++'s footsteps here. C# (and others) use
this technique to implement 'call to base' functionality. Some compilers emit
this type of IL so that their method resolution code can bind to virtual
methods in a custom way. And others could do it in an attempt to "devirtualize"
method calls when they know there are no overrides.

**Verification Changes**

Late in Whidbey, some folks decided this is subtly strange enough that we at
least don't want partially trusted code to be doing it. That it's even possible
is often surprising to people. We resolved the mismatch between expectations
and reality through the introduction of a new verification rule.

The rule restricts the manner in which callers can make non-virtual calls to
virtual methods, specifically by only permitting it if the target method is
being called on the caller's 'this' pointer. This effectively allows an object
to call up (or down, although that would be odd) its own type hierarchy. With
this change, the above example fails verification, "The 'this' parameter to the
call must be the calling method's 'this' parameter."

**Identity Tracking**

The verifier implements this magic using a technique called identity tracking.
We don't use this style of tracking in many places. The verifier ordinarily
tracks only the static type of items on the stack. But in this case, it needs
to be comfortable that you're using the same _arg.0_ pointer for the method
call as was passed onto the caller's stack frame. If you've executed a _starg
0_ in the IL stream, for example, you won't be permitted to make the call. Even
if you do a _ldarg.0_ followed by a _starg 0_, the verifier tosses you out the
window.

A catch here is that while you might be operating dynamically on the 'this'
pointer, the verifier avoids statically tracking pointers across method calls.
An example of where this can produce a false positive is as follows

> class A { public virtual void f() { Console.WriteLine("Foo::f"); } }
>
>
>
> class B : A { public override void f() { Console.WriteLine("Bar::f"); }
>
>
>
>     private B Echo(B b) { return b; }
>
>
>
>     public void FailsVerification() { Echo(this).A::f(); } }

It's clear that FailsVerification is really just invoking methods on its this
pointer. But it does so in a roundabout fashion. (Of course that 'A::f()'
syntax is psuedo-code; it would compile in C++, but C# doesn't offer such a
feature.) Regardless, the IL that gets produced isn't verifiable.

