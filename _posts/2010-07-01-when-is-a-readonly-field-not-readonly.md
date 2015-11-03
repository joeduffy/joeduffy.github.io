---
layout: post
title: When is a readonly field not readonly?
date: 2010-07-01 12:41:20.000000000 -07:00
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
In .NET today, readonly/initonly-ness is in the eye of the provider. Not the beholder.

Although both C# and the CLR verifier go to great pains to ensure you don't change
a readonly/initonly field outside of its constructor (or class constructor, in the
case of a static field), this guarantee doesn't imply what you might imagine. It
means what it says: you can't change such fields except for in certain contexts.

If you try, C# won't let you, including forming byrefs to them:

```
v.cs(0,0): error CS0191: A readonly field cannot be assigned to (except in a constructor or a variable initializer)
v.cs(0,0): error CS0192: A readonly field cannot be passed ref or out (except in a constructor)
v.cs(0,0): error CS0198: A static readonly field cannot be assigned to (except in a static constructor or a variable initializer)
v.cs(0,0): error CS0199: A static readonly field cannot be passed ref or out (except in a static constructor)
```

And neither will the CLR verifier:

```
[IL]: Error: [c:\v.exe : C::Main][offset 0x00000001] Cannot change initonly field outside its .ctor.
```

Of course, attempting to invoke an operation on a readonly struct will make a defensive
copy locally, and invoke the method against that. This ensures the readonly contents
cannot change.

One unfortunate hole in this safety is with unions. You do not need unsafe code to
break readonly, and yet the effect is the same as with an unverifiable program that
writes to a readonly field:

```
struct S1 {
    public readonly int X;
}

struct S2 {
    public int X;
}

[StructLayout(LayoutKind.Explicit)]
struct S3 {
    [FieldOffset(0)]
    public S1 A;
    [FieldOffset(0)]
    public S2 B;
}
```

Now we can change A.X via B.X, even though A.X is supposedly readonly:

```
S3 s3 = ...;
int x = s3.A.X;
s3.B.X++;
ASSERT(x == s3.A.X); // false; it is +1
```

The same would have been true even if the field S3.A was marked readonly.

This is quite an evil trick. I have to be honest that I believe this is a CIL verification
hole, and should produce unverifiable MSIL much like when you try to overlay structs
containing overlapping GC references. Nevertheless, it is what it is.

Let's step back. Why does all of this matter, anyway, and what guarantees were we
hoping that readonly would provide?

It would be ideal, I assert, if the guarantee was not just "the target field can
only be written to in the constructor", but also "the target field, once read, cannot
be observed with a different value later on". This would not be true during construction,
but we'd like to say it holds at all other times.

The above example throws a wrench in this idea. As does the following example. But
this new example will be more disturbing, because the solution is not a simple verifier
change.

What would you expect this program to print to the console?

```
struct S {
    public readonly int X;

    public S(int x) { X = x; }

    public void MultiplyInto(int c, out S target) {
        System.Console.WriteLine(this.X);
        target = new S(X * c);
        System.Console.WriteLine(this.X); // same? it is, after all, readonly.
    }
}

S s = new S(42);
s.MultiplyInto(10, out s);
```

As you may or may not have guessed, the output is "42" followed by "420". Yes, the
value of 'this.X' changes after we have assigned to 'target' inside MultiplyTo, because
the caller aliases the out-param with the 'this' param. Recall that parameter passing
for structs in C# is done byref, so that these two references actually physically
point to the same location when that call is made. The assignment to 'target', therefore,
actually replaces the entire contents of 'this' all at once. And hence this gives
the illusion that readonly fields are shifting.

You might be tempted to say that this can be prevented with alias analysis. But this
is deceptively difficult to do. Consider this more complicated example:

```
class C {
    public struct S S;
}

void M1(C c) {
    M2(c, out c.S);
}

void M2(C c, out S s) {
    c.S.MultiplyInto(10, out s);
}
```

It is in no way clear inside M2 that the two aliases refer to the same location.
The aliasing occurred higher up in the stack. Although byrefs are restricted to stack-only
passing, making the necessary alias analysis tantalizingly close to attainable, it
is nontrivial to say the least. Presumably we would have had to have blocked the
forming of the byref within M1, rather than its use within M2. We could fall back
to runtime checks, but that is also unfortunate for numerous reasons.

The moral of the story? Structs as containers of readonly values are not to be trusted,
at least not for situations that call for bulletproof safety, such as caching values
in the compiler rather than rereading them, because the fields are readonly. Although
C# and the CLR do a good job at verifying readonly/initonly are done right at the
initialization site, there are still places where these guarantees break down. Thankfully
the byref aliasing problem does not threaten thread-safety, but the union problem
does. And in conclusion, I do have to imagine all of this will get fixed somewhere
down the road, it's just a matter of when and where.

