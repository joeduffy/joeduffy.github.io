---
layout: post
title: CLR thread pool injection, stuttering problems
date: 2006-07-08 21:18:26.000000000 -07:00
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
The CLR thread pool is a very useful thing. It amortizes the cost of thread 
creation and deletion--which, on Windows, are not cheap things--over the life of 
your process, without you having to write the hairy, complex logic to do the 
same thing yourself. The algorithms it uses have been tuned over three major 
releases of the .NET Framework now. Unfortunately, it's still not perfect. In 
particular, it stutters occasionally.

As I've [hinted at 
before](http://www.bluebytesoftware.com/blog/PermaLink,guid,ed78e4f1-fcaa-47a8-920b-804fe217c9d3.aspx), 
we have a lot of work actively going on right now that we hope to show up over 
the course of the next couple CLR versions (keep an eye on those CTPs!). This 
may include vastly improved performance for work items and IO completions, 
significantly reducing the overhead of using our thread pool (in some cases to 
as little as ~1/8th of what it is today), eliminating accidental deadlocks due 
to lots of blocked thread pool workers, and a slew of useful new features 
(prioritization, isolation, better debugging, etc.).

One silly thing our thread pool currently does has to do with how it creates new 
threads. Namely, it severely throttles creation of new threads once you surpass 
the "minimum" number of threads, which, by default, is the number of CPUs on the 
machine. We limit ourselves to at most one new thread per 500ms once we reach or 
surpass this number. This can be pretty bad for some workloads, most notable 
those that are "bursty"; i.e. those that exhibit interspersed inactive and 
active periods rather sporadically and unpredictably. ASP.NET is a great example 
of an environment in which this frequerntly happens. Here's an illustration:

1. Imagine we have a 4 CPU web server. The "minimum" thread count used thus 4 
   (assuming the default).

2. The web server has just started up.

3. 16 new requests come in within a short period of time.

4. Ther CLR quickly create 4 thread pool threads to service the first 4 
   requests. Because we don't want to add any more for another 500ms, the other 
12 requests sit in the queue.

5. The 4 thread pool threads are running some arbitrary web page response. 
   Imagine the response generation code does some type of database query that 
   takes 4 seconds to complete. (This is a strong argument for using ASP.NET 
   asynchronous pages (see 
   [http://msdn.microsoft.com/msdnmag/issues/05/10/WickedCode/](http://msdn.microsoft.com/msdnmag/issues/05/10/WickedCode/)) 
   -- in which case, the 4 thread pool threads would free up to execute 4 new 
   requests almost immediately -- or perhaps simply rearchitecting the seemingly 
   poor database interaction, but ignore this for now.)

6. After 500ms, a new thread pool thread is created, and the 5th request is 
   serviced.

7. We now wait another 500ms to add another thread, service, the next request, 
   and so forth.

If the server has a constant load, eventually the pool will become "primed." But 
if a burst of work is followed by an inactive period of time, the threads in the 
thread pool start timing out waiting for new work, and eventually will retire 
themselves, until the pool shrinks back to the minimum. Imagine that this 
happens and then a bunch of new work arrives. Oops. This can clearly lead to 
some nasty scalability nightmares. KB article 821261, [Contention, poor 
performance, and deadlocks when you make Web service requests from ASP.NET 
applications](http://support.microsoft.com/?id=821268), describes this problem 
among others.

To "fix" this we added the ability in v1.1 to specify the minimum thread count 
in the thread pool, either with the configuratoin file or with the 
ThreadPool.SetMinThreads API. See KB article 810259, [FIX: SetMinThreads and 
GetMinThreads API Added to Common Language Runtime ThreadPool 
Class](http://support.microsoft.com/default.aspx?scid=kb;en-us;810259), for 
details. It turns out that Microsoft Biztalk Server has run into the same 
problem: [FIX: Slow performance on startup when you process a high volume of 
messages through the SOAP adapter in BizTalk Server 
2004](http://support.microsoft.com/default.aspx?scid=kb;en-us;886966). I 
suspect many other commercial products have run into this as well. And it's 
rather annoying that each of them have to figure this out after they've shipped 
something, turning into a support bulletin, an internal bug-fix, and (I would 
guess) a service pack containing said bug-fix.

I wouldn't actually call what we did a fix. At best, it's a workaround. Hell, 
one of the KB articles above says that if you want decent scalability you need 
to change the minWorkerThreads count to 50. Our default is 1! Not too far off, 
eh? Shouldn't decent scalability be _the default_ behavior?

We need to fix this for real.

Now, of course, it's a hard problem to solve. You don't want to be too liberal 
adding threads to the pool because it can cause poor scalability should a large 
number of those extra threads suddenly become runnable. In an ideal world, no 
threads block, and having the same number of threads as you have CPUs gives you 
the best performance. (Better cache utilization, less overhead due to context 
switching, and so forth.) But software is often far less than ideal. As noted 
above, ASP.NET asynchronous pages are a _great _way to acheive this, and 
compared to injecting a whole bunch of relatively expensive threads into the 
process, it's obviously a better design. Unfortunately, I am not convinced all 
of our customers will stumble across this design, nor will it be brain-dead 
simple to rearchitect an existing site to take advantage of the feature without 
considerable work.

My hope is that we can solve this problem in the CLR by applying clever 
heuristics that even out over time. For example, we may start out life being 
over eager and generous with thread injection, but then "learn our lesson" after 
running for a period of time. This would lead to stabalization and an 
increasingly superior performance over the life of the process for the work that 
the server experiences. For example, if the server often experiences bursts, we 
will monitor the number of threads that lead to the best throughput during such 
an active period, and during periods of inactivity we will avoid retiring 
threads. This ensures that the next time the server is busy, work can be 
responded to in a more scalable manner, albeit with some extra working set 
overhead for keeping those threads around for longer. Perhaps more appropriate 
configuration settings could be dynamically recommended based on statistics 
gatherer during previous up-times of the server. And of course, we can offer 
more reasonable defaults for clients with short-living processes that might be 
harmed by over-eagerness with thread injection.

If anybody has experienced this problem in the wild, I'd love any feedback you 
might have. Feel free to leave a comment or email me at joedu at you-know-where 
dot com.

