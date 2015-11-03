---
layout: post
title: Ignoring lock acquisition during (native) shutdown
date: 2006-10-14 22:30:11.000000000 -07:00
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
When a Windows process shuts down, one of the very first things to happen is the
killing of all but one thread. This sole remaining thread is then responsible for
performing shutdown duties, both in kernel and in user mode, including executing
the appropriate DLL\_PROCESS\_DETACH notifications for the DLLs loaded in the process.
A great treatise on shutdown and the associated subtleties can be found on, of course,
[Chris Brumme's weblog](http://blogs.msdn.com/cbrumme/archive/2003/08/20/51504.aspx).

It's entirely possible that at least one of those threads was executing under the
protection of one or more critical sections when the shutdown was initiated. Since
threads are killed in a fairly hostile manner (not like, say, asynchronous thread
aborts which are at least a little less rude, even the so-called rude version of
a thread abort), these critical sections will have been left in an acquired state.
And any associated program state is apt to be left very inconsistent indeed.
Worse, you might imagine that if the shutdown thread later needed to acquire one
of those oprhaned critical sections, the shutdown process would deadlock.

Although that's intuitively what you may expect to occur, the OS actually does
something a little funny during shutdown to avoid this problem. It effectively ignores
calls to kernel32!EnterCriticalSection and kernel32!LeaveCriticalSection. A call
to enter a CRITICAL\_SECTION will first check to see if it's owned by another thread
and, if it is, the section is automatically re-initialized before acquiring
it. The result? If one of the previously killed threads, t0, held on to critical
section A, for instance, and had partially modified some state protected by it just
before the shutdown began, then the shutdown thread, t1, is permitted to freely
"acquire" critical section A too, even though it was found as being officially
owned by t0.

This means that code running during shutdown must tolerate any corrupt state that
may have been left behind as a result. For obvious reasons, this is quite difficult. It's
especially difficult if you write some code that somebody believes they can call during
shutdown without you having gone through that thoughts exercise. The multi-threaded
CRT uses locks internally for malloc/free, for instance, and reportedly cannot
reliably tolerate process exit code-paths, which means can't even safely rely on
memory allocation and freeing during process exit without spurious AVs, heap corruption,
and other bad things. Other services are obviously apt to suffer from similar
problems, particularly if they comprise of arbitrary application logic. You simply
can't rely on invariant safe-points holding at lock boundaries when a shutdown is
in process.

Mutexes also enjoy this same "weakening" behavior, at least on Windows XP. This policy
doesn't, however, apply to waits on other kernel synchronization objects, like
events and semaphores. If you rely on these during shutdown you're just asking
for a deadlock. Actually if you are regularly using any sort of synchronization in
your DllMain—including acquiring critical sections and mutexes—you're asking
for loads of trouble. Shutdown callbacks run under the protection of the OS loader
lock, demanding extreme care, but that's [another topic altogether](http://blogs.msdn.com/oldnewthing/archive/2004/01/28/63880.aspx).

Here is a sample VC++ program that shows off this behavior. We declare a bunch of
code in the DllMain: process attach initializes a CRITICAL\_SECTION and a mutex,
and then detach attempts to acquire them. We then define an exported function,
GetAndBlock, that acquires the synchronization objects and sleeps for a long
time:

```
#include <stdio.h>
#include <windows.h>

CRITICAL_SECTION g_cs;
HANDLE g_mutex;

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpReserved)
{
    switch (fdwReason) {
        case DLL_PROCESS_ATTACH:
            InitializeCriticalSection(&g_cs);

            g_mutex = CreateMutex(NULL, FALSE, NULL);
            break;
        case DLL_PROCESS_DETACH:
            printf("%x: Acquiring g_cs during shutdown...", GetCurrentThreadId());
            EnterCriticalSection(&g_cs);

            printf("success.\r\n");

            printf("%x: Acquiring g_mutex during shutdown...", GetCurrentThreadId());
            WaitForSingleObject(g_mutex, INFINITE);
            printf("success.\r\n");

            DeleteCriticalSection(&g_cs);

            CloseHandle(g_mutex);

            break;
    }

    return TRUE;
}

__declspec(dllexport) DWORD WINAPI GetAndBlock(LPVOID lpParameter)
{
    // Acquire the mutual exclusion locks.
    EnterCriticalSection(&g_cs);
    WaitForSingleObject(g_mutex, INFINITE);

    printf("%x: g_cs and g_mutex acquired.\r\n", GetCurrentThreadId());

    // And just wait for a little while...
    SleepEx(25000, TRUE);

    return 0;
}
```

And finally we have an EXE that just invokes GetAndBlock and initiates a process
shutdown on separate threads. The result is that the shutdown thread acquires the
synchronization objects which the GetAndBlock thread currently has ownership of. Post
Windows 95, the shutdown thread is always the thread that initiated the shutdown,
whereas before that it was (seemingly) chosen at random; so when run on a modern
OS at least, this sample is guaranteed to demonstrate the desired behavior:

```
#include <windows.h>

DWORD WINAPI GetAndBlock(LPVOID lpParameter);

int main()
{
    HANDLE hT1 = CreateThread(NULL, 0, &GetAndBlock, NULL, 0, NULL);

    SleepEx(100, TRUE);
    ExitProcess(0);
}
```

The results of running are a little non-eventful:

```
C:\...>shutdown.exe
664: g_cs and g_mutex acquired.
d18: Acquiring g_cs during shutdown...success.
d18: Acquiring g_mutex during shutdown...success.
```

As expected, no hangs occur. If you want to see what happens when a hang does happen,
just replace CreateMutex with CreateEvent. It's not pretty.

_Update 10/17/2006: Thanks to Jan Kotas for pointing out that the multi-threaded
CRT is actually not safe from the sort of issues I talk about in this article. I
wasn't able to get it to happen in a test program--one of the great things about
repro'ing race conditions :)--but have fixed that part up._

