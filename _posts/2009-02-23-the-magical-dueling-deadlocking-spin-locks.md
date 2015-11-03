---
layout: post
title: The magical dueling deadlocking spin locks
date: 2009-02-23 20:59:14.000000000 -08:00
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
Pop quiz: Can this code deadlock?

```
SpinLock slockA = new SpinLock();
SpinLock slockB = new SpinLock();

Thread 1            Thread 2
~~~~~~~~            ~~~~~~~~
slockA.Enter();     slockB.Enter();
slockA.Exit();      slockB.Exit();
slockB.Enter();     slockA.Enter();
slockB.Exit();      slockA.Exit();
```

The answer, as I'm sure you suspiciously guessed, is "it depends."

I previously posted [some thoughts](http://www.bluebytesoftware.com/blog/2008/06/13/VolatileReadsAndWritesAndTimeliness.aspx)
about whether a full fence is required when exiting the lock.  In that post,
I focused primarily on timeliness.  But what might be even more frightening
is that the answer to my question above is yes, provided two things:

1. Exit doesn't end with a full fence.
2. Enter doesn't start with a full fence.

Just making Exit a store release and Enter a load acquire is insufficient.
Here's why.

Imagine a super simple spin lock that satisfies our deadlock criteria:

```
class SpinLock {
    private volatile int m_taken;

    public void Enter() {
        while (true) {
            if (m_taken == 0 &&
                    Interlocked.Exchange(ref m_taken, 1) == 0) {
                break;
            }
        }
    }

    public void Exit() {
        m_taken = 0;
    }
}
```

Clearly Exit satisfies #1.  The technique of using an ordinary read of m_taken
before resorting to the XCHG call is often known as a TATAS (test-and-test-and-set)
lock, and this can help alleviate contention.  And it also means we will satisfy #2
above.

To see why deadlock is possible, imagine the following (fully legal) compiler transformation.
The compiler first inlines everything, so for Thread 1 we have:

```
Thread 1
========
while (true) {
    if (slockA.m_taken == 0 &&
            Interlocked.Exchange(ref slockA.m_taken, 1) == 0) {
        break;
    }
}

slockA.m_taken = 0;

while (true) {
    if (slockB.m_taken == 0 &&
            Interlocked.Exchange(ref slockB.m_taken, 1) == 0) {
        break;
    }
}

slockB.m_taken = 0;
```

What has to happen next is pretty subtle.  It's even unlikely a compiler would
do this intentionally (as far as I can tell).  But it's entirely legal to morph
the above code into something like this:

```
Thread 1
========
while (true) {
    if (slockA.m_taken == 0 &&
            Interlocked.Exchange(ref slockA.m_taken, 1) == 0) {
        break;
    }
}

while (slockB.m_taken == 0) ;;

slockA.m_taken = 0;

if (Interlocked.CompareExchange(ref slockB.m_taken, 1) != 0) {
    while (slockB.m_taken != 0 ||
        Interlocked.Exchange(ref slockB.m_taken, 1) != 0) ;;
}

slockB.m_taken = 0;
```

The load(s) of slockB.m_taken have moved before the store to slockA.m_taken; this
is legal, even if they are both marked volatile.  A load acquire can move above
a store release, and the code remains functionally equivalent.  Now, the code
required to fix up this code motion is pretty hokey.  We clearly can't do the
XCHG before the store to slockA.m_taken, so we need to try it afterwards.
But that brings about an awkward transformation: if it fails, we must effectively
do what the original code did, spinning until we acquire the slockB lock.

Do you see the deadlock yet?

Imagine the compiler did similar code motion on Thread 2:

```
Thread 2
========
while (true) {
    if (slockB.m_taken == 0 &&
            Interlocked.Exchange(ref slockB.m_taken, 1) == 0) {
        break;
    }
}

while (slockA.m_taken == 0) ;;

slockB.m_taken = 0;

if (Interlocked.CompareExchange(ref slockA.m_taken, 1) != 0) {
    while (slockA.m_taken != 0 ||
        Interlocked.Exchange(ref slockA.m_taken, 1) != 0) ;;
}

slockA.m_taken = 0;
```

Oh no!  See it now?

If Thread 1 and Thread 2 both enter the critical regions for slockA and slockB at
the same times, they will end up spin-waiting for the other to leave before exiting
their respective lock.

**_Boom_** : deadlock.

