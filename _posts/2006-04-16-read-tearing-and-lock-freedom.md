---
layout: post
title: Read tearing and lock freedom
date: 2006-04-16 18:32:52.000000000 -07:00
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
[I wrote about torn reads
previously](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c40a187f-4eeb-43c9-8532-35d480abd1e1),
in which, because loads from and stores to > 32-bit data types are not actually
"atomic" on a 32-bit CPU, obscure magic values are seen in the program from
time to time. This isn't as scary as ["out of thin air"
values](http://www.cs.umd.edu/users/jmanson/java/journal.pdf), but can be
troublesome nonetheless. I noted that, [by using a
lock](http://msdn.microsoft.com/msdnmag/issues/05/08/Concurrency/default.aspx),
you can serialize access to the location to ensure safety.

You can of course write such thread-safe code that avoids taking a lock,
usually motivated by performance. [Vance](http://blogs.msdn.com/vancem/) has [a
pretty detailed write-up of this on
MSDN](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels/default.aspx).
Most of the time, you shouldn't try to be so clever, as it will get you in
trouble sooner or later, and is even worse to debug than a typical race. But
for really hot code-paths, it can make a measurable difference. (Note the key
word: _measurable_. If you've measured a problem, you might consider such
techniques... but otherwise, stay far, far away. (Have I made enough
qualifications and disclaimers yet?))

If you access individual pointer-sized byte segments of the data structure,
such as 32-bit aligned segments (e.g. `volatile` or `__declspec(align(x))`
in VC++, all values on the CLR), you can load and store in a known order.
Furthermore, you need to use the appropriate types of loads and stores with
fences in the appropriate places; load/acquire and store/release are usually
adequate. You can then use the intrinsic properties of this order to make
statements about the correctness of your algorithm.

For example, imagine you have some code that increments a 64-bit counter on a
32-bit system. Aside from overflow, the value always increases. If you always
increment the low 32-bits, followed by the high, and if you always read the
high, followed by the low, you'll be guaranteed that, should you read a torn
value, it will be too low rather than too high (not counting for overflow, of
course). Sometimes it can be _really_ low, such as when the low 32-bits wrap
back to 0, in which case the higher 32-bit increment needs to carry one.
Depending on your situation, this might be precisely what you are looking for.
(I wrote some code last week that needed exactly this.)

For example, your typical code might read and write under a lock, in
VC++/Win32:

    ULONGLONG ReadCounter_Lock(volatile ULONGLONG * pTarget, CRITICAL_SECTION * pCs)
    { 
      ULONGLONG val;

      EnterCriticalSection(pCs);
      val = *pTarget;
      LeaveCriticalSection(pCs);

      return val;
    }

    ULONGLONG IncrCounter_Lock(volatile ULONGLONG * pTarget, CRITICAL_SECTION * pCs)
    {
      ULONGLONG val;

      EnterCriticalSection(pCs);
      val = *pTarget;
      *pTarget = val + 1;
      LeaveCriticalSection(pCs);

      return val;
    }

But, using the load/store order described above, it can become lock free:

    #define LO_LONG(x) (reinterpret_cast<volatile LONG *>((x)))
    #define HI_LONG(x) (reinterpret_cast<volatile LONG *>((x)) + 1)

    ULONGLONG ReadCounter_NoLock(volatile ULONGLONG * pTarget)
    {
      ULONGLONG val;

    #ifdef _Win64
      val = *pTarget;
    #else
      // Read high 32-bits first, then low:
      *HI_LONG(&val) = *HI_LONG(pTarget);
      *LO_LONG(&val) = *LO_LONG(pTarget);
    #endif

      return val;
    }

    ULONGLONG IncrCounter_NoLock(volatile ULONGLONG * pTarget)
    {
      ULONGLONG oldVal;

    #ifdef _Win64
      oldVal = static_cast<LONGLONG>(
        InterlockedIncrement64(static_cast<LONGLONG *>(pTarget)));
    #else
      // Increment the low 32-bits first, then high:
      if ((*LO_LONG(&oldVal) = InterlockedIncrement(LO_LONG(pTarget))) == 0)
      {
        *HI_LONG(&oldVal) = InterlockedIncrement(HI_LONG(pTarget));
      }
      else
      {
        *HI_LONG(&oldVal) = *HI_LONG(pTarget);
      }
    #endif

      return oldVal;
    }

It's obvious which is simpler to code, understand, and maintain. But the latter
technique can come in handy when you're in a pinch.

For information on other similar techniques, including multi-word CAS and
object-based STM, [Tim Harris](http://research.microsoft.com/~tharris/)'s
recent ["Concurrent programming with locks"
paper](http://research.microsoft.com/~tharris/drafts/cpwl-submission.pdf) is an
excellent read. Most of it isn't built and ready for you to use today, but the
details of the algorithms are in there if you'd like to play around a little.
And there's a lot of literature out there about creating lock-free data
structures. Interestingly, you can end up worse off than if you'd used a lock
in the first place. Many such lock free algorithms are _optimistic_ meaning
that they do a bunch of work hoping not to run into contention; when they do,
they have to throw away work, rinse, and repeat. Your mileage can vary
dramatically based on workload.

