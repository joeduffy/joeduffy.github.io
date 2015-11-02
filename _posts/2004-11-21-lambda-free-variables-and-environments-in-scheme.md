---
layout: post
title: Lambda free variables and environments in Scheme
date: 2004-11-21 01:39:19.000000000 -08:00
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
Generating and dealing with Scheme lambda expressions in IL is a relatively
interesting problem. Scheme is statically-scoped, making the implementation a
bit more straightforward than, say, Common LISP. I have not yet determined the
_best_ approach in all cases yet, but certainly have a _workable_ approach.
There are many optimizations to be had, but I'll worry more about this at some
point in the future. Interestingly, the approach I have arrived at is very
similar to C# 2.0's anonymous delegate syntax, albeit for the auto-generated
delegates.

Consider a lambda expression as follows:

> (let (y 0) (define (mkincadder x) (lambda (z) (begin (set! y (+ y 1)) (+ x y
> z))))

This is a tad tricky, but can be roughly translated into the following C# 2.0
program:

> delegate object \_lambd(object z); static int y = 0; static \_lambd
> mkincadder(object x) { return delegate (object z) { y = y + 1; return x + y +
> z; }; }

Both a consumer in Scheme and C# will produce the same output. Here is a sample
program for each, both of which print out the numbers "7," "8," and "9" to the
console:

> Scheme: (let (a (mkincadder 5)) (begin (print (a 2)) (print (a 2)) (print (a
> 2))))
>
>
>
> C#: \_lambd a = mkincadder(5); Console.WriteLine(a(2));
> Console.WriteLine(a(2)); Console.WriteLine(a(2));

In fact, the implementation I've devised is nearly identical to the anonymous
delegate example. The one optimization I make is that the programmer is not
required to define a delegate signature, as this is a gory detail hidden by the
Scheme compiler itself. The compiler reuses auto-generated delegates with the
same signature, essentially building up a dictionary of unique delegate
signatures.

What happens under the hood is that each lambda is captured in a class with a
single apply method. The value of a lambda expression is simply a delegate to
this method. Any free variables from within the lambda body that are bound to
something other than an argument are teased out into a class variable and
captured at the time an instance is constructed. So for example, the generated
class for the lambda above looks like this (pseudo-code):

> public class \_\_lambd1 { private int x; private int y;
>
>
>
>   public \_\_lambd1(int x, int y) { this.x = x; this.y = y; }
>
>
>
>   public delegate object \_\_func(object z);
>
>
>
>   public object apply(object z) { y = y + 1; return x + y + z; } }
>
>
>
> public class \_\_global { public \_\_lambd1.\_\_func mkincadder(object x) {
> \_\_lambd1 ret = new \_\_lambd1(x, 0); return new
> \_\_lambd1.\_\_func(ret.apply); } }

Generating an entire class is overkill for simple lambdas which don't contain
non-arg free variables, an optimization I will likely make by accumulating such
functions on a single static class similar to the generated \_\_global class
containing named lambdas. Additionally, I will likely place functions that
share environments on the same class...

An interesting complication arises, however, when many lambdas begin to access
and mutate state within a shared environment. In fact, the concept of an
environment, while straightforward to do in an environment-passing interpreter,
feels like a lost concept in the clumsy translation to IL. At this point, I see
several options, a few of which seem feasible.

First, consider what I mean by this:

> (let (y 0) (define (mkincadder x) (lambda (z) (begin (set! y (+ y 1)) (+ x y
> z)))) (define (dec x) (set! y (- y x))))

Here we now have two things that can access the y variable: mkincadder and dec.
Why is this problematic? Well, now we cannot simply capture free variables and
store them as instance fields on individual lambda classes. We need to use some
sharable location in memory which can be mutated and where the function updates
will be visible to each other. For this particular example, the answer is
relatively straightforward: simply put an internal y variable on the \_\_global
class, and ensure the functions that must share an environment are declared on
it. In this case, that means mkincadder and dec get defined on \_\_global.
There will end up being only a single instance of \_\_global being used at
runtime, accomplishing the goal of having a shared environment.

This is the example pseudo-code for \_\_global; not much changes for the actual
lambda implementations other than referencing \_\_global for the y variable:

> public class \_\_global { internal object y = 0; public \_\_lambd1.\_\_func
> mkincadder(object x) { \_\_lambd1 ret = new \_\_lambd1(this, x); return new
> \_\_lambd1.\_\_func(ret.apply); } public \_\_lambd2.\_\_func dec(object x) {
> \_\_lambd2 ret = new \_\_lambd2(this, x); return new
> \_\_lambd2.\_\_func(ret.apply); } }

As mentioned above, the compiler now knows that any references to y from within
the lambdas must get turned into a reference to \_\_global.y. Notice that we
pass this to the constructor so it can hook a reference to its "parent
environment".

This seems to work for most cases. Here are a couple other solutions I had
previously considered which I might need to rely on slight variants for in
cases where the above doesn't work.

An alternative approach is to use nested classes. Items with shared
environments would get generated on the same class as above, while parent
environments would be implemented simply by searching up the outer class
hierarchy. This approach unfortunately gets pretty hairy quickly, though, as
the number of chained environments increases. As long as the Scheme compiler
hides this as an implementation detail that never surfaces to consumers, that's
fine. But this is unavoidable should somebody want to use us from C#.

A slight permutation of this solution would be to use inheritance rather than
nesting. That is, shared environment variables would be "inherited" using
static fields, and could be "hidden" by simply injecting identically-named
fields on derived classes. At code generation time, we could detect the right
place to reference in the class hierarchy based on what is defined where. This
is also tricky, however, because sometimes we would want to use static
variables and sometimes instance, depending on whether multiple environments
with different bindings for the same variable could be created (yes in most
cases).

Lastly, I could preserve the notion of an environment using a dictionary-like
construct passed around at runtime. This could be like a standard
environment-passing interpreter, and I would have fine-grained control over
what is referenced and how environments are explicitly chained together.
Unfortunately, I fear that the performance would suffer greatly with this
approach. (Instead of ldfld/stfld instructions, I would now have to call
methods to access and store variables. Ugh.)

These are certainly interesting problems, and I am just beginning to do a bit
of research on what other IL-based compilers do.

