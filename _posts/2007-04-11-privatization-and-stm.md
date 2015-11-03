---
layout: post
title: Privatization and STM
date: 2007-04-11 12:11:45.000000000 -07:00
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
Late last summer, an interesting issue with traditional optimistic read-based software
transactional memory (STM) systems surfaced.  We termed this "privatization"
and there has been a good deal of research on possible solutions since then.
I won't talk about solutions here, but I will give a quick overview of the problem
and a pointer to recent work.

As a quick refresher, optimistic reads are nice because they are invisible.
Being invisible eliminates the responsibility from the reading transaction to inform
other transactions about the act of reading.  Why is that nice?  Because
informing other transactions requires shared writes, which are expensive and often
require atomic (compare-and-swap) writes.  Doing that on every read can clearly
hamper your performance.  With optimistic systems, this step can be skipped,
which is a stark contrast to pessimistic read-based systems.

As many have already described (e.g. [Harris and Fraser](http://research.microsoft.com/~tharris/papers/2003-oopsla.pdf)),
this is often accomplished by having the reader observe a location-specific version
number after the read and ensuring that writing transactions increment this same
version number during commit.  Transactions later validate the observed version
numbers, and if any changed, the transaction rolls back.  Notice that the reading
transactions continue to do work after the optimistic read, in hopes that the work
needn't be thrown away later due to a conflict.  This, as you can imagine,
is where the "optimistic" terminology comes from.  But this is also why
we run into the privatization issue.

To illustrate, imagine that we have some linked list and two transactions, Tx1 and
Tx2.  Tx1 walks the list and updates all nodes (perhaps by incrementing some
counter), and Tx2 simply removes one node from the list so that it can do some work
privately with it.  The code might look like this:

```
class Node {
    Node next;
    int value;
}

    Node head = ...;

    // Tx1:
    atomic {
S0:     Node n = head;
S1:     while (n != null) {
S2:        n.value++;
S3:        n = n.next;
        }
    }

    // Tx2:
    Node n;
    atomic {
S4:     n = head.next; // take the 2nd element
S5:     head.next = n.next;
    }
S6: Console.WriteLine(n.value);
```

Assuming all nodes have values of 0 to begin with, and Tx2 commits before Tx1,
is it possible for Tx2 to print out the value 1 at S6?  Perhaps surprisingly
(and disappointingly), the answer is yes (with traditional optimistic read systems,
as described in the literature).

How?  Say Tx1 executes S0 through S3 first.  So Tx1's local variable
n now contains a reference to the 2nd node in the list.  Then Tx2 runs S4 and
S5, removing the 2nd node from the list.  Then Tx2 commits successfully, and
the IP is sitting at S6 but hasn't run yet.  Note that Tx1 is doomed at this
point—it has read a reference to the 2nd node via the head's next reference which
is now out of date—but doesn't know it and, with traditional optimistic read
systems, won't find out until it tries to commit.

From here, things go terribly wrong.  Tx1 may run and write to the 2nd node's
value which, in this particular example, could cause S6 to erroneously print out
the value of 1.  Worse, for more complicated data structures, invariants may
be horribly broken as there are plenty of races: S6 could even execute while Tx1
is in the process of rolling back, etc.  This can clearly be catastrophic.

This problem is described in depth in Larus and Rajwar's [recent transactional
memory book](http://www.amazon.com/exec/obidos/ASIN/1598291246/bluebytesoftw-20).
Spear, et. al recently released a [technical report](http://www.cs.rochester.edu/u/scott/papers/2007_TR915.pdf)
that also overviews the problem and presents some possible approaches to solve it.  Some
have suggested that data must be once-transactional, always-transactional, but some
thought exercises and other simpler examples should be sufficient to convince you
that that direction isn't very straightforward either.

