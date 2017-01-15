---
layout: post
title: Throwing, catching, and a little bit of paranoia
date: 2005-01-13 21:51:49.000000000 -08:00
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
The CLR employs a two phase exception handling model. In the first phase, the
stack will be searched for an appropriate exception handler (i.e. one who's
filter is able to deal with the exception), and in the second, the stack will
unwind until the frame containing the handler is reached. Unwinding the stack
causes finally blocks on the frames being blown through to be executed in the
process. This does mean, however, that filters further up in the stack get a
chance to run before finally blocks, resulting in some potentially odd
behavior.

There are some interesting consequences of this design that, until today, I had
not been cognizant of. Not only are they a bit unintuitive, but they are quite
scary, too! Chris Brumme is the obvious expert in this area, and has an
[awesome essay on the whole topic of exceptions in the runtime over on his
blog](http://blogs.msdn.com/cbrumme/archive/2003/10/01/51524.aspx). Eric
Lippert also [has a post
here](http://weblogs.asp.net/ericlippert/archive/2004/09/01/224064.aspx) that
talks about the specific issue I am referring to in the context of VB.

Basically, say you write this code here:

    void g() {
      // A: impersonate, change context on thread, etc.
      try {
        throw new Exception();
      } finally { 
        // B: revert impersonation, context change, etc.
      }
    }

All looks well, right? Aside from the subtle nuance that a throw could
theoretically occur between `A` and beginning of the try block, it seems that
code outside of `g()` could never execute under the elevated permissions (or
within a locked region, etc.) before `B` reverts whatever state was mucked with.
This is quite a canonical example - the recommended pattern for people who wish
to perform cleanup before an unhandled exception transfers control elsewhere.

Wrong! Before the finally block, and hence `B`, even gets executed, filters
further up the stack will have a chance to tell the runtime whether they will
handle the thrown exception or not. A nice filter will just say yes or no,
while a naughty filter might take advantage of the context you might have
(accidentally) left on the thread. There's really no limit to what a filter can
do, and based on the context you might have unintentionally leaked (security,
synchronization, and so on), the possibilities are endless. Even partially
trusted code filters will run. Uh oh. This certainly isn't good! (Luckily an
`XxxPermission.Assert()` is only valid for the stack frame in which it occurs,
e.g. so at least _these_ can't leak up the stack.)

C# doesn't enable you to write filters (yet), but VB does. Obviously, IL
supports these in a first class way. As an example, if the following IL snippet
was used to call into `g()`, the region from `IL_filt_beg` to `IL_filt_end` would
execute after `A` is called but before `B` above:

    .try { 
      ldarg.0
      call instance void X::g()
      leave.s
      IL_after 
    } filter {
    IL_filt_beg:
      pop // do something naughty!
      ldc.i4.1
    IL_filt_end:
      endfilter 
    } { 
      pop
      leave.s
      IL_after
    }
    IL_after: ...

The [compilable IL found
here](http://www.bluebytesoftware.com/code/05/01/13/exfilt.il.txt) shows a
demonstration of this. The C# psuedo-code is:

    class X {
      static void Main() { 
        X x = new X();
        x.f();
      }

      void f() { 
        try { 
          g(); 
        } catch filter (gotcha()) // not legal code, of course 
        { 
          Console.WriteLine("2nd phase: execute handler. In f().catch{}");
        }
      }

      void g() { 
        Console.WriteLine("Security context applied!");
        try { 
          throw new Exception(); 
        } finally { 
          Console.WriteLine("Security context reverted.");
        }
      }

      bool gotcha() {
        Console.WriteLine("1st phase: search for handler. Haha, gotcha!");
        return true;
      }
    }

The output of which is:

> Security context applied!
>
> 1st phase search for handler. Haha, gotcha!
>
> Security context reverted.
>
> 2nd phase: execute handler. In f().catch{}");

This clearly demonstrates what happens. `gotcha()` is invoked before the context
has been removed in the finally block. One possible solution, of course, is to
write your original code as:

    void g() {
      // A: impersonate, change context on thread, etc.
      try { 
        throw new Exception();
      } catch {
        // B: revert impersonation, context change, etc.
        throw;
      } finally {
        // B: revert impersonation, context change, etc.
      }
    }

Which may seem a little paranoid, but indeed guarantees cleanup will occur
under most normal circumstances (well, when your app isn't about to die, of
course). ;)

Also note that `catch { }` isn't quite the same as `catch (Exception) { }`, due to
the capability of the runtime to toss around _anything_ (even objects of a type
not derived from `System.Exception`). C++/CLI actually makes liberal use of this
feature, as do a couple other 3rd party languages. Because C# doesn't even
enable you to write code that makes use of exception filters _or_ throwing
non-Exception exceptions, it's admittedly not obvious to most people that they
even need to worry about such things!

