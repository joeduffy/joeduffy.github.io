---
layout: post
title: Thread-safety, torn reads, and the like
date: 2006-02-07 22:33:13.000000000 -08:00
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
I was on a mail thread today, the topic for which was the meaning—and perhaps
lack of comprehensiveness—of the statement: "This type is thread safe."
Similar statements are scattered throughout our product documentation, without
any good central explanation of its meaning and any caveats.

It's relatively difficult to make such a statement. The .NET Framework is
generally written so that all static members are thread-safe, while instance
members are not. There are some notable exceptions, mostly to do with immutable
types (e.g. the primitives, System.DateTime, System.Type, etc.), but they are
infrequent.

This brings me to the types of thread safety issues we're generally concerned
with.

The first problem is torn reads and writes. Operations that deal with data
whose size is greater than the native machine-sized pointer (i.e.
sizeof(void\*)) are not atomic in the ISA. This applies to 64-bit operations on
32-bit platforms, 128-bit on 64-bit, etc. We happen to provide you two
intrinsic 64-bit types—Int64 (C# long) and Double (C# double)—which makes
this issue a tad tricky. So this code

> static long x; // … x = 1111222233334444;

consists of two DWORD MOVs at the machine level, one to the most significant
half and then the least significant half (in that order, at least in the
Whidbey x86 JIT). Reads likewise involve two MOV instructions.

If you're doing naked reads and writes with such values, instructions can be
interleaved such that only one DWORD has been written. That means a thread
racing with the above assignment can see x with a value of (x &
0xFFFFFFFF00000000), or 2524709548 in decimal. This is obviously surprising, as
the two values (at first glance) don't seem to be related. And this same
principle applies to reads and writes of any value type instances whose size is
greater than sizeof(void\*).

This can be solved by protecting all access to the data under a lock or via an
interlocked operation. Interlocked.Exchange will do the trick for writes, and
Interlocked.Read for reads. Note that most platforms offer 128-bit interlocked
instructions. Unfortunately, because of the platform-specificity, the Win32
APIs and our System.Threading APIs don't broadly support them. Hopefully this
changes over time. For the same reason you often need two void\*-sized writes
on 32-bit, you often need the same on 64-bit.

In summary, any type that exposes a writable 64-bit field, or which returns a
64-bit value which has been copied by a field that might be in motion, is not
thread-safe. And any internal reads and writes need to be done under the
protection of a lock or interlocked operation. A method that updates an
internal field, for example, can race with a property that returns the current
value.

The second problem is read/modify/write sets of instructions. If reads and
writes can be multiple instructions long, it should be clear that by default a
read/modify/write is at least three. For a 64-bit value on a 32-bit platform,
it's six. At any point in that invocation, interleaved execution can cause an
update to go missing. The solution here, again, is to do this inside a lock.
The Interlocked.CompareExchange function is great for this purpose, as it takes
advantage of hardware-level read/modify/write instructions. Thankfully they are
supported by all modern hardware ISAs.

The last problem is that of ensuring coarser-grained data structure invariants
can never be seen in a broken state by concurrent execution. This is especially
difficult since arbitrary managed programs don't capture such invariants in the
program itself. Aside from static state, most Framework types don't even come
close to attempting to provide this level of guarantee. Static caches and
lazily initialized state, for example, are places where the Framework needs to
account for concurrent access. Old-style collections with SyncRoots tried to
provide similar protection, but the new generic collections don't any longer,
mostly because of the performance hit you take on sequential code-paths. But
those cases are the exception, not the norm.

The immutable types mentioned above are nice in that, aside from
initialization-time, they never break their internal invariants. Thus, aside
from assignments of instances to shared variables, you needn't worry about any
special synchronization.

In summary, any type that breaks invariants must do so in such a way that these
invariants can never be observed due to concurrent execution. This means all
access to data needs to be serialized with respect to coarser grained
operations updating state. Our Framework isn't written in this way, so if you
share it, you usually take responsibility for locking it.

My preference is for developers to assume that all types are unsafe, and to
explicitly lock when accessing them concurrently. Regardless of the
documentation's claims. We simply do not check for these things across
releases, and some code that works today might break tomorrow because we
accidentally forgot to account for a torn read.

