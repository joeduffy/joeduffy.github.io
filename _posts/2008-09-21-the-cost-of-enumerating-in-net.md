---
layout: post
title: The cost of enumerating in .NET
date: 2008-09-21 00:14:58.000000000 -07:00
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
The enumeration pattern in .NET unfortunately implies some overhead that makes it
difficult to compete with ordinary for loops.  In fact, the difference between

```
T[] a = ...;
for (int i = 0, c = a.Length; i < c; i++) ...action(a[i])...;
```

and

```
T[] a = ...;
IEnumerator<int> ae = ((IEnumerable<T>)a).GetEnumerator();
while (ae.MoveNext()) ...action(ae.Current)...;
```

is about 3X.  That is, the former is 1/3rd the expense of the latter, in terms
of raw enumeration overhead.  Clearly as action becomes more expensive the significance
of this overhead lessens.  But if your plan is to invoke a small action over
a large number of elements, using an enumerator instead of indexing directly into
the array could in fact cause your algorithm to take 3X longer to finish.

There are many reasons for this problem.  They are probably obvious.  Using
an enumerator requires at least two interface method calls just to extract a single
element from the array.  Because there are O(length) number of these operations,
the overhead imposed will be O(length) as well.  Contrast that with the nice,
compact for loop, which emits ldarg IL instructions that access the array directly.
This will end up computing some offset (e.g., i \* sizeof(T)) and dereferencing right
into the array memory.  The enumerator needs to do that, of course, but only
after the two interface calls are made.  Additionally, it is possible for the
JIT compiler to omit the bounds check on the array access if it knows 'c' in
the predicate 'i < c' was computed from 'a.Length', because arrays in .NET
are immutable and their size cannot change.

