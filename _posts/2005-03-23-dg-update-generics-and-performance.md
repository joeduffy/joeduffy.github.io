---
layout: post
title: 'DG Update: Generics and Performance'
date: 2005-03-23 12:23:30.000000000 -07:00
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
This can probably fall into the "paranoid programmer" category... where this
time the paranoia is not about async exceptions, but rather about pulling in
the JIT unnecessarily.

Back in September, we did a fair amount of work documenting and getting FxCop
rules in place to check when the use of generics can cause an NGen'd assembly
to JIT. This was mostly in response to our general no-JIT plan that most
managed code we ship is on. In particular, Avalon drove us hard to come up with
this.

Joel has a great entry about code sharing vis-a-vis generics [over on his
blog](http://blogs.msdn.com/joelpob/archive/2004/11/17/259224.aspx). I'd read
that alongside this.

(BTW, in re-reading my DG update entry before posting, I think there's some
significant clarification and re-work that we could/should do. Add it to the
growing stack of things to do! :))

**Generics and Performance

**

- Do consider the performance ramifications of generics. Specific
  recommendations arise from these considerations and are described in
guidelines that follow.

**Execution Time Considerations

**

- Generic collections over value types (e.g. List<int>) tend to be faster than
  equivalent collections of Object (e.g. ArrayList) because they avoid boxing
items.

- Generic collections over all types also tend to be faster because they do not
  incur a checked cast to obtain items from the collection.

- The static fields of a generic type are replicated, unshared, for each
  constructed type. The class constructor of a generic type is called for each
constructed type. For example,

public class Counted<T>

{

    public static int count;

    public T t;

    static Counted()

    {

        count = 0;

    }

    Counted(T t)

    {

        this.t = t;

        ++count;

    }

}

Each constructed type Counted<int>, Counted<string>, etc. has its own copy of
the static field, and the static class constructor is called once for each
constructed type. These static member costs can quietly add up. Also, accesses
to static fields of generic types may be slower than accesses to static fields
of ordinary types.

- Generic methods, being generic, do not enjoy certain JIT compiler
  optimizations, but this is of little concern for all but the most performance
critical code. For example, the optimization that a cast from a derived type to
a base type need not be checked is not applied when one of the types is a
generic parameter type.

**Code Size Considerations

**

- The CLR shares IL, metadata, and some JIT'd/NGEN'd native code across
  types/methods constructed from generic types/methods. Thus the space cost of
each constructed type is modest, less than that of an empty conventional
non-generic type. But see also 'current limitations' below.

- When a generic type references other generic types, then each of its
  constructed types constructs its transitively referenced generic types. For
example, List<T> references IEnumerable<T>, so use of List<string> also incurs
the modest cost of constructing type IEnumerable<string>.

**Current Code Sharing Limitations

**

In the current CLR implementation, native code method sharing for disparate
generic type combinations occurs only for types constructed over reference type
parameters (e.g., List<object>, List<string>, List<MyReferenceType>). Each type
constructed over value type parameters (e.g., List<int>, List<MyStruct>,
List<MyEnum>) will incur a separate copy of the native code for the methods in
those constructed types. For comparison purposes, this is similar to the
runtime cost of creating your own strongly typed collection class.

A consequence of this is that using a generic type defined in mscorlib in
combination with value type parameters also from mscorlib could cause an NGen
image to invoke the JIT during execution, resulting in a negative effect on
performance. This is limited to mscorlib because it is the only assembly always
loaded domain-neutral, and for a variety of reasons there are limitations on
code sharing when working with domain-neutral assemblies. (Note:
domain-neutrality is a load time decision, so it is possible that this would
affect other assemblies, too.) For generic types that take a single type
parameter, for example, t is relatively straightforward to determine whether
this will affect your scenario: When instantiating G<VT>, where generic type G
and value type parameter VT are both defined in mscorlib, you will JIT unless
G<VT> is found in the following list:

ArraySegment<Byte>

Nullable<Boolean>

Nullable<Byte>

Nullable<Char>

Nullable<DateTime>

Nullable<Decimal>

Nullable<Double>

Nullable<Guid>

Nullable<Int16>

Nullable<Int32>

Nullable<Int64>

Nullable<Single>

Nullable<TimeSpan>

List<Boolean>

List<Byte>

List<DateTime>

List<Decimal>

List<Double>

List<Guid>

List<Int16>

List<Int32>

List<Int64>

List<SByte>

List<Single>

List<TimeSpan>

List<UInt16>

List<UInt32>

List<UInt64>

