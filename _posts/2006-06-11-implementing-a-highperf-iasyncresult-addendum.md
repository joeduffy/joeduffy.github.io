---
layout: post
title: 'Implementing a high-perf IAsyncResult: addendum'
date: 2006-06-11 20:45:34.000000000 -07:00
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
After posting my last article on creating a lazy allocation IAsyncResult, I 
received a few mails on the ordering of the completion sequence. It was wrong 
and has been updated. Thanks to [those who pointed this 
out](http://pluralsight.com/blogs/dbox/).

I used the following incorrect ordering: 1) set IsCompleted to true, 2) invoke 
the callback, and 3) signal the handle.

This can lead to deadlocks if the callback waits on the handle. My 
implementation carefully avoided EndXxx-induced deadlocks (by checking 
IsCompleted before waiting on the handle), but if the callback directly 
WaitOne's on the IAsyncResult.AsyncWaitHandle property, the callback will of 
course deadlock. Directly accessing the handle might be attractive to the 
callback author, especially for higher level orchestration via WaitAny and 
WaitAll. So it's probably something we'd like to support. One way to avoid this 
is to invoke the callback asynchronously with BeginInvoke, but a better solution 
is to use the correct ordering instead.

The correct ordering is: 1) set IsCompleted to true, 2) signal the handle, and 
3) invoke the callback.

The first version I wrote had the correct ordering, since that seemed to be the 
logical choice. Unfortunately, the [Framework Design 
Guidelines](http://www.amazon.com/exec/obidos/redirect?link_code=ur2&tag=bluebytesoftw-20&camp=1789&creative=9325&path=http%3A%2F%2Fwww.amazon.com%2Fgp%2Fproduct%2F0321246756%2F) 
lists the steps in the wrong order, which led me down that path. I've let 
[Brad](http://blogs.msdn.com/brada/) and 
[Krzys](http://blogs.msdn.com/kcwalina/) about this. A customer who read my blog 
actually mailed Brad about this error too, just about simultaneously. There may 
be rationale behind this, but we've used the correct ordering in the file and 
network IO APIs since V1.0 so I think it's just wrong.

It's worth pointing out that the network classes already use a lazy allocation 
scheme very similar to the one I wrote about. Check out the 
System.Net.LazyAsyncResult internal type in System.dll. I'm advocating for 
moving file IO onto the same plan in the next release of the Framework. We'll 
see how it turns out.

Lastly, some might notice I originally said this would be a two part series. 
Well, I wrote a whole bunch of code to implement a sophisticated LRU-based 
resurrection caching scheme--to avoid allocating IAsyncResults every time--and 
then realized that my example doesn't do anything expensive on IAsyncResult 
creation that would warrant such a thing. The result? It was actually slower 
than the ordinary lazy version I posted a couple weeks back. I think the 
techniques I used are interesting nonetheless, so I am going to try and rework 
the example to incorporate some expensive buffer management, and then see where 
I stand. But I'm not promising anything just yet. And this was a great reminder 
that solving actual profiled problems is always more worthwhile than solving 
perceived, yet unmeasured, non-problems.

