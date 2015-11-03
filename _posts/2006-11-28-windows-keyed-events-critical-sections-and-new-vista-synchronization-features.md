---
layout: post
title: Windows keyed events, critical sections, and new Vista synchronization features
date: 2006-11-28 21:32:46.000000000 -08:00
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
There's surprisingly little information out there on Windows keyed events.
That's probably because the feature is hidden inside the OS, not exposed publicly
through the Windows SDK, and is used only by a small fraction of kernel- and user-mode
OS features.  The Windows Internals book makes brief mention of them, but only
in passing on page 160.  Since keyed events have been revamped markedly for
Vista, a quick write up on them felt appropriate.  I had the pleasure to chat
at length today with the developer who designed and implemented the feature back
in Windows XP.  (I typically try to get work done during the day, but it
seems the whole Microsoft campus was offline, aside from the two of us, due to
the 1 or 2 inches of snow we received last evening).  I doubt much of this will
make it into my book, since knowing it all won't necessarily help you write better
concurrent software.

First here's the quick backgrounder on why keyed events were even necessary.
Before Windows 2000, critical sections, when initialized, were truly initialized.
That meant their various dynamically allocated blobs of memory were allocated, contained
the right bit patterns, and also that the per-section auto-reset event that is used
to block and wake threads under contention was allocated and ready.  Unfortunately,
there are a finite number of kernel object HANDLEs per process, of which auto-reset
events consume one, and each object consumes some amount of non-pageable pool memory.
It also turns out lots of code uses critical sections.  Around the Windows 2000
time frame, a lot more people were writing multithreaded code, primarily for server
SMP programs.  It's relatively common now-a-days to have hundreds or thousands
of them in a single process.  And many critical sections are used only occasionally
(or never at all), meaning the auto-reset event often isn't even necessary!
Aside from the auto-reset event, the entire critical section is pageable and has
no impact on a fixed size resource.

This was a problem, and had big scalability impacts.  So starting with Windows
2000, the kernel team decided that allocation of the event would be delayed until
it's first needed.  That means EnterCriticalSection had to, in response to
the first contended acquire, allocate the event.  But there's a problem with
this.  If memory is low, or the number of HANDLEs in the process had been exhausted,
this lazy allocation would actually fail.  Suddenly EnterCriticalSection, which
would never have failed previously (stack overflow aside), could throw an exception.
What's worse, you couldn't really recover from these exceptions: the CRITICAL\_SECTION
data structure was left in an unusable and damaged state.  But wait, it gets
worse.  I'm told there was a sizeable cleanup initiated that involved filing
many, many bugs to fix code that used EnterCriticalSection throughout the Windows
and related code-bases.  Unfortunately, then people realized that LeaveCriticalSection
could also fail under some even more obscure circumstances.  (If EnterCriticalSection
fails, throwing an out of memory exception, the subsequent LeaveCriticalSection would
see the damaged state and think it could help out by allocating the event.
This too could fail, causing even more corruption.)  What to do?  Wrap
each call to EnterCriticalSection AND LeaveCriticalSection in its own separate \_\_try/\_\_except
clause?  And do precisely what in response, since the data structure was completely
hosed anyway?

The bottom line was that no human being could possibly write reliable software using
critical sections.  Terminating the process, or isolating those bits of code
that used such a damaged critical section somehow, were the only intelligible responses.
Most of Microsoft's software, including the CRT and plenty of important applications,
would probably not do anything, and remain busted.

Still, the people responsible for the original change believed strongly that the
impacts to reliability were the lesser of two evils: that limiting Windows scalability
so fundamentally was a complete non-starter.  As a short-term solution, then,
InitializeCriticalSectionAndSpinCount was hacked so that passing a dwSpinCount argument
with its high-bit set, e.g. InitializeCriticalSectionAndSpinCount(&cs, 0x80000000
| realSpinCount), would revert to the pre-Windows 2000 behavior of pre-allocating
the event object.  No longer would low resources possibly cause exceptions out
of EnterCriticalSection and LeaveCriticalSection.  But all that code written
to use the ordinary InitializeCriticalSection API was still vulnerable.  And
this just pushed the fundamental reliability vs. scalability decision back onto the
poor developer.  What a horrible choice to have to make.

