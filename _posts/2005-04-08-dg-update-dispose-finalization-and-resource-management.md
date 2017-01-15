---
layout: post
title: 'DG Update: Dispose, Finalization, and Resource Management'
date: 2005-04-08 15:17:01.000000000 -07:00
categories:
- Technology
tags: []
status: publish
type: post
published: true
meta:
  _wpas_done_all: '1'
  _edit_last: '1'
author:
  login: admin
  email: joeduffy@acm.org
  display_name: joeduffy
  first_name: ''
  last_name: ''
---
Alright! Here it is: the revised "Dispose, Finalization, and Resource
Management" Design Guideline entry. I mentioned this work previously
[here](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=1fe0f820-5b2b-4b17-82af-08142e7f308a)
and
[here](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=69041542-cd48-4d47-9499-a88aa3737081).
At ~25 printed pages, it's not what I would consider to be a minor update. Took
me much longer than anticipated, but I'm happy with the result. I got to work
with and received good amounts of feedback from
[HSutter](http://www.pluralsight.com/blogs/hsutter/default.aspx),
[BrianGru](http://blogs.msdn.com/bclteam/),
[CBrumme](http://blogs.msdn.com/cbrumme/),
[Jeff Richter](http://www.wintellect.com/weblogs/wintellect/), and a couple other
folks on it... Good fun.

As usual, questions, comments, and feedback are requested. Hope it comes across
formatted half-decently.

_Update: 4/16/05: Fixed a few typos that were bugging me & came up during the
internal review of this doc._

## 1.1 Dispose, Finalization, and Resource Management

The CLR's garbage collector (GC) does an amazing job at managing memory
allocated directly to CLR objects, but was explicitly not designed to deal with
unmanaged memory and OS-managed resources. In many cases, objects running
inside the CLR need to interact with resources from the unmanaged world.
There's a considerable gap between these two worlds, requiring a bridge to
explicitly manage the touch points. The responsibility for building such a
bridge lies mostly in the hands of managed API developers.

The primary goal when managing such resources is quite simply to make use of
them in the most efficient manner. This is especially important when resources
are limited, e.g. when only a limited quantity is available. You should strive
to provide your users with the controls needed to acquire and release resources
as needed, in addition to ensuring a safety net exists to prevent long-running
resource leaks. Thankfully, the .NET Framework comes with an array of
abstractions to hide the details of unmanaged resources from most platform
developers (e.g. with HWnds, database connections, GDI handles, SafeHandle),
but the sheer number of resource types available means that you'll sometimes
need to write code to manage them yourself.

This section documents the recommended pattern for implementing both explicit
and implicit resource cleanup. This is often referred to as the "Dispose" or
"IDisposable" pattern, and normally involves the `IDisposable` interface, a
`Dispose` method for explicit cleanup, and in some cases a `Finalize` method for
implicit cleanup. Implementing this pattern correctly—when appropriate—is
critical to ensuring proper, timely cleanup of resources, and also to provide
users with a deterministic, familiar way of disposing of resources.

> *Annotation (Krzysztof Cwalina):* Many people who hear about the Dispose pattern
> for the first time complain that the GC isn't doing its job. They think it
> should collect resources, and that this is just like having to manage resources
> as you did in the unmanaged world. The truth is that the GC was never meant to
> manage resources. It was designed to manage memory and it is excellent in doing
> just that.

### 1.1.1 Overview

Managed types must occasionally encapsulate control over resources that are not
managed by the CLR. In such cases, the smallest possible class, or "wrapper,"
should be used to encapsulate these resources. Ideally, this thin wrapper
should contain just allocation along with provisions for basic access to and
freeing of the resources. Enclosing classes can be used to provide a more
natural view over the resource through abstracted APIs, taking care not to
expose the internal resource wrapper. Following this pattern helps to mitigate
many of the risks and difficulties outlined further in this section.

An explicit `Dispose` method should always be provided to enable users to free
resources owned by an instance deterministically. Implicit cleanup by means of
a `Finalize` method is also required when a class directly owns such a resource,
but often the resource wrapping class—such as `SafeHandle` for example—will
take care of this for you. This leaves only the task of creating an explicit
cleanup mechanism to the Framework developer. We discuss both implicit and
explicit cleanup in the next section.

#### Implicit Cleanup

Implicit cleanup should always be provided by protecting resources with a
`SafeHandle`. In fact, implementing finalizers by hand is seldom necessary thanks
to the introduction of this type in the .NET Framework 2.0. If supplementary
finalization semantics are required, you can implement the protected `Finalize`
method yourself using the special finalizer syntax in your favorite language
(e.g. `~T()` in C# and `!T()` in C++). The runtime will invoke `Finalize` for you
nondeterministically as part of the GC's finalization process, providing a last
chance for your object to ensure resources are released at the end of its
lifetime. By nondeterministic, this simply means that the GC will call `Finalize`
at an undefined point in time after there are no longer any live references to
your object. Correctly implementing finalizers by hand is a notoriously
difficult task—please see details further below should you decide you have to
do so.

#### Explicit Cleanup

In every case where a type owns resources—or owns types which themselves own
resources—you should give users the ability to explicitly release them.
Developers will then have the option to initiate the release of resources once
the object is no longer in use. This alleviates some of the reliance on the GC
for destruction of resources (something which can subtly harm performance), and
also provides users a deterministic way to reclaim resources. Moreover, if the
external resource is scarce or expensive, as is the case with OS-allocated
handles (e.g. file handles), performance can be improved and resource
starvation avoided if they are released once no longer needed. Explicit control
should always be provided with a `Dispose` method based on the `IDisposable`
interface (in C++, simply write a destructor, `~T()`, for your type `T`; the
compiler will generate the entire underlying `Dispose` mechanics).

Read below for more information on the general pattern, as it actually involves
more than simply writing a `Dispose` method when creating a non-sealed class.

> *Annotation (Clemens Szyperski):* The only problem is that automatic management
> of memory and objects makes it difficult to ensure that resources held by
> objects are released deterministically (that is, early). The reliance on the GC
> can lead programmers to think that they don't need to worry about this anymore,
> which is not the case. In fact, any object that implements `IDisposable` should
> be mentally tagged with a red flag and should not be allowed to fall off the
> scene without `Dispose` having been called. The finalization/safe handle safety
> net is really not good enough to prevent lousy user experiences - such as a
> file remaining locked for an unexpectedly long time after "save" and "close" of
> a document window (but with the app still running). Careful use of AppDomains
> and their forced unloading (which triggers safe handles) is sometimes a way to
> deal with this rigorously.

> *Annotation (Herb Sutter):* Finalizers are actually even worse than that. Besides
> that they run late (which is indeed a serious problem for many kinds of
> resources), they are also less powerful because they can only perform a subset
> of the operations allowed in a destructor (e.g., a finalizer cannot reliably
> use other objects, whereas a destructor can), and even when writing in that
> subset finalizers are extremely difficult to write correctly. And collecting
> finalizable objects is expensive: Each finalizable object, and the potentially
> huge graph of objects reachable from it, is promoted to the next GC generation,
> which makes it more expense to collect by some large multiple.

Today, on most GC systems including .NET, the right advice is: When you have to
do cleanup for your object, you almost always want to provide it in a
destructor (`Dispose`), _not_ in a finalizer. When you do want a finalizer, you
want it in addition to a destructor (`Dispose`), _not_ instead of `Dispose`.

> *Annotation (Brian Grunkemeyer):* There are two different concepts that are
> somewhat intertwined around object tear-down. The first is the end of the
> lifetime of a resource (such as a Win32 file handle), and the second is the end
> of the lifetime of the object holding the resource (such as an instance of
> `FileStream`). Unmanaged C++ provided destructors which ran deterministically
> when an object left scope, or when the programmer called `delete` on a pointer to
> an object.  This would end the resource's lifetime, and at least in the case of
> `delete`, end the lifetime of the object holding onto the resource. The CLR's
> finalization support only allows you to run code at the end of the lifetime of
> the object holding a resource. Relying on finalization as the sole mechanism
> for cleaning up resources extends the resource's lifetime to be equal to the
> lifetime of the object holding the resource, which can lead to problems if you
> need exclusive access to that resource or there are a finite number of them,
> and can hurt performance. Hence, witness the Dispose pattern for managed code,
> allowing you to define a method to explicitly mimic the determinism & eagerness
> of destructors in C++. This relegates finalization to a backstop against users
> of a type who do not call `Dispose`, which is a good thing considering the
> additional restrictions on finalizers.

Now that you understand this, note that the `Finalize` & `Dispose` methods serve
very different purposes. Unfortunately, they're surfaced differently in
different languages. C# calls a finalizer a destructor, forcing you to use
`~T()`, whereas `Dispose` is a normal method. In C++ starting with version 2 of the
.NET Framework, `Dispose` methods are generated from code written using the
destructor syntax (`~T`), whereas the finalizer will be specified using some
other syntax like `!T()`. C# arguably emphasized the wrong aspect of object
lifetime (instead of resource lifetime) by giving the special C++ name the
wrong meaning. But note that when you see the word destructor or `~T()` in any
discussion on `Dispose()` or object lifetime, pay attention to exactly what the
author intended. I prefer using "finalizer" and "dispose" to alleviate any
language-induced confusion. Note that this pattern also calls for `Dispose(void)`
& `Dispose(bool)` in places.

Generally speaking, it is considered good design for consumers of a disposable
instance to call `Dispose` when they are done using it. This is simpler in
languages like C# which provides a "using" block to automate calling `Dispose`
for local objects, and in languages like C++ which fully automate "using" with
stack-based semantics. However, implicit cleanup is still necessary for cases
where a user neglects or fails to invoke the explicit release mechanism,
essentially transferring responsibility to the runtime to perform the cleanup.

### 1.1.2 Dispose Pattern

If your class is not sealed and has to perform resource cleanup, you should
follow the pattern exactly as it appears below. For sealed classes, this
pattern need not be followed, meaning you should simply implement your
`Finalizer` and `Dispose` with the simple methods (i.e. `~T()` (`Finalize`) and
`Dispose()` in C#). When choosing the latter route, your code should still adhere
to the guidelines below regarding implementation of finalization and dispose
logic.

This pattern has been designed to ensure reliable, predictable cleanup, to
prevent temporary resource leaks (as a result of skipped disposes, for
example), and most importantly to provide a standard, unambiguous pattern for
compilers and developers to author disposable classes and for programmers
consuming disposable instances. The description below also offers guidance on
when and why you should implement a finalizer, as not every disposable type
needs one. Lastly, versioning classes that require resource cleanup poses some
challenges, especially when introducing a new type into an existing class
hierarchy. This is also discussed below.

> *Annotation (Herb Sutter):* You really don't want to write a finalizer if you can
> help it. Besides problems already noted earlier in this chapter, writing a
> finalizer on a type makes that type more expensive to use even if the finalizer
> is never called. For example, allocating a finalizable object is more expensive
> because it must also be put on a list of finalizable objects. This cost can't
> be avoided, even if the object immediately suppresses finalization during its
> construction (as when creating a managed object semantically on the stack in
> C++).

If using C++, simply write the usual destructor (`~T()`) and the compiler will
automatically generate all of the machinery described later in this section. In
the rare cases where you do want to write a finalizer (`!T()`) as well, the
recommended way to share code is to put as much of the work into the finalizer
as the finalizer is able to handle (e.g., the finalizer cannot reliably touch
other objects, so don't put code in there that needs to use other objects), put
the rest in the destructor, and have your destructor call your finalizer
explicitly.

* Do implement the dispose pattern when your type is unsealed and contains
resources that explicitly need to be or can be freed, for example raw handles,
or other unmanaged resources. This pattern provides a standardized means for
developers to deterministically destroy or free resources owned by an object.
It also aids subclasses to correctly release base class resources.

* Do fully implement the dispose pattern on classes with disposable
subtypes, even if the base type does not own resources. This will enable
programmers coding against the base class to dispose of further derived
instances properly. A great example of this pattern is the v2.0
`System.IO.Stream` class. Although it is an abstract base class which doesn't
hold on to resources, most of its subclasses do; because of this, it follows
this pattern.

* Do implement `IDisposable` only on classes where a class in its parent
hierarchy has not already done so. The `public void Dispose()` method should be
left final (i.e. not marked `virtual`) and consist of only two operations: a
virtual call to `Dispose(true)` and a call to `GC.SuppressFinalize(this)`, in that
order. The call to `SuppressFinalize` should only occur if `Dispose(true)` executes
successfully—thus, you should not place the call inside a finally block.
Types inheriting from other classes which already follow this pattern can and
should reuse the existing implementation of `Dispose()`.

<blockquote>
<p><i>Annotation (Brad Abrams):</i>  We had a fair amount of debate about the relative
ordering of calls in the `Dispose()` method. E.g.</p>
<pre><code>public void Dispose()
{
  Dispose(true);
  GC.SuppressFinalize(this); 
}
</code></pre>
Or
<pre><code>public void Dispose()
{
  GC.SuppressFinalize(this);
  Dispose(true);
}
</code></pre>
</blockquote>

We opted for the first ordering as it ensures that `GC.SuppressFinalize()` only
gets called if the `Dispose` operation completes successfully.

> *Annotation (Jeffrey Richter):* I too wrestled back and forth with the order of
> these calls. Originally, I felt that `SuppressFinalize` should be called prior to
> `Dispose`. My thinking was this: if `Dispose` throws an exception then, it will
> throw the same exception when `Finalize` is called and there is no benefit this
> and the 2nd exception should be prevented. However, I have since changed my
> mind and I now agree with this guideline that `SuppressFinalize` should be called
> after `Finalize`. The reason is because `Dispose()` calls `Dispose(true)` which may
> throw but when `Finalize` is called later `Dispose(false)` is called and this may
> be a different code path than before and it would be good if this different
> code path executed. And, the different code path may not throw the exception.

> *Annotation (Brian Grunkemeyer):* The ordering is important to give your
> finalization code (in `Dispose(false)`) a chance to clean up the resource even if
> some higher level guarantees usually made when disposing the object can't be
> made. A `Dispose` method should be able to guarantee correctness & free the
> resource when it completes. But if the code for guaranteeing correctness
> fails, we fall back on the finalizer, which calls `Dispose(false)`. This may
> entail some amount of corruption or data loss, but at that point the corruption
> is inevitable, and at least we can ensure we don't have a resource leak.
> Finalization code already has to deal with partially constructed objects, so
> the additional burden of dealing with an object where the `Dispose(true)` code
> path failed shouldn't be significant.

* Do create or override the `protected virtual void Dispose(bool disposing)`
method to encapsulate all of your cleanup logic. All cleanup should occur in
this method, predicated—if necessary—by the disposing argument. The
argument's value will equal `false` if being invoked from inside a finalizer,
which should be used to ensure any code running from a finalizer is careful to
follow the `Finalize` guidelines detailed in the next section.

> *Annotation (Jeffrey Richter):* The idea here is that `Dispose(Boolean)` knows
> whether it is being called to do explicit cleanup (the Boolean is `true`) versus
> being called due to a garbage collection (the Boolean is `false`). This
> distinction is useful because, when being disposed explicitly, the
> `Dispose(Boolean)` method can safely execute code using reference type fields
> that refer to other objects knowing for sure that these other objects have not
> been finalized or disposed of yet. When the Boolean is `false`, the
> `Dispose(Boolean)` method should not execute code that refer to reference type
> fields because those objects may have already been finalized.

> *Annotation (Joe Duffy):* Jeff's comment might seem to be an overstatement under
> careful examination. For example, can't you safely access reference type
> objects that aren't finalizable? The answer is yes you can, _iff_ you are
> certain that it doesn't rely on finalizable state itself. This reliance could
> be directly or indirectly through complex relationships with other reference
> types--a pretty nontrivial thing to figure out (and something which is subject
> to change from release to release). So unless you're 100% certain, just avoid
> doing it.

* Do make a call to your base class's `Dispose(bool disposing)` method (if
available) as the last operation in your `Dispose(bool)` implementation. Make
sure to preserve the value of the disposing argument by passing the same value
that your method received. This makes sure that base classes are given a chance
to clean up of resources, but not before your cleanup code executes (which
could rely on their presence).

* Do implement a finalizer if your object is responsible for controlling
the lifetime of at least one resource which does not have its own finalizer.
Types like `SafeHandle`, for example, have their own finalizers responsible for
cleaning up resources. In other cases, however, users will often neglect to
write code which guarantees executing explicit dispose logic. If your base
class has already overridden `Finalize` to follow this pattern, you should not
override it yourself, as it will make the call to your virtual `Dispose(bool)`
override appropriately.

When implementing your finalizer, place all finalization cleanup logic inside
the `Dispose(bool disposing)` method. Your `Finalize` method should make a single
virtual call to `Dispose(false)` and nothing more. As noted above, any logic not
appropriate to execute during finalization should be written so as not to fire
if the disposing argument is false. Such restrictions are discussed further
below.

* Do not re-implement the `IDisposable` interface, override `void Dispose()`,
or override `Finalize` if a base type in your class hierarchy has already defined
them according to this pattern. You should just override `Dispose(bool)` and add
your cleanup logic, making sure to call upwards to your base class.
Re-implementing `Finalize` can actually result in unnecessary calls to
`Dispose(bool)`.

> *Annotation (Joe Duffy):* Having multiple finalizers in a class hierarchy which
> follows this pattern can result in redundant calls to perform cleanup logic. A
> virtual finalize method that automatically chains to
> `base.Finalize()`—precisely what the C# compiler creates by default—will make
> `n` virtual calls `Dispose(bool)`, where `n` is the number of finalizers the
> hierarchy following this pattern. This happens because `Finalize` is called
> virtually which in turn virtually calls `Dispose(bool)`, both of which chain to
> their base classes. So long as types are written to be resilient to multiple
> disposes (ignoring unnecessary calls), the only problem this will create is the
> subtle performance overhead to make the redundant chains of virtual method
> calls.

> *Annotation (Herb Sutter):* Note that what Joe mentions about C# doesn't happen
> in C++, because C++ generates the recommended machinery whereby `Dispose(bool)`
> in the only point that chains to the base (disposer or finalizer).

* Do not create any other variations of the `Dispose` method other than the
two specified here: `void Dispose()` and `void Dispose(bool disposing)`. `Dispose`
should be considered a reserved word in order to help codify this pattern and
prevent confusion among implementers, users, and compilers. Some languages
(like C++) may choose to automatically implement this pattern on certain types,
such as taking methods like `~T()` and `!T()`, and folding them into one
`Dispose(bool)` method.

#### Simple Example w/out Finalize (C#)

For the majority of types implementing the Dispose pattern, you will not need
to implement your own `Finalize` method. This example shows the simple case, for
example when using a `SafeHandle` to take care of the implicit cleanup:

    public class SimpleCleanup : IDisposable
    {
      // some fields that require cleanup
      private SafeHandle handle;

      private bool disposed = false; // to detect redundant calls

      public SimpleCleanup()
      {
        this.handle = /* ... */; 
      }

      protected virtual void Dispose(bool disposing)
      {
        if (!disposed)
        {
          if (disposing)
          {
            if (handle != null)
              handle.Dispose();
          }

          disposed = true;
        }
      }

      public void Dispose()
      {
        Dispose(true);
      }
    }

#### Complex Example w/ Finalize (C#)

Consider this example of the shell of a correct base-type implementation of the
more complex pattern. That is, an implementation that has its own `Finalizer`.
This also demonstrates what a class newly introducing cleanup into a class
hierarchy should look like:

    public class ComplexCleanupBase : IDisposable
    {
      // some fields that require cleanup

      private bool disposed = false; // to detect redundant calls

      public ComplexCleanupBase()
      {
        // allocate resources
      }

      protected virtual void Dispose(bool disposing)
      {
        if (!disposed)
        {
          if (disposing)
          {
            // dispose-only, i.e. non-finalizable logic
          }

          // shared cleanup logic

          disposed = true;
        }
      }

      ~ComplexCleanupBase()
      {
        Dispose(false);
      }

      public void Dispose()
      {
        Dispose(true);
        GC.SuppressFinalize(this);
      }
    }

This code snippet shows what a class extending `ComplexCleanupBase` would do to
hook into the `Dispose` and `Finalize` lifecycle to ensure correct cleanup
behavior:

    public class ComplexCleanupExtender : ComplexCleanupBase
    {
      // some new fields that require cleanup

      private bool disposed = false; // to detect redundant calls

      public ComplexCleanupExtender() : base()
      {
        // allocate more resources (in addition to base's)
      }

      protected override void Dispose(bool disposing)
      {
        if (!disposed)
        {
          if (disposing)
          {
            // dispose-only, i.e. non-finalizable logic
          }

          // new shared cleanup logic

          disposed = true;
        }

        base.Dispose(disposing);
      }
    }

Notice that it does not re-implement `Dispose` or `Finalize` as its parent class
already does so. The base type implementations will correctly forward to the
most derived `Dispose(bool)` method so that resource cleanup occurs in the
correct order.

#### Example w/ Finalize (C++)

Implementing this in C++ can be accomplished using the new syntax:

    public ref class ComplexCleanupBase
    {
    private:
      bool disposed;
    public:
      ComplexCleanupBase() : disposed(false)
      {
        // allocate resources
      }

      // implicitly implements IDisposable

      virtual ~ComplexCleanupBase()
      {
        Console::WriteLine("Base::~dtor");

        if (!disposed)
        {
          // dispose-only, i.e. logic not suitable for finalizer

          this->!ComplexCleanupBase();

          disposed = true;
        }
      }

      virtual !ComplexCleanupBase()
      {
        Console::WriteLine("Base::!finalizer");

        if (!disposed)
        {
          disposed = true;
        }
      }
    };

Overriding dispose behavior is done as follows. Notice that the chaining to
base class cleanup logic happens automatically:

    public ref class ComplexCleanupExtender : ComplexCleanupBase
    {
    private:
      // some new fields that require cleanup

      bool disposed;
    public:
      ComplexCleanupExtender() : disposed(false)
      {
        // allocate more resources
      }

      virtual ~ComplexCleanupExtender()
      {
        Console::WriteLine("Extender::~finalizer");

        if (!disposed)
        {
          // dispose-only, i.e. logic not suitable for finalizer

          this->!ComplexCleanupExtender();

          disposed = true;
        }
      }

      virtual !ComplexCleanupExtender()
      {
        Console::WriteLine("Extender::!finalizer");

        if (!disposed)
        {
          // shared cleanup logic

          disposed = true;
        }
      }
    };

#### Versioning Considerations

If you choose to add this pattern to an existing unsealed class, you might end
up unintentionally affecting existing subclasses. For the same reasons changing
semantic contracts between a base and derived class can cause subtle breaking
changes, introducing the concept of disposability into the base of a class
hierarchy where it previously didn't exist can be problematic. Further, you
might introduce new compilation warnings for existing subclasses when adding a
new method to a base class. This section briefly summarizes a few things you
should carefully analyze as part of making such a decision.

* Introducing a `public void Dispose()` or `protected virtual void Dispose(bool)` 
method into an existing class hierarchy could cause C# compiler warnings for subclasses
which have introduced disposability themselves, i.e.
"hiding inherited member, add new or override to make intent explicit." This is
a source-level breaking change, possibly preventing compilation for developers
treating warnings as errors.

* Introducing a `protected virtual void Dispose(bool)` method could
result in missed disposes for subclasses which have already implemented
`Dispose(bool)`. The subclass `Dispose(bool)` will not have been written to chain
to its base (since no `Dispose(bool)` existed previously). Thus, when calling
`Dispose()` on the derived type, it will not automatically result in a call to
its base, meaning that resources will be temporarily leaked, and could even
result in finalization being skipped if the further derived type makes a call
to `GC.SuppressFinalize`. If you own the subclasses, of course, you can easily
change this by adding a call to `base.Dispose(bool)`. But for types shipped
publicly, consider that one of your users might have authored subclasses.

* If you are subclassing a disposable type that does not follow this
pattern exactly, you'll likely run into a few challenges. The following table
describes how to "correct" such a subclass both so that you may correctly hook
into resource lifetime. This also corrects the subclass so that further derived
classes are presented with a clear contract which follows this pattern. The
cases considered include what to do if the base implements `IDisposable`
publicly, privately, or not at all; where the base does or doesn't have a
`virtual Dispose(bool)`; and/or the base does or doesn't have an override of
`Finalize`:

<style>
  .border-left {
      border-left: 1px solid;
  }

  .no-border td {
      border-top: 0px solid;
      border-bottom: 0px solid;
  }

  .border-bottom {
      border-bottom: 1px solid;
  }
</style>

<table class="border-bottom">
  <tr>
    <th rowspan="2" class="border-bottom">Base has Dispose?</th>
    <th rowspan="2" class="border-bottom">Base has virtual Dispose(bool?)</th>
    <th rowspan="2" class="border-bottom">Base has Finalize?</th>
    <th colspan="3" class="border-left">What to do when deriving</th>
  </tr>
  <tr>
    <th class="border-bottom">IDisposable</th>
    <th class="border-left border-bottom">Virtual Dispose(bool)</th>
    <th class="border-left border-bottom">Override Finalize</th>
  </tr>
  <tr>
    <td>no</td>
    <td>no</td>
    <td>no</td>
    <td rowspan="4" class="border-left">implement public sealed</td>
    <td rowspan="12" class="border-left">
      if not already present in base then create protected,
      else override
    </td>
    <td rowspan="12" class="border-left">
      if overridden but not sealed in base then re-override and seal
    </td>
  </tr>
  <tr class="no-border">
    <td>no</td>
    <td>no</td>
    <td>yes</td>
  </tr>
  <tr class="no-border">
    <td>no</td>
    <td>yes</td>
    <td>no</td>
  </tr>
  <tr class="no-border">
    <td>no</td>
    <td>yes</td>
    <td>yes</td>
  </tr>
  <tr>
    <td>publicly</td>
    <td>no</td>
    <td>no</td>
    <td rowspan="4" class="border-left">reimplement with private sealed</td>
  </tr>
  <tr class="no-border">
    <td>publicly</td>
    <td>no</td>
    <td>yes</td>
  </tr>
  <tr class="no-border">
    <td>nonpublicly</td>
    <td>no</td>
    <td>no</td>
  </tr>
  <tr class="no-border">
    <td>nonpublicly</td>
    <td>no</td>
    <td>yes</td>
  </tr>
  <tr>
    <td>publicly</td>
    <td>yes</td>
    <td>no</td>
    <td rowspan="4" class="border-left">
      if base version is not sealed then override
      public sealed
    <td>
  </tr>
  <tr class="no-border">
    <td>publicly</td>
    <td>yes</td>
    <td>yes</td>
  </tr>
  <tr class="no-border">
    <td>nonpublicly</td>
    <td>yes</td>
    <td>no</td>
  </tr>
  <tr class="no-border">
    <td>nonpublicly</td>
    <td>yes</td>
    <td>yes</td>
  </tr>
</table>

> *Annotation (Herb Sutter):* This table is drawn from what the C++ compiler
> generates automatically when it detects a base class not following the Dispose
> pattern as described in this section.

### 1.1.3 Dispose

If a type is implementing disposability either through the pattern described
above or a simple implementation of the `IDisposable` interface, the following
guidelines apply. Note that these pertain to any code that runs during the
disposal of an instance—either inside `Dispose()`, `Dispose(bool)`, or any other
methods that might get called during `Dispose`.

#### Authoring Disposable Classes

* Do implement `IDisposable` on every type that has a finalizer. This gives
users of your type a means to explicitly perform deterministic cleanup of those
same resources which the finalizer is responsible for. You may also implement
`Dispose` on types without finalizers, e.g. in circumstances when transitively
disposing of object state or using objects which manage their resources with
finalizers already.

> *Annotation (Jeffrey Richter):* This guideline is very important and should
> always be followed without exception. Without this guideline, a user of a type
> can't control the resource properly.

> *Annotation (Herb Sutter):* Languages ought to warn on this case. If you have a
> finalizer, you want a destructor (`Dispose`). The only exception is value types,
> because you can't have either a destructor or a finalizer (because the CLR
> makes arbitrarily many bitwise copies, it isn't possible to write teardown
> correctly for value types).

* Do allow your `Dispose` method to be called more than once. The method may
choose to do nothing after the first call. It should not generate an exception.

> *Annotation (Brian Grunkemeyer):* A `Dispose(bool)` method may be called multiple
> times because of resurrection (i.e. someone calling
> `GC.ReRegisterForFinalization` on your instance), or because a verifiable program
> called either `Dispose(void)` or `Finalize()` on your object multiple times. While
> rare, strange, and often frowned upon, these aren't strictly illegal.

> *Annotation (Herb Sutter):* Unfortunately, having `Dispose(bool)` called multiple
> times isn't that strange… it's what C#'s automatically generated finalizer
> chaining does to the `Dispose(bool)` pattern by default, and why when authoring
> class hierarchies in C# it's especially important to implement the
> `Dispose(bool)` pattern only once in the class hierarchy. See Joe Duffy's
> annotation earlier in this chapter for more details.

* Do transitively dispose of any disposable fields defined in your type
from your `Dispose` method. You should call `Dispose()` on any fields whose
lifecycle your object controls. For example, consider a case where your object
owns a private `TextReader` field. In your type's `Dispose`, you should call the
`TextReader` object's `Dispose`, which will in turn dispose of its disposable
fields (`Stream` and `Encoding`, for example), and so on. If implemented inside a
`Dispose(bool disposing)` method, this should only occur if the disposing
parameter is `true` — touching other managed objects is not allowed during
finalization. Additionally, if your object doesn't own a given disposable
object, it should not attempt to dispose of it, as other code could still rely
on it being active. Both of these could lead to subtle-to-detect bugs.

<blockquote>
<p><i>Annotation (Herb Sutter):</i> In C++, you can just follow the natural idiom of
storing any other objects whose lifetime is controlled by your own object as
being directly held by value, and the above is done automatically. In this
example, you'd hold the <code>TextReader</code> by value:</p>
<pre><code>ref class R {
// …
private:
  TextReader tr; // by value, not by reference (^)
};</code></pre>

<p>Here <code>R::~R()</code> will automatically call <code>tr.~TextReader()</code>,
following the usual C++ semantics. (More specifically, in the compiler-generated 
machinery <code>R.Dispose(true)</code> will invoke <code>tr.Dispose()</code>.)</p>
</blockquote>

* Consider setting disposed fields to null before actually executing
dispose when reference cycles in an object graph are possible. For example,
consider this situation:


    public class CyclicClassA : IDisposable
    {
      private TextReader myReader;
      private CyclicClassB cycle;

      public void Dispose()
      {
        if (myReader != null)
        {
          ((IDisposable)myReader).Dispose();
          myReader = null;
        }

        if (cycle != null)
        {
          CyclicClassB b = cycle;
          cycle = null;

          b.Dispose();
        }
      }
    }

    public class CyclicClassB : IDisposable
    {
      private Bitmap bmp;
      private CyclicClassA cycle;

      public void Dispose()
      {
        if (bmp != null)
        {
          bmp.Dispose();
          bmp = null;
        }

        if (cycle != null)
        {
          CyclicClassA a = cycle;
          cycle = null;

          a.Dispose();
        }
      }
    }

In this example, given an instance of `CyclicClassA a` and `CyclicClassB b`, if
`a.cycle = b` and `b.cycle = a`, transitive disposal would ordinarily cause
an infinite loop. In the above example, notice that the object's state is
nulled out first to prevent such a cyclic loop from happening.

* Avoid throwing an exception from within `Dispose` except under critical
situations where the containing process has been corrupted (leaks, inconsistent
shared state, etc.). Users expect that a call to `Dispose` would not normally
raise an exception. For example, consider the manual try-finally in this
snippet:


    void NaiveConsumer()
    {
      TextReader tr = new StreamReader(File.OpenRead("foo.txt"));

      try
      {
        // do some stuff
      }
      finally
      {
        tr.Dispose();

        // more stuff
      }
    }

If `Dispose` could raise an exception, further finally block cleanup logic will
not execute. To work around this, the user would need to wrap every call to
`Dispose` (within their finally block!) in a try block, which leads to very
complex cleanup handlers. If executing a Dispose(bool disposing) method, never
throw an exception if disposing is false. Doing so will terminate the process
if executing inside a finalizer context.

* Consider making your object unusable after calling `Dispose`. Recreating
an object that has already been disposed is often a difficult undertaking,
especially in cases where transitive disposals have taken place. In such
circumstances, invoking further operations on a disposed object should throw an
`ObjectDisposedException`. If you are able to reconstruct state, be sure to warn
users that they must potentially re-dispose of an object multiple times, the
first time and once again after each reconstruction.

The following example demonstrates one possible approach for recreation. It is
meant to show the concept only, not to convey any specific pattern to follow:


    class Recreatable : IDisposable
    {
      private bool disposed = false;

      public void Dispose()
      {
        Dispose(true);

        this.disposed = true;

        GC.SuppressFinalize(this);
      }

      // Dispose(bool) implementation…

      // whenever you call a method that access the resources of
      // this class, check to see if the state is disposed, if
      // so, reopen this resource.

      public void DoStuff()
      {
        if (disposed)
        {
            ReOpen();
        }

        // do the work
      }

      // Note: The following code does not handle thread-safety
      // issues, it is meant to convey the concept only.

      public void ReOpen()
      {
        this.disposed = false;

        GC.ReRegisterForFinalization(this);

        handle = // get new  handle

        otherRes = new OtherResource();
      }
    }

* Do implement a `Close` method for cleanup purposes if such terminology is
standard, for example as with a file or socket. When doing so, it is
recommended that you make the `Close` implementation identical to `Dispose`, as
we've set this precedent with Framework types as early as V1.0. Most developers
will not think to call both `Close` and `Dispose` on an object, but instead will
call one or the other. Try to delegate cleanup responsibility to `Dispose` (e.g.
by calling `Close()` from `Dispose()`) in such circumstances, and make sure to
carefully document any situations that deviate from this pattern.

Note that one such scenario that would justify deviation is if an object can be
opened and closed multiple times without recreating the instance. For example,
the .NET Framework uses this pattern with the
`System.Data.SqlClient.SqlConnection` class. You are able to open and close a
connection to the database multiple times, but an instance should still be
disposed of afterwards. Optionally, you can release resources upon `Close` and
lazily reacquire them in instances where multiple opens are possible.

* Consider nulling out large managed object fields in your `Dispose` method.
This is seldom necessary, but should be considered when a field is expensive to
keep around, yet its owning object might be held on to longer than necessary.
Simply because `Dispose` was called does not mean that its reference is being
released. This could happen, for example, if its container (the object being
disposed) is referred to from within a long-running scope (or stored in a
static variable), and not explicitly nulled out. Doing this could help to
reduce the lifetime of the object by making it eligible for garbage collection
sooner. The definition of large and expensive is of course subjective and
should be based on performance profiling and measurement.

* Avoid creating disposable value types, and never create a value type
which manages the lifetime of unmanaged resources directly. Except for
situations where a value type will never be copied (e.g. existing only as a
local within a method body) or only copied in very controlled ways, it is in
practice difficult to predict how disposing of a value type will interact with
the pass-by-copy semantics. For example, once a new copy has been handed out,
one copy could try to access fields that another copy had already disposed.

#### Working With Disposable Objects

* Consider disposing of any `IDisposable` object instances when you are done
with them. This is covered partially by the rule above which states objects
should transitively dispose of disposable fields, but also should be taken into
consideration also with local object allocations. You should dispose of locals
whose reference never leaves the code block in which they reside prior to
exiting the block. The easiest way to do this in C# is with the using
statement. The easiest way to do this in C++ is by allocating objects on the
stack (the default).

Be careful, however, not to dispose of an object while it is still in use.
Unlike finalization, it's very easily to accidentally clean up resources on an
object which is still actively in use.

* Do not swallow exceptions arising from a call to `Dispose`. Invoking
`Dispose` on any object will only ever throw an exception in very critical
circumstances. In such cases, it would not be prudent to catch and attempt to
continue executing as normal.

#### C# and VB Using Statement, C++ Stack Semantics

The C# and VB languages offer a `using` statement, and the C++ language offers
stack allocation semantics, to make it easier for developer to work with
disposable objects by automatically disposing when control leaves a precise
scope. This happens regardless of whether this occurs through normal control
flow or as a result of an exception.

In C# and VB, `using` is appropriate for fine-grained scopes, where the life of
an object spans an easily defined block of code. For longer spanning lifetimes,
such as disposable fields, you will instead have to invoke `Dispose` directly on
an object. In C++, holding fields by value is appropriate for disposable fields
that are linked to the lifetime of their enclosing object (e.g., `OtherType t;`
instead of `OtherType^ t;` where `^` is an object reference indirection). The
fields' Disposers will be called automatically when the enclosing object is
destroyed, regardless of whether this occurs through normal control flow or as
a result of an exception.

For example, the following C# code:

    void UseDisposableObject()
    {
      using (Resource r = new Resource())
      {
        // use the resource
      }
    }

which is equivalent to the following C++ code:

    void UseDisposableObject()
    {
      Resource r;

      // use the resource
    }

gets expanded to IL which looks very similar to the following C# code:

    void UseDisposableObject()
    {
      {
        Resource resource = new Resource();

        try
        {
          // use the resource
        }
        finally
        {
          if (resource != null)
            ((IDisposable)resource).Dispose();
        }
      }
    }

Notice how the `using` statement cleans up the code at the call-site quite a bit,
making dispose much more attractive from the developer's point of view. You can
also write "stacked" using statements which get translated into the obvious
boilerplate try/finally blocks:

    using (Resource r1 = new Resource())
    using (Resource r2 = new Resource())
    {
      // use r1 and r2
    }

which is equivalent to the following C++ code:

    {
      Resource r1;
      Resource r2;

      // use r1 and r2
    }

### 1.1.4 Finalization

If you choose to implement finalization logic for your type, you should take
care to do it in the correct manner. Finalizers are notoriously difficult to
implement correctly, primarily because you cannot make certain (normally valid)
assumptions about the state of the system around you during their execution.
The following guidelines should be taken into careful consideration.

Note that these guidelines apply not just to the `Finalize` (C# `~T()`, C++ `!T()`)
method, but to any code that executes during finalization. In the case of the
Dispose pattern defined above, this means logic which executes inside
`Dispose(bool disposing)` when disposing is `false`.

* Do carefully consider any case where you think a finalizer is needed.
There is a real cost associated with instances with finalizers, both from a
performance and code complexity standpoint. Prefer using resource wrappers such
as `SafeHandle` to encapsulate unmanaged resources where possible, in which case
a finalizer becomes unnecessary because the wrapper is responsible for its own
resource cleanup — refer to section 1.1.4 for more details.

Finalization increases the cost and duration of your object's lifetime as each
finalizable object must be placed on a special finalizer registration queue
when allocated, essentially creating an extra pointer-sized field to refer to
your object. Moreover, objects in this queue get walked during GC, processed,
and eventually promoted to yet another queue that the GC uses to execute
finalizers. Increasing the number of finalizable objects directly correlates to
more objects being promoted to higher generations, and an increased amount of
time spent by the GC walking queues, moving pointers around, and executing
finalizers. Also, by keeping your object's state around longer, you tend to use
memory for a longer period of time, which leads to an increase in working set.

* Do make your `Finalize` method protected, not public or private. C# and
C++ developers do not need to worry about this, as the compiler does it for you
automatically.

* Do free only owned unmanaged resources in your type's `Finalize` method.
Do not touch any finalizable objects your type may have a reference to, as
there is significant risk that they will have already been finalized. Even
managed objects whose lifecycle you own could be in an inconsistent state.

For example, a finalizable object `a` that has a reference to another
finalizable object `b` cannot reliably use `b` in `a`'s finalizer, or vice
versa. There is no ordering among finalizers (short of a weak ordering
guarantee for critical finalization). Also, objects stored in static variables
will get collected at certain points during an appdomain unload or while
exiting the process. Accessing a static variable that refers to a finalizable
object (or calling a static method that may use values stored in static
variables, like any sort of tracing infrastructure that writes to a file) is
not safe, though you can use `Environment.HasShutdownStarted` (in v1.1 and
higher) to detect whether your finalizer is running during an AD unload or
while exiting the process.

> *Annotation (Jeffrey Richter):* Note that it is OK to touch unboxed value type
> fields.

* Do not directly call the `Finalize` method. This is not a legal operation
in C#, but is possible in VB and C++, and is in fact verifiable IL. While these
guidelines suggest writing finalizers that are resilient to being called under
the worst possible circumstances, developers might still assume that a
finalizer will only be called by the CLR's finalization thread.

* Do gracefully handle situations in which your finalizer is invoked more
than once. This means you might need a way to detect whether finalization has
already occurred on a given instance. As described in the following examples,
it is sometimes necessary to detect and code against. Consider nulling or
zero-ing out resource references and handles and checking for these conditions
during finalization to skip cleanup logic. Alternatively, if detection isn't so
simple, consider adding a boolean flag to indicate whether finalization has
already occurred.

As an example of two instances in which a `Finalize()` method could be run more
than once, consider the following: 1) As indicated above, verifiable IL can
explicitly invoke the `Finalize()` method on your object multiple times. 2) Any
arbitrary, untrusted caller who has a reference to your object can invoke
`GC.ReRegisterForFinalize` during their own finalization. If your object has
already been finalized, this will sign it up for an additional trip through the
finalization process.

* Do not assume your object is unreachable during finalization. Other
objects that are with you in the finalizer queue might still have live
references with which they could access your state, potentially even after
you've run your finalizer. You should be sure to detect inconsistent state
during execution of any methods that might compromise security and other object
invariants resulting from this behavior.

> *Annotation (Brian Grunkemeyer):* Note that your finalizer may run while instance
> methods on your type are running as well. If you define a finalizer that closes
> a resource used by your type, you may need to call `GC.KeepAlive(this)` at the
> end of any instance method that doesn't use the this pointer after doing some
> operation on that resource. If you can use `SafeHandle` to encapsulate your
> resource, you can almost always remove the finalizer from your type, which
> means you no longer have to worry about this race with your own finalizer.

* Do not assume your finalizer will always run. In some very rare
circumstances only critical finalizers will be run, and in even rarer
conditions no finalizers will ever get a chance to execute.

Precisely when and how and when this can occur differs based on whether you are
running unhosted or in a hosted environment. In unhosted scenarios,
finalization for an object can be skipped during timed-out process exits, if a
finalizer thread is aborted after it has dequeued your object and before it has
called `Finalize` (in which case, the runtime proceeds to the next object in the
queue), or if a process is terminated without a managed shutdown (e.g. P/Invoke
to `kernel32!ExitProcess`). In hosted scenarios these conditions also apply, but
the host can further initiate a rude AppDomain unload, in which case only
critical finalizers are given a chance to execute. In SQL Server hosting, for
example, normal AppDomain unloads will escalate to a rude unload should a
thread or finalizer not respond within an acceptable timeframe.

Even in the absence of one of the rare situations noted above, a finalizable
object with a publicly accessible reference could have its finalization
suppressed by any arbitrary untrusted caller. Specifically, they can call
`GC.SuppressFinalize` on you and prevent finalization from occurring altogether,
including critical finalization. A good mitigation strategy to deal with this
is to wrap critical resources in a non-public instance that has a finalizer. So
long as you do not leak this to callers, they will not be able to suppress
finalization. If you migrate to using `SafeHandle` in your class and never expose
it outside your class, you can guarantee finalization of your resources (with
the caveats mentioned above and assuming a correct `SafeHandle` implementation).

* Consider using a critical finalizable object (`SafeHandle`, or any type
whose type hierarchy contains `CriticalFinalizerObject`) for situations where a
finalizer absolutely must execute even in the face of AppDomain unloads and
rude thread aborts. Refer to the section above on `SafeHandles` for more
information.

* Avoid allocating memory in finalizers. Allocations may fail due to lack
of memory, and finalizers should be simple enough that they don't fail.

* Do not allocate memory from within a critical finalizer, or from
`SafeHandle`'s `ReleaseHandle` method, at least not on the success paths. These
methods are constrained execution regions, and as such, developers agree to be
constrained to only calling a reliable subset of the Framework marked with
appropriate reliability contracts. If your critical finalizer detects
corruption or gets a bad error code from Win32, throwing an exception may be a
reasonable way of reporting this failure (though for `SafeHandle`'s `ReleaseHandle`
method, returning `false` is preferred). Note that unhandled exceptions thrown on
the finalizer thread will tear down unhosted processes.

* Do not call virtual members from finalizers except for in very
controlled designs, such as the `Dispose(bool)` method outlined in the pattern
above. Even in these cases, malicious subclasses could inject harmful behavior
into the virtual method call, possibly resulting in surprising behavior, such
as an unhandled exception. This is because the most derived implementation of
the virtual method will be run and there is no guarantee that it will chain to
its base class as it is supposed to.

Consider the C# example below, which demonstrates a dynamically dispatched call
to `Dispose`. The author of `Base` likely expected `Base`'s `Dispose` method to be
called at some point (i.e. that any subclasses would "chain" upwards with a
call to `base.Dispose()`, as would be enforced in all C++-authored derived
classes for example), but in reality `Derived`'s version of `Dispose` never does
this. This results in base class resources not being freed, and likely memory
leaks. If the `Derived` `Dispose()` method suppressed finalization, resources that
`Base` owns might not even get freed during finalization!

    public class Base : IDisposable
    {
      public virtual void Dispose() // BUG: This method shouldn't be virtual.
      {
        Console.WriteLine("Base's Cleanup");

        GC.SuppressFinalize(this);
      }

      ~Base()
      {
        Dispose();
      }
    }

    public class Derived : Base
    {
      public override void Dispose()
      {
        Console.WriteLine("Derived Cleanup");

        GC.SuppressFinalize(this);
      }

      ~Derived() // BUG: Shouldn't override finalizer.
      {
        Dispose();
      }
    }

A few potential solutions for this problem are to make `Dispose` non-virtual,
inject a private `DisposeImpl` method that `Base`'s `Dispose` method delegates to and
that the finalizer calls explicitly. This is a risk in general with the
`Dispose(bool)` pattern outlined at the beginning of this section — if subclasses
never chain appropriately, the system can exhibit resource de-allocation
problems.

> *Annotation (Brian Grunkemeyer):* Note that with the above code, `Derived`'s
> finalizer will run, then call `Derived`'s `Dispose` method. The C# compiler also
> adds a try/finally to every finalizer that calls the base class finalizer, so
> `Derived`'s finalizer will call `Base`'s finalizer, which will virtually call
> `Dispose`, running `Derived`'s finalizer a second time. This redundant call to
> `Dispose` also illustrates why a class hierarchy should only have one finalizer.

* Do write finalizers that are tolerant of partially constructed instances
(i.e. objects whose constructors may have never completed). You should make
sure to validate all assumed invariants that could affect a finalizer's
execution. Even resources that are allocated in an object's constructor might
not be valid if an exception was thrown mid-way through construction. This
might be more likely than you would think. If you do not explicitly throw from
the constructor, a subclass might do so before chaining to the base class
constructor, or one of many possible asynchronous infrastructure exceptions
could have interrupted the constructor, for example. In these cases the
finalizer will still execute, but some or all fields might not be fully
initialized.

For example, in the following code, list may be `null` if the constructor throws
an exception before list is assigned to:

    public class MyClass
    {
      private ArrayList list;

      public MyClass()
      {
        // some work

        list = new ArrayList();
      }

      ~MyClass() // bug: list could be null
      {
        foreach (IntPtr i in list)
        {
          CloseHandle(i);
        }
      }
    }

Consider this fix to the finalizer which avoids an unhandled
`NullReferenceException` from occurring on the finalizer thread (which would end
up terminating the program):

    ~MyClass() // fixed
    {
      if (list != null)
      {
        foreach (IntPtr i in list)
        {
          CloseHandle(i);
        }
      }
    }

> *Annotation (Jeffrey Richter):* If a constructor throws an exception, the CLR
> will still call the object's Finalize method. So, when your Finalize method is
> called, the object's fields may not have all been initialized; your Finalize
> method should be robust enough to handle this.

* Do write finalizers that are threading-agnostic. Finalizers can execute
in any order, on any thread, can occur on multiple objects concurrently, and
even on the same object simultaneously. In general, the runtime makes no
guarantees as to the threading policy of finalization, so you should avoid any
dependency on how it might be implemented today.

> *Annotation (Chris Brumme):* I describe the threading environment for
> finalization at
> [http://blogs.msdn.com/cbrumme/archive/2004/02/20/77460.aspx](http://blogs.msdn.com/cbrumme/archive/2004/02/20/77460.aspx
> "http://blogs.msdn.com/cbrumme/archive/2004/02/20/77460.aspx").  As you can see
> there, techniques like resurrection can cause your application threads and the
> finalizer thread to access your object concurrently. In other words, from a
> security perspective you should assume brutal multi-threading. But in all
> other respects you should assume that only one thread is active in your object
> when you are finalizing or disposing. You are free to ignore this possibility
> so long as it doesn't cause security holes. If this is a security risk, you
> must fix it. An obvious way to fix it is by adding thread safety to
> finalization.

`StringBuilder` is a good example of this. If you use a `StringBuilder` from
multiple threads, you will get garbage text built up in the buffer. That's the
caller's problem. But earlier implementations of `StringBuilder` actually
exposed a security hole when used in this manner. It was possible to create
mutable strings, where the result of `StringBuilder.ToString` could be modified.
This was a huge security hole and it was fixed. But the data integrity hole, is
not a security hole and it will never be fixed. Consider the same sort of
distinction when deciding whether to make your `Finalize` implementation
thread-safe or not.

> *Annotation (Brian Grunkemeyer):* The CLR may choose to use multiple finalizer
> threads in the future, and these could be threadpool threads or even your main
> thread. We need the freedom to run finalizers on these other threads, so we
> must impose this rather small additional burden on class authors.

* Avoid blocking execution from within a finalizer. For example, do not
perform synchronization or lock acquisition, sleep the thread, or any other
similar operations, unless you have identified a real security or stress bug
that would cause finalization to fail under the conditions discussed above.
These operations could delay or even prevent other finalizers in the queue from
running entirely, for example if the host notices a long-running block and
responds by escalating to a rude abort. If you must execute atomic thread-safe
operations, prefer the `Interlocked` class, as it is lightweight and
non-blocking.

* Do not raise unhandled exceptions or otherwise leak exceptions from your
finalizer, except for in very system critical circumstances (such as
OutOfMemory, for example). Doing so will shut down the entire process (as of
V2.0), tearing down the application, and preventing other finalizers from
executing and resources from being released in a controlled manner.

* Avoid resurrecting yourself by setting a reference to a rooted context,
i.e. through a GC reachable reference such as a static field or reachable
objects to which you still have a reference. Re-registering an object has
performance implications and can cause unexpected behavior. Objects you have
references to might have already completed finalization, meaning it is almost
never safe to resume normal execution once you've been placed into the
finalizer queue. If recycling objects, try to do so in your `Dispose` method
instead, and only in `Finalize` as a last resort.

> *Annotation (Rico Mariani):* This isn't especially a different issue than other
> finalization type issues. If you are recycling an unmanaged resource you may
> already need a finalizer. The time to recycle yourself is when you are
> Disposed. If you are getting finalized with any frequency at all you are
> already in trouble — recycling doesn't put you in significantly more trouble.
> See _Objects: Release or Recycle?__ _(
> [http://blogs.msdn.com/ricom/archive/2004/02/11/71143.aspx](http://blogs.msdn.com/ricom/archive/2004/02/11/71143.aspx)),
> and look under Option Two for more details. Assuming that the finalization is
> happening infrequently this can be an excellent approach to avoiding _Mid Life
> Crisis_ (
> [http://weblogs.asp.net/ricom/archive/2003/12/04/41281.aspx](http://weblogs.asp.net/ricom/archive/2003/12/04/41281.aspx)).
> This guideline isn't intended to prohibit object pools, but rather to make sure
> you are considering any recycling policy with due care.

* Do not assume that avoiding resurrecting yourself prevents you from
being rooted again after or during finalization. This could occur, for example,
if somebody behind you in the finalizer queue has a reference to you and
becomes resurrected. Because finalization is unordered, there is no guarantee
that this will not occur. At this point, your object will have already been
finalized, but other objects could attempt to use you as though you were still
alive. In these cases, you need to be sure not to break class invariants that
may not hold after finalization has executed. Consider throwing an exception in
these circumstances — i.e. treat this as similar to the use of already disposed
object as described above.

* Do not modify thread context from within your finalizer, as it will end
up polluting the finalizer thread. Remember, your finalizer will be executed on
an entirely separate thread than what your object was executing on while it was
alive. As such, don't leave the finalizer thread impersonated, access thread
local storage, or put a weird culture on it, for example.

> *Annotation (Brian Grunkemeyer):* Consider the finalizer thread more like a
> threadpool thread -- if you break it by polluting its state, you buy it.

* Do not assume that, because some object is reachable while you're being
finalized, that it has not been or is not in the process of being
finalized — e.g., static fields, common infrastructure, and so on. During
AppDomain unloads or process shutdown, even critical infrastructure components
may have begun or completed finalization, too. In such situations, the
predicate method `AppDomain.CurrentDomain.IsFinalizingForUnload()` will evaluate
to `true`.

> *Annotation (Brian Grunkemeyer):* Back during the implementation of V1.0, I was
> debugging a problem where a finalizer didn't seem to be called. To help figure
> out if the finalizer was running at all, I added a call to `Console.WriteLine`
> inside it, but then my app started blowing up with an unhandled
> `ObjectDisposedException`. How could simply adding a call to `Console.WriteLine` to
> the finalizer break the app?
>
> The problem turned out to be that the underlying console stream was being
> finalized before my instance. The lesson I learned was to follow this
> guideline: only use non-finalizable instance data from your own finalizer. But
> I also happened to own the code for the `Console` class, so I special cased
> `Console.WriteLine` — now we never close the handles for stdout, stdin, or
> stderr. This is somewhat useful for printf-style debugging and logging, and
> turned out later to be required to support multiple appdomains within the same
> process (i.e. you don't want arbitrary appdomains closing your process-wide
> handle for stdout). So bottom line: using Console from your finalizer is
> actually a safe thing to do, but watch out for everything else.

* Do not define finalizers on value types. Only reference types get
finalized by the CLR, and thus any attempt to place a finalizer on a value type
will be ignored. The C# and C++ compilers enforce this rule.

#### C# Finalizers

The `Finalize` method is inherited from `System.Object` on every class, although
only those that redefine it are eligible for finalization. C# has special
syntax which makes writing finalizers easier, and in fact prevents you from
overriding `Finalize` as though it were an ordinary method. The following code,
for example:

    public class Resource
    {
      ~Resource ()
      {
        // de-allocate resources
      }
    }

Gets translated by the C# compiler into the following conceptually equivalent
(although illegal) C# snippet:

    public class Resource
    {
      protected override void Finalize()
      {
        try
        {
          // de-allocate resources
        }
        finally
        {
          base.Finalize();
        }
      }
    }

> *Annotation (Joe Duffy):* Earlier in the .NET Framework's lifetime, finalizers
> were consistently referred to as destructors by C# programmers. As we become
> smarter over time, we are trying to come to terms with the fact that the
> `Dispose` method is really more equivalent to a C++ destructor (deterministic),
> while the finalizer is something entirely separate (nondeterministic). The fact
> that C# borrowed the C++ destructor syntax (i.e. `~T()`) surely had at least a
> little to do with the development of this misnomer. Confusing the two has been
> unhealthy in general for the platform, and as we move forward the clear
> distinction between resource and object lifetime needs to take firm root in
> each and every managed software engineer's head.

> *Annotation (Jeffrey Richter):* It is very unfortunate that the C# team chose to
> use the tilde syntax to define what is now called a finalizer. Programmers
> coming from an unmanaged C++ background naturally think that you get
> deterministic cleanup when using this syntax. I wish the team had chosen a
> symbol other than tilde; this would have helped developers substantially in
> learning how the .NET platform is different than the unmanaged architecture.

### 1.1.5 Dispose Pattern Example

This section shows a more complete and complex example of the dispose pattern
in C#, as described in the above sections.

    using System;
    using System.Security;
    using System.ComponentModel;
    using System.Runtime.ConstrainedExecution;
    using System.Runtime.InteropServices;

    public class ComplexWindow : IDisposable
    {
      private MySafeHandleSubclass handle; // pointer for a resource
      private Component component; // other resource you use

      private bool disposed = false;

      public ComplexWindow()
      {
        handle = CreateWindow(
            "MyClass", "Test Window",
            0, 50, 50, 500, 900,
            IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);

        component = new Component();
      }

      // implements IDisposable
      public void Dispose()
      {
        Dispose(true);
        GC.SuppressFinalize(this);
      }

      protected virtual void Dispose(bool disposing)
      {
        if (!this.disposed)
        {
          // if this is a dispose call dispose on all state you
          // hold, and take yourself off the Finalization queue.

          if (disposing)
          {
            if (handle != null)
              handle.Dispose();

            if (component != null)
            {
              component.Dispose();
              component = null;
            }
          }

          // free your own state (unmanaged objects)
          AdditionalCleanup();

          this.disposed = true;
        }
      }

      // finalizer simply calls Dispose(false)
      ~ComplexWindow()
      {
        Dispose(false);
      }

      // some custom cleanup logic
      private void AdditionalCleanup()
      {
        // this method should not allocate or take locks, unless
        // absolutely needed for security or correctness reasons.
        // since it is called during finalization, it is subject to
        // all of the restrictions on finalizers above.
      }

      // whenever you do something with this class, check to see if the
      // state is disposed, if so, throw this exception.
      public void ShowWindow()
      {
        if (this.disposed)
        {
          throw new ObjectDisposedException("");
        }

        // otherwise, do work
      }

      [DllImport("user32.dll", SetLastError = true,
        CharSet = CharSet.Auto, BestFitMapping = false)]
      private static extern MySafeHandleSubclass CreateWindow(
        string lpClassName, string lpWindowName, int dwStyle,
        int x, int y, int nWidth, int nHeight, IntPtr hwndParent,
        IntPtr Menu, IntPtr hInstance, IntPtr lpParam);

      internal sealed class SafeMyResourceHandle : SafeHandle
      {
        private HandleRef href;

        // called by P/Invoke when returning SafeHandles
        private SafeMyResourceHandle () : base(IntPtr.Zero, true)
        {
        }

        // no need to provide a finalizer - SafeHandle's critical
        // finalizer will call ReleaseHandle for you.

        public override bool IsInvalid
        {
          get { return handle == IntPtr.Zero; }
        }

        override protected bool ReleaseHandle()
        {
          // this method is a constrained execution region, and
          // *must* not allocate

          return DeleteObject(href);
        }

        [DllImport("gdi32.dll", SuppressUnmanagedCodeSecurity]
        [ReliabilityContract(Consistency.WillNotCorruptState, CER.Success)]
        private static extern bool DeleteObject(HandleRef hObject);

        [DllImport("kernel32")]
        internal static extern SafeMyResourceHandle CreateHandle(int someState);
      }
    }

    // derived class
    public class MyComplexWindow : ComplexWindow
    {
      private Component myComponent; // other resource you use

      private bool disposed = false;

      public MyComplexWindow()
      {
        myComponent = new Component();
      }

      protected override void Dispose(bool disposing)
      {
        if (!this.disposed)
        {
          if (disposing)
          {
            // free any disposable resources you own
            if (myComponent != null)
              myComponent.Dispose();

            this.disposed = true;
          }

          // perform any custom clean-up operations
          // such as flushing the stream
        }

        base.Dispose(disposing);
      }
    }

> *Annotation (Brian Grunkemeyer):* Note that the derived `MyComplexWindow` class
> above doesn't strictly need to add in its own `Dispose(Boolean)` -- it could
> instead check to see whether `myComponent` was set to `null` in `Dispose(bool)` and
> in all methods that use that type. `Dispose(bool)` should still chain to its base
> class in all cases though. The drawback with this approach is it may be more
> difficult to maintain if you start adding multiple fields to your type.

### 1.1.6 SafeHandle

Using classes derived from `SafeHandle` allows you to wrap a handle to an
unmanaged resource. It provides protection for handle recycling security
attacks, critical finalization, and special managed/unmanaged interop
marshaling. The expectation is that you will subclass `SafeHandle` (or a type
like `SafeHandleZeroOrMinusOneIsInvalid`) for your own resource type.

* Do use `SafeHandle` for wrapping scarce unmanaged resources such as OS
handles, preferring it to IntPtr or Int32 representations for native handles,
e.g. as in:

    private SafeMyResourceHandle handle;

If your resource is very light-weight, such as a small unmanaged buffer for
example, it is not subject to recycling attacks, and your scenario is very
performance sensitive, you might consider avoiding `SafeHandle`. `SafeHandle` has
many advantages, such as reducing the graph promotion due to Finalization,
avoid recycling attacks, and guaranteeing no leaks even in the face of rude
AppDomain unloading, but it may be too heavy-weight for very light-weight
resources.

> *Annotation (Brian Grunkemeyer):* Note that we publicly expose a few `SafeHandle`
> subclasses for commonly used handle types, like `SafeFileHandle` and
> `SafeWaitHandle` in the `Microsoft.Win32.SafeHandles` namespace. For a discussion
> of what led us to designing `SafeHandle`, read
> [http://blogs.msdn.com/bclteam/archive/2005/03/16/396900.aspx](http://blogs.msdn.com/bclteam/archive/2005/03/16/396900.aspx).

### 1.1.7 HandleCollector and Memory Pressure

* Avoid making calls to `GC.Collect()` and `GC.GetTotalMemory(true)` with the
intent of controlling the GC's policy to provoke collecting resources eagerly.
Calling `GC.Collect()` interferes with the natural GC collection schedule, which
negatively impact performance of your application. In general, both methods
were designed primarily for testing purposes. Use the
`System.Runtime.InteropServices.HandleCollector` class or the
`GC.AddMemoryPressure` methods in their place.

#### Handle Collector

`HandleCollector` tracks unmanaged handles in order to initiate collections in
response to specific thresholds (specified during construction) being met.
Whenever allocating a resource which is managed by a collector, simply call
`Add`; when freed, call `Remove`. Once the number of handles surpasses a given
threshold, a GC will occur, hopefully cleaning up any excess resources that may
be eligible.

> *Annotation (Jeffrey Richter):* Internally, `HandleCollector` and `AddMemoryPressure`
> both call `GC.Collect`. So what this guideline is trying to say is that there are
> times when calling `GC.Collect` is useful but you should really try to avoid it
> if possible. If you do call GC.Collect, you should have a really good reason to
> do it and `HandleCollector`/`AddMemoryPressure` exist for good reasons: because it
> is better to force a collection and adversely affect performance than it is for
> your program to malfunction because it can't create another handle to an
> unmanaged resource or because there isn't enough unmanaged memory available to
> for a necessary allocation.

This snippet demonstrates how GDI handles can be limited to a threshold of
between 10 and 50. The lower bound is where collection is suggested to begin,
while the upper bound is a hard limit on the absolute number of resources that
are available:

    HandleCollector collector = new HandleCollector("GdiHandles", 10, 50);

    IntPtr CreateSolidBrush()
    {
      collector.Add();

      try
      {
        return CreateSolidBrushImpl();
      }
      catch
      {
        // if allocation fails, decrement the live handle count
        collector.Remove();
        throw;
      }
    }

    void DeleteBrush(IntPtr handle)
    {
      DeleteObjectImpl(handle);
      collector.Remove();
    }

#### Add and Remove Memory Pressure

Using `GC.AddMemoryPressure` gives hints to the GC when a managed object's cost
is higher than it appears due to unmanaged resources. Pass to it the size of
the unmanaged resource, and the GC will alter its collection strategy in
response to the increased amount of pressure on an object.
`GC.RemoveMemoryPressure` is used to reduce the pressure once the resources have
been freed. For example, the following snippet of code demonstrates how to add
and remove memory pressure each time a new `Bitmap` is acquired and released
respectively:

    public class Bitmap : IDisposable
    {
      private long bmpSize;

      public Bitmap(string path)
      {
        bmpSize = new FileInfo(path).Length;

        GC.AddMemoryPressure(bmpSize);

        // allocation work
      }

      public void Dispose()
      {
        Dispose(true);
        GC.SuppressFinalize(this);
      }

      protected void Dispose(bool disposing)
      {
        // cleanup work

        GC.RemoveMemoryPressure(bmpSize);
      }

      ~Bitmap()
      {
        Dispose(false);
      }
    }

Note, however, that if you're allocating a large number of small byte
allocations, it is more efficient to add and remove pressure in large chunks.
For example, megabytes or 100's of kilobytes at a time. You might want to
implement a special pressure manager class to handle this, as shown in the
following snippet. The `BitmapPressureManager` class adds and removes memory
pressure transactions in 500KB quantities of memory. The `Bitmap` class from
above has been modified to call through to this new class instead:

    public class Bitmap : IDisposable
    {
      private long bmpSize;

      public Bitmap(string path)
      {
        bmpSize = new FileInfo(path).Length;

        BitmapPressureManager.AddMemoryPressure(bmpSize);

        // allocation work
      }

      public void Dispose()
      {
        Dispose(true);
        GC.SuppressFinalize(this);
      }

      protected void Dispose(bool disposing)
      {
        // cleanup work

        BitmapPressureManager.RemoveMemoryPressure(bmpSize);
      }

      ~Bitmap()
      {
        Dispose(false);
      }
    }

    internal static class BitmapPressureManager
    {
      private const long threshold = 524288; // only add pressure in 500KB chunks

      private static long pressure;
      private static long committedPressure;

      private static readonly object sync = new object();

      internal static void AddMemoryPressure(long amount)
      {
        Interlocked.Add(ref pressure, amount);
        PressureCheck();
      }

      internal static void RemoveMemoryPressure(long amount)
      {
        AddMemoryPressure(-amount);
      }

      private static void PressureCheck()
      {
        if (Math.Abs(pressure - committedPressure) >= threshold)
        {
          lock (sync)
          {
            long diff = pressure - committedPressure;
            if (Math.Abs(diff) >= threshold) // double check
            {
              if (diff < 0)
              {
                GC.RemoveMemoryPressure(-diff);
              }
              else
              {
                GC.AddMemoryPressure(diff);
              }

              committedPressure += diff;
            }
          }
        }
      }
    }

