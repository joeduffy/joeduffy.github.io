---
layout: post
title: Guaranteeing CLR data alignment at N byte boundaries
date: 2007-01-22 20:27:07.000000000 -08:00
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
I was recently asked by a customer how to guarantee alignment of CLR data on 16-byte
boundaries.  They needed this capability to interoperate with code that uses
SSE vector instructions to manipulate the data (which require 16-byte alignment).
The bad news is that there's no real good way of doing this.  That is, there
isn't any "align at N bytes" feature for the CLR in which type layout and stack
_and_ heap allocation cooperate.  The good news is that you can fake it.

(I spoke about alignment with respect to atomic cmpxchg8b instructions previously,
[right here](http://www.bluebytesoftware.com/blog/PermaLink,guid,e799b1de-d43c-4c48-99db-2532a392ca86.aspx),
for those interested in reading about that too.)

The details of how to go about ensuring 16-byte alignment depend on whether
you allocate your data on the stack or the GC heap.  For illustration purposes,
imagine we're dealing with an array of float32[]'s.  We'd like to ensure
the beginning lies on a 16-byte boundary:

1. float [] a0 = new float[N]; // GC-allocated array of N floats

2. float \* a1 = stackalloc float[N]; // stack-allocated array of N floats

If you use the former, GC allocation (1), you're going to have a really tough time.
The GC moves objects around on you as it performs compactions, and only aligns the
1st element of the array on a 4-byte boundary.  So even if you manage to get
your object allocated on a 16-byte boundary (by chance), it is apt to move during
a subsequent GC.

To solve this problem, you'd have to pin the object.  Pinning causes [GC fragmentation](http://msdn.microsoft.com/msdnmag/issues/06/11/CLRInsideOut/default.aspx),
so I really encourage you to avoid this approach and go with stack allocation, (2),
if you can afford it.  A float[] on the stack is similarly aligned to begin
at a 4-byte boundary, but, unlike (1), it will subsequently not move around.
Of course stack allocation is often impossible, or difficult, if you are writing
a reusable library that may be called in an unknown context (where the caller may
have very little stack left).  This is a tradeoff you would have to make.
If the pinning is very short lived, i.e. the duration of a single function call, it
might be tolerable for you, a la P/Invoke.

Regardless of whether you choose (1) with pinning or (2) by itself, you've now
got a stable address.  And you can use the stable address to calculate the next
16-byte element in the array from the base address, and then use that as the start
of the array.  You will need some extra padding at the end for the worst case,
which is _base + 3_, meaning at most 12 bytes, so you need to allocate 3 extra floats
in the array.  Here's an example:

```
void * AlignUp(void * p, ulong alignBytes)
{
    ulong addr = new UIntPtr(p).ToUInt64();
    alignBytes -= 1; // adjust pointer for arithmetic
    if (((1<<(IntPtr.Size\*4 - 1)) - alignBytes) <= addr) {
        throw new Exception("overflow");
    }
    ulong newAddr = (addr + alignBytes) & ~alignBytes;
    return new UIntPtr(newAddr).ToPointer();
}

...

float * p = stackalloc float[N + 3];
p = (float *)AlignUp(p, 16);
... use p ...
```

Note that if you were to use an array of doubles instead, you'd have some challenges.
That's because a 8-byte value on the 32-bit CLR is only 4-byte aligned, and therefore
you can end up with a situation where the next 16-byte granularity is in the middle
of a single element.  For example, 12 + 8 = 20 byte, +8 = 28 byte, +8 = 36 byte,
and so on.  None of these are 16-byte aligned.  Not that it really matters,
so long as you allocate enough memory, but you will need to do some casting of the
array reference, as shown in the above code, to do the arithmetic.

Note also that there's a StructLayout attribute that allows you to specify alignment,
through its padding field, but sadly this doesn't impact the GC's heap or the
JIT's stack alignment, and so it's useless for our purposes.  Though the
relative alignment _within _the data structure will be correct, the absolute alignment
is not guaranteed to be so.

OK, so I know all of this isn't pretty.  But it works.

