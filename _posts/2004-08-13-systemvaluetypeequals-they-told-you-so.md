---
layout: post
title: System.ValueType.Equals... they told you so...
date: 2004-08-13 22:02:36.000000000 -07:00
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
[Those perf architects](http://blogs.msdn.com/ricom/) are usually right. For
instance, when they
[recommend](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dnpag/html/scalenetchapt05.asp)
that you provide an explicit override implementation of the Equals(object)
method for your value types, it's a good idea to listen. Unless you intend to
never compare your instances for memberwise equivallence, that is.

In fact, not heeding this particular advice causes your value types to fall
back to the System.ValueType implementation of Equals(). ValueType.Equals()
takes an object parameter, causing value types to box as they're handed off to
this method, and also uses reflection to determine memberwise equivallence.
Needless to say, it's not overly performant for uses within loops, or other
code with high performance requirements.

Specifically, the core of this implementation looks something like this (see
[here](http://www.dotnet247.com/247reference/System/ValueType/__rotor) for the
full Rotor implementation):

    public override bool Equals(Object obj) {
      // ...
      FieldInfo[] thisFields = thisType.InternalGetFields(BindingFlags.Instance |
        BindingFlags.Public | BindingFlags.NonPublic, false);

      for (int i = 0; i < thisFields.Length; i++) {
        thisResult = ((RuntimeFieldInfo)thisFields[i]).InternalGetValue(thisObj, false);
        thatResult = ((RuntimeFieldInfo)thisFields[i]).InternalGetValue(obj, false);

        if (thisResult == null) {
          if (thatResult != null)
            return false;
        }
        else if (!thisResult.Equals(thatResult)) {
          return  false;
        }
      }

      return true;
    }

I wrote a test harness (full code available
[here](http://www.bluebytesoftware.com/code/04/08/13/TestVtEquals.txt)) to test
out the performance impact that this has. As with most hack perf harnesses, the
exact results should be taken with a huge rock of salt. However, the deltas are
significant enough that I felt compelled to post this entry.

My value type looks like this:

    struct ValueTypeA
    {
      private string a;
      public string A
      {
        get { return a; }
        set { a = value ; }
      }

      private DateTime b;
      public DateTime B
      {
        get { return b; }
        set { b = value; }
      }

      private int c;
      public int C
      {
        get { return c; }
        set { c = value; }
      }
    }

...And my main loop looks like this:

    [MethodImpl(MethodImplOptions.NoInlining)]
    void DoDefaultEquals(Array a)
    {
      ValueTypeA[] aa = (ValueTypeA[])a;

      for (int i = 1; i < aa.Length; i++)
        for (int j = 0; j < i; j++)
          aa[i].Equals(aa[j]);
    }

Admittedly, this is a very contrived, comparison-intensive example.
Nonetheless, let's consider the default implementation as our baseline, that is
1.0 or 100%; the other numbers will be scaled appropriately to make comparing
results less arbitrary (e.g. scenario 1 took 37,151 milliseconds to run, etc.).

So, what if we explicitly override Equals(object) in our value type?

    public override bool Equals(object o)
    {
      if (o is ValueTypeA)
      {
        ValueTypeA v = (ValueTypeA)o;

        return A == v.A && B == v.B && C == v.C;
      }
      else
      {
        return false;
      }
    }

This actually comes in way under the default implementation. In fact, on my
computer it took on average about 10.5% (0.105) of the time the original
scenario took to execute! Pretty darn good!

But we can still improve slightly, as the above implementation requires the
value types are boxed before being passed to the implementation.

    public override bool Equals(object o)
    {
      if (o is ValueTypeA)
        return Equals((ValueTypeA)o);
      else
        return false;
    }

    public bool Equals(ValueTypeA v)
    {
      return A == v.A && B == v.B && C == v.C;
    }

This one comes in at 6.5% (0.065) of the original implementation's execution
time.

So just for summary, these are the comparative results I got on my machine:

> Default ValueType.Equals(): 100% Equals() Override (w/ boxing): 10.5%
> Equals() Override (w/out boxing): 6.5%

For yucks, I tried a loop which used Array.IndexOf() to look up value types
stored in an array.

    [MethodImpl(MethodImplOptions.NoInlining)]
    void DoFind(Array a)
    {
      for (int j = 0; j < 100; j++)
      {
        ValueTypeA[] aa = (ValueTypeA[])a;

        for (int i = 0; i < aa.Length; i++)
          Array.IndexOf(aa, aa[i]);
      }
    }

I received similar results:

> Default ValueType.Equals(): 100% Equals() Override (w/ boxing): 28.5%
> Equals() Override (w/out boxing): 27%

These difference in performance here is fairly substantial. The take away is
not specific figures, but rather that overall a custom implementation of Equals
makes sense if you expect your value types to be compared for equivallence.

Truthfully, I'm surprised that the C# compiler doesn't optimize for this. One
could imagine the compiler detecting the absence of an Equals override,
triggering an injection of a simple, brainless memberwise comparison. I'm sure
there are plenty of reasons not to do this (e.g., adding stuff that'd bloat the
metadata... stuff that might not even be required), but this is painful,
boilerplate code that complicates the maintenance of value types. Sufficient
justification to me.

