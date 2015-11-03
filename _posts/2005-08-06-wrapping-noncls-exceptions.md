---
layout: post
title: Wrapping non-CLS exceptions
date: 2005-08-06 10:55:26.000000000 -07:00
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
I got to work on a fun DCR with [Chris Brumme](http://blogs.msdn.com/cbrumme/)
back around the time we were shipping Whidbey Beta2. (DCR means Design Change
Request, essentially an unplanned change to the design of a component.) We went
back and forth as to whether or not to release it with Beta2, but given that
the implementation would have been right up against our lock down period, the
risk was too high. Thus, it'll first appear in our next CTP, RC, or whatever
release comes out before Whidbey RTMs.

**The Problem**

The crux of the problem is this. Lots of code gets written in C# assuming that
catch (Exception) is sufficient to backstop any exception a piece of CLR
software can generate. It turns out that, while doing so is not CLS compliant,
IL can throw just about anything. The throw instruction will happily take a
reference on the stack to any managed object--not just those whose type falls
into the Exception type hierarchy--and unwind the stack with it in hand.

A typical user (and even some Framework developers) write exception handling
code that looks like this (without all the Console.WriteLines of course :P):

> try { Console.WriteLine("Inside try..."); F(); Console.WriteLine("Exiting
> try"); } catch (Exception e) { Console.WriteLine("In catch ({0})", e); }
>
>
>
> Console.WriteLine("Outside try...exiting gracefully");

Now, this will work perfectly fine if F did as follows:

> static void F() { // foo...  throw new InvalidOperationException(); // bar...
> }

InvalidOperationException derives from Exception, so the catch block picks it
up. But what if F did this?

> static void F() { // foo...  throw 0; // bar...  }

Well, thankfully you can't write that in C#. But you can in verifiable IL:

> .method private hidebysig static void  F() cil managed { .maxstack  1 .locals
> init (int32 V\_0) ldc.i4.0 box [mscorlib]System.Int32 throw }

The specific type, int in this case, really doesn't matter. It could be any
other reference type that doesn't somehow derive from Exception, a value type,
or even a null reference!

You might turn your nose up at the idea of catching all exceptions. I did. But
consider if you need to roll back sensitive state that was introduced inside
the try block. [I've already covered why doing this in the finally block only
might not be
sufficient.](http://www.bluebytesoftware.com/blog/SearchView.aspx?q=exceptions
two pass#ab8716b75-b068-46b5-9926-0b889861c09c) If F() were a virtual method
that a user could override and somehow supply an object of their choosing, a
malicious user could use this (along with an exception filter) to mount a nasty
security attack. Coming from a Java background, I was initially very surprised
how real this problem is...The world becomes much more complex when you interop
so tightly with the OS. For example, the CLR has to work well with SEH
primarily for situations where mixed call stacks make unmanaged-to-managed (and
vice versa) transitions. Suffice it to say that the two pass model introduces
lots of complexities.

**The Solution**

Many people think that this is inherently a C# problem. Isn't it C#, not the
runtime, that forces people to think in terms of Exception-derived exception
hierarchies? Certainly there is precedent that indicates throwing arbitrary
objects is a fine thing for a language to do. Just take a look at C++ and
Python. And furthermore, C# actually enables you to fix this problem:

> try { F(); } catch { // ...  }

This approach has two problems. First, the catch-all handler doesn't expose to
the programmer the exception that was thrown. C# could have changed this (e.g.
with TLS data exposed through a static member, e.g. Exception.GetLastThrown, or
something like that). That still wouldn't solve the problem that things that
aren't exceptions don't accumulate a stack trace as they pass through the
stack, making them nearly impossible to debug. But probably worse, the average
programmer doesn't even know this is a problem! Including those who are writing
code for the Frameworks that Microsoft ships. But they really shouldn't have to
know. This problem spans many languages, and it really made sense for the
runtime to help them out.

We solved the problem by introducing some new behavior inside the exception
subsystem of the CLR. It's mostly transparent to the user. When something gets
thrown that is not derived from Exception, we instantiate a new
System.Runtime.CompilerServices.RuntimeWrappedException, supply the originally
thrown object as an instance field of that puppy, and propagate that instead.
It's public; most people will never catch such things directly, but you can if
you need to access the thing that got thrown in the first place.

This has some nice benefits. The C# user can continue writing catch
(Exception), and--since RuntimeWrappedException derives from Exception--will
receive any non-CLS exceptions. The try/catch block we had originally written
will just work for free now. And furthermore, we now capture stack trace for
everything, meaning that debugging and crash dumps are immediately much more
useful. Lastly, there's still a playground for languages that wish to continue
participating in throwing exceptions not derived from Exception.

**Supporting Naughty Languages**

This last point actually complicates the design quite a bit. We queried our
language community, and perhaps not-so-surprisingly, there are a lot of
compilers that can throw anything. C++/CLI is one of them. So we had to
preserve the existing semantics for those languages, while still enabling C#
users to get the benefits of this change. Thus was born
System.Runtime.CompilerServices.RuntimeCompatibilityAttribute. The C# and VB
compilers will auto-decorate any compiled assemblies with this attribute,
setting its property WrapNonClsExceptions to true. The runtime keys off of that
to determine whether the old or new behavior is desired. The default is that we
don't _surface_ the aforementioned wrapping behavior (although as an
implementation detail, we still do it). We expect more of these
compatibility-preserving changes in the future, which resulted in the somewhat
generic attribute naming.

If the attribute is absent, or present and WrapNonClsExceptions is set to
false, we still actually wrap the exception internally so we can (1) maintain
good stack traces for debugging and (2) to cleanup and optimize some of the
exception code paths that had to branch based on the type of the exception. But
we unwrap it as we match it against catch handlers. And we unwrap it when we
deliver it to catch filters. So these languages don't know anything ever
changed.

It's actually gets a bit more complicated than this, however. For
cross-language call stacks, we actually do the unwrapping based on whatever the
assembly in which the catch clause's assembly wants to do. Say method M in
C++/CLI assembly A throws an int; this is called by method N in C# assembly B.
At throw time, we construct a new RuntimeWrappedException and use that for
propagation. If assembly A catches it, all it sees is the int...It never knows
we wrapped it. But if it leaks, and assembly B had wrapped the call in M with a
catch (Exception), that handler will actually see a RuntimeWrappedException.
Furthermore, consider if there were another C++/CLI assembly C; if N didn't
catch the leaked int, it would surface in C as if it never got wrapped. This is
what users expect to happen, and it composes very nicely.

Most users won't even know about this change. But hopefully their code gets
more secure and robust for free.

