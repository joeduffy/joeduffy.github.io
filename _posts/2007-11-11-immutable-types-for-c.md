---
layout: post
title: Immutable types for C#
date: 2007-11-11 14:11:41.000000000 -08:00
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
I've been asked a number of times about immutable types support for C#.  Although
C# doesn't offer first class language support in the way that F# does, you can get
pretty far with what you do have in your hands already.  Nothing prevents you
from creating immutable data structures today, of course, but the problem is that
there's no compiler or runtime support to ensure you've done it right.

I just hacked together some new attributes and a handful of FxCop rules as an experiment.
I've been very happy with the result.  Sure it's not baked into the language,
but it's a start.  If there's any interest, I can make the code available
so you can play with it too.

**Attributes and analysis**

Imagine we had an ImmutableAttribute.  Annotating a type with it indicates that
objects of that particular type are immutable, i.e. that their state never changes
after being constructed.  This is great from a concurrency standpoint because
it means access to such objects do not require synchronization.  This can lead
to more efficient code that not only has a higher chance of being correct but is
also vastly easier to maintain.  Well, what kind of restrictions would such
a type be subject to?

_1. Immutable types must have only initonly fields._

The first rule takes advantage of existing CLR type system and language support for
initonly fields (a.k.a. readonly in C#).  Marking a field as initonly ensures
it is never written to after the constructor has finished executing.  So long
as all fields are initonly, the class is effectively already "shallow" immutable.

_2. Immutable types must only contain fields of immutable types._

The second rule ensures transitivity, or "deep" immutability.  The mutability
of a complex object is typically, but not always, comprised of not only its own fields
but also the state in the objects it refers to.  With this rule and the prior
rule, we're about 90% there.

_3. Immutable types should only subclass other immutable types._

To give the appearance that a particular object is immutable, that object's type
must not depend on other types that are mutable, as articulated by the previous rule.
The 'base' reference is effectively just another field, and so this rule is derived
from the previous one.  If an immutable type could inherit mutable members and
fields, then it wouldn't really be immutable after all.

_4. Mutable types should not subclass immutable types._

Similar to the previous rule, it is also a bad thing if a mutable subtype can override
behavior from the subtype, giving the appearance of mutability.  Say we have
an immutable class IC with a virtual method f, and some mutable subclass MC overrides
f to introduce logic that logically mutates the state of an object.  Although
the rules above are sufficient to ensure that the object is physically immutable,
this can circumvent immutability safety through polymorphism.  A related piece
of advice: public immutable types should be sealed, to prevent outside classes that
do not abide by immutability analysis from breaking code which assumes a given type
is immutable.  Alternatively, virtual members can be eliminated.

_5. Immutable types must not leak the 'this' reference during construction._

This rule is subtle.  Although initonly ensures fields are never written to
after construction, these fields may be written to any number of times while an object
is actively being constructed.  If some code called during construction publishes
a reference to the object (e.g. by storing it in a static variable), then other threads
might access the object while it still appears to be mutable.  They may witness
a partially initialized object, an object whose fields are still changing, and so
on.

And that's it!  5 simple rules.  It may sound complicated, but the code
to perform the static analysis for all but the last one is straightforward and a
dozen-or-so lines apiece.  A few things are worth mentioning.  First, the
[CLR's memory model](http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx)
ensures that, after an object is constructed and published, reads of its fields cannot
be reordered to break immutability.  Additionally, there are many immutable
types in the CLR today that are not verified as such.  So in my analysis rules,
I have hard-coded a set of well known immutable types so that you can use them w/out
problem: Object, String, DateTime, TimeSpan, Boolean, Byte, SByte, Int16, Int32,
Int64, IntPtr, UInt16, UInt32, UInt64, UIntPtr, Decimal, Double, Single, and ValueType.
Ideally if we supported this in the .NET Framework, we'd annotate them.

**Impact to imperative programming**

Programming in an immutable world is rather tricky.  As someone who has done
most of his programming for the past 10+ years in C-style languages, I just take
for granted that data structures change over time.  With immutability, there
tends to be a whole lot more copying and functional-style function calling, where
data structures are passed as an input argument and the "mutated" copy is returned
as an output argument.  I'm trying to kick the mutability habit, since I fully
believe immutability is one key to being successful with massive degrees of parallelism.
And it usually leads to cleaner code too.

But it's hard.  Using something as simple as an array field on an immutable
type will fail the above rules, since the CLR's array types are mutable.
I'll explore building one below, but this probably points to a need for better
immutability support in the .NET Framework.  It's not too difficult to imagine
providing base classes for common needs when building immutable data structures.

**Circumventing the analysis**

As you begin to explore immutable types in a bit more depth, you'll realize there
are often cases where immutability-by-cleverness is possible.  That is to say,
although one or more of the rules above have been violated, the end result still
appears to be immutable.  I can build an immutable list out of a linked list
to avoid depending on CLR arrays, and mark the nodes as immutable, but they must
refer to elements stored within the list.  Should we require the elements to
also be immutable?  Perhaps, but perhaps not, depending on whether you
consider the state of the list to also include the state of the elements inside it.
Usually that wouldn't be the case.  And, besides, if we know what we're doing,
we can create an immutable list based on an array anyway, which enables O(1)
IList<T>-style random access.  We just need to be careful to encapsulate the
array object and to never store an element into it post-construction.

To facilitate working around some of the rules in ways that are often necessary,
I have provided options on ImmutableAttribute to suppress certain checks.  Additionally,
there is a MutableAttribute which can mark certain fields to indicate they are not
subject to the same restrictions as other fields on an immutable type.

**An ImmutableList<T>**

As an illustration, here is an ImmutableList<T>.  It implements IList<T>, but
sadly it must throw exceptions in several circumstances because both IList<T> and
ICollection<T> offer methods that are intrinsically mutable.  Undoubtedtly there
are bugs because I whipped it up quickly and have omitted a lot of needed error checking.
I just wanted to give the general idea of how it might be done:

```
/// <summary>
/// A list that has been written to be observationally immutable.  A mutable array
/// is used as the backing store for the list, but no mutable operations are offered.
/// </summary>
/// <typeparam name="T">The type of elements contained in the list.</typeparam>

[Immutable]
public sealed class ImmutableList<T> : IList<T>
{
    [Mutable]
    private readonly T[] m_array;

    /// <summary>
    /// Create a new list.
    /// </summary>
    public ImmutableList()
    {
        m_array = new T[0];
    }

    /// <summary>
    /// Create a new list, copying elements from the specified array.
    /// </summary>
    /// <param name="arrayToCopy">An array whose contents will be copied.</param>
    public ImmutableList(T[] arrayToCopy)
    {
        m_array = new T[arrayToCopy.Length];
        Array.Copy(arrayToCopy, m_array, arrayToCopy.Length);
    }

    /// <summary>
    /// Create a new list, copying elements from the specified enumerable.
    /// </summary>
    /// <param name="enumerableToCopy">An enumerable whose contents will
    /// be copied.</param>
    public ImmutableList(IEnumerable<T> enumerableToCopy)
    {
        m_array = new List<T>(enumerableToCopy).ToArray();
    }

    /// <summary>
    /// Retrieves the immutable count of the list.
    /// </summary>
    public int Count
    {
        get { return m_array.Length; }
    }

    /// <summary>
    /// A helper method used below when a mutable method is accessed. Several
    /// operations on the collections interfaces IList<T> and
    /// ICollection<T> are mutable, so we cannot support them. We offer
    /// immutable versions of each.
    /// </summary>
    private static void ThrowMutableException(string copyMethod)
    {
        throw new InvalidOperationException(
            String.Format("Cannot mutate an immutable list; " +
            "see copying method '{0}'", copyMethod));
    }

    /// <summary>
    /// Whether the list is read only: because the list is immutable, this
    /// is always true.
    /// </summary>
    public bool IsReadOnly
    {
        get { return true; }
    }

    /// <summary>
    /// Accesses the element at the specified index.  Because the list is
    /// immutable, the setter will always throw an exception.
    /// </summary>
    /// <param name="index">The index to access.</param>
    /// <returns>The element at the specified index.</returns>
    public T this[int index]
    {
        get
        {
            return m_array[index];
        }
        set
        {
            ThrowMutableException("CopyAndSet");
        }
    }

    /// <summary>
    /// Copies the list and adds a new value at the end.
    /// </summary>
    /// <param name="value">The value to add.</param>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndAdd(T value)
    {
        T[] newArray = new T[m_array.Length + 1];
        m_array.CopyTo(newArray, 0);
        newArray[m_array.Length] = value;
        return new ImmutableList<T>(newArray);
    }

    /// <summary>
    /// Returns a new, cleared (empty) immutable list.
    /// </summary>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndClear()
    {
        return new ImmutableList<T>(new T[0]);

    }

    /// <summary>
    /// Copies the list and modifies the specific value at the index provided.
    /// </summary>
    /// <param name="index">The index whose value is to be changed.</param>
    /// <param name="item">The value to store at the specified index.</param>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndSet(int index, T item)
    {
        T[] newArray = new T[m_array.Length];
        m_array.CopyTo(newArray, 0);
        newArray[index] = item;
        return new ImmutableList<T>(newArray);
    }

    /// <summary>
    /// Copies the list and removes a particular element.
    /// </summary>
    /// <param name="item">The element to remove.</param>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndRemove(T item)
    {
        int index = IndexOf(item);
        if (index == -1)
        {
            throw new ArgumentException("Item not found in list.");
        }
        return CopyAndRemoveAt(index);
    }

    /// <summary>
    /// Copies the list and removes a particular element.
    /// </summary>
    /// <param name="index">The index of the element to remove.</param>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndRemoveAt(int index)
    {
        T[] newArray = new T[m_array.Length - 1];
        Array.Copy(m_array, newArray, index);
        Array.Copy(m_array, index + 1, newArray, index, m_array.Length - index - 1);
        return new ImmutableList<T>(newArray);
    }

    /// <summary>
    /// Copies the list adn inserts a particular element.
    /// </summary>
    /// <param name="index">The index at which to insert an element.</param>
    /// <param name="item">The element to insert.</param>
    /// <returns>A modified copy of this list.</returns>
    public ImmutableList<T> CopyAndInsert(int index, T item)
    {
        T[] newArray = new T[m_array.Length + 1];
        Array.Copy(m_array, newArray, index);
        newArray[index] = item;
        Array.Copy(m_array, index, newArray, index + 1, m_array.Length - index);
        return new ImmutableList<T>(newArray);
    }

    /// <summary>
    /// This method is unsupported on this type, because it is immutable.
    /// </summary>
    void ICollection<T>.Add(T item)
    {
        ThrowMutableException("CopyAndAdd");
    }

    /// <summary>
    /// This method is unsupported on this type, because it is immutable.
    /// </summary>
    void ICollection<T>.Clear()
    {
        ThrowMutableException("CopyAndClear");
    }

    /// <summary>
    /// Checks whether the specified item is contained in the list.
    /// </summary>
    /// <param name="item">The item to search for.</param>
    /// <returns>True if the item is found, false otherwise.</returns>
    public bool Contains(T item)
    {
        return Array.IndexOf<T>(m_array, item) != -1;
    }

    /// <summary>
    /// Copies the contents of this list to a destination array.
    /// </summary>
    /// <param name="array">The array to copy elements to.</param>
    /// <param name="index">The index at which copying begins.</param>
    public void CopyTo(T[] array, int index)
    {
        m_array.CopyTo(array, index);
    }

    /// <summary>
    /// Retrieves an enumerator for the list's collections.
    /// </summary>
    /// <returns>An enumerator.</returns>
    public IEnumerator<T> GetEnumerator()
    {
        for (int i = 0; i < m_array.Length; i++) {
            yield return m_array[i];
        }
    }

    /// <summary>
    /// Retrieves an enumerator for the list's collections.
    /// </summary>
    /// <returns>An enumerator.</returns>
    IEnumerator IEnumerable.GetEnumerator()
    {
        return ((IEnumerable<T>)this).GetEnumerator();
    }

    /// <summary>
    /// Finds the index of the specified element.
    /// </summary>
    /// <param name="item">An item to search for.</param>
    /// <returns>The index of the item, or -1 if it was not found.</returns>
    public int IndexOf(T item)
    {
        return Array.IndexOf<T>(m_array, item);
    }

    /// <summary>
    /// This method is unsupported on this type, because it is immutable.
    /// </summary>
    void IList<T>.Insert(int index, T item)
    {
        ThrowMutableException("CopyAndInsert");
    }

    /// <summary>
    /// This method is unsupported on this type, because it is immutable.
    /// </summary>
    bool ICollection<T>.Remove(T item)
    {
        ThrowMutableException("CopyAndRemove");
        return false;
    }

    /// <summary>
    /// This method is unsupported on this type, because it is immutable.
    /// </summary>
    void IList<T>.RemoveAt(int index)
    {
        ThrowMutableException("CopyAndRemoveAt");
    }
}
```

I won't spend much time going over this code.  Just notice that the type is
marked with the ImmutableAttribute, the array field is marked with the MutableAttribute
(since it's not itself an immutable type and would fail the analysis otherwise),
and that any operations that modify the list must make a copy of the entire thing.

**Summary**

This has been an interesting exercise.  Through it, I have come to realize that
first class immutability in the type system is not such a farfetched dream.
The most onerous aspect to it is probably the restrictions it imposes on subclassing
in the programming model, effectively bifurcating the type system into those types
that are mutable and those types that are immutable.  But, in the end, I'm
not so sure it's too bad a problem: interchanging the two seems like a very bad
idea anyway.

Feedback on all of this would be appreciated.  Do you see it as useful?
If you had it, would you use it in your programs today?  Do you believe that
it is one step needed (of many!) to bring us towards a world in which building
concurrent programs is simpler?

