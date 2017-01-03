---
layout: post
title: Delegates v2.0, co- and contravariant support
date: 2005-01-21 20:42:46.000000000 -08:00
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
In Whidbey, we have a few great changes to delegates, two of which are
particularly cool for languages of all sorts.

First, we have unbound delegates. These enable you to new up a delegate without
having to supply an object instance at creation time. You just provide the
method handle as you would with a static method, for example, and bind it
lazily to an instance at invocation time. Interestingly, trying to pass null as
the object pointer in v1.1 would die with a `NullReferenceException`.

C++/CLI has language syntax to support unbound delegates, but C# unfortunately
does not. This feature is great for functional language-like algorithms and was
initially conceived of to support STL.NET. As an example, say you have a
collection of homogenous objects and want to apply an instance function against
each object in the set. To do this generically today, you'd have to use the
reflection APIs, admittedly a little less nice than the C++ syntax. Now with
unbound delegates, the code which iterates over the set's contents and does the
invoking just supplies the target pointer as it calls invoke.

Another cool feature is relaxed delegates. These enable you to bind to
functions using covariant return and contravariant parameter types, and are in
fact supported by C#. You get this feature for free and don't even need to
change anything to take advantage of it. As an example of its use, consider
this class hierarchy:

    class A {}
    class B : A {}
    class C : B {}

And this delegate:

    delegate B f(B b);

In v1.1, the only valid method signature to which you could refer would have to
have exact parameter and return types, e.g. as in

    B g(B b);

Now in v2.0 you can bind to properly variant methods, too, e.g. as in

    B h(A a);
    C h(B b);
    C h(A a);

Based on the type hierarchy defined above, `C` is covariant with respect to `B`,
and thus can be substituted for the return type; conversely, `A` is contravariant
with respect to `B`, and thus can be used as the parameter type. Any combination
of this variance is allowed. The following is not valid, however, as we're
going the opposite direction (i.e. contravariant return, covariant parameters):

    A h(C c);

Out and ref parameters continue to be treated as invariant for delegates, as do
generic type parameters.

Now just to get co- and contravariance built into the runtime's type system. :)

