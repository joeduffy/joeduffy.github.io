---
layout: post
title: The CLR commits the whole stack
date: 2007-03-09 16:43:10.000000000 -08:00
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
The CLR commits the entire reserved stack for managed threads.   This by
default is 1MB per thread, though [you can change the values with compiler settings,
a PE file editor, or by changing the way you create threads](http://www.bluebytesoftware.com/blog/PermaLink,guid,4c0e068c-f7d7-4979-86b1-688b5a29c115.aspx).
We've been having a fascinating internal discussion on the topic recently, and I've
been surprised how many people were unaware that the CLR engages in this practice.
I figure there's bound to be plenty of customers in the real world that are also
unaware.

**Let's see some pages**

This behavior can be seen quite easily by breaking into a debugger (like WinDbg)
and inspecting the status of the virtual memory pages comprising a thread's stack.
For example, from WinDbg the !teb command will show you the highest stack address
(StackBase) and !vadump will show you the status of all pages in the process's address
space.  From this you can see that the relevant stack pages are in the state
MEM\_COMMIT rather than MEM\_RESERVE.

Here's a quick example taken from a sample managed program.  I've broken right
inside the Main function and will dump [the TEB](http://www.bluebytesoftware.com/blog/PermaLink,guid,eb98baaf-0837-498d-a1e7-e4e16788f912.aspx):

```
0:000> !teb
TEB at 000007fffffde000
    ExceptionList:      0000000000000000
    StackBase:          0000000000190000
    StackLimit:         0000000000189000
    ...
```

Based on this information, combined with the fact that we know managed thread stacks
are 1MB by default, we can determine what memory addresses to look for: we subtract
100000 (1MB) from 190000 (StackBase) to arrive at the base address of the stack pages:
90000.  Now we dump the virtual memory pages:

```
0:000> !vadump
...
(1)
BaseAddress:       0000000000090000
RegionSize:        0000000000001000
State:             00002000  MEM_RESERVE
Type:              00020000  MEM_PRIVATE

(2)
BaseAddress:       0000000000091000
RegionSize:        00000000000f0000
State:             00001000  MEM_COMMIT
Protect:           00000004  PAGE_READWRITE
Type:              00020000  MEM_PRIVATE

(3)
BaseAddress:       0000000000181000
RegionSize:        0000000000001000
State:             00002000  MEM_RESERVE
Type:              00020000  MEM_PRIVATE

(4)
BaseAddress:       0000000000182000
RegionSize:        0000000000007000
State:             00001000  MEM_COMMIT
Protect:           00000104  PAGE_READWRITE + PAGE_GUARD
Type:              00020000  MEM_PRIVATE

(5)
BaseAddress:       0000000000189000
RegionSize:        0000000000007000
State:             00001000  MEM_COMMIT
Protect:           00000004  PAGE_READWRITE
Type:              00020000  MEM_PRIVATE
...
```

That summarizes the stack memory.  But what does it all mean?  I've labeled
the individual regions above with numbers so I can reference them.  And, remember
folks, the stack grows downward in the address space, so we'll discuss them in reverse
order:

5. The actively used portion of the stack.  Notice that the BaseAddress equals
the thread's current StackLimit, and that its BaseAddress+RegionSize equals StackBase.
The thread is actively using stack memory only within this region.

4. The guard portion of the stack.  When an attempt is made to write to an address
within this range (i.e. as the thread's stack grows by virtue of the program
calling functions, stackalloc'ing, etc.), the memory's guard status is cleared
and a fault is triggered.  The OS traps this fault, and responds by committing
additional guard region and then resuming at the faulting instruction.  What
used to be the guard page has now become part of 5, and the program can continue
on its merry old way.  (Assuming there is room to commit another guard region;
if not, stack overflow ensues.)  A couple things are worth noting.  Because
the CLR commits the entire stack, the OS doesn't really have to "commit" the memory:
it just annotates the next region as the new guard.  Also notice that the guard
in this program is 28KB in size.  Normally the guard is just a single page,
but the CLR uses SetThreadStackGuarantee to increase the amount of committed stack
we are guaranteed to have at any point in time, at least on OSes that support it.
This makes responding to stack overflow easier.

3. This is often referred to as the "hard guard page".  If you try to write
to this, the OS rips down your process.  In the wink of an eye, it's gone,
no callbacks, no nice Dr. Watson dumps, it just disappears.  As guard pages
are committed, this page is moved so that it's just beyond the guard region.
I don't know precisely how this happens w/out having to commit more memory (since
it's marked MEM\_RESERVE), but I suspect the OS just magically rearranges some page
table information.

2. This is the rest of the stack.  It hasn't been used yet, and it's not part
of the guard region.  This is where you'll see a difference between a managed
thread's stack and a native thread's stack: the pages are marked MEM\_COMMIT for
managed code, whereas they'd be MEM\_RESERVE for native.

1. This is the final destination of the hard guard page, after the whole stack has
been committed and the guard rests just before it at the end of the stack, this page
will always remain.  It is treated as a separate MEM\_RESERVED page and will
never be committed.

One additional thing is worth noting.  When the CLR pre-commits the whole stack,
it uses VirtualAlloc to do so.  This leaves the guard page close to the bottom
of the stack, the hard guard page just behind it, and the StackLimit in the TEB,
set to the address where the guard page ends.  This surprises some people, i.e.
they expect to see a StackLimit set to, say, 91000 in the above example.  But
remember, the OS doesn't get involved at all in our pre-committing of the stack.

**Method to the madness**

Why in the heck would we do all of this?

Believe it or not, there is a method to the madness.  When the OS tries to commit
a new guard region, it can fail.  It won't fail due to insufficient virtual
memory space (not that such things would matter much on X64 anyhow), because the
memory is already reserved.  We can handle those cases just fine.  Rather,
it might fail if there is insufficient pagefile backing to commit the memory.
This would manifest as a stack overflow.  Sadly, at the point of this stack
overflow, the CLR's vectored exception handler (which responds to ERROR\_STACK\_OVERFLOW)
would then have only the guard region's worth of stack space in which to do anything
reasonably intelligent.  (Which, recall, was traditionally one page.)
The unhosted CLR just has to issue a failfast in this case, but it also wants to
do things like create a Windows Event Log entry, play nicely with Dr. Watson and
debuggers, and so on.

This is also required for hosts like SQL Server who try to continue running in the
face of stack overflow.  In these cases, the CLR has to call out to the host
to see what it would like to do.  Maybe the host can run in just a page's
worth of stack, and maybe it can't.  The CLR doesn't try to recover in unhosted
situations because it is extremely difficult, and there are even problems with some
of Win32 itself not being able to tolerate the presence of stack overflow (most notably
CRITICAL\_SECTIONs).  But the SQL Server engine is a very carefully engineered
piece of software and they have a lot of experience (and success, apparently) remaining
running in these cases.

If we commit the entire stack, there is no fear of running out of physical space
during stack growth, because the whole thing has already been backed.

But of course this is the major downside to this design as well.  The pressure
this puts on the pagefile is not negligible.  If you have 1,000 threads in a
process, you need 1GB of pagefile space to back all of their stacks.  Sure,
that's a lot of threads, but heck, that's a lot of disk space too!  A stack
page won't require physical memory until it's actually faulted in (i.e. read
from or written to), but the pagefile expense is a high price to pay for what amounts
to be an obscure (and dubious) condition.

I say "dubious" because you have to wonder: is it even worth it anyway?
Probably not.  On modern Windows OSes that support SetThreadStackGuarantee,
there's little reason to commit anything but the guaranteed guard region.
The CLR uses this API, which means we can size the guaranteed region large enough
to so we can always run our stack overflow logic within it.  Committing any
more than this really is just a waste.  Even on OSes without this API, however,
we're going to failfast the process in this situation anyhow.  Sure, if we
didn't commit the whole thing up front, then these "out of pagefile space"
situations might result in an inability to log an Event Log entry, notify a debugger,
and so on, but will we really be able to do that anyway given the extreme resource
pressure the machine has to be under to create this situation?  Probably not.

In the end, it matters little what I think about the design.  This is how it
is, and I figured you all should know about it.