(Strangely, it appears going through IList&lt;T&gt; is even slower than enumeration.
In fact, it appears to be more than 3X the cost of going through IList&lt;T&gt;'s enumerator,
and over 10X that of indexing into the array using true ldarg instructions instead
of interface calls to IList&lt;T&gt;'s element indexer.)

All of this actually makes it somewhat difficult for those on my team building PLINQ
to compete with hand written programs.  That's true of LINQ generally.
In fact, LINQ tends to be worse, because you string several enumerators together
to form a query, often leading to even more overhead attributed to enumeration.
So you might reasonably wonder: if people care about performance, then why would
they willingly start off 3X "in the hole" in hopes that they will eventually
gain it back when they use machines with >= 4 cores?  It's a completely fair
criticism (although you must recall that everything I'm talking about is "pure
overhead" and once you begin to have sizable computations in the per-element action
it matters less and less).  We continually do a lot of work to try to recoup
these costs.

There are actually many alternative enumeration models, and I think .NET needs to
change direction in the future.  In addition to the overhead associated with
the pattern, .NET's enumeration pattern is a "pull" model (versus "push"),
which makes it incredibly hard to tolerate blocking within calls to MoveNext.
Over time, I think we will need to pursue the push model more seriously.

I've thrown together a few different examples of alternative enumeration techniques.
To cut to the chase, here is a simple micro-benchmark test that enumerates over 1,000,000
elements 25 times, invoking an empty (non-inlineable) method for each element.
The per-element work here is quite small (although not empty) and so the results
are a bit more extreme than a real workload would show:

```
For loop (int[])        739255 tcks     % of baseline
For loop (IList<int>)   7534609 tcks    1019.216%
ForEach loop (int[])    829617 tcks     112.2234%
int[] IEnumerator<int>  2152414 tcks    291.1599%
IEnumerator<int>        2062876 tcks    279.048%
IFastEnumerator<int>    1758992 tcks    237.9412%
IForEachable<int> [s]   1103745 tcks    149.305%
IForEachable<int> [i]   976742 tcks     132.1252%
IForEachable2<int>      957883 tcks     129.5741%
```

These are:

- "For loop (int[])" is an ordinary for loop over the array directly.

- "For loop (IList&lt;int&gt;)" is an ordinary for loop over the array's
IList&lt;T&gt; interface.

- "ForEach loop (int[])" is an ordinary foreach loop over the array directly.

- "int[] IEnumerator&lt;int&gt;" uses the array's implementation of IEnumerator&lt;T&gt;.

- "IEnumerator&lt;int&gt;" is a custom IEnumerator&lt;T&gt; implementation.

- "IFastEnumerator&lt;int&gt;" is an implementation of new pull interface (defined
below).

- "IForEachable&lt;int&gt;" is an implementation of a new push interface (defined below)
that uses delegates to represent the per-element action.  The only difference
between the "[s]" and "[i]" variants are that the delegate is bound to a
static method for "[s]" and an instance method for "[i]".

- "IForEachable2&lt;int&gt;" is a slight variant of IForEachable&lt;T&gt; (also defined below).

Notice that with IForEachable2&lt;T&gt;, we've gotten within 30% of the efficient for
loop.  Unfortunately, I do get somewhat different numbers when compiling with
the /o+ switch:

```
For loop (int[])        777746 tcks     % of baseline
For loop (IList<int>)   7569517 tcks    973.2634%
ForEach loop (int[])    735846 tcks     94.61264%
int[] IEnumerator<int>  2340361 tcks    300.9159%
IEnumerator<int>        2063039 tcks    265.2587%
IFastEnumerator<int>    1806568 tcks    232.2825%
IForEachable<int> [s]   1090644 tcks    140.2314%
IForEachable<int> [i]   946090 tcks     121.6451%
IForEachable2<int>      1234201 tcks    158.6895%
```

For comparison purposes, I get numbers like this if the loop body is completely empty
except for accessing the current element:

```
For loop (int[])        452039 tcks     % of baseline
For loop (IList<int>)   422732 tcks     93.51671%
ForEach loop (int[])    461274 tcks     102.043%
int[] IEnumerator<int>  1958711 tcks    433.3058%
IEnumerator<int>        1730502 tcks    382.8214%
IFastEnumerator<int>    1372421 tcks    303.6068%
IForEachable<int> [s]   1091720 tcks    241.5101%
IForEachable<int> [i]   958401 tcks     212.0173%
IForEachable2<int>      664572 tcks     147.0165%
```

And this (with /o+):

```
For loop (int[])        262146 tcks     % of baseline
For loop (IList<int>)   263302 tcks     100.441%
ForEach loop (int[])    372924 tcks     142.2581%
int[] IEnumerator<int>  1889132 tcks    720.6412%
IEnumerator<int>        1635837 tcks    624.0175%
IFastEnumerator<int>    1479579 tcks    564.4103%
IForEachable<int> [s]   1096712 tcks    418.3592%
IForEachable<int> [i]   962261 tcks     367.0706%
IForEachable2<int>      698340 tcks     266.3935%
```

These numbers aren't quite as meaningful because we have no idea what's being
optimized away by the C# and JIT compilers.  For example, they may notice we're
not using the current element at all and therefore eliminate the access altogether.
Nevertheless, the relative ranking of efficiency has remained nearly the same (with
the notable exception of the array's IList&lt;T&gt; test being much less worse).

(All of these numbers were gathered on a 32-bit OS on a 64-bit machine.  Because
the JIT compilers for 32-bit and 64-bit are so different, you can expect vastly different
results across architectures.)

Anyway, here is what IFastEnumerator&lt;T&gt;, IForEachable&lt;T&gt;, and
IForEachable2&lt;T&gt; look like:

```
interface IFastEnumerable<T>
{
    IFastEnumerator<T> GetEnumerator();
}

interface IFastEnumerator<T>
{
    bool MoveNext(ref T elem);
}

interface IForEachable<T>
{
    void ForEach(Action<T> action);
}

interface IForEachable2<T>
{
    void ForEach(Functor<T> functor);
}

abstract class Functor<T>
{
    public abstract void Invoke(T t);
}
```

I also have a data type called SimpleList&lt;T&gt; that implements each of these, including
IEnumerable&lt;T&gt;.  This is what the test harness uses for its benchmarking.
So any boneheaded mistakes I've made in the implementation of this class could
cause us to draw the wrong conclusions about the interfaces themselves.  Hopefully
there are none:

```
class SimpleList<T> :
    IEnumerable<T>, IFastEnumerable<T>, IForEachable<T>, IForEachable2<T>
{
    private T[] m_array;

    public SimpleList(T[] array) { m_array = array; }

    // Etc ...
}
```

The class of course implements IEnumerable&lt;T&gt; in the standard way:

```
IEnumerator<T> IEnumerable<T>.GetEnumerator()
{
    return new ClassicEnumerable(m_array);
}

System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()
{
    return new ClassicEnumerable(m_array);
}

class ClassicEnumerable : IEnumerator<T>
{
    private T[] m_a;
    private int m_index = -1;

    internal ClassicEnumerable(T[] a) { m_a = a; }

    public bool MoveNext() { return ++m_index < m_a.Length; }
    public T Current { get { return m_a[m_index]; } }
    object System.Collections.IEnumerator.Current { get { return Current; } }
    public void Reset() { m_index = -1; }
    public void Dispose() { }
}
```

The idea behind IFastEnumerable&lt;T&gt; (and specifically IFastEnumerator&lt;T&gt;) is to return
the current element during the call to MoveNext itself.  This cuts the number
of interface method calls necessary to enumerate a list in half.  The impact
to performance isn't huge, but it was enough to cut our overhead from about 3X
to 2.3X.  Every little bit counts:

```
IFastEnumerator<T> IFastEnumerable<T>.GetEnumerator()
{
    return new FastEnumerable(m_array);
}

class FastEnumerable : IFastEnumerator<T>
{
    private T[] m_a;
    private int m_index = -1;

    internal FastEnumerable(T[] a) { m_a = a; }

    public bool MoveNext(ref T elem)
    {
        if (++m_index >= m_a.Length)
            return false;
        elem = m_a[m_index];
        return true;
    }
}
```

The IForEachable&lt;T&gt; interface is a push model in the sense that the caller provides
a delegate and the ForEach method is responsible for invoking it once per element
in the collection.  ForEach doesn't return until this is done.  In addition
to having far fewer method calls to enumerate a collection, there isn't a single
interface method call.  Delegate dispatch is also much faster than interface
method dispatch.  The result is nearly twice as fast as the classic IEnumerator&lt;T&gt;
pattern (when /o+ isn't defined).  Now we're really getting somewhere!

```
void IForEachable<T>.ForEach(Action<T> action)
{
    T[] a = m_array;
    for (int i = 0, c = a.Length; i < c; i++)
        action(a[i]);
}
```

Delegate dispatch still isn't quite the speed of virtual method dispatch.
And delegates bound to static methods are actually slightly slower than those bound
to instance methods, which is why you'll notice a slight difference in the original
"[s]" versus "[i]" measurements.  The reason is subtle.  There
is a delegate dispatch stub that is meant to call the target method: when the delegate
refers to an instance method, the 'this' reference pushed in EAX points to the
delegate object when it is invoked and the stub can simply replace it with the target
object and jump; for static methods, however, all of the arguments need to be "shifted"
downward, because there is no 'this' reference to be passed and therefore the
first actual argument to the static method must take the place of the current value
in EAX.

The IForEachable2&lt;T&gt; interface just replaces delegate calls with virtual method calls.
Somebody calling it will pass an instance of the Functor&lt;T&gt; class with the Invoke
method overridden.  The implementation of ForEach then looks quite a bit like
IForEachable&lt;T&gt;'s, just with virtual method calls in place of delegate calls:

```
void IForEachable2<T>.ForEach(Functor<T> functor)
{
    T[] a = m_array;
    for (int i = 0, c = a.Length; i < c; i++)
        functor.Invoke(a[i]);
}
```

And that's it.

To summarize, .NET enumeration costs something over typical for loops that index
straight into arrays.  Most programs needn't worry about these kinds of overheads.
If you're accessing a database, manipulating a large complicated object, or what
have you, inside of the individual iterations, then the overheads we're talking
about here are miniscule.  In fact, walking 1,000,000 elements is in the microsecond
range for all of the benchmarks I showed, even the slowest ones.  So none of
this is anything to lose sleep over.  But if you have a closed system that controls
all of its enumeration, it may be worth doing some targeted replacement of enumerators
with the more efficient patterns, particularly if you tend to enumerate lots and
lots of elements lots and lots of times in your program.

