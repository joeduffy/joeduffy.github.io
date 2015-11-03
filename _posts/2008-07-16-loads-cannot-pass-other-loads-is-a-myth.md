---
layout: post
title: '"Loads cannot pass other loads" is a ~myth'
date: 2008-07-16 19:43:00.000000000 -07:00
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
The adjacent release/acquire problem is well known.  As an example, given the
program:

```
P0          P1
==========  ==========
X = 1;      Y = 1;
R0 = Y;     R1 = X;
```

The outcome R0 == R1 == 0 is entirely legal.  This could happen because writes
are delayed in processor store buffers; so before R0 = Y retires, the store X = 1
may have not even left the local processor P0; similarly, before R1 = X retires,
the store Y = 1 may not have even left processor P1.  It is as if the program
was written as follows:

```
P0          P1
==========  ==========
R0 = Y;     R1 = X;
X = 1;      Y = 1;
```

The standard way to fix this is to emit a full fence:

```
P0          P1
==========  ==========
X = 1;      Y = 1;
XCHG;       XCHG;
R0 = Y;     R1 = X;
```

But here is one that may be a little surprising:

```
P0          P1
==========  ==========
X = 1;      Y = 1;
R0 = X;     R2 = Y;
R1 = Y;     R3 = X;
```

Assuming X and Y are "volatile" to the compiler, is R1 == R3 == 0 a possible outcome
in this program?

Based on the rules we provide for [.NET's MM](http://www.bluebytesoftware.com/blog/2007/11/10/CLR20MemoryModel.aspx),
and [Intel's whitepaper](http://www.intel.com/products/processor/manuals/318147.pdf),
one could reasonably argue "no".  The reasoning goes as follows.  True
data dependence prohibits R0 = X from moving before X = 1, and the no load/load reordering
rule (e.g. Intel's Rule 2.1) prohibits R1 = Y from moving before R0 = X.  Thus,
transitively, R1 = Y may not move before X = 1.  Similarly, true data dependence
prohibits R2 = Y from moving before Y = 1, and the no load/load reordering rule prohibits
R3 = X from moving before R2 = Y, and therefore R3 = X may not move before Y = 1.
Given this reasoning, the individual instruction streams cannot be reordered in place.
And therefore, no interleaving of them will yield R1 == R3 == 0, because either X
= 1 or Y = 1 must happen first, and both R1 = Y and R3 = X must come later.
Hence at least one of R1 or R3 will observe a value of 1.

Sadly, this reasoning is incorrect.  Rule 2.4 in the Intel whitepaper states
that "intra-processor forwarding is allowed."  They even have an innocent example
in the paper, but it actually doesn't exhibit load/load reordering.  It does,
however, illustrate that stores may be delayed for some time in a write buffer.
Perhaps surprisingly, such intra-processor forwarding of buffered stores is actually
permitted to satisfy subsequent loads from that location by the same processor _before_
the store has left the processor.  This can happen even if it means passing
intermediate loads from different memory locations!  The result is that load/load
reordering is effectively possible under some circumstances.  Loads still physically
retire in order of course, but because they may be satisfied by pending writes that
other processors cannot yet see, it is as if the original program were written as:

```
P0          P1
==========  ==========
R1 = Y;     R3 = X;
X = 1;      Y = 1;
R0 = X;     R2 = Y;
```

The fundamentally contradicts what most people believe about .NET's MM, and indeed,
Intel's MM as specified in that whitepaper.  To be fair, the whitepaper actually
does call this out, but in a roundabout and misleading fashion.  The text in
Rule 2.1, which states that "no loads can be reordered with other loads", is far
too strong.

Anytime a little hole in something as fundamental as MM axioms is uncovered, it is
cause for concern.  So I found this discovery deeply disturbing.  Many
abstractions and theorems are proved with the assumption that the MM is rock
solid.  I know a lot of code I have written relies on such proofs.

That said, I've been racking my brain (and in fact was having nightmares about it
last evening) trying to uncover a case where this is worse than the existing release/acquire
reordering issue that I opened this post with.  Everything I come up with is
saved at the last minute by rules 2.1 (for stores) and 2.5 "stores are transitively
visible".  The basic problem is that a processor can get stuck seeing its own
written value for some time, during which other processors cannot, but ultimately
it doesn't seem to matter because the buffer will eventually be flushed.  Then
any intermediary values that the destination may have held while that processor was
stuck will have been overwritten anyway, so the outcome should be explainable (albeit
racey).  I'm still thinking hard about this.

