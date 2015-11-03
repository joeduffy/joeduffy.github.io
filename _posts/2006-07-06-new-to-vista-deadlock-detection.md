---
layout: post
title: 'New to Vista: deadlock detection'
date: 2006-07-06 12:20:48.000000000 -07:00
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
As I mentioned in [a recent 
post](http://www.bluebytesoftware.com/blog/PermaLink,guid,17433c64-f45e-40f7-8772-dedb69ab2190.aspx), 
Windows Vista has new built-in support for deadlock detection. At the time, I 
couldn't find any publicly available documentation on this feature. Well, I just 
found it:

> [Wait Chain Traversal](http://windowssdk.msdn.microsoft.com/en-us/library/ms681622.aspx)
> Wait Chain Traversal (WCT) enables debuggers to diagnose application hangs 
> and deadlocks. A wait chain is an alternating sequence of threads and 
> synchronization objects; each thread waits for the object that follows it, 
> which is owned by the subsequent thread in the chain. [Read 
> More](http://windowssdk.msdn.microsoft.com/en-us/library/ms681622.aspx).

The new APIs 
[OpenThreadWaitChainSession](http://windowssdk.msdn.microsoft.com/en-us/library/ms680543.aspx), 
[CloseThreadWaitChainSession](http://windowssdk.msdn.microsoft.com/en-us/library/ms679282.aspx), 
and 
[GetThreadWaitChain](http://windowssdk.msdn.microsoft.com/en-us/library/ms679364.aspx) 
permit both asynchronous and synchronous detection and response. MSDN also has a 
[fairly detailed code 
sample](http://windowssdk.msdn.microsoft.com/en-us/library/ms681418.aspx) that 
uses the new APIs to print out the wait chain for all threads in a process.

