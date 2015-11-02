---
layout: post
title: Modifying stack reserve and commit sizes on existing binaries
date: 2006-07-03 17:12:22.000000000 -07:00
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
When threads are created on Windows, the caller of the [CreateThread 
API](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/createthread.asp) 
has the option to supply stack reserve/commit sizes. If not specified--i.e. the 
stack size parameter is 0--Windows just uses the sizes found in the PE header of 
the executable. Microsoft's linkers by and large use 1MB reserve/2 page commit 
by default, although most let you override this (e.g. [LINK.EXE's 
/STACK:xxx,[yyy]](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/vccore/html/_core_.2f.stack_linker.asp) 
option and [VC++'s CL.EXE /F 
xxx](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/vccore98/html/_core_.2f.f.asp)). 
The CLR always pre-commits the entire stack for managed threads.

You'll often find situations where a program has been deployed and starts 
running out of stack space. Many times this is just a bug. But this also often 
happens when more data is fed to the application than was used during testing, 
causing deeper recursion or larger stack allocated data structures than is 
typical. ASP.NET, for example, uses 256KB stack sizes by default to minimize 
memory pressure due to large numbers of concurrent requests. It does this by 
setting the PE header's reserve size to 256KB, and relying on the fact that the 
CLR thread-pool creates its threads with a default stack size. I think WSDL.EXE 
also uses a 256KB stack to make startup faster. I was recently chatting with a 
customer who kept stack overflowing WSDL.EXE due to an extremely large XML file 
they were trying to parse (recursive XML parsers tend to use very deep stacks 
anyhow).

If you don't have the source code for the program in question, you can always 
use the [EDITBIN.EXE 
utility](http://msdn2.microsoft.com/en-us/library/xd3shwhf.aspx) that comes in 
the VC++ SDK to change the PE header's default stack values. Say you have an 
executable, FOO.EXE, that has been deployed and suddenly starts running out of 
stack space. You know it's not a bug -- it simply needs to consume more stack 
than was originally reserved. Running `EDITBIN.EXE FOO.EXE /STACK:2097152`, for 
example, changes the default stack to 2MB. This of course only works for threads 
that are created using the default stack size; if they override it explicitly, 
changing the PE header has no effect. This always works for threads in the CLR's 
thread pool.

**_Warning_** : Using EDITBIN.EXE like this can invalidate support and servicing 
warranties on commercial executables. You might want to use this approach for 
workarounds in your own organization or for personal use, but I don't recommend 
it for, say, Microsoft shipped binaries. There's no guarantee things will 
continue working as you'd hope, especially if you're shrinking the stack size 
instead of growing it. And next time you download an update from the Windows 
Update server, you may find that you've accidentally hosed your machine 
(although it honestly seems rather unlikely).

