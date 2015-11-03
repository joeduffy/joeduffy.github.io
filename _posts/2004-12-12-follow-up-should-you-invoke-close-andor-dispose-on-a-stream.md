---
layout: post
title: 'Follow up: Should you invoke Close() and/or Dispose() on a Stream'
date: 2004-12-12 20:41:13.000000000 -08:00
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
Thanks for [all of the
answers](http://www.bluebytesoftware.com/blog/CommentView.aspx?guid=51ad4b85-269e-45c0-97d0-57982c392d11)
to [the
quiz](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=51ad4b85-269e-45c0-97d0-57982c392d11).
I appreciate the involvement, and most of the feedback was exactly the kind of
thing we're looking for.

**Quiz Answers**

Before jumping into this in too much detail, I'll first go ahead and answer the
set of answers from the first post. Several answers to the post were correct,
while others were mostly correct. I loved the comment "Obviously its a
confusing API. [snip] Keep it simple, no?" I couldn't agree more. :) Anyhow, on
to the answers!

- _What does invoking Close() on an open Stream do?_ The implementation should
  free any large allocations of memory (flushing of buffers, for example) and
release any unmanaged resources. I'm speaking in terms of the contract of this
method, but obviously FileStream and other Stream-derived types we ship
implement this contract correctly. There's no guarantee that the object will be
useable after calling this.

- _What does invoking Dispose() on an open Stream do?_ It calls Close().

- _Should you call both at some point in a Stream's lifecycle?  _No! Call one
  or the other, they do the same exact thing.

  - _If not, why?_ Calling both is wasteful as they do the same thing. They are
    both resilient to multiple calls, so nothing terrible will happen if you do
end up calling them both.

- _Can you call only one without having to call the other?  _Yep. In fact, you
  should.

- _Is it weird that there is both a Close() and Dispose() on a single type, or
  does that seem natural? Based on your understanding of the pattern, do you
think we should continue to use it, or is there a better one?  _I think it is
certainly confusing, and that in the future we can work on making this clearer.
My philosophy—outlined further below—is that hiding Dispose() as an
explicit interface implementation has resulted in a lot of confusion around
user perception of disposability. If a public Dispose() method suddenly showed
up on FileStream, for example, people would likely not know what to do (and
probably end up calling both).

**A Bit of History**

We have had guidelines around Dispose() for quite a long time, and it turns out
that most people developing classes for the Framework actually follow them! The
guidelines suggest that, should a more domain-appropriate name for a
Dispose()-like activity be present (e.g. closing a stream, database connection,
etc.), a class should explicitly implement IDisposable.Dispose(), and create
the more domain-specific method to cleanup resources to be directly called by
developers. In such a situation, both Dispose() and this other method, usually
Close(), should do the same thing.

The only reasoning I've heard for originally creating this redundancy is to
play nicely with C#'s using statement (or other IDisposable-based mechanisms).
It isn't expected that people would ever manually call Dispose(), hence the
reason for effectively hiding it. For example,

> using (Stream s = //...)
>
>
>
> {
>
>
>
>   //...
>
>
>
> }

...or

> Stream s = //...
>
>
>
> try
>
>
>
> {
>
>
>
>   //...
>
>
>
> }
>
>
>
> finally
>
>
>
> {
>
>
>
>   s.Close();
>
>
>
> }

...are both expected coding patterns. But,

> Stream s = //...
>
>
>
> try
>
>
>
> {
>
>
>
>   //...
>
>
>
> }
>
>
>
> finally
>
>
>
> {
>
>
>
>   ((IDisposable)s).Dispose();
>
>
>
> }

...is not. If Dispose() were public, the cast wouldn't be necessary in the last
example, but admittedly many people would probably write code like this:

> Stream s = //...
>
>
>
> try
>
>
>
> {
>
>
>
>   //...
>
>
>
> }
>
>
>
> finally
>
>
>
> {
>
>
>
>   s.Close();
>
>
>
>   s.Dispose();
>
>
>
> }

We're already making it easy to write the following code in today's world:

> using (Stream s = //...)
>
>
>
> {
>
>
>
>   try
>
>
>
>   {
>
>
>
>     //...
>
>
>
>   }
>
>
>
>   finally
>
>
>
>   {
>
>
>
>     s.Close();
>
>
>
>   }
>
>
>
> }

...which incidentally is probably a better pattern if you did have to call both
Close() and Dispose(), just in case Close() had decided to throw an exception.

**The Dispose(bool) Pattern**

For some situations, such as with FileStream, for example, we've further
refined the pattern to use Dispose(bool disposing). This is necessary in
situations where cleanup logic differs depending on whether you are finalizing
or explicitly disposing of an object, and helps to prevent duplication of
cleanup code in multiple methods. Unfortunately, Dispose(bool) should always be
a protected method, so without any support for protected interfaces, it's
really just a documented pattern and not captured as an interface contract
anywhere. Nonetheless, it's very widely used in the Framework.

The idea is that all of the logic for cleanup goes into Dispose(bool), and both
the finalizer and Dispose() method call into it passing different bool values.
A finalizer calling Dispose(bool) passes in false, while Dispose() passes in
true as the argument. The method then uses this information to sort of
bifurcate its logic into stuff appropriate to do during finalization and other
things which are appropriate in both finalize and dispose cases. The former is
a subset due to the strict requirements around what you can and cannot do/touch
in a finalizer along with the fact that you don't need to suppress finalization
if you are already being finalized. This pattern will typically look something
like this:

> class MyType : IDisposable
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
>     ~MyType()
>
>
>
>     {
>
>
>
>         Dispose(false);
>
>
>
>     }
>
>
>
>
>
>
>
>     public void Dispose()
>
>
>
>     {
>
>
>
>         Dispose(true);
>
>
>
>     }
>
>
>
>
>
>
>
>     protected virtual void Dispose(bool disposing)
>
>
>
>     {
>
>
>
>         // shared cleanup logic
>
>
>
>
>
>
>
>         if (disposing)
>
>
>
>         {
>
>
>
>             // dispose-specific logic
>
>
>
>             GC.SuppressFinalize(this);
>
>
>
>         }
>
>
>
>     }
>
>
>
>
>
>
>
> }

Base classes will then override Dispose(bool) to customize behavior, making
sure to call base.Dispose(disposing) at the very end of the override. The least
derived type's implementation makes a virtual call to Dispose(bool), so it's
never necessary for a further derived type to change this definition.
Interestingly, the only dispose-specific logic that typically needs to be
captured is a call to GC.SuppressFinalize(this).

So what happens if we throw a Close() method into the mix? Well, the Close()
method itself just does the same thing as Dispose() -- that, they both make a
call to Dispose(true). But, the pattern also goes on to say that you should
explicitly implement Dispose(), hiding it from the public surface of the class.
(Note this is the case even in situations where the Dispose(bool) pattern isn't
being used. So, if you just have a Close() and Dispose() method, Dispose()
should be explicitly implemented.) So our class changes to the following:

> class MyType : IDisposable
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
>     ~MyType()
>
>
>
>     {
>
>
>
>         Dispose(false);
>
>
>
>     }
>
>
>
>
>
>
>
>     public void Close()
>
>
>
>     {
>
>
>
>         Dispose(true);
>
>
>
>     }
>
>
>
>
>
>
>
>     void IDisposable.Dispose()
>
>
>
>     {
>
>
>
>         Dispose(true);
>
>
>
>     }
>
>
>
>
>
>
>
>     protected virtual void Dispose(bool disposing)
>
>
>
>     {
>
>
>
>         // shared cleanup logic
>
>
>
>
>
>
>
>         if (disposing)
>
>
>
>         {
>
>
>
>             // dispose-specific logic
>
>
>
>             GC.SuppressFinalize(this);
>
>
>
>         }
>
>
>
>     }
>
>
>
>
>
>
>
> }

To further illustrate the way methods relate to and delegate to each other
under this pattern, consider this diagram:

![](http://www.bluebytesoftware.com/blog/images/12-04-disposebool.gif)

Regardless of the complexity, notice what a developer would see in
IntelliSense: one method called Close(). It's easy to lose track of this fact
when discussing all of these implementation details.

**Some Philosophy**

It turns out that I disagree with the hiding of Dispose() in such
circumstances. Arguably, somebody won't forget to Close() a FileStream, but
anything that holds on to precious resources should scream out that it needs to
be cleaned up and I believe that a Dispose() method is a consistent and clear
way to do just that. Moreover, the contract of Dispose() and Close() are
slightly different to me: Dispose() is the equivalent to a deterministic
destructor, while Close() is a semantically-meaningful operation for a given
class. For example, FileStream.Dispose() means "I am done with this stream,
clean up any expensive resources to hold on to and make it unusable from this
point on;" on the other hand, FileStream.Close() means precisely "Flush the
buffer and close the file." (You could argue that flushing should be an
explicit action, too, but that's a different topic.) Yes disposing a FileStream
will end up closing it, but this is a subset of the range of actions Dispose()
could take. That they are implemented in the same fashion is… well… an
implementation detail, and I don't particularly see the need to confuse people
by continuing to pretend they are the same exact thing.

I firmly believe that hiding Dispose() has already damaged our ability to
educate users about disposability. For example, we can now never make Close()
do something different than Dispose() on FileStream. There are plenty of
customers out there who have been told that Close() is equivalent and have
written code that makes this assumption. Changing the semantics at this point
would break existing code. You could also convincingly argue that because of
this very point, we should never make Close() and Dispose() differ under any
circumstance… But I digress. :)

Things are further complicated by our use of "re-openable" resources, such as
System.Diagnostics.Process (you can Start(), Close(), Start(), Close(), …
where each Close() effectively disposes of the instance and each Start()
recreates it) and System.Data.SqlClient.SqlConnection (you can Open(), Close(),
Open(), Close(), … where each Close() is almost identical to Dispose() with
some minor differences).

**Future Direction**

Our pattern as implemented has caused a bit of confusion and problems recently
internally, so I am wondering if anybody out there has also run into problems
with it. If so, speak up! We'd love to hear feedback.

One very real issue is that if you're going to subclass Stream, there's no way
to chain the base class Dispose() method since it's explicitly implemented
(which turns out to be a private method in the metadata). To do it right, you
just need to know that Dispose() calls Close() (a pretty intimate piece of
implementation trivia). Further, in the Dispose(bool) cases, you need to ignore
Dispose() and just write a Dispose(bool) implementation that makes sure to
chain the base class method. Unfortunately, you just have to take it on its
face that the base class is implemented correctly and that your re-implemented
dispose method will end up being called at precisely the right time. Moreover,
the fact that the pattern is not captured as an interface of any sort makes
such hierarchies feel a bit brittle after several levels of inheritance. The C#
compiler auto-chains finalizers, a very nice convenience; it'd also be nice if
it knew the right thing to do with Dispose() implementations, too.

We had recently considered changing this pattern and the associated Framework
classes to have public Dispose() methods, but it is fraught with problems. Not
only would these very familiar classes now have two public cleanup methods
(Dispose() and Close(), for example), but it turns out that encouraging derived
classes to override Dispose() is a bad idea with the current pattern. It relies
on base classes overriding Dispose(bool) and leaving Dispose() alone.

There are certainly alternate designs to consider, and lots of room for support
by both the C# compiler and the CLR in deterministic resource cleanup.
[These](http://pluralsight.com/blogs/hsutter/)
[guys](http://blogs.msdn.com/slippman/) have done a great job pioneering this
space with their forthcoming release of C++/CLI, which has both automatic
deterministic finalization and generation and chaining of Dispose() methods
(what they refer to destructors… yet another thing we as C#-ers need to work
on: a finalizer is not a destructor; Dispose() is much closer to what has been
for a long time referred to as a destructor, and we'd be better of if we got
our terminology straight). I encourage you to check it out.

I'll have plenty more information coming in the following weeks, including an
update to our [existing Design
Guidelines](http://msdn.microsoft.com/library/en-us/cpgenref/html/cpconfinalizedispose.asp)
for implementing finalizers and Dispose() methods… Stay tuned.

**Appendix: A Tidbit on Explicitly Implemented Interfaces**

Interestingly, explicitly implemented interface methods have the drawback of
not being able to bind to a precise version in the hierarchy anyways (even
though they are non-virtual). Calling a method through an interface map will
always end up as a virtual call to the most-derived implementation. Consider
this example:

> class A : IDisposable
>
>
>
> {
>
>
>
>     void IDisposable.Dispose()
>
>
>
>     {
>
>
>
>         Console.WriteLine("A.Dispose()");
>
>
>
>     }
>
>
>
>
>
>
>
>     internal void Close()
>
>
>
>     {
>
>
>
>         ((IDisposable)this).Dispose();
>
>
>
>     }
>
>
>
> }
>
>
>
>
>
>
>
> class B : A, IDisposable
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
>     void IDisposable.Dispose()
>
>
>
>     {
>
>
>
>         Console.WriteLine("B.Dispose()");
>
>
>
>     }
>
>
>
>
>
>
>
> }

With these classes, calling:

> B b = new B();
>
>
>
> b.Close();

...will end up in a virtual dispatch to the Dispose() implementation on class
B. This shouldn't be surprising, but it means that you can never really be sure
that you're the last interface implementation in a hierarchy which can be
troublesome in situations like the C# using statement. For example,

> using (B b = new B())
>
>
>
> {
>
>
>
> }

...will likewise end up as a call to B's version of Dispose() although A might
not be designed to deterministically release its resources correctly should its
Dispose() behavior be overridden.

