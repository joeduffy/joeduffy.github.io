---
layout: post
title: Stack allocations and fixed arrays
date: 2006-05-30 12:29:58.000000000 -07:00
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
C# 1.0 shipped with the ability to stack allocate data with the stackalloc 
keyword, much like C++'s  
[alloca](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/vclib/html/_CRT__alloca.asp). 
There are restrictions, however, around what you can allocate on the stack: 
Inline arrays of primitive types or structs that themselves have fields of 
primitive types (or structs that etc...). That's it. C# 2.0 now allows you to 
embed similar inline arrays inside other value types, even for those that are 
allocated inside of a reference type on the heap, by using the fixed keyword.

And of course, you can allocate arrays of those value types on the stack too:

```
using System;

unsafe class Program {
    struct A {
        internal int x;
        internal fixed byte y[1024];
    }

    public static void Main() {
        byte * bb = stackalloc byte[2048];
        Console.WriteLine("&bb         : {0:X}", (uint)&bb);
        Console.WriteLine("&bb[1]      : {0:X}", (uint)&bb[1]);
        Console.WriteLine("&bb[2048]   : {0:X}", (uint)&bb[2048]);

        A * a = stackalloc A[2048];
        Console.WriteLine("&a          : {0:X}", (uint)&a);
        Console.WriteLine("&a->x       : {0:X}", (uint)&a->x);
        Console.WriteLine("&a->y[0]    : {0:X}", (uint)&a->y[0]);
        Console.WriteLine("&a->y[2048] : {0:X}", (uint)&a->y[2048]);
        Console.WriteLine("&a[1]       : {0:X}", (uint)&a[1]);

        Console.WriteLine("&a[2048]    : {0:X}", (uint)&a[2048]);
    }
}
```

The use of this is of course almost always limited to unmanaged interop 
scenarios. For example, there's at least one place in the BCL where we use this 
to stack allocate the binary layout of a security descriptor that we then pass 
into the Win32 CreateMutex API, which avoids having to create a new interop 
struct. (Whether such hacks are a good thing to put in our code-base is another 
topic altogether...)

The stack allocated data doesn't outlive the stack frame, so as soon as you 
return from the function in which the stackalloc occurs, the data is gone. If 
you pass a pointer to it and somebody stores it, they could later try to 
dereference a pointer into dead (and possibly since reused) stack space. And 
reading too far can lead to buffer over- or underflows which bash other data on 
the stack. Using this requires compilation with /unsafe, and needless to say, 
you need to be careful with it (if not avoid it altogether).

