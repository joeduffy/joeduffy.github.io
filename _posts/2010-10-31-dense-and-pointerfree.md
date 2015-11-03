---
layout: post
title: Dense, and pointer-free
date: 2010-10-31 17:41:41.000000000 -07:00
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
I rambled on and on a few weeks back about how much performance matters. Although
I got a lot of contrary feedback, most of it had to do with my deliberately controversial
title than the content of the article. I had intended to post a redux, but something
more concise is on my mind lately.

GC-based memory management is a boon to productivity, not to mention program safety.
Few would argue with this. However, the most effective developers know how their
particular GC works, and optimize their program's data structure, allocation, and
lifetime behavior to suit their particular GC best.

This is dangerous, but a pragmatic fact of life. It is dangerous because who's
to say that the runtime team doesn't intend to entirely revamp the GC's collection
strategy next release, at which point your thoughtfulness may actually harm you?
It's a pragmatic fact for a few reasons: it's probably not likely that the behavior
of your favorite GC is going to change too fundamentally over time; if it did, you'd
need to rethink things anyhow; oh, and when was that next release anyway (2 or more
years out); and finally, what do you care about more, the theoretical loose coupling,
or real results today?

One of the worst data structures for traversal is a linked list. That's because
its contents are fetched by pointer-chasing, an act that usually destroys locality,
unless the data associated with each pointer was carefully constructed to live next
to its previous and next pointer's data. This seldom happens, because the main
point of a linked list is to free you from such constraints.

One of the best data structures for traversal, on the other hand, is an array. Adjacent
elements are truly adjacent to one another in memory, meaning that as you fetch the
i'th element from memory, you're probably pulling in the i'th, i+1'th, …,
and so on, thanks to spatial locality. Of course, if the elements are just pointers,
then you're back to the chasing game; as with anything, it depends.

How many elements you prefetch of course depends on the size of the elements with
respect to your processor's cache line. If you're working with 8-byte elements,
and 128-byte cache lines, then you may pay 100 cycles for the first fetch, and then
amortize that cost over the subsequent 15 found cheaply in cache for 10 cycles. The
result is about 250 cycles total; compare this to a linked list, where you'll probably
spend 1,600 cycles, or more than 6X the cost. And of course you're trashing other
data in the cache in the process. As you traverse more and more of the list, the
numbers snowball, and the amortization of locality, or lack thereof, provides a stark
contrast.

There's another subtle reason why this is important. Stop and think about what
happens when a GC occurs.

Yep, that's right. Your data structures need to be traversed during a GC, after
all, to ascertain the liveness of any pointers held within. That scan looks a whole
heck of a lot like the same traversal I just described, and enjoys the same locality
properties. So we can immediately conclude that data structures whose traversal is
efficient will translate into less time spent in the GC chasing pointers, and better
cache efficiency.

For programs that are sensitive to long pause times, this is huge. I talk to customers
all the time whose programs are sensitive to microsecond-long GC delays, and --
aside from ensuring good GC lifetime practices, like ensuring all objects either
die young or live long -- being conscious about locality can be immensely important.
Especially for any long-lived, large data structures that will be subject to Gen2
collections throughout their lifetime.

There is another useful trick to know. If a data structure contains no pointers,
the GC will not have to trace these pointers. Obvious, right? A linked list inherently
contains pointers, so this trick really doesn't apply: the GC will need to traverse
the whole live portions of the object graph. What's interesting is that an array,
on the other hand, may or may not contain elements that contain pointers. For example,
an array of ints clearly has no pointers, whereas an array of string references clearly
does. This doesn't just apply to the primitive types, but also custom structs which
may or may not contain references. When the GC encounters such an array, its contents
need not be traversed: instead, the array is alive, and that's that. Yet another
opportunity to eliminate pointer chasing. Not only does this save the GC from doing
some heavy lifting, but the pointer-free structs eliminate the need for the GC write
barriers on array stores too.

So think of all this next time you're confronted with the decision to employ a
tree, graph, or linked list, and whether a dense, and perhaps pointer-free, representation
could be beneficial. Even if it means you must replace pointers with index calculations.
The locality benefits may not matter, but then again, they may. And at least you
can knowingly make a balanced tradeoff, with these potential advantages in mind.

