---
layout: post
title: CLR data alignment and CMPXCHG8B
date: 2006-12-06 22:06:36.000000000 -08:00
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
I took this past week off so that I could work on my book.  Well, I'm happy
to report that I've been successfully writing like a madman, averaging around
15-20 solid pages per day.  I still have a long way to go, but I'm getting
more confident with the passing of each day that this book will be...  well...
a book that I'd actually like to sit down and read.

_[**Update: 12/7/2006:** Correction made -- the CLR's JITs_ do not _generate manual
alignment code.  Instead, we defer to the costly OS handler for alignment fixups.]_

In the process of writing the section on data alignment, I realized there is very
little documentation on the alignment policy used by the CLR.  This is in contrast
to [Kang Su Gatlin](http://blogs.msdn.com/kangsu/)'s wonderful MSDN [treatise on
the subject for VC++](http://msdn2.microsoft.com/en-gb/library/aa290049(VS.71).aspx),
which leaves absolutely nothing hidden in the closet.  Well, I still don't have
all of the answers for you.  Sorry.  You'll have to wait for the book.
But in the meantime, I've discovered that there's a myth that deserves a little debunking.

In the MSDN documentation for [InterlockedCompareExchange64](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/interlockedcompareexchange64.asp),
it says:

> "The variables for this function must be aligned on a 64-bit boundary; otherwise,
> this function will behave unpredictably on multiprocessor x86 systems and any non-x86
> systems."

I've also heard and read this from other various sources.  I've heard, for example,
that LOCK CMPXCHG8B will still do a load/compare/store sequence, but that, if the
address isn't 8-byte aligned, the instruction will not be atomic.  This would
lead to sporadic atomicity failures, probably even more difficult to track down than
a typical race.  Given that the CLR doesn't faithfully align 64-bit data types
on 8-byte boundaries (as we'll see momentarily), I suddenly feared that Interlocked.CompareExchange(ref
Int64, ...) was HORRIBLY broken.  Without an MP machine at home, I couldn't
test this out, so I decided to do a little digging.

In the manuals for many AMD processors and older Intel X86 processors, I found no
reference to CMPXCHG8B requiring an aligned address.  What I did find, however,
in the [Intel 64-bit and IA32 System Programmer's Manual Part A](http://www.intel.com/design/processor/manuals/253668.pdf)
was the following (emphasis mine):

> "**The integrity of a bus lock is not affected by the alignment of
> the memory field.** The LOCK semantics are followed for as many bus cycles as necessary
> to update the entire operand. However, it is recommend that locked accesses be aligned
> on their natural boundaries for better system performance:
> 
> - Any boundary for an 8-bit access (locked or otherwise).
> - 16-bit boundary for locked word accesses.
> - 32-bit boundary for locked doubleword accesses.
> - 64-bit boundary for locked quadword accesses."

If I'm reading that right, this means the common wisdom around 8-byte alignment and
LOCK CMPXCHG8B is hogwash.  (Sadly, proving the absence of some flaky processor
that crashes or has unpredictable behavior under certain circumstances is rather
difficult, especially if someone at some point though it was true enough to put it
in the MSDN documentation.  If somebody out there knows of a real case -- and
it's not just hear say -- please let me know!)  If this is true of all X86 processors,
it means that Interlocked.CompareExchange(ref Int64, ...) isn't horribly broken on
the CLR after all.  (Yaay.)  It would have been broken...  because,
as I said earlier, the CLR does NOT align 64-bit values on 8-byte address boundaries...

Conversing briefly with Simon Hall over email, the dev that owns most (all?) of the
type layout infrastructure, I've concluded the following:  CLR type layout tries
to eliminate all misaligned data layout through a combination of padding and field
reordering.  This means that data of &gt;= 8-bytes on 64-bit always begins on 8-byte
boundaries, and data of &gt;= 4-bytes on 32-bit always begins (at least) on 4-byte boundaries.
I say "at least" because emperical evidence shows that type layout actually aligns
many 8-byte fields on 8-byte boundaries, even on 32-bit.  (It turns out this
doesn't matter much...  neither the 32-bit JIT nor the GC respect this when
allocating data.)  In summary, the CLR ensures that no field that could
have fit inside a single 4/8-byte segment ever spills across a boundary.  The
CLR also adds necessary padding to StructLayout(Sequential) types, while still preserving
the original field ordering.

Therefore, the only cases where we end up with truly misaligned data is with StructLayout(Explicit)
and StructLayout(Pack=...) types.  For example the simple struct, struct S {
[FieldOffset(6)] int i; }, will always be misaligned, on 32- and 64-bit alike.
In such cases, our JIT simply generates the naive code and lets the OS perform misalignment fixups.
This is actually rather costly, as Kang Su's aforementioned article explaines.
We could have, like the VC++ compiler, generate the manual alignment code using a
combination of loads and shifts, but my guess is that most of our customers don't
care and will never notice.

To preserve the hard work done by type layout, our JITs and the GC guarantee that
all allocated data is aligned on at least 4-byte (on 32-bit) or 8-byte (on 64-bit)
boundaries.  I say "at least" once again because I know, for example, that VC++
aligns stack frames on 16-byte boundaries for 64-bit.  I don't claim to understand
why.  We might do something similar.

Here's an interesting program that just prints out a few field addresses, and whether
things are 8-byte aligned.  You'll interestingly notice that the int/long fields
that are adjacent to one another are padded with 4-bytes in between on 32- and
64-bit, but that the JIT and GC only align on 4-byte addresses on 32-bit.  I
presume this is so that the layout doesn't have to change between 32- and 64-bit,
but I can't say for sure:

```
using System;
using System.Runtime.InteropServices;

class C {
    internal S s;
}

struct S {
    internal int x;
    internal long y;
    internal byte z;
}

unsafe class P {
    static void Main(string[] args) {
        int pad = 5;
        if (args.Length > 0) pad = int.Parse(args[0]);

        Console.WriteLine("Field\t[Begin\tEnd)\t%8");

        PrintStackS(pad);
        PrintHeapS(pad);
    }

    static void PrintStackS(int x) {
        int * pad = stackalloc int[x];
        S * s = stackalloc S[1];
        PrintAddr(s);
    }

    static void PrintHeapS(int x) {
        for (int i = 0; i < x; i++) new object();

        C c = new C();
        fixed (S * pcs = &c.s) {
            PrintAddr(pcs);
        }
    }

    static unsafe void PrintAddr(S \* ps) {
        ulong xa = new UIntPtr(&ps->x).ToUInt64();
        Console.WriteLine("X\t{0:X}\t{1:X}\t{2}",
            xa, xa + sizeof(int), xa % 8);

        ulong ya = new UIntPtr(&ps->y).ToUInt64();
        Console.WriteLine("Y\t{0:X}\t{1:X}\t{2}",
            ya, ya + sizeof(long), ya % 8);

        ulong za = new UIntPtr(&ps->z).ToUInt64();
        Console.WriteLine("Z\t{0:X}\t{1:X}\t{2}",
            za, za + sizeof(byte), za % 8);
    }
}
```

Running it with a few different inputs yields these results:

```
C:\Temp>8by
Field   [Begin  End)    %8
X       12F440  12F444  0
Y       12F448  12F450  0
Z       12F450  12F451  0
X       1273670 1273674 0
Y       1273678 1273680 0
Z       1273680 1273681 0

C:\Temp>8by 2
Field   [Begin  End)    %8
X       12F44C  12F450  4
Y       12F454  12F45C  4
Z       12F45C  12F45D  4
X       1273664 1273668 4
Y       127366C 1273674 4
Z       1273674 1273675 4
```

If the CLR ever decides to support a 128 CAS operation, Interlocked.CompareExchange(ref
Int128, ...), which I hope we will, we would need to guarantee alignment on 16-byte
boundaries.  In comparison to CMPXCHG8B, CMPXCHG16B does indeed fail when issued
against an address that isn't 16-byte aligned.  Instead of failing silently,
a GP fault is generated.  This is difficult, because not only must type layout
respect the alignment (you can already get this with StructLayout(..., Pack=16)),
but the JIT and the GC would also need to allocate correctly.  Or, of course,
you could over-allocate a chunk of data and shift the start pointer to the first
aligned address inside of it.  This might work for the stack, but for GC
allocated data this is going to keep shifting around on you, and probably won't work
very well.  Before the CLR supports Interlocked.CompareExchange(ref Int128,
...), however, I suppose we ought to provide an Int128.  :)

