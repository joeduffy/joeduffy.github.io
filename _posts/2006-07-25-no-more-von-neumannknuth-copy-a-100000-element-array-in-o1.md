---
layout: post
title: 'No more von Neumann+Knuth: copy a 100,000 element array in O(1)'
date: 2006-07-25 23:32:03.000000000 -07:00
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
A colleague lent me a copy of W. Daniel Hillis's PhD thesis, _The Connection Machine_,
which is also [available in book form from The MIT Press](http://www.amazon.com/exec/obidos/ASIN/0262580977/bluebytesoftw-20).
I only began reading it last night, but I have been continuously amazed. It's been
enlightening to realize how much framing problems differently (and, in many cases,
more naturally) can make programming _without_ concurrency seem ridiculous.

To give you an idea, here's a quote from the thesis:

> "When performing simple computations over large amounts of data, von Neumann
> computers are limited by the bandwidth between memory and processor. This is a
> fundamental flaw in the von Neumann design; it cannot be eliminated by clever
> engineering."

Here is a quick illustration: What's the most efficient way of copying a source
array of 100,000 elements to a destination array of 100,000 elements? With a
single-CPU this would typically be O(n), where n is the length of the array. If
you could minimize costs due to thread creation and communication, _and_ ensure
good locality, you might be able to gain some parallel speedup by using multiple CPUs.

With The Connection Machine, however, you can do it in O(1) time. Simply instruct
the 100,000 source cells, each of which holds a single array element, to communicate
their value to the 100,000 destination cells, and instruct the destination cells
to receive and store the value. This happens instantaneously, across the machine,
not in serial fashion. If any node _a_ can communicate with any other node _b_ in
1 time unit, the entire array is copied in just 1 time unit, not 100,000!
(Designing such an interconnect is, of course, quite difficult...)

I found it particularly interesting that, back in 1985, at least _this_ author
recognized the impending demise of an entirely sequential approach to all problems.

