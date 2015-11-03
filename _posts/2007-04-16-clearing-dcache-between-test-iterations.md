---
layout: post
title: Clearing Dcache between test iterations
date: 2007-04-16 18:11:02.000000000 -07:00
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
To gather meaningful performance metrics, it's usually a good idea to run several
iterations of the same test, averaging the numbers in some way, to eliminate noise
from the results.  This is true of sequential and fine-grained parallel performance
analysis alike.  Though it's clearly important for sequential code too, data
locality can add enough noise to your parallel tests that you'll want to do something
about it.  For example, if iteration #1 enjoys some form of temporal locality
left over from iteration #0, then all but the first iteration would receive an unfair
advantage.  This advantage isn't usually present in the real world -- most library
code isn't called over and over again in a tight loop -- and could cause test
results to appear rosier than what customers will actually experience.  Therefore,
we probably want to get rid of it.

To eliminate this noise, we can clear the Dcaches (data caches) of all processors
used to run tests before each iteration.  How do you do that?  Well...

Intel offers a WBINVD instruction to clear a processor's Dcache, but sadly it's a
privileged instruction and there's no way to get at it from user-mode.  So that's
a no-go for most Windows programmers.  There's also a Win32 function to clear
a processor's Icache, but this doesn't work for Dcaches, which is what we're after,
so we're out of luck there too.

Instead, we can implement a really low tech solution.  Take some random data,
sized big enough to fill a processor's L2 cache, and read the whole thing from each
processor whose cache we wish to clear before each iteration.  This will
evict all of the existing lines in the caches that could be left over from previous
iterations.  All of the new lines will be brought in as shared, and, while they
will be evicted when we start using real data in the query, this effectively simulates
a cold cache.  Here's an example of this:

```
const int s_garbageSize = 1024 * 1024 * 64; // 64MB.
static IntPtr s_garbage =
    System.Runtime.InteropServices.Marshal.AllocHGlobal(s_garbageSize);

unsafe static void ClearCaches()
{
    for (int i = 0; i < Environment.ProcessorCount; i++) {
        SetThreadAffinityMask(GetCurrentThread(), new IntPtr(1 << i));
        long * gb = (long *)s\_garbage.ToPointer();

        for (int j = 0; j < s_garbageSize / sizeof(long); j++) {
            long x = *(gb + j); // Read the line (shared).
            long y = Math.Max(Math.Min(x, 0L), 0L); // Prevent optimizing away the read.
        }
    }
    SetThreadAffinityMask(GetCurrentThread(), new IntPtr(0));
}

[DllImport("kernel32.dll")]
static extern IntPtr GetCurrentThread();
[DllImport("kernel32.dll")]
static extern IntPtr SetThreadAffinityMask(IntPtr hThread, IntPtr dwThreadAffinityMask);
```

This clearly isn't the most efficient implementation.  On multi-core architectures,
some cores are apt to share some levels of cache, so with the above approach we'll
end up doing duplicate (and wasted) work.  And few processors on the market have
64MB of L2 cache -- I've just chosen a reasonable number that's bigger than most
processors -- so we could try to be more precise there too.  You could use the
GetLogicalProcessorInformation API, new to Windows Server 2003 (server) and Vista
(client), if you really wanted to be a stud.  In any case, this does the trick.

