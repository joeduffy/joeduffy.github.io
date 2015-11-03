---
layout: post
title: Extension methods as default interface method implementations
date: 2010-02-09 18:21:49.000000000 -08:00
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
One of my comments in the 2nd edition of the .NET Framework design guidelines (on
page 164) was that you can use extension methods as a way of getting default implementations
for interface methods.  We've actually begun using these techniques here on
my team.  To illustrate this trick, let's rewind the clock and imagine we were
designing new collections APIs from day one.

Let's say we gave the core interfaces the most general methods possible.  These
may neither be the most user friendly overloads nor the ones that most people use
all the time.  They would, however, be those from which all the other convenience
methods could be implemented.  An INewList<T> interface that was designed with
these principles in mind may look like this:

```
public interface INewList<T> : IEnumerable<T>
{
    int Count { get; }
    T this[int index] { get; set; }

    void InsertAt(int index, T item);
    void RemoveAt(int index);
}
```

This interface is missing all the nice convenience methods you will find on .NET's
IList<T>, like Add, Clear, Contains, CopyTo, IndexOf, and Remove.  So it's not
really as nice to use.  You can't write an API that takes in an INewList<T>
and performs an Add against it, for example, like you can with IList<T>.

One approach to solving this might be to write a concrete class -- much like .NET's
System.Collections.ObjectModel.Collection<T> -- that provides concrete implementations
of all of these methods, and then other lists can simply subclass that.  But
we can do better.

Instead, let's give INewList<T> default implementations of all of these methods.
How do we do this?  That's right: with extension methods.  Voila!

```
public static class NewListExtensions
{
    public static void Add<T>(this INewList<T> lst, T item) {
        lst.InsertAt(lst.Count, item);
    }

    public static void Clear<T>(this INewList<T> lst) {
        int count;
        while ((count = lst.Count) > 0) {
            lst.RemoveAt(count - 1);
        }
    }

    public static bool Contains<T>(this INewList<T> lst, T item) {
        return lst.IndexOf(item) != -1;
    }

    public static void CopyTo<T>(this INewList<T> lst, T[] array, int arrayIndex) {
        for (int i = 0; i < lst.Count; i++) {
            array[arrayIndex + i] = lst[i];
        }
    }

    public static int IndexOf<T>(this INewList<T> lst, T item) {
        var eq = EqualityComparer<T>.Default;
        for (int i = 0; i < lst.Count; i++) {
            if (eq.Equals(item, lst[i])) {
                return i;
            }
        }
        return -1;
    }

    public static bool Remove<T>(this INewList<T> lst, T item) {
        int index = lst.IndexOf(item);
        if (index == -1) {
            return false;
        }

        lst.RemoveAt(index);
        return true;
    }
}
```

Well isn't that neat.  We've now given any INewList<T> implementations all these
common methods without dirtying their class hierarchies, built atop a tiny core of extensibility.
This is much like .NET's Collection<T> which exposes the core as abstract methods.
Indeed, we can go even further.  Any convenience overloads, like the multitude
of CopyTos on List<T> in .NET, can be given to all INewList<T>'s also.  And
yet implementing INewList<T> remains as braindead simple as it was before: two properties
and two methods.  In fact, it's simpler than doing a more feature-rich IList<T>,
because the convenience methods come for free.

It would be even niftier if you could add these methods straight onto INewList<T>,
and have the C# compiler emit the extension methods silently for you.  In other
words:

```
public interface INewList<T> : IEnumerable<T>
{
    ... interface methods (as above) ...

    void Add(T item) {
        InsertAt(Count, item);
    }

    void Clear() {
        int count;
        while ((count = Count) > 0) {
            RemoveAt(count - 1);
        }
    }

    ... and so on ...
}
```

Although this would just be sugar for the NewListExtensions class shown earlier,
it sure saves some typing and makes it the pattern more apparent and first class.

Though cool, this whole idea is certainly not perfect.

For one, there are no extension properties.  So you can't use this trick for
properties.

But the more obvious and severe downside to this approach that these methods are
not specialized for the given concrete type.  For example, the Clear method
is potentially far less efficient than a hand-rolled List<T>, because it does O(N)
RemoveAts rather than a single O(1) fixup of the count.

Recall now that the compiler binds more tightly to instance methods than extension
methods.  So we could implement our own little list class with a faster Clear
method if we'd like:

```
class MyList : INewList<T>
{
    ... the two properties and two methods from INewList<T> ...

    public void Clear() {
        .. efficient! ...
    }
}
```

Now when someone calls Clear on a MyList<T> directly, the compiler will bind to the
efficient Clear.

This is still not perfect.  If you pass the MyList<T> to an API that takes in
an INewList<T>, any calls to Clear will fall back to the extension method.
Extension methods are not virtual in any way.  You can try to simulate virtual
dispatch, but it gets messy quick.  For example, say we defined an IFasterList<T>
that includes all those convenience methods that lists frequently want to make faster;
we can then do a typecheck plus virtual dispatch in the extension method.

For now, let's pretend that's just the Clear method:

```
public interface IFasterList<T> : INewList<T>
{
    void Clear();
}
```

Of course, MyList<T> above would now implement IFasterList<T>.  Invocations
through IFasterList<T> will automatically bind to the faster variant; but if objects
that implement IFasterList<T> get passed around as IList<T>s, you lose this ability.
So the Clear extension method can now do a typecheck:

```
public static void Clear<T>(this INewList<T> lst) {
    IFasterList<T> fstLst = lst as IFasterList<T>;
    if (fstLst != null) {
        fstLst.Clear();
        return;
    }

    int count;
    while ((count = lst.Count) > 0) {
        lst.RemoveAt(count - 1);
    }
}
```

This works but is obviously a tedious and hard-to-maintain solution.  It would
be neat if someday C# figured out a way to "magically" reconcile virtual dispatch
and extension methods.  I don't know if there is a clever solution out there.
I am skeptical.  Nevertheless, despite this flaw, the above techniques are certainly
thought provoking and interesting enough to play around with and consider for your
own projects.  And at the very least, it's fun.  Enjoy.

