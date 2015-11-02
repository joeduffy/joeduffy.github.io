---
layout: post
title: Simple SSE loop vectorization from managed code
date: 2007-05-30 00:45:26.000000000 -07:00
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
Intel and AMD processors have had very limited support for SIMD computations in the
form of MMX and SSE since the late 90s.  Though most programmers live in
a MIMD-oriented world, SIMD programming had a surge in research interest [in
the 80s](http://www.amazon.com/exec/obidos/ASIN/0262580977/bluebytesoftw-20), and
has remained promising for all those years, albeit a bit silently.  Vectorization
is a fairly popular technique primarily in niche markets such as the FORTRAN and
supercomputing communities.  Given the rise of GPGPU (see [here](http://www.gpgpu.org/),
[here](http://research.microsoft.com/research/pubs/view.aspx?tr_id=1040), and [here](http://research.microsoft.com/research/pubs/view.aspx?msr_tr_id=MSR-TR-2005-183))
and [rumors floating about](http://arstechnica.com/articles/paedia/hardware/clearing-up-the-confusion-over-intels-larrabee.ars)
in the microprocessor arena, this is an interesting space to watch.

You can get at SSE from managed code, though it requires some hoop jumping and the
interop overheads end up killing you.  Let's take a quick look at what it takes
to use classic loop stripmining techniques for a pairwise multiplication of two arrays.

Since we can't access the SSE instructions directly in managed code, we need to first
define a native DLL.  We'll call it 'vecthelp.dll' and it just exports a single
function:

```
#include <xmmintrin.h>

const int c_vectorStride = 4;

extern "C" __declspec(dllexport)

void VectMult(float * src1, float * src2, float * dest, int length)
{
    for (int i = 0; i < length; i += c_vectorStride) {
        // Vector load, multiply, store.
        __m128 v1 = _mm_load_ps(src1 + i); // MOVAPS
        __m128 v2 = _mm_load_ps(src2 + i); // MOVAPS
        __m128 vresult = _mm_mul_ps(v1, v2); // MULPS
        _mm_store_ps(dest + i, vresult); // MOVAPS
    }
}
```

'VectMult' takes two pointers to float arrays, 'src1' and 'src2', of size 'length',
and does a pairwise multiplication, storing results into 'dest'.  It walks the
array with a stride of 4.  On each iteration, it does a vector load using the
SSE intrnsic '\_mm\_load\_ps', which loads 4 contiguous floats from 'src1' and 'src2'
into XMMx registers.  Then we multiply them via '\_mm\_mul\_ps' which is a 4-way
vector multiply (i.e. the multiplication for each pair occurs in parallel).
Lastly, we store the results back to the 'dest' array.  Note we naively assume
the array's size is a multiple of 4.

To use this routine, we just need to P/Invoke.  Well, sadly we also need to
do some tricky alignment since SSE demands 16 byte alignment.  As [I've written
before](http://www.bluebytesoftware.com/blog/PermaLink,guid,cbf30710-ff97-4bed-a336-e5aab3ef2eb7.aspx),
this isn't easy to acheive on the CLR.  I've used stack allocation to avoid
pinning the arrays, though clearly for large arrays this would easily lead to stack
overflow.  It's just for illustration.

```
using System;

unsafe class Program {
    [System.Runtime.InteropServices.DllImport("vecthelp.dll")]
    private extern static void VectMult(
        float * src1, float * src2, float * dest, int length);

    public static void Main()
    {
        const int vecsize = 1024 * 16; // 16KB of floats.

        float * a = stackalloc float[vecsize + (16 / sizeof(float)) - 1];
        float * b = stackalloc float[vecsize + (16 / sizeof(float)) - 1];
        float * c = stackalloc float[vecsize + (16 / sizeof(float)) - 1];

        // To use SSE, we must ensure 16 byte alignment.
        a = (float *)AlignUp(a, 16);
        b = (float *)AlignUp(b, 16);
        c = (float *)AlignUp(c, 16);

        // Initialize 'a' and 'b':
        for (int i = 0; i < vecsize; i++) {
            a[i] = i;
            b[i] = vecsize - i;
        }

        // Now perform the multiplication.
        VectMult(a, b, c, vecsize);

        ... do something with c ...
    }

    private static void * AlignUp(void * p, ulong alignBytes)
    {
        ulong addr = (ulong)p;
        ulong newAddr = (addr + alignBytes - 1) & ~(alignBytes - 1);
        return (void *)newAddr;
    }
}
```

I wish I could report some stellar perf numbers, to the tune of the vector version
being 4X faster than a non-vector equivalent.  Sadly the P/Invoke overheads
kill perf unless the array is unreasonably large.  Who needs to multiply two
16MB arrays of floats together?  Some people I'm sure, but not many.  If
the P/Invoke overheads are excluded, however, arrays as small as a few hundred elements
see 2X speedup.  And for larger arrays it hovers around 3X.

Clearly as future architectures offer more vector width, these speedups just increase.
And perhaps there will eventually be more incentive for native CLR support.
Just imagine if we had a 32-core system in which each core had a 16-way vector arithmetic
unit: that's 32X16 (512) degrees of parallelism if you can just subdivide the problem
appropriately.  GPUs, of course, already offer many-fold larger vector
width than SSE, which is one reason why GPGPU is attractive.  Maybe I'll
show how to write a DirectX pixel shader that adds two float arrays together in a
future post.

