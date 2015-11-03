---
layout: post
title: New Vista concurrency features
date: 2006-06-21 23:44:52.000000000 -07:00
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
Windows Vista has some great new features for concurrent programming. For those 
of you still writing native code, it's worth checking them out. For those 
writing managed code, we have a bunch of great stuff in the pipeline for the 
future, but unfortunately you'll have to wait. Or convert (back) to the dark 
side.

The Vista features include:

1. Reader/writer locks. The kernel32 function InitializeSRWLock takes a pointer 
   to a SRWLOCK structure, just like InitializeCriticalSection, and initializes 
   it. AcquireSRWLockExclusive and AcquireSRWLockShared acquire the lock in the 
   specific mode and ReleaseSRWLockXXX releases the lock. This is a "slim" RW lock, 
   meaning it's actually comprised of a pointer-sized value, and is ultra-fast and 
   lightweight, much like existing Win32 CRITICAL\_SECTIONs. It should be about the 
   cost of a single interlocked operation to acquire. E.g.

```
SRWLOCK rwLock;
InitializeSRWLock(&rwLock);
AcquireSRWLockShared(&rwLock);
// ... shared operations ...
ReleaseSRWLockShared(&rwLock);
```

2. Condition variables. These integrate with RW locks and critical sections, 
   enabling you to do essentially what you can already do with 
   Monitor.Wait/Pulse/PulseAll. InitializeConditionVariable takes a pointer to a 
   CONDITION\_VARIABLE and initializes it. SleepConditionVariableCS and 
   SleepConditionVariableSRW release the specified lock (either CRITICAL\_SECTION 
   or SRWLOCK) and wait on the condition variable as an atomic action. When the 
   thread wakes up again, it immediately attempts to acquire the lock it released 
   during the wait. WakeConditionVariable wakes a single waiter for the target 
   condition and WakeAllConditionVariable wakes all waiters, much like Pulse and 
   PulseAll. E.g.

```
Buffer \* pBuffer = ...;
PCRITICAL\_SECTION pCsBufferLock = ...;
PCONDITION\_VARIABLE pCvBufferHasItem = ...;

// Producer code:
EnterCriticalSection(pCsBufferLock);
while (pBuffer->Count == 0) {
    SleepConditionVariableCS(pCvBufferHasItem, pCsBufferLock, INFINITE);
}
// process item...
LeaveCriticalSection(pCsBufferLock);

// Consumer code:
EnterCriticalSection(pCsBufferLock);
pBuffer->Put(NewItem());
LeaveCriticalSection(pCsBufferLock);
WakeAllConditionVariable(pCvBufferHasItem);
```

   More details on condition variables can be [found on 
   MSDN](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/using_one-time_initialization.asp).

3. Lazy/one-time initialization. This allows you to write lazy allocation 
   without fully understanding memory models and that sort of nonsense. The new 
   APIs in kernel32, InitXXX, support both synchronous and asynchronous 
   initialization. These have some amount of overhead for the initialization case 
   due to the use of a callback, but in general this will be fast enough for most 
   lazy initialization and much less error prone. Herb Sutter has proposed a 
   similar construct for the VC++ language, and to be honest I wish we had this 
   built-in to C# too.  [See the MSDN docs for an example and more 
   details.](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/using_one-time_initialization.asp)

4. An overhauled thread pool API. The Windows kernel team has actually rewritten 
   the thread pool from the ground up for this release. Their APIs now support 
   creating multiple pools per process, waiting for queues to drain or a specific 
   work item to complete, cancellation of work, cancellation of IO, and new cleanup 
   functionality, including automatically releasing locks. It also has substantial 
   performance improvements due to a large portion of the code residing in 
   user-mode instead of kernel-mode. MSDN has [a comparison between the old and new 
   APIs](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/thread_pool_api.asp).

5. A bunch of new [InterlockedXXX 
   variants](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/interlocked_variable_access.asp).

6. Application deadlock detection. This is separate from the existing Driver 
   Verifier ability to diagnose deadlocks in drivers. This capability integrates 
   with all synchronization mechanisms, from CRITICAL\_SECTION to SRWLOCK to Mutex, 
   and keys off of any calls to XXXWaitForYYYObjectZZZ. Unfortunately, I think this 
   is new to the latest Vista SDK, and thus there isn't a lot of information 
   available publicly. This could probably make a good future blog post if there's 
   interest.

Have fun with this stuff, of course. But be careful. Don't poke an eye out.

