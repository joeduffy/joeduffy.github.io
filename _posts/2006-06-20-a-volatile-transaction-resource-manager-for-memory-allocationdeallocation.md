---
layout: post
title: A volatile transaction resource manager for memory allocation/deallocation
date: 2006-06-20 16:45:09.000000000 -07:00
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
Jim Johnson started [a series back in 
January](http://pluralsight.com/blogs/jimjohn/archive/2006/01/21/18170.aspx) 
that I'm dying to see continued. It's about writing resource managers in 
System.Transactions, which surprisingly turns out to be incredibly 
straightforward. Provided you are able to implement the correct ACI[D] 
transactional qualities for the resource in question, that is. Juval Lowy's 
[December 2005 MSDN Magazine article on volatile resource 
managers](http://msdn.microsoft.com/msdnmag/issues/05/12/Transactions/) 
described how to build what turns out to be essentially mini-transactional 
memory, without much of the syntax, implicit and transitive qualities, and 
robustness.

As an example of where you might use a resource manager, imagine that you wanted 
to ensure that any memory allocations and deallocations inside a transaction 
scope participate with the System.Transactions ambient transaction. Maybe you'd 
like your allocations to be in sync with the database server or web service to 
which you're also transacting access. I'll walk through an example of how 
straightforward writing such a resource manager can be.

First, our starting class is quite simple. It just allocates and frees memory. 
Sans transactions, it looks like this:

```
using System.Runtime.InteropServices;

public static class Mm {
    public static IntPtr Malloc(long bytes) {
        return Marshal.AllocHGlobal(new IntPtr(bytes));
    }
    public static void Free(IntPtr pp) {
        Marshal.FreeHGlobal(pp);
    }
}
```

Mm.Malloc returns a pointer to 'bytes' amount of memory via kernel32!GlobalAlloc 
(which turns out to be a crappy way to manage memory by the way, and is still 
alive only to support DDE, the clipboard, and OLE, or so I'm told; it works as 
an example though). Mm.Free takes a pointer to memory that was previously 
allocated via Mm.Malloc and frees it. Pretty simple.

OK, that's not incredibly useful, especially considering that we're just making 
single-line invocations to the Marshal class. But it's a starting point.

Ultimately, what we want to ensure is that at the end of a transaction, any 
memory allocation and deallocation that happened within the transaction is 
consistent with the outcome of that transaction. That means, quite simply, that 
if memory was allocated and the transaction commits, we keep the memory 
allocated around; but if, on the other hand, the transaction rolls back, we must 
undo the allocation. Similarly, if we free memory and the transaction commits, 
then the memory remains freed; if it rolls back, we must undo the freeing.

If we want to build such a thing directly on top of existing facilities we 
clearly can't do this precisely as I suggest. How do you undo a call to free in 
the CRT, for example? You can't. Once you call free, the memory's gone, returned 
to the pool, and possibly used before your transaction even knows what to do 
with itself. But it turns out that we can "fake it" sufficiently close enough 
that most people can't tell that we're faking it. Here's what we do instead:

1. When somebody allocates memory, we log a compensating action in the 
   transaction that frees the memory should we roll back. If the transaction 
   commits, we do nothing more.

2. When somebody frees memory, we defer the call to commit time. If it never 
   commit, we never free the memory.

This is fairly well known in database literature. Take a look at Jim Gray's 1980 
paper, [A Transaction 
Model](http://research.microsoft.com/~gray/papers/A%20Transaction%20Model%20RJ%202895.pdf), 
where he describes REDO and UNDO actions, to see what I mean. (1980! That was 
ages ago.) What we're saying basically is that allocation logs an UNDO action 
and freeing logs a REDO action. The isolation leaks out of this in some 
regard--evidence of our "faking it"--because the fact that our freed memory 
isn't instantaneously available to other allocations might be noticed, 
especially under high stress conditions. OOMs may result that would have not 
otherwise happened, and the working set of the program may increase, especially 
for long running transactions. Cest la vie.

Anyhow… on to the implementation of these ideas. It's surprisingly simple.

We will allow instances of our Mm class to be created by the implementation. 
From the viewpoint of a user, the class is still entirely static and cannot be 
constructed. These instances will become enlistments responsible for 
implementing transactional semantics and responding to certain event 
notifications from the System.Transactions machinery. To do so, the class must 
implement the System.Transactions interface IEnlistmentNotification:

```
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Transactions;

public sealed class Mm : IEnlistmentNotification {
    /** Fields **/
    private LinkedList<IntPtr> m_freeOnCommit = new LinkedList<IntPtr>();
    private LinkedList<IntPtr> m_freeOnRollback = new LinkedList<IntPtr>();

    [ThreadStatic]
    private static Dictionary<Transaction, Mm> s_currentMm;
    /** Constructors **/
    private Mm() {}

    /** Methods **/
    public static IntPtr Malloc(long bytes) {
        ...
    }

    public static void Free(IntPtr pp) {
        ...
    }
}
```

We've added two linked lists to hold the deferred (m\_freeOnCommit) and 
compensating actions (m\_freeOnRollback). And we have a thread-static dictionary 
that maps the current transaction to the enlisted instance of Mm. This is pretty 
straightforward stuff, although there are a plethora of alternative designs. Now 
let's see how we get data into these things. The Malloc and Free implementations 
will change slightly to check for an existing transaction:

```
public static IntPtr Malloc(long bytes) {
    IntPtr pp = Marshal.AllocHGlobal(new IntPtr(bytes));

    // If insufficient memory, OOM is thrown and we never log the free.
    Mm mm = GetCurrentMm();
    if (mm != null) {
        // Compensating activity to ensure that if we rollback, we free.
        mm.m_freeOnRollback.AddLast(pp);
    }

    return pp;
}

public static void Free(IntPtr pp) {
    Mm mm = GetCurrentMm();
    if (mm != null) {
        // We defer the freeing of memory in case we don't commit.
        mm.m_freeOnCommit.AddLast(pp);
    } else {
        Marshal.FreeHGlobal(pp);
    }
}
```

This implements the commit and rollback behavior I described above, i.e. we add 
the memory location to free on to the deferred or compensated list according to 
the rules we've already established. GetCurrentMm is responsible for lazily 
allocating and enlisting an instance of Mm. If there is no active ambient 
transaction, it just returns null:

```
private static Mm GetCurrentMm() {
    // Are we in a transaction?
    Transaction currTx = Transaction.Current;
    if (currTx == null) {
        // Return null to indicate we're not in a transaction.
        return null;
    }

    // Have we already allocated and enlisted a volatile RM for this transaction?
    Mm currMm = null;
    if (s_currentMm == null) {
        s_currentMm = new Dictionary<Transaction, Mm>();
    } else {
        s_currentMm.TryGetValue(currTx, out currMm);
    }

    // No RM found, create/enlist one.
    if (currMm == null) {
        currMm = new Mm();
        s_currentMm.Add(currTx, currMm);
        currTx.EnlistVolatile(currMm, EnlistmentOptions.None);
    }

    return currMm;
}
```

And of course we have a RemoveCurrentMm which will be used eventually to remove 
the enlistment information from our dictionary:

```
private static void RemoveCurrentMm() {
    Transaction currTx = Transaction.Current;
    if (currTx != null && s_currentMm != null) {
        s_currentMm.Remove(currTx);
    }
}
```

So now we have all of the information about what should be freed and when, but 
there's no code that actually executes the free operations. To do that, all we 
have to do is implement the IEnlistmentNotification interface properly, 
iterating the proper list, and invoking Malloc.FreeHGlobal on the contents. In 
other words, Commit and Rollback just invoke free on all of the memory addresses 
in the respective linked list:

```
void IEnlistmentNotification.Commit(Enlistment enlistment) {
    FreeAll(m_freeOnCommit);
    RemoveCurrentMm();
    enlistment.Done();
}

void IEnlistmentNotification.Rollback(Enlistment enlistment) {
    FreeAll(m_freeOnRollback);
    RemoveCurrentMm();
    enlistment.Done();
}

private void FreeAll(LinkedList<IntPtr> toFree) {
    foreach (IntPtr p in toFree) {
        Marshal.FreeHGlobal(p);
    }
}
```

We're assuming in all of those cases that FreeAll and RemoveCurrentMm can't 
fail. If our commit or rollback processing failed mid-way, that would put the 
entire process at risk: memory could be leaked or become corrupt. 
System.Transactions will respond to that by sending InDoubt notifications to all 
enlistments. Since the only way we can potentially contain and resolve volatile 
state corruption is to crash the process, that's exactly what we do:

```
void IEnlistmentNotification.InDoubt(Enlistment enlistment) {
    Environment.FailFast("State protected by RM is in question");
}
```

This is a Byzantine response, sure, but it's the only way we can guarantee that 
state doesn't become corrupt when the transaction's fate is InDoubt. If the fate 
of one or more resource managers cannot be determined, we don't know whether to 
commit or fail for sure. We could guess, of course, but guessing doesn't lead to 
pleasant behavior in software, especially when we have to debug it. (And if 
you're making guesses, you'll probably have to spend more time debugging, so 
it's a double whammy of sorts.)

And that's it! Now we can use memory operations inside of a transaction, and 
have it behave as expected. Just as an example, this test case ensures that 
writing to memory that was allocated in a transaction that eventually aborts 
causes an AccessViolation:

```
bool test1success = false;
IntPtr pMem1 = IntPtr.Zero;
try {
    try {
        using (TransactionScope txScope = new TransactionScope()) {
            pMem1 = Mm.Malloc(1024 * 1024); // get 1MB of space
            throw new Exception(); // cause an abort
        }
    } catch {
        // The txn was aborted, we expect reading from memory to fail.
        uint * pInt = (uint *)pMem1.ToPointer();
        *pInt = 0xdeadbeef;
    }
} catch (AccessViolationException) {
    test1success = true;
}
```

Console.WriteLine("Test 1 succeeded: {0} (rollback of malloc)", test1success);

There are three other tests that may be of interest in the source file for the 
Mm class and associated code: 
[MallocFree.cs](http://www.bluebytesoftware.com/code/06/06/mallocfree.txt).

Of course this approach is not perfect in several areas. One that comes to mind 
immediately is the fact that we're doing a potentially expensive lookup for an 
ambient transaction on every memory allocation and deletion, which could be too 
much, especially if it happened in some general purpose allocation and 
deallocation routines. And of course automatically finding the transaction and 
using might also be a bad idea. We might instead want the user to opt-in to 
transactional Malloc and Free at the callsite, so that users aren't surprised 
when their malloc or free never happens (the transaction rolled back). 
Nevertheless, this article at least cracked the surface of a very difficult 
problem and surfaced some interesting issues.

