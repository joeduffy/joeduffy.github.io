---
layout: post
title: Explicit layout structs and unions
date: 2005-02-03 22:13:48.000000000 -08:00
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
During [our](http://blogs.msdn.com/brada/archive/2005/01/31/363837.aspx)
[chat](http://msdn.microsoft.com/netframework/programming/classlibraries/)
yesterday, a question came up about explicit layout structs.

**Overlapping Fields**

In particular, somebody was wondering why overlapping reference pointers are
disallowed, yet overlapping value types are entirely legal. Consider what would
happen if we did allow this: accessing a reference to an instance of type _a_
through an overlapping reference field of incorrect type _b _would result in
very bad behavior (or worse: a value type field_ b_ whose bytes would be
interepreted as a reference to who the heck knows where).

I'm not precisely sure what the runtime would do in such a circumstance (die
gracefully one would hope), but I suspect its not so clearly defined -- hence
the disallowance of this construct. :)

Overlapping structs are allowed since structs are just well defined sequences
of bytes. One could argue this is a blemish on the CTS's type soundness (and I
would agree wholeheartedly), but I'll leave that to other folks to debate.

**Union<T,U>?**

So anyhow, it got me wondering: could one throw together a general purpose
union type using generics? I decided to try...

> using System.Runtime.InteropServices;
>
>
>
>
>
>
>
> [StructLayout(LayoutKind.Explicit)]
>
>
>
> struct Union<T,U>
>
>
>
>     where T : struct
>
>
>
>     where U : struct
>
>
>
> {
>
>
>
>
>
>
>
>   // fields
>
>
>
>   [FieldOffset(0)]
>
>
>
>   private bool isT;
>
>
>
>   [FieldOffset(1)]
>
>
>
>   private T tValue;
>
>
>
>   [FieldOffset(1)]
>
>
>
>   private U uValue;
>
>
>
>
>
>
>
>   // ctors
>
>
>
>   public Union(T t)
>
>
>
>   {
>
>
>
>     uValue = default(U); //shutup compiler
>
>
>
>     tValue = t;
>
>
>
>     isT = true;
>
>
>
>   }
>
>
>
>
>
>
>
>   public Union(U u)
>
>
>
>   {
>
>
>
>     tValue = default(T); //shutup compiler
>
>
>
>     uValue = u;
>
>
>
>     isT = false;
>
>
>
>   }
>
>
>
>
>
>
>
>   // properties
>
>
>
>   public bool IsT
>
>
>
>   {
>
>
>
>     get { return isT; }
>
>
>
>   }
>
>
>
>
>
>
>
>   public T TValue
>
>
>
>   {
>
>
>
>     get { return tValue; }
>
>
>
>     set { tValue = value; isT = true; }
>
>
>
>   }
>
>
>
>
>
>
>
>   public U UValue
>
>
>
>   {
>
>
>
>     get { return uValue; }
>
>
>
>     set { uValue = value; isT = false; }
>
>
>
>   }
>
>
>
>
>
>
>
> }

This enables you to do fancy unions with certain kinds of structs, using just
one wasted byte at the beginning for the bool isT. It'd be nice if you could do
reference types, too, but unless you can guarantee nobody will ever try to
access, say, uValue when isT is true, it ain't gonna happen. Further, even with
structs this wouldn't work if T or U had at least one reference type instance
field for the same reasons outlined above -- you could imagine bad things
happening if you were allowed to access a "corrupt" pointer, basically just
some random bytes which make up a value type instance interpreted as a pointer
to a memory location (ouch).

Looks great, right? Well, minus all of the aforementioned caveats. I marvelled
at the beauty of this code. What a clever chap I am, I told myself. It even
compiled!

**Not So Good News**

Unfortunately we don't allow execution of even this watered down version.

Why?

Because of the use of generics.

As I said, compilers permit it (at least C# does), but it won't pass our
verifier and thus causes a TypeLoadException if you try to use the generated
IL. In this case, it should be obvious that we _could _correctly lay out the
struct in memory when the type is being JITted. However, the behavior here --
even if it passed verification -- simply isn't defined at all. Further, my
guess is that there are some JIT optimizations (e.g. eager struct size
computation that might not be generics-aware yet) that would be thrown off if
we just permitted this to get through. Not that it isn't possible, just that we
haven't spent the time to enable it... probably because of the relative
obscurity (leave it to me to find the obscure things). :)

The behavior is entirely deterministic statically and thus at runtime because
we only place the parameterized types at the end of the struct. Once the type
is closed and we know the type arguments, we can easily compute the size (e.g.
1 + max(sizeof(T), sizeof(U))). If we had fields after the parameterized types,
however, it'd be impossible to specify the right offsets statically and thus
we'd run into problems. Although, we could still easily determine the right
amount of storage at JIT time. One could imagine a
[FieldOffset(max(sizeof(T),sizeof(U))+x)] construct that made this possible.

It's a shame. A general purpose Union<T,U> type would be pretty damn cool.

