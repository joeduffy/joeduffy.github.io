---
layout: post
title: More on Sencha type safety
date: 2004-12-31 01:14:31.000000000 -08:00
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
So I've decided to go back and try to do some static type checking for Sencha.
This is for a few reasons:

- It seems too easy not to do.

- Many of the one-off optimizations I was contemplating would have all been
  solved by a more general typing strategy.

- I'm interested in the area of type soundness in compiler implementations more
  so than many others, so it's a bit selfish, too.

I injected a new backend phase which traverses and "rewrites" the AST to
contain typing information before doing code generation. That is, each node in
the tree is given an evaluation type. The two base cases are: 1) function
evaluation, where the evaluation type is the return type; and, 2) literals,
where the evaluation type is the literal type. Everything else just borrows the
type from one of its subordinates. There are lots of cases where I can still
get stuck, however, and have to back out and resort to type erasure in such
situations. This means using object everywhere, with lots of boxing and
casting. This tends to have a viral nature up the AST, as once I start using
erasure on a less elder node, everyone further up in the tree starts to see
object as the inherited type. As an example, consider the Scheme if statement:

> <if-stmt> ::= (if <test> <consequent> <alternate>)

This has the type:

> <consequent> : **T** , <alternate> : **T**
> ----------------------------------- <if-stmt> : **T**
>
>
>
> <consequent> : **T1** , <alternate> : **T2**
> ----------------------------------- <if-stmt> : **typeof(_object_)**

In other words, if <consequent> and <alternate> are both of the same type **T**
, the type of <if-stmt> is **T**. Otherwise, we erase to _ **object** _, and
ensure to box up whatever is left on the stack; that is, if <test> evaluates to
true and **T1** is a value type, we must box; if <test> is false and **T2** is
a value type, we must box.

The chances to get stuck are numerous right now, and not just limited to funky
type mismatches like that mentioned above. This is primarily my own fault, as
any lambda gets generated as having an object return value. I theoretically can
support arbitrary return types since each lambda is represented by a generic
delegate (T1 Func1<T1,T2>(T2 a), T1 Func2<T1,T2,T3>(T2 a, T3 b), T1
Func3<T1,T2,T3,T4>(T2 a, T3 b, T4 c), and so on). But for now, I just make sure
to box everything up before passing it to such a function as an argument, and
ensure that from within the delegate I box any value types before returning.
The bottom line here is that any time I encounter an application of a first
class function, I have to resort to complete erasure of its arguments and
return value which ripples up the AST. In Scheme, this is obvioulsy a pretty
pervasive idiom, so I will certainly put the effort in to make this better.

The primary benefits right now are small optimizations, where I can now ask the
simple question: "What type does this expression evaluate to?" and make
optimizations (such as avoiding boxing) based on that. Moreover, I can bind to
more appropriate overloads of primitive and Framework methods since I know the
type in most cases. [My example from yesterday's
post](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=e748f403-94cc-48e4-8e29-b3e71284ff27)
with the (+ 1 2 3 4 5) Scheme expression looks a bit better now. Since I can
now bind to the type-safe version, the IL looks like this:

> .method public hidebysig static void  Main(string[] A\_0) cil managed {
> .entrypoint // Code size       91 (0x5b) .maxstack  4 .locals init ([0]
> float64[] V\_0) IL\_0000:  ldc.i4.4 IL\_0001:  newarr
> [mscorlib]System.Double IL\_0006:  stloc      V\_0 IL\_000a:  nop IL\_000b:
> nop IL\_000c:  ldc.r8     1.  IL\_0015:  ldloc.0 IL\_0016:  ldc.i4.0
> IL\_0017:  ldc.r8     2.  IL\_0020:  stelem.r8 IL\_0021:  ldloc.0 IL\_0022:
> ldc.i4.1 IL\_0023:  ldc.r8     3.  IL\_002c:  stelem.r8 IL\_002d:  ldloc.0
> IL\_002e:  ldc.i4.2 IL\_002f:  ldc.r8     4.  IL\_0038:  stelem.r8 IL\_0039:
> ldloc.0 IL\_003a:  ldc.i4.3 IL\_003b:  ldc.r8     5.  IL\_0044:  stelem.r8
> IL\_0045:  ldloc.0 IL\_0046:  call       float64
> [SenchaRuntimeLibrary]Sencha.Runtime.StandardSchemeFunctions::op\_Add(float64,
> float64[]) IL\_004b:  box        [mscorlib]System.Double IL\_0050:  call
> string [SenchaRuntimeLibrary]Sencha.Runtime.RuntimeHelper::ToString(object)
> IL\_0055:  call       void [mscorlib]System.Console::WriteLine(string)
> IL\_005a:  ret } // end of method Program::Main
>

Note that if I were to do something like (+ 1 2 ((lambda () 3)) 4 5), it breaks
down immediately and erases everything. It should be obvious that this can bind
to the op\_Add(double, double[]) overload, but it actually can't. This is
because, as stated above, all lambdas return object. Thus, when I evaluate
((lambda () 3)), the evaluation type of this expression turns out to be object.
This will be a focus for optimizations in the future.

