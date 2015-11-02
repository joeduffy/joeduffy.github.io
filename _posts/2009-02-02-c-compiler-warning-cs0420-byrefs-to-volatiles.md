---
layout: post
title: 'C# compiler warning CS0420: byrefs to volatiles'
date: 2009-02-02 14:08:00.000000000 -08:00
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
I frequently get asked about the C# compiler's warning CS0420 about taking byrefs
to volatile fields.  For example, given a program

```
class P {
    static volatile int x;

    static void Main() {
        f(ref x);
    }

    static void f(ref int y) {
        while (y == 0) ;
    }
}
```

the C# compiler will complain

```
xx.cs(8,15): warning CS0420: 'P.x': a reference to a volatile field
    will not be treated as volatile
```

because of the line containing 'ref x'.  (The same applies to 'out' parameters
too.)  The natural question is, of course, whether to worry about it.

In general, the answer is yes, you must worry.  In the above example, the use
of the 'y' parameter inside 'f' will not be treated as volatile, as the warning says.
What does that mean in practice?  For one, the read of 'y' in 'f's while loop
could be considered loop invariant by the JIT compiler and hoisted, and you'd possibly
loop forever.  It also means that on IA64 platforms, such reads will be emitted
as ordinary loads instead of the special load-acquire variant that is emitted for
volatile loads.  This can lead to reordering bugs.  In other words, you
lose the volatile-ness of the field as soon as you cast it away as an ordinary byref.
And unlike C++ where you can have a volatile pointer, there's no way to mark a .NET
byref as volatile.

(You can use the Thread.VolatileRead and VolatileWrite methods to use a byref in
a volatile manner.  Unfortunately they are far more costly than ordinary volatile
loads and stores.)

There is one particularly annoying case in which this warning is complete noise:
when passing a byref to an API that internally performs volatile (or stronger) loads
and stores.  I.e., the Interlocked.\*, Thread.VolatileRead, and VolatileWrite
methods.  Because these APIs internally use explicit memory barriers and atomic
hardware instructions, the byref will effectively be treated as volatile regardless
of whether it was taken from a volatile field or not.  And therefore it is safe.

For instance, the compiler will warn you about the following code

```
volatile int x;

static void f() {
    Interlocked.Exchange(ref x, 1);
}
```

even though there is no problem.  You can suppress the warning with a "#pragma
warning disable" just before the call

```
volatile int x;

static void f() {
#pragma warning disable 0420
    Interlocked.Exchange(ref x, 1);
#pragma warning restore 0420
}
```

and then restore it immediately afterwards.  (It's a good idea to restore the
warning so that you catch other possibly-problematic instances from being missed.)

This comes up a whole lot.  Why?  Because many times you'll mark a
field volatile, even though it is updated exclusively with CAS operations, because
it's also used in other contexts: e.g., sequences where loads mustn't reorder or
erroneously be considered loop invariant.  I personally have a habit of always
marking these variables as such, mostly as a carryover from Win32 whose InterlockedXX
family of APIs demand volatile pointers (i.e., volatile \* LONG).

I'm told that this annoying case might be fixed in the next C# compiler, by the way.
Until then, I figured I'd throw this up for reference purposes.

