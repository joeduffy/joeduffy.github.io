---
layout: post
title: A new SysInternals tool for printing multicore architecture information
date: 2008-11-02 23:36:22.000000000 -08:00
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
A few months back, while writing my [new book](http://www.amazon.com/exec/obidos/ASIN/032143482X/bluebytesoftw-20),
I whipped together a tool to dump information about your processor layout using the
[GetLogicalProcessorInformation](http://msdn.microsoft.com/en-us/library/ms683194.aspx)
function from C#.  You can find the code snippet in Chapter 5, Advanced Threads,
of my book.  (A developer on the Windows Core OS team, Adam Glass, had
also written a similar tool in C++.)  I will be posting code to the [companion
site](http://www.bluebytesoftware.com/books/winconc/winconc_book_resources.html)
for my book in the coming weeks, at which point you can easily get your hands on
it.

Anyway, I sent the code to Mark Russinovich suggesting it might make a useful SysInternals
tool, and he agreed.  Now it's up on microsoft.com for download, under the name
of Coreinfo: [http://technet.microsoft.com/en-us/sysinternals/cc835722.aspx](http://technet.microsoft.com/en-us/sysinternals/cc835722.aspx).
When run, Coreinfo pretty prints information about the mapping from cores
to sockets, cores to NUMA nodes, and what kinds of caches are shared on the machine.
Particularly for somebody like me who is always running code on different kinds of
machines -- and given that parallel code performance heavily depends on memory hierarchy
-- I've found this tool to be invaluable and very helpful.  Enjoy.

