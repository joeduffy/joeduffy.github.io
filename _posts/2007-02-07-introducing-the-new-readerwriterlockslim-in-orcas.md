---
layout: post
title: Introducing the new ReaderWriterLockSlim in Orcas
date: 2007-02-07 11:47:19.000000000 -08:00
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
In Orcas, we offer a new reader/writer lock: System.Threading.ReaderWriterLockSlim.

**Motivation for a new lock**

The primary reason for creating this type was that we wanted to provide an official
reader/writer lock for the .NET Framework that people could actually rely on
for performance-critical code.  It was no secret that the current ReaderWriterLock
type was such a pig, costing somewhere around 6X the cost of a monitor acquisition
for uncontended write lock acquires, that most people avoided it entirely.
Jeff Richter [wrote an entire MSDN article](http://msdn.microsoft.com/msdnmag/issues/06/06/ConcurrentAffairs/)about
this, and [Vance Morrison showed how to build your own on his weblog](http://blogs.msdn.com/vancem/archive/2006/03/28/563180.aspx).
It was really too bad customers couldn't depend on the class in the Framework,
and to be honest most devs _really_ shouldn't be in the business of writing
and maintaining their own reader/writer lock.

Second, we had a large number of qualms with the existing lock's design.
It had funny recursion semantics (and is in fact broken in a few thread reentrancy
cases we know about), and has a dangerous non-atomic upgrade method.  Did you
know that you actually need to check the WriterSeqNum before and after a call to
our ReaderWriterLock's UpgradeToWriteLock method to ensure it didn't change during
the upgrade?  You do.  The code actually releases the reader lock before
upgrading to the write lock, which allows other threads to sneak in, acquire the
lock in between, and possibly change state that was read during the decision to upgrade.
The reason?  If we upgraded and then released the read lock, two threads
trying to simultaneously upgrade would deadlock one another.  All of these problems
represent very fundamental flaws in the existing type's design.

So we decided to build a new one that solves all of these problems.  To be honest,
I would have liked to fix the current one, but the existing API and compatibility
responsibilities make that just about impossible.  We considered obsoleting
the existing one, but as I note at the end of this article, there are still reasons
to prefer the old lock.

**Three modes: read, write, and upgradeable-read**

The new ReaderWriterLockSlim supports three lock modes: Read, Write, and UpgradeableRead,
and has the methods EnterReadLock, EnterWriteLock, EnterUpgradeableReadLock, and
corresponding TryEnterXXLock and ExitXXLock methods, that do what you'd expect.
Read and Write are easy and should be familiar: Read is a typical shared lock mode,
where any number of threads can acquire the lock in the Read mode simultaneously,
and Write is a mutual exclusion mode, where no other threads are permitted to simultaneously
hold the lock in any mode.  The UpgradeableReadLock will probably be new to
most people, though it's a concept that's well known to database folks, and is
the magic that allows us to fix the upgrade problem I mentioned earlier.  We'll
look at it more closely in a moment.

The performance of the new lock is roughly equal to that of Monitor.  When I
say "roughly", I mean that it's within a factor of 2X in just about all cases.
And the new lock favors letting threads acquire the lock in Write mode over Read
or UpgradeableRead, since writers tend to be less frequent than readers, generally
leading to better scalability.  We'd originally considered providing a set
of contention management options to choose from, but decided in the end to ship
a simpler design that works well for most cases.

**Upgrading**

Let's look at upgrades more closely now.  The UpgradeableRead mode allows
you to safely upgrade from Read to Write mode.  Remember I mentioned earlier
that our old lock breaks atomicity in order to provide deadlock-free upgrade capabilities
(which is bad, particularly since most people don't realize it).  The new lock
neither breaks atomicity nor causes deadlocks.  We acheive this by allowing
only one thread to be in the UpgradeableRead mode at once, though there may be any
number of other threads in Read mode while there's one UpgradeableRead owner.

Once the lock is held in the UpgradeableRead mode, a thread can then read state
to determine whether to downgrade to Read or upgrade to Write.  Note that this
decision should ideally be made as fast as possible: holding the UpgradeableRead
lock forces any new Read acquisitions to wait, though existing Read holders are still
permitted to remain active.  (Sadly the CLR team seems to have removed two methods,
DowngradeToRead and UpgradeToWrite, that I had originally designed for this purpose.
I admit what follows isn't the most obvious way to do it.)   To downgrade,
you simply call EnterReadLock followed by ExitUpgradeableReadLock: this permits other
Read and UpgradeableRead acquisitions to finish that were previously held up by the
fact that there was an UpgradeableRead lock held.  To upgrade, you similarly
call EnterWriteLock: this may actually have to wait until there are no longer any
threads that still hold the lock in Read mode.  There's no real reason to
also exit the UpgradeableReadLock at this point unlike the downgrade case, though
in some cases it makes your code more uniform.  E.g.:

```
ReaderWriterLockSlim rwl = ...;
...
bool upgraded = true;
rwl.EnterUpgradeableReadLock();
try {
    if (... read some state to decide whether to upgrade ...) {
        rwl.EnterWriteLock();
        try {
            ... write to state ...
        }
        finally {
            rwl.ExitWriteLock();
        }
    }
    else {
        rwl.EnterReadLock();
        rwl.ExitUpgradeableReadLock();
        upgraded = false;
        try {
            ... read from state ...
        } finally {
            rwl.ExitReadLock();
        }
    }
}
finally {
    if (upgraded)
        rwl.ExitUpgradeableReadLock();
}
```

**Recursive acquires**

Another nice feature with the new lock is how it treats recursion.  By default,
all recursive acquires, aside from the upgrade and downgrade cases already mentioned,
is disallowed.  This means you can't call EnterReadLock twice on the same
thread without first exiting the lock, for example, and similarly with the other
modes.  If you try, you get a LockRecursionException thrown at you.  You
can, however, turn recursion on at construction time: pass the enum value LockRecursionPolicy.SupportsRecursion
to your lock's constructor, and voila, recursion will be permitted.  The chosen
policy for a given lock is subsequently accessible from its RecursionPolicy property.

There's one special case that is never permitted, regardless of the lock recursion
policy: acquiring a Write lock when a Read lock is held.  We considered enabling
this, or at least giving a new enum value for it, but decided to hold off for now:
if it turns out customers need it, we can always add it later.  But it's dangerous
and leads to the same Read-to-Write upgrade deadlocks that the old lock was prone
to, and so we didn't want to lead developers down a path fraught with danger.
If you need this kind of recursion, it's a "simple" matter of changing your
design to hoist a call to either EnterWriteLock or EnterUpgradeableReadLock (and
the corresponding Exit method) to the outermost scope in which the lock is acquired.

There are corresponding properties IsReadLockHeld, IsWriteLockHeld, and IsUpgradeableReadLockHeld,
to determine whether the current thread holds the lock in the specified mode.
You can also query the WaitingReadCount, WaitingWriteCount, and WaitingUpgradeCount properties
to see how many threads are waiting to acquire the lock in the specific mode, and
CurrentReadCount to see how many concurrent readers there are.  The RecursiveReadCount,
RecursiveWriteCount, and RecursiveUpgradeCount properties tell you how many
recursive acquires the current thread has made for the specific mode.

**Some limitations: reliability**

Lastly, I mentioned there are some caveats around where this lock's use is appropriate.
Well, there's one, really: it's not hardened to be reliable.  This means
a few things.

First, unlike the existing ReaderWriterLock, the ReaderWriterLockSlim type does not
cooperate with CLR hosts through the hosting APIs.  This means a host will not
be given a chance to override various lock behaviors, including performing deadlock
detection (as SQL Server does).  Thus, you really ought not to use this lock
if your code will be run inside SQL Server.

Next, the lock is not robust to asynchronous exceptions such as thread aborts and
out of memory conditions.  If one of these occurs while in the middle of one
of the lock's methods, the lock state can be corrupt, causing subsequent deadlocks,
unhandled exceptions, and (sadly) due to the use of spin locks internally, a pegged
100% CPU.  So if you're going to be running your code in an environment that
regularly uses thread aborts or attempts to survive hard OOMs, you're not going
to be happy with this lock.  Unfortunately the lock doesn't even mark critical
regions appropriately, so hosts that do make use of thread aborts won't know that
the thread abort could possibly put the AppDomain at risk: many hosts would prefer
to wait, or immediately escalate to an AppDomain unload, if an individual thread
abort is necessary while the thread is in a critical region.  But in the case
of ReaderWriterLockSlim, a host has no idea if a thread holds the lock because the
implementation doesn't call Begin- and EndCriticalRegion.  And the kind of
problems [I mentioned in the previous post](http://www.bluebytesoftware.com/blog/PermaLink,guid,d9ff204a-a8a5-400e-bcbc-dedb90a7d11a.aspx)
are always an issue with ReaderWriterLockSlim, because we don't necessarily guarantee
that there will be no instructions in the JIT-generated code between the acquisition
and entrance to the following try block.

**Summary**

In summary, the new ReaderWriterLockSlim lock eliminates all of the major adoption
blockers that plagued the old ReaderWriterLock.  It performs much better, has
deadlock-free and atomicity-preserving upgrades, and leads developers to program
cleaner designs free of lock recursion.  There are some downsides to the new
lock, however, that may cause programmers writing hosted or low-level reliability-sensitive
code to wait to adopt it.  Don't get me wrong, most people really don't
need to worry about these topics, so I apologize if my words of warning have scared
you off: but those that do really need to be told about the state of affairs.
Thankfully, I'm confident that many of these issues will be fixed in subsequent
releases.  And for most developers out there, the new ReaderWriterLockSlim is
perfect for the job.

