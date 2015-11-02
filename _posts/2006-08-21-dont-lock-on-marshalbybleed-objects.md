---
layout: post
title: Don't lock on marshal-by-bleed objects
date: 2006-08-21 20:50:14.000000000 -07:00
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
_[**Update** - 8/22/06 - fixed typos and paid homage to VSTS 2005's code analysis
which checks for this problem.]_

From the department of [Spolsky's Law of Leaky Abstractions](http://www.joelonsoftware.com/articles/LeakyAbstractions.html),
we turn today to accidental lock conflicts across AppDomain boundaries.

The CLR supports various cross-AppDomain marshaling mechanisms, one of which is known
by the lovely name of [marshal-by-bleed](http://www.bluebytesoftware.com/blog/'http://blogs.msdn.com/cbrumme/archive/2003/06/01/51466.aspx).
This simply means that pointers from multiple AppDomains actually refer to the same
location in memory. Most of the time some form of marshaling is required for objects
so that we can safely isolate separate AppDomains from one another.

In managed code, you can lock on any object through the Monitor type, exposed in
C# and VB via the 'lock' and 'SyncLock' keywords, respectively. The implementation of
Monitor.Enter/Exit uses space in the object header and/or the object's sync-block
to record exclusive ownership of the lock. The fact that objects typically don't
bleed across AppDomains is a GoodThing(tm), as this is how add-ins, SQL Server, and
other hosts isolate failures between components. When writing code, we typically
assume state in one AppDomain can't corrupt state in another, totally independent,
AppDomain.

Unfortunately, domain neutral Type objects (as well as other Reflection types, e.g.
XXInfos) are actually shared across all AppDomains in the process. They are marshal-by-bleed. Strings
also fall into this camp. A string argument to a remoted MarshalByRefObject
method invocation may be bled, as can be any process-wide interned string literal.
The System.Threading.Thread object (called the thread-base-object, aka TBO, internally)
also bleeds across AppDomains. What a bloody mess! (Ha ha.)

So why does this all matter?!

Recall that lock owner information is tied to the instance. If you use any of these
things as a target of Monitor.Enter, code running in one AppDomain can actually interfere
with code in another AppDomain. That's because they are using the same object
and thus the same lock information underneath. What a lousy abstraction--this was
never meant to leak through! And it can cause trouble too. If one AppDomain
orphans the lock (forgets to release it), it may cause deadlocks in other AppDomains.
Even sans deadlocks, this fact can simply yield false conflicts, which can
subsequently negatively impact scalability.

For example, consider this code:

```
lock (typeof(object)) {
    ...
}
```

Code in AppDomain A uses the same Type object to represent 'typeof(object)' as code
in AppDomain B. Therefore they share lock information.

If we run such code from multiple AppDomains, the code yields a conflict:

```
WaitHandle wh = new ManualResetEvent("XXX", false);
lock (typeof(object)) {
    AppDomain ad2 = AppDomain.CreateDomain("2");
    ad2.DoCallBack(delegate {
        ThreadPool.QueueUserWorkItem(delegate {
            WaitHandle wh2 = new ManualResetEvent("XXX", false);
            lock (typeof(object)) {
                wh2.Set();
            }
        });
    });
    wh.WaitOne();
}
```

If one AppDomain is waiting for a synchronization event from another--as in this
example--this can actually yield a deadlock. If you replaced the lock statements
in this example with, say, lock ("Foo") { ... }, you'll see the same result due to
string literal interning.

Clearly this is nasty problem, especially if Framework code were to use such patterns.
This is one reason you'll notice we strongly discourage locking on Type objects.
Even if you're not in mscorlib (by default the only domain neutral assembly), your
type can be loaded domain neutral based on hosting policy, among other things. And
therefore you may not even catch said bugs during testing.

Note that MarshalByRefObjects aren't subject to these problems. Although operations
in one AppDomain can refer to the same instance in another, these accesses go through
a proxy. Locking on the proxy is different than locking on the raw underlying object,
and thus no false conflicts.

This is enforced with the [DoNotLockOnObjectsWithWeakIdentity VSTS 2005 code analysis
rule](http://msdn2.microsoft.com/en-us/library/ms182290.aspx).

If all of this is making you feel rather queasy, fear not. We have a weekly "CLR
Foundations" meeting where a large portion of the CLR Team meets to discuss the history
of the CLR and .NET Framework. A couple weeks back this topic came up in passing.
Most people on the team were quite surprised, and many even seemed to be enshrouded
in disbelief. At least we can recognize a mistake _after_ it's been made. ;)

