---
layout: post
title: Concurrent counting
date: 2008-05-16 20:18:59.000000000 -07:00
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
Counting events and doing something once a certain number have been registered is
a highly common pattern that comes up in concurrent programming a lot.  In the
olden days, COM ref counting was a clear example of this: multiple threads might
share a COM object, call Release when done with it, and hence memory management was
much simpler.  GC has alleviated a lot of that, but the problem of deciding
when a shared IDisposable resource should be finally Disposed of in .NET is strikingly
similar.  And now-a-days, things like CountdownEvent are commonly useful for
orchestrating multiple workers (see [MSDN Magazine](http://msdn.microsoft.com/en-us/magazine/cc163427.aspx)),
which (although not evident at first) is based on the same counting principle.

Coding up one-off solutions to all of these is actually pretty simple.  But
doing so seems unfashionably ad-hoc, at least to me.  Codifying the pattern
can be done in a couple dozen lines of code, so that it can be reused for many purposes.
As an example, here is a reusable Counting&lt;T&gt; class, written in C#, that just invokes
action delegate once the count reaches zero:

```
#pragma warning disable 0420
using System;
using System.Threading;

public class Counting<T>
{
    private readonly T m_obj;
    private volatile int m_count;
    private readonly Action<T> m_action;

    public Counting(T obj, int initialCount, Action<T> action)
    {
        m_obj = obj;
        m_count = initialCount;
        m_action = action;
    }

    public int AddRef()
    {
        int c;
        if ((c = Interlocked.Increment(ref m_count)) == 1)
            throw new Exception();
        return c;
    }

    public int Release()
    {
        int c;
        if ((c = Interlocked.Decrement(ref m_count)) == 0)
            m_action(m_obj);
        return c;
    }

    public T Obj { get { return m_obj; } }
}
```

Notice I've used the IUnknown vocabulary of AddRef and Release.  Old habits
die hard.

The CountdownEvent I mentioned earlier is just a simple extension to this basic functionality.
In fact, we don't need to write another class; it's merely an instance of Counting&lt;T&gt;,
where the T is a ManualResetEvent.  Setters directly use the Counting&lt;T&gt; object's
Release method to register a signal, while waiters can use the WaitOne method on
the raw ManualResetEvent itself.  The event will be set once all signals have
arrived:

```
Counting<ManualResetEvent> countingEv = new Counting<ManualResetEvent>(
    new ManualResetEvent(false), N, e => e.Set()
);

...

// Setter:
countingEv.Release();

// Waiter:
countingEv.Obj.WaitOne();
```

(Exposing a traditional Set/Wait interface would of course be nicer, but even then
Counting&lt;T&gt; makes the implementation brain-dead simple.)

Similarly, the "who should dispose" problem is easy to solve with Counting&lt;T&gt;.
Say that, instead of setting the event, we actually want to Dispose of some IDisposable
object when all threads are done with it:

```
Counting<ManualResetEvent> ev = new Counting<ManualResetEvent>(
    new ManualResetEvent(false), N, e => e.Dispose()
);
```

Though this does the trick, we might instead wrap it in a more convenient package:

```
public class CountingDispose<T> : Counting<T>, IDisposable
    where T : IDisposable
{
    public CountingDispose(T obj, int initialCount) :
        base(obj, initialCount, d => d.Dispose()) { }
}
```

Given this definition, threads can use the CountingDispose&lt;T&gt; object as they would
any IDisposable thing.  This facilitates use in C# using blocks.  Only
when all threads have called Dispose will Dispose be called on the actual underlying
object:

```
CountingDispose<ManualResetEvent> ev = new CountingDispose<ManualResetEvent>(
    new ManualResetEvent(false), N
);

...

// Some threads wait:
using (ev) {
    ... ev.WaitOne(); ...
}

// Some threads set:
using (ev) {
    ... ev.Set(); ...
}
```

I've found that the extremely simple Counting&lt;T&gt; idea is a surprisingly powerful
one.  It's fairly extensible too; for example, you clearly may want to run
actions at different points in the counting, use clever synchronization to ensure
actions run at particular points are processed in-order (useful for progress reporting),
to reset the count afterwards, and so on.  It's way too simple to claim it's
anything terribly amazing, but thought I'd share the idea anyway.

