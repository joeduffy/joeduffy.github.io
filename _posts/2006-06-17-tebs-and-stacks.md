---
layout: post
title: TEBs and stacks
date: 2006-06-17 12:48:13.000000000 -07:00
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
Ntdll exports an undocumented function from WinNT.h:

```
PTEB NtCurrentTeb();
```

This gives you access to the current thread's TEB (thread environment block), 
which is a per-thread data structure that holds things like a pointer to the SEH 
exception chain, stack range, TLS, fiber information, and so forth. This 
function actually returns you a PTEB, which is defined as \_TEB\*. \_TEB is an 
internal data structure defined in winternl.h, and consists of a bunch of byte 
arrays. You can cast this to PNT\_TIB (defined as \_NT\_TIB\*), which gives you 
access to the data in a strongly typed way. And \_NT\_TIB is a documented data 
structure, unlike \_TEB, meaning you can actually rely on it not breaking 
between versions of Windows.

For example, this code prints out the current thread's stack base and limit. The 
base is the start of the user-mode stack, and the limit is the last committed 
page, which grows as you use more stack:

```
PNT_TIB pTib = reinterpret_cast<PNT_TIB>(NtCurrentTeb());
printf("Base = %p, Limit = %p\r\n",
    pTib->StackBase, pTib->StackLimit);
```

There's a shortcut you can take. You can always find a pointer to the TEB in the 
register FS:[18h]:

```
PNT_TIB pTib;
_asm {
    mov eax,fs:[18h]
    mov pTib,eax
}
printf("Base = %p, Limit = %p\r\n",
    pTib->StackBase, pTib->StackLimit);
```

There's an even shorter shortcut you can take. You can actually find the base 
and limit in different segments of the FS register, FS:[04h] for the base and 
FS:[08h] for the limit:

```
void * pStackBase;
void * pStackLimit;
_asm {
    mov eax,fs:[04h]
    mov pStackBase,eax
    mov eax,fs:[08h]
    mov pStackLimit,eax
}
printf("Base = %p, Limit = %p\r\n",
    pStackBase, pStackLimit);
```

Unfortunately, the \_asm keyword is not supported on all architectures, so the 
above code is only guaranteed to work on x86 (e.g. the VC++ Intel Itanium 
compiler doesn't support it). Furthermore, the hardcoded offsets 04h and 08h are 
clearly wrong on 64-bit: you need more than 4 bytes to represent a 64-bit 
pointer. NtCurrentTeb hides all of this and uses whatever platform-specific 
technique is needed to retrieve the information.

Matt Pietrek's [1996](http://www.microsoft.com/msj/archive/S2CE.aspx) and 
[1998](http://www.microsoft.com/msj/0298/hood0298.aspx) Microsoft Systems 
Jounral articles are the best reference I could find on TEBs, aside from the 
[Windows 
Internals](http://www.amazon.com/exec/obidos/ASIN/0735619174/bluebytesoftw-20) 
book.

Believe it or not, this is useful information. I wrote some code recently that 
took a different code path based on whether it was writing to the stack or the 
heap, and using the TEB does the trick.

I have written about 7 pages on user-mode stacks in my upcoming concurrency 
book. This ranges from CLR stack frames to stack overflow to just how stacks 
work internally in Windows. I haven't found any book or resource that collects 
all of this information together in one place. It turns out that most developers 
don't need to worry about stacks at all, but this understanding is [crucial to 
moving forward to more advanced concurrency programming 
models](http://www.bluebytesoftware.com/blog/PermaLink,guid,db077b7d-47ed-4f2a-8300-44203f514638.aspx).

