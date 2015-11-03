---
layout: post
title: 'To parallelize, or not to parallelize: that is the question'
date: 2006-05-07 22:07:16.000000000 -07:00
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
One of the challenges when designing reusable software that employs hidden 
parallelism -- such as a BCL API that parallelizes sorts, for-all style data 
parallel loops, and so forth -- is deciding, without a whole lot of context, 
whether to run in parallel or not. A leaf level function call running on a 
heavily loaded ASP.NET server, for example, probably should not suddenly take 
over all 16 already-busy CPUs to search an array of 1,000 elements. But if 
there's 16 idle CPUs and one request to process, doing so could reduce the 
response latency and make for a happier user. Especially for a search of an 
array of 1,000,000+ elements, for example. In most cases, before such a function 
"goes parallel," it has to ask: Is it worth it?

Answering this question is surprisingly tough. Running parallel at a high level 
might be more profitable, such as enabling multiple incoming ASP.NET requests to 
be processed, but often fine-grained parallelism can lead to better results. And 
just as often, a combination of the two works best. Consider an extreme case: 
Imagine that most ASP.NET web requests for a particular site ultimately acquire 
a mutual exclusive lock on a resource, essentially serializing a portion of all 
web requests. Of course, this is a design that's going to kill scalability 
eventually. But regardless, it could be present to a lesser degree, and might 
actually be an architectural requirement of the system. Executing some 
finer-grained operations in parallel might lead to better throughput in this 
case, especially those performed while the lock is held.

And clearly, the act of parallelizing an algorithm is not just based on the 
static properties of the system itself, but also dynamic capabilities and 
utilization of the machine. There are some APIs that allow dynamic querying of 
the machine state, which can aid in this process, e.g.:

- [System.Environment.ProcessorCount](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/sysinfo/base/getsysteminfo.asp): 
  This property (new in 2.0) tells you how many hardware threads are on the 
system. Note that the number includes hyper-threads on Intel architectures, 
which really shouldn't be counted as a full parallel unit when deciding whether 
to parallelize your code. 
[GetSystemInfo](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/sysinfo/base/getsysteminfo.asp) 
can give you richer information, albeit with some P/Invoke nonsense. We should 
give a better interface into this data for the next version of the Framework.

- Processor:% Processor Time performance counter: This gives you the % 
  utilization of a specific processor and allows asynchronous querying. Using 
it, you could query each processor on the system to figure out what the overall 
system utilization is, and specifically how many sub-parts to break your problem 
into. The CLR thread-pool uses this today to decide when to inject or retire 
threads. You can use it too to determine whether introducing parallelism is a 
wise thing to do. Although your code may not have a lot of "context," this is 
often a good heuristic that even leaf level algorithms can use.

- System:Processor Queue Length performance counter: For more sophisticated 
  situations, you can not only key off of the processor utilization, but also 
off the queue length of processes waiting to be scheduled. For a really deep 
queue (say, more than 2x the number of processors), introducing additional work 
is likely to lead to unnecessary waiting.

Using these are apt to lead to statistically good decisions. But clearly this is 
a heuristic, and as such the state of the system could change dramatically 
immediately after obtaining the values, perhaps making your deicision look naive 
and ill-conceived in retrospect. The worst case could be bad, but perhaps not 
terrible. The worst aspect of this is that performance characteristics could 
vary dramatically, and your users might respect predictable execution over 
sometimes-fast execution. The good news is that each of these functions are 
fairly cheap to call, amounting to less than 0.5ms total in some quick-and-dirty 
tests I wrote that read from all three.

But spending any time answering the question is tricky business. Assuming the 
software dynamically executes some code to decide if, and to what degree, we 
should run in parallel, and assuming these calculations are not done in parallel 
themselves ;), all of this work amounts to a fixed overhead on some part of the 
overall system, reducing overall parallel speedup (due to [Amdahl's 
Law](http://en.wikipedia.org/wiki/Amdahl's_law)). We hope that in the future we 
can hide a lot of this messy work in the guts of the runtime and WinFX stack, 
but for now it's mostly up to you to decide.

