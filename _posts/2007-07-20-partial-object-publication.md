---
layout: post
title: Partial object publication
date: 2007-07-20 21:01:54.000000000 -07:00
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
Whether or not it's possible for an object to be published before it has been fully
constructed is perhaps the most common .NET memory model-related question that arises
time and time again.  In fact, there was a discussion this week on an internal
.NET alias, and another a couple weeks ago [in the Joel on Software forums](http://discuss.joelonsoftware.com/default.asp?joel.3.518960).

The basic question is:  Can one thread read a pointer to an object whose constructor
has not finished running on a separate thread?

This pattern pops up quite a bit in lazily initialization scenarios, for instance.
For example, given some class C:

```
class C {
    public int f;
    public static C s_c;
    public C() {
        f = 55;
    }
}
```

And some code that lazily initializes and then uses the object:

```
if (s_c == null) s_c = new C();
Console.WriteLine(s_c.f);
```

Specifically, is it possible in this case to write 0 (or garbage) to the console,
instead of 55?

(Note that related examples, like the Joel on Software thread, use separate initialization
routines or steps before publishing the pointer.  It boils down to the same
issue.)

How could observing anything other 'f' value than 55 possibly happen anyway,
you might wonder?  Well, since some processors are free to execute certain instructions
out-of-order, the write of the return value of 'new C()' could theoretically
retire before the write to that instance's 'f' field.  This isn't an
issue on X86, since the processor memory model doesn't permit it, but architectures
like IA64 do permit such reordering.  Moreover, some compilers might decide
to reorder writes; in this example, if the constructor were to be inlined, the compiler
could subsequently use code motion to delay the write to the field.

(Note: obviously the constructor could publish a reference to 'this' before it has
finished.  In this case, clearly other threads could then access the instance
before it was fully constructed.)

On .NET, the answer is no, this kind of code motion and processor reordering is not
legal.  This specific example was a primary motivation for the strengthening
changes we made to the .NET Framework 2.0's implemented memory model in the CLR.
Writes always retire in-order.  To forbid out-of-order writes, the CLR's JIT
compiler emits the proper instructions on appropriate architectures (i.e. in this
case, ensuring all writes on IA64 are store/release). Although reads can retire out-of-order,
the data dependence on the pointer value being published prevents subsequent read
of fields from happening before the read of the pointer itself.  So thankfully
this simply cannot happen.

A lot of .NET code out there, including code in the Framework itself, would have
suddenly been open to reordering bugs when the CLR 2.0 shipped with IA64 support
had we not made this decision.  We decided to sacrifice some performance on
one particular architecture (and possibly subsequent ones) to ensure these tricky
races didn't bite people unexpectedly, and to avoid a costly audit of the entire
Framework.

Lastly, I will note a couple things.  First, this strength is not specified
in ECMA, so other implementations of the CLI do not provide such guarantees.
(I hope one day we decide to standardize the stronger model.)  I don't know
what Mono implements, but it may be weaker.  Second, the Java Memory Model does
not prohibit such publication reorderings, unless the assignments are to a 'final'
field.  So I'm sure people who are familiar with the JMM will assume this
pattern is broken on .NET and use locks and/or explicit memory barriers instead.
This approach is more conservative and still leads to correct code, however,
so it really matters very little for most code.

