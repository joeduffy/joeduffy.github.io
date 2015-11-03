---
layout: post
title: Checking for sufficient stack space
date: 2006-07-15 12:39:43.000000000 -07:00
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
Stack overflow can be catostrophic for Windows programs. Some Win32 libraries 
and commercial components may or may not respond intelligently to it. For 
example, I know that, at least as late as Windows XP, a Win32 CRITICAL\_SECTION 
that has been initialized so as to never block can actually end up stack 
overflowing in the process of trying to acquire the lock. Yet MSDN claims it 
cannot fail if the spin count is high enough. A stack overflow here can actually 
lead to orphaned critical sections, deadlocks, and generally unreliable software 
in low stack conditions. The Whidbey CLR now does a lot of work to probe for 
sufficient stack in sections of code that manipulate important resources. And we 
pre-commit the entire stack to ensure that overflows won't occur due to failure 
to commit individual pages in the stack. If a stack overflow ever does occur, 
however, it's considered a major catastrophy--since we can't reason about the 
state of what native code may have done in the face of it--and therefore, the 
default unhosted CLR will fail-fast.

In some rare cases, it is useful to query for the remaining stack space on your 
thread, and change behavior based on it. It could enable you to fail gracefully 
rather than causing a stack overflow, possibly in Win32, causing the process to 
terminate.  A UI that needs to render some very deep XML tree, and does so using 
stack recursion, could limit its recursion or show an error message based on 
this information, for example.  It could decide that it needs to spawn a new 
thread with a larger stack to perform the rendering.  Or it may just be a handy 
way to log an error message during early testing so that the developers can fine 
tune the stack size or depend less heavily on stack allocations to get the job 
done.

I've previously mentioned that the TEB has a StackBase and StackLimit, and that 
it [can be dynamically queried using the ntdll!NtCurrentTeb 
function](http://www.bluebytesoftware.com/blog/PermaLink,guid,eb98baaf-0837-498d-a1e7-e4e16788f912.aspx). 
Unfortunately, the StackLimit is only updated as you actually touch pages on the 
stack, and thus it's not a reliable way to find out how much uncommitted stack 
is left. The CLR uses kernel32!VirtualAlloc to commit the pages, not by actually 
moving the guard page, so StackLimit is not updated as you might have expected. 
There's an undocumented field, DeallocationStack, at 0xE0C bytes from the 
beginning of the TEB that will give you this information, but that's 
undocumented, subject to change in the future, and is too brittle to rely on.

The RuntimeHelpers.ProbeForSufficientStack function may look promising at first, 
but it won't work for this purpose. It probes for a fixed number of bytes (48KB 
on x86/x64), and if it finds there isn't enough, it induces the normal CLR stack 
overflow behavior.

The good news is that the kernel32!VirtualQuery function will get you this 
information. It returns a structure, one field of which is the AllocationBase 
for the original allocation request. When Windows reserves your stack, it does 
so as one contiguous piece of memory. The MM remembers the base address supplied 
at creation time, and it turns out that this is the "end" of your stack 
(remember, the stack grows downward). With a little P/Invoke magic, it's simple 
to create a CheckForSufficientStack function using this API. Our new function 
takes a number of bytes as an argument and returns a bool to indicate whether 
there is enough stack to satisfy the request:

```
public unsafe static bool CheckForSufficientStack(long bytes) {
    MEMORY_BASIC_INFORMATION stackInfo = new MEMORY_BASIC_INFORMATION();

    // We subtract one page for our request. VirtualQuery rounds UP to the next page.
    // Unfortunately, the stack grows down. If we're on the first page (last page in the
    // VirtualAlloc), we'll be moved to the next page, which is off the stack!  Note this
    // doesn't work right for IA64 due to bigger pages.
    IntPtr currentAddr = new IntPtr((uint)&stackInfo - 4096);

    // Query for the current stack allocation information.
    VirtualQuery(currentAddr, ref stackInfo, sizeof(MEMORY_BASIC_INFORMATION));

    // If the current address minus the base (remember: the stack grows downward in the
    // address space) is greater than the number of bytes requested plus the reserved
    // space at the end, the request has succeeded.
    return ((uint)currentAddr.ToInt64() - stackInfo.AllocationBase) >
        (bytes + STACK_RESERVED_SPACE);
}

// We are conservative here. We assume that the platform needs a whole 16 pages to
// respond to stack overflow (using an x86/x64 page-size, not IA64). That's 64KB,
// which means that for very small stacks (e.g. 128KB) we'll fail a lot of stack checks
// incorrectly.
private const long STACK_RESERVED_SPACE = 4096 * 16;

[DllImport("kernel32.dll")]
private static extern int VirtualQuery (
    IntPtr lpAddress,
    ref MEMORY_BASIC_INFORMATION lpBuffer,
    int dwLength);

private struct MEMORY_BASIC_INFORMATION {
    internal uint BaseAddress;
    internal uint AllocationBase;
    internal uint AllocationProtect;
    internal uint RegionSize;
    internal uint State;
    internal uint Protect;
    internal uint Type;
}
```

If this returns true, you can be guaranteed that an overflow will not occur. 
Well, modulo stack guarantee issues, that is...

Notice that we have to consider some amount of reserved space at the end of the 
stack. Platforms typically reserve a certain amount to ensure custom stack 
overflow processing can be triggered. Windows actually reserves a few pages at 
the end of the stack for this reason. If, after a stack overflow occurs, a 
double stack overflow is triggered (that is, stack overflow handling actually 
exceeds these pages), Windows takes over and kills the process. The CLR prefers 
to initiate a controlled shut-down: telling the host, if any, and fail-fasting 
otherwise. This means it needs to reserve even more than Windows does 
automatically. The kernel32!SetThreadStackGuarantee can be used for this. In any 
case, we need to consider that when looking for enough stack space in our 
function. The code above assumes 16 4KB pages are required; this is more than is 
typically needed, so it may lead to false positives (but we hope no false 
negatives). Also note the program above is very x86/x64-specific, and won't work 
reliably on IA-64: it hard-codes a 4KB page size. It's a trivial excercise to 
extend this to use information from kernel32!GetSystemInfo to use the right page 
size dynamically.

As an example, check out this code:

```
static unsafe void Main() {
    Test(8*1024, 8*1024, true);
    Test(0, (960*1024) + (8*1024), false);
    Test(960*1024, 8*1024, false);
}

static unsafe void Test(int eatUp, long check, bool expect) {
    byte * bb = stackalloc byte[eatUp];
    Console.WriteLine("eatUp: {0}, check: {1}: {2}",
        eatUp, check,
        CheckForSufficientStack(check) == expect ?
        "SUCCESS" : "FAIL");
}
```

As I've [described 
previously](http://www.bluebytesoftware.com/blog/PermaLink,guid,4c0e068c-f7d7-4979-86b1-688b5a29c115.aspx), 
the stack size can depend on the EXE PE file or parameters passed when creating 
a thread. This example assumes a 1MB stack size.

