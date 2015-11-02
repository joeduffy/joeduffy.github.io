---
layout: post
title: Verifiable ByRef returns?
date: 2006-05-24 18:23:45.000000000 -07:00
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
In managed code, you can pass ByRefs "down the stack." You can't do much aside 
from that, however, other than use things like ldind and stind on them. And of 
course, you can cast them to native pointers, store them elsewhere, and so on, 
but those sorts of (evil) things are unverifiable.

Right? Well, sort of.

In Whidbey, we made a change to the verification rules such that a function can 
now return a ByRef to a caller. This of course is safe so long as the ByRef 
doesn't refer to a stack location. A field ref inside a heap-allocated object, 
static field ref, or an array element ref are all just fine. And of course, a 
function can just return a ByRef that was passed to it as an argument. Take a 
look at this IL:

```
.assembly extern mscorlib {}
.assembly byrefret {}

.class Program extends [mscorlib]System.Object {
    .field static int32 s_x

    .method static void Main() {
        .entrypoint
        call int32& Program::f()
        ldind.i4
        call void [mscorlib]System.Console::WriteLine(int32)
        call int32& Program::g()
        ldind.i4
        call void [mscorlib]System.Console::WriteLine(int32)
        ret
    }

    .method static int32& f() {
        ldsflda int32 Program::s_x
        ret
    }

    .method static int32& g() {
        .locals init (int32 x)
        ldloca x
        ret
    }
}
```

Function f verifies just fine, since it just returns a ByRef to a static field, 
whereas function g fails verification, because it returns a ByRef to a local on 
the stack. You actually can't write code to produce the IL shown above from any 
of Microsoft's compilers except for VC++, i.e. C# won't let you say "static ref 
int f() { return ref s\_x; }".

Now, why would you ever want such a thing? VC++ needed it, for example, to 
implement STL.NET. Traditional STL returns references to elements inside of 
internal data structures, which can subsequently be modified. Without this 
support, such values would need to be copied, or the STL.NET APIs would have had 
to deviate from the traditional STL APIs.

Interestingly, this doesn't change the ECMA Specification. It's always been 
loose on the issue, saying in Section 12.1.1.2 of Partition I: "Verification 
restrictions guarantee that, if all code is verifiable, a managed pointer to a 
value on the evaluation stack doesn't outlast the life of the location to which 
it points." Since you can't return a ByRef to a stack location, we don't violate 
this guarantee. Our previous verifier was simply being overly strict.

