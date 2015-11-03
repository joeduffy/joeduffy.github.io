---
layout: post
title: A lazy initialization primitive for .NET
date: 2007-06-09 14:09:14.000000000 -07:00
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
Windows Vista has a new [one-time initialization feature](http://msdn.microsoft.com/msdnmag/issues/07/06/Concurrency/),
which I'm pretty envious of being someone who writes most of his code in C# and
answers countless questions about [double-checked locking in the CLR](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/).
Rather than sprinkling double-checked locking all over your code base, along with
the ever-lasting worry in the back of your mind that you've gotten the synchronization
incorrect, it's a better idea to consolidate it into one place.

That's the purpose of the LazyInit&lt;T&gt; and LazyInitOnlyOnce&lt;T&gt; structs below.
Both let you specify an "initialization" routine (as a delegate) which gets invoked
at the appropriate time to lazily initialize the state.   The only difference
between the two is that LazyInit&lt;T&gt; might invoke your delegate more than once, due
to races, but it will ensure only one value "wins".  LazyInitOnlyOnce&lt;T&gt;
does the extra work to ensure the initialization routine only gets called once, though
at a slightly higher cost: we might need to block a thread, which means allocating
a Win32 event.

Why the two?  I had originally written this with a Boolean specified at construction
time to pick one over the other, but this required an extra object field which, for
LazyInit&lt;T&gt; which was never used, along with a Boolean field.  I defined both
as structs to make them super lightweight to use, and getting rid of the extra two
fields seemed worth the extra baggage of an extra class, given that such a type could
end up used very pervasively throughout a large code-base.  As it stands, LazyInit&lt;T&gt;
is just the size of a pointer plus the size of T.  LazyInitOnlyOnce&lt;T&gt; adds
one additional pointer to that.

To start with, both use the same Initializer&lt;T&gt; delegate:

```
public delegate T Initializer<T>();
```

And here's LazyInit&lt;T&gt;, the simpler of the two:

```
public struct LazyInit<T> where T : class
{
    private Initializer<T> m_init;
    private T m_value;

    public LazyInit(Initializer<T> init)
    {
        m_init = init;
        m_value = null;
    }

    public T Value
    {
        get
        {
            if (m_value == null) {
                T newValue = m_init();

                if (Interlocked.CompareExchange(
                        ref m_value, newValue, null) != null &&
                            newValue is IDisposable) {
                    ((IDisposable)newValue).Dispose();
                }
            }

            return m_value;
        }
    }
}
```

Note that T is constrained to a reference type, so that we can use a null check to
determine when initialization is needed.  We could have used a separate Boolean,
but this would required adding another field as well as [considering some trickier
memory model issues](http://www.bluebytesoftware.com/blog/PermaLink,guid,3420c247-2da5-411b-8ce7-05082e1aba30.aspx).

If the Interlocked.CompareExchange fails, it means we lost the lazy initialization
race with another thread, and thus just return the value the other thread produced.
We also Dispose of the garbage object if it implements IDisposable.  This pattern
is very common in lazy initialization scenarios, like allocating an expensive kernel
object lazily on demand.  We'd prefer to get rid of it right away since we
know it will never be used.

I wish there was a way to make boxing a compile-time error for some value types.
Clearly you don't ever want to box one of these, because making a copy will entirely
break the synchronization guarantees.

I've omitted some error checking, like ensuring m\_init actually got initialized
to a non-null value.

Say you need a lazily initialized event on your object.  You would just do this:

```
public class C
{
    private LazyInit<EventWaitHandle> m_event;
    private object m_otherState;
    public C()
    {
        m_event = new LazyInit<EventWaitHandle>(
            delegate { return new ManualResetEvent(false); });
        m_otherState = ...;
    }

    ...

    private void DoSomething()
    {
        ...
        if (... need to set the event ...)
            m_event.Value.Set();
    }
}
```

And lastly, here's LazyInitOnlyOnce&lt;T&gt;:

```
public struct LazyInitOnlyOnce<T> where T : class
{
    private Initializer<T> m_init;
    private T m_value;
    private object m_syncLock;

    public LazyInitOnlyOnce(Initializer<T> init)
    {
        m_init = init;
        m_value = null;
        m_syncLock = null;
    }

    public T Value
    {
        get
        {
            if (m_value == null) {
                object newSyncLock = new object();
                object syncLockToUse = Interlocked.CompareExchange(
                    ref m_syncLock, newSyncLock, null);
                if (syncLockToUse == null)
                    syncLockToUse = newSyncLock;
                lock (syncLockToUse) {
                    if (m_value == null)
                        m_value = m_init();
                    m_syncLock = null;
                    m_init = null;
                }
            }

            return m_value;
        }
    }
}
```

We use a monitor to ensure mutual exclusion.  I lazily allocate the object used
for synchronization, but this is clearly a tradeoff.  We pay for the added complexity
to the code and the extra interlocked instruction (on the slow path), but avoid having
to allocate an extra object when we create the struct itself and keep it alive, when
we might not ever need it.  There's already an allocation for the delegate,
but this just means there's one instead of two.

It may also not be obvious why I null out the m\_syncLock field before exiting.
If we don't, the object will remain live as long as the lazily initialized variable
remains live.  We want the object to be GC'd as soon as possible, because
it is no longer needed.

You can use a class constructor in .NET to acheive a similar effect.  Static
field initializers, however, execute in the class constructor, meaning if you have
multiple lazily initialized objects or static methods, they all get initialized at
once.  This is much more like LazyInitOnlyOnce&lt;T&gt; than LazyInit&lt;T&gt;, since the
CLR uses locks to prevent the class constructor from running on multiple threads
at once.

Anyway, there's very little that is novel here.  But I do believe having these
primitives in the .NET Framework would be immensely useful.  It would at
least help steer people towards the recommended and most efficient lazy initialization
pattern, which is to use double-checked locking, rather than having them possibly
pursue more complicated designs.  It also removes the need to worry about volatile
and Thread.MemoryBarrier, for those that aren't knowledgeable of the work
we did in the CLR 2.0 to ensure double-checked locking works properly.  Lastly,
it has the added benefit of getting rid of tricky calls to Interlocked.CompareExchange
and lock statements scattered throughout your code, in favor of something more declarative.
What do you think?

