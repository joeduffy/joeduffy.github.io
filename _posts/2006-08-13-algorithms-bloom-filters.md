---
layout: post
title: 'Algorithms: Bloom filters'
date: 2006-08-13 13:45:48.000000000 -07:00
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
I've run across several algorithms lately that have benefited from the use of a [Bloom
filter](http://en.wikipedia.org/wiki/Bloom_filter). This led me to dig
up the original paper ( [Space/time trade-offs in hash coding with allowable errors](http://citeseer.ist.psu.edu/cache/papers/cs/26683/http:zSzzSzwww.ovmj.orgzSzGNUnetzSzpaperszSzp422-bloom.pdf/bloom70spacetime.pdf))
in which the idea was proposed. What surprised me a little was that this technique
was invented 35 years ago, by a fellow by the name of Burton Bloom, and yet it remains
a simple and effective way to speed up a certain category of modern software
problems.

The technique summarizes the contents of a set into a concise value (the _filter_) from
which quick answers may be computed. This value is typically generated using
some form of hash-coding of the set elements and stored within a bitmap,
enabling ultra-fast bitwise updates and queries. This value promises to never return
a false negative, although it is permitted to return false positives. So long as
the false positive rate is low, many queries that would ordinarily have come up empty
handed after a lengthy search will be retired in constant time. As an element is
added to the set, the value is updated to reflect its presence. A tricky part of
this technique, however, is that, because the value often summarizes the elements
using one-bit-to-many-elements, removing an element from the set typically cannot
just reset the corresponding bit. As items are removed over time, this can lead to
a stale value, an increasing rate of false positives, and a higher number of lengthy
searches. Thus the value must be periodically recomputed to combat this problem.

Let's take an example. Say you had a balanced binary tree that was frequently searched,
infrequently deleted from, and whose searches more often lead to misses than they
do hits. You can expect _O_(log n) search time. That's not bad, but for large values
of n you may have incentive to speed up the common case, which happens to be the
worst case for a perfectly balanced binary tree: a search that turns up empty.
Using a Bloom filter gives you a slightly modified algorithm whose search complexity
is Ω(1) for our problem's best case, and still _O_(log n) otherwise. This
also adds some notable cost due to the need to periodically recompute the filter
value, which is an _O_(n) operation, but since we infrequently delete items, we expect
this to pay off in spades.

Say we already had a BinaryTree&lt;T&gt; data structure. We could easily adopt a Bloom
filter with a series of minor modifications.

First, a new field to remember the filter's value. I've chosen a 64-bit bitmap for
illustration:

```
long filterValue = 0;
```

And since we've used a bitmap, we need a routine to calculate any arbitrary element's single
bit position. Remember, false positives are OK, and therefore multiple elements
may share the same bit:

```
long GetFilterValueForElement(T e) {
    return 1 << (e.GetHashCode() % (sizeof(long) * 8));
}
```

When adding an item to the set, we must change the filter's value:

```
filterValue |= GetFilterValueForElement(e);
```

Here's the beneficial change. While searching for an item, we can add a quick check
up front to speed up queries:

```
if ((filterValue & GetFilterValueForElement(e)) == 0) {
    // Element not found: we can be assured this is correct.
}
// Perform the existing, lengthier search. might be a false positive.
```

And of course, we must periodically do the _O_(n) operation on the tree to recompute
the filter. We might do this whenever the tree becomes empty and every n deletions,
for example:

```
if (isEmpty || (++deletionCount % recomputeFilterPeriod) == 0) {
    filterValue = 0;
    foreach (T e in this) {
        filterValue |= GetFilterValueForElement(e);
    }
}
```

You could even keep track of the number of false positives seen, and use that to
determine when to initiate the recomputation.

This technique clearly won't work well in data structures and problems in which the
deletion-to-query ratio is high, but there are plenty of situations where this technique
helps tremendously. Logs of various forms, for example, exhibit the property that
they are added to but never deleted. Depending on the density of the data structure,
you may want to use an array instead of a bitmap--or a bitmap with more bits--to
represent the summary. I ran a quick test and the simple bit-shifting hash-coding
mechanism above yielded a full filter (~0) after only 227 random object allocations.
You can of course even decide to reduce the density of your bitmap dynamically
by detecting a close-to-full map and upgrading to a larger filter data
structure. A dense filter often corresponds to a higher false positives rate,
in which case you simply waste time maintaining and checking a value that doesn't
give you any benefit.