This is when keyed events were born.  They were added to Windows XP as a new
kernel object type, and there is always one global event \KernelObjects\CritSecOutOfMemoryEvent,
shared among all processes.  There is no need for any of your code to initialize
or create it—it's always there and always available, regardless of the amount
of resources on the machine.  Having it there always adds a single HANDLE per
process, which is a very small price to pay for the benefit that comes along with
it.  If you dump the handles with !handle in WinDbg, you'll always see one
of type KeyedEvent.  Well, what does it do?

A keyed event allows threads to set or wait on it, just like an ordinary event.
But having just a single, global event would be pretty useless, given that we'd
like to somehow solve the original critical section problem, which effectively requires
a single event per critical section.  Here's where the ingenuity arises.
When a thread waits on or sets the event, they specify a key.  This key is just
a pointer-sized value, and represents a unique identifier for the event in question.
When a thread sets an event for key K, only a single thread that has begun waiting
on K is woken (like an auto-reset event).  Only waiters in the current process
are woken, so K is effectively isolated between processes although there's a global
event.  K is most often just a memory address.  And there you go: you have
an arbitrarily large number of events in the process (bounded by the addressable
bytes in the system), but without the cost of allocating a true event object for
each one.

By the way, if N waiters must be woken, the same key N is set multiple times, meaning
for manual-reset-style sets, the list of waiters somehow needs to be tracked.
(Although not an issue for critical sections, this comes up for SRWLs, noted below.)
This gives rise to a subtle corner case: if a setter finds the wait list associated
with K to be empty, it must wait for a thread to arrive.  Yes, that means the
thread setting the event can wait too.  Why?  Because it's just how keyed
events work; without it, there would be extra synchronization needed to ensure a
waiter didn't record that it was about to wait (e.g. in the critical section bits),
the setter to see this and set the keyed event (and leave), and lastly the waiter
to actually get around to waiting on the keyed event.  This would lead to a
missed pulse, and possibly deadlock, if it weren't for the current behavior.

So you can probably imagine how this solves the original problem.  When a critical
section finds that it can't allocate a dedicated event due to low resources, it
will just wait and set the keyed event, using the critical section's address in
memory as the key K.  You might think: well, gosh, with this nifty new keyed
events thingamajiggit, why didn't they get rid of per-critical section events entirely?
I did at least.

There are admittedly some drawbacks to keyed events.  First and foremost, the
implementation in Windows XP was not the most efficient one.  It maintained
the wait list as a linked list, so finding and setting a key required an O(n) traversal.  Here
n is the number of threads waiting globally in the system.  The head of
the list is in the keyed event object itself, and entries in the linked list are
threaded by reusing a chunk of memory on the waiting thread's ETHREAD for
forward- and back-links—cleverly avoiding any dynamic allocation whatsoever (aside
from the ETHREAD memory which is already allocated at thread creation time).
But given that the event is shared physically across the entire machine, depending
on a linked list like this for all critical sections globally would not have scaled
very well at all.  And this sharing can also result in contention that is difficult
to explain, since threads have to use synchronization when accessing the list.

> _[**Update: 2/2/2007** : Neill, the dev I mentioned at the outset, just emailed
me a correction to my original write-up.  I had incorrectly stated that the
forward- and back-links happen through TEB memory (which is user-mode); they actually
use ETHREAD memory.]_

But keyed events have improved quite a bit in Windows Vista.  Instead of using
a linked list, they now use a hash-table scheme, trading the possibility of hash
collisions (and hence some amount of contention unpredictability) in favor of improved
lookup performance.  This improvement was good enough to use them as the sole
event mechanism for the new "slim" reader/writer locks (SRWLs), condition variables,
and one-time initialization APIs.  Yes, you heard that right…  None of
these new features use traditional events under the covers.  They use keyed
events instead.  This is in part why the new SRWLs are super light-weight, taking
up only a pointer-sized bit of data and not requiring any event objects whatsoever.
Critical sections still use auto-reset events, but I understand that this is primarily
for AppCompat reasons.  It's admittedly nice when debugging to be able to
grab hold of the HANDLE for the internal event and dump information about it, something
you can't do with keyed events, and plenty of customers depend on this information
being there.

The improvement that keyed events offer to reliability and the alleviation of HANDLE
and non-pageable pressure is overall a very welcome one, and one that will undoubtedly
pave the way for new synchronization OS features in the future.  I personally
hope that one day they are made available to user-mode code through the Windows SDK.