This is so because we have added some code to bake the data structures for
these generic instantiations into mscorlib. Because it affects the working set
of mscorlib, we couldn't do it for every possible combination. For generic type
instantiations that take multiple type parameters, the rules are more complex:
Roughly, when instantiating G<T1…Tn>, where generic type G and each T in
T1…Tn are defined in mscorlib, at least one of which is a value type, you
will JIT unless G<T1…Tn> is found in the following list (note: substitute
Object for any reference type parameter):

Dictionary<Char, Object>

Dictionary<Int16, IntPtr>

Dictionary<Int32, Byte>

Dictionary<Int32, Int32>

Dictionary<Int32, Object>

Dictionary<IntPtr, Int16>

Dictionary<Object, Char>

Dictionary<Object, Guid>

Dictionary<Object, Int32>

KeyValuePair<Char, UInt16>

KeyValuePair<UInt16, Double>

Please notice that JIT will neither occur when using a custom generic type with
mscorlib type arguments (e.g. MyType<int>), nor when using an mscorlib type
with your own type arguments (e.g. List<MyStruct>).

What is described above is actually the worst case scenario. There are some
subtleties that could result in a more relaxed application of these rules.
Unless the coverage above has caused you to worry whether you might be
affected, it's probably safe to skip this section. A more comprehensive
explanation of these subtle variables follows:

**_Annotation (RicoM):

_**

Let A be an assembly, G a generic type on n parameters, T1…Tn

A generic type G<T1,…,Tn> shares code with type H<S1,…,Sn> if and only if

- G = H and,

- for all i in [1..n] either

- Ti = Si, or,

- Ti shares code with Si, or,

- both Ti and Si are reference types.

------

Assume that A has been NGen'd, then:

If G is defined in A

- A may use G<T1…Tn> with no restrictions on T1…Tn, no JITting is required,

- A will include G<Object,…,Object> even if it is not otherwise mentioned

- The above two uses are present in A for other assemblies to use

(Remaining cases G not defined in A)

If all of T1…Tn are defined in A

- A may use G<T1…Tn> with no restrictions on T1…Tn, no JITting is required

- Any such G<T1…Tn> will be present in the NGen'd image of A for other
  assemblies to use

(Remaining case at least one of T1..Tn not defined in A)

If A depends on assembly B and B has a type that shares code with G<T1…Tn>

- A may use G<T1…Tn> as found in B, no JITting is required

- A will not contain code for G<T1…Tn>

(Remaining case, no match possible, this is the fallback position)

A copy of G<T1…Tn> will be emitted into the NGen'd code for A, this code is
available for other assemblies to use (subject to these same rules)

If A is loaded domain-specific and G, T1..Tn are all loaded from domain-neutral
assemblies then

- The CLR will be unable to use the copy in A and will JIT a new one

Otherwise

- The copy of the code in A is used and there is no JITting

These rules apply transitively to all generic instantiations encountered when
JITting the code for both the non-generic classes (which may contain generic
members), and generic classes (which may have generic members or parameters
themselves) and the "seed" <Object,…,Object> instantiations in the assembly.

In the future, more method sharing may be possible, but a high degree of code
sharing over different struct type parameters is unlikely or impossible.

**Summary

**

In summary, from the performance perspective, generics are a
sometimes-efficient facility that should be applied with great care and in
moderation. When you employ a new constructed type formed from a pre-existing
generic type, with a reference type parameter, the performance costs are modest
but not zero. The stakes are much higher when you introduce new generic types
and methods for use internal or external to your assembly. If used with value
type parameters, each method you define can be quietly replicated dozens of
times (when used across dozens of constructed types).

- Do use the pre-defined System.Collections.Generic types over reference types.
  Since the cost of each constructed type AGenericCollection<ReferenceType> is
modest, it is appropriate to employ such types in preference to defining new
strongly-typed-wrapper collection subtypes.

- Do use the pre-defined System.Collections.Generic types over value types in
  preference to defining a new custom collection type. As was the case with C++
templates, there is currently no sharing of the compiled methods of such
constructed types -- e.g. no sharing of the native code transitively compiled
for the methods of List<MyStruct> and List<YourStruct>. Only construct these
types when you are certain the savings in dynamic heap allocations of avoiding
boxing will pay for the replicated code space costs.

- Do use Nullable<T> and EventHandler<T> even over value types. We will work to
  make these two important generic types as efficient as possible.

- Do not introduce new generic types and methods without fully understanding,
  measuring, and documenting the performance ramifications of their expected
use.

