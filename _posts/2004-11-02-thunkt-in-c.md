---
layout: post
title: Thunk in C#
date: 2004-11-02 01:54:02.000000000 -07:00
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
A thunk is a relatively common construct in functional programming where the
passing of arguments won't result in any side effects. In these cases, the
compiler can silently emit code that bypasses computing the value of an
argument altogether at the call site in case it isn't used in a method body at
all. If it does end up being used, however, it will be lazily evaluated at the
last possible moment. This is sometimes referred to as call-by-lazy-evaluation.
It is said that the argument passed is _frozen_ at the time of invocation, and
_thawed_ when it is needed. Further references typically avoid re-thawing once
the initial thaw has ocurred.

It might sound odd that an argument would be passed in to a method but not used
at all. But depending on the code paths a method takes, it could end up not
needing to reference it at all. Consider the simplest case: where a caller
spends time retrieving results from a database to construct some fancy input,
but then the call fails before the target method even has a chance to inspect
this data, possibly because one of the other arguments was in an invalid format
or out of the valid range. It's terribly inefficient that the client had to
compute this in the first place!

Just playing around, I've thrown together a Thunk<T> class. It's nothing
special, but it seems to work rather nicely with C#'s new anonymous delegate
syntax.

public class Thunk<T>

{

    private T value;

    private ThawFunction thaw;

    private bool thawed;

    public delegate T ThawFunction();

    public Thunk(ThawFunction thaw)

    {

        this.thaw = thaw;

    }

    public T Value

    {

        get

        {

            if (IsFrozen)

            {

                this.value = thaw();

                thawed = true;

            }

            return this.value;

        }

    }

    public bool IsFrozen

    {

        get { return !thawed; }

    }

}

As an example of its usage, consider this test class:

public class ThunkExample

{

    public static void Main(string[] args)

    {

        ThunkExample ex = new ThunkExample();

        string longText = "Pretend this is some long text that is expensive to
split.";

        ex.WithThunk(longText);

        ex.WithoutThunk(longText);

    }

    public void WithThunk(string longText)

    {

        WithThunkDoWork(longText.Length, new Thunk<string[]>(delegate { return
longText.Split(' '); }));

    }

    public void WithThunkDoWork(int strlen, Thunk<string[]> words)

    {

        if (strlen > 2048)

            throw new ArgumentOutOfRangeException("strlen", "Must be <= 2048");

        Console.WriteLine("-- WithThunk --");

        foreach (string w in words.Value)

            Console.WriteLine(w);

    }

    public void WithoutThunk(string longText)

    {

        WithoutThunkDoWork(longText.Length, longText.Split(' '));

    }

    public void WithoutThunkDoWork(int strlen, string[] words)

    {

        if (strlen > 2048)

            throw new ArgumentOutOfRangeException("strlen", "Must be <= 2048");

        Console.WriteLine("-- WithoutThunk --");

        foreach (string w in words)

            Console.WriteLine(w);

    }

}

If you take a look at the IL for the WithThunk vs. WithoutThunk method, you'll
see a fundamental difference. Specifically, WithoutThunk computes a bunch of
local values, and leaves them on the stack for the following call to the
WithoutThunkDoWork(...) method.

  IL\_0009:  newarr     [mscorlib]System.Char IL\_000e:  stloc.0 IL\_000f:
ldloc.0 IL\_0010:  ldc.i4.0 IL\_0011:  ldc.i4.s   32 IL\_0013:  stelem.i2
IL\_0014:  ldloc.0 IL\_0015:  callvirt   instance string[]
[mscorlib]System.String::Split(char[])

So the difference is that WithoutThunk evaluates the string[] argument at the
call site, while WithThunk delays calculation to its first use in the \*DoWork
methods. If the data is not used at all, it doesn't get calculated. Obviously
this is a contrived example, but if the delayed operation was expensive -- e.g.
as in the database example cited above -- this could have tangible benefits at
runtime.

A couple things would make this construct nicer sans first class CLR support.
Consider if C# had mixins, for example. Thunk<T> could then derive from T, and
some compiler generated code could implement simple wrapper methods that
forwarded any calls to its value field. Of course this would only work if all
methods were virtual, but it's a start. We could then pass thunks around
pretending they were instances of a given type, and (in theory, at least)
existing code would work with them just fine. Alternatively, overloading
assignment and dereferencing operators might be nice, too. This would allow one
to assign to and dereference a thunk as though it were just an instance of the
type it wrapped. Similar to the Nullable<T> type, rarely does one actually want
to access and use it as a typical object.

Lastly, a few caveats. All of this assumes that the performance hit resulting
from late bound delegate calls is acceptable in your scenario. If you're
wrapping an operation that has side effects, this is not a good idea for
obvious reasons. (How cool would it be if C# hasd restrictions on
side-effects?)

