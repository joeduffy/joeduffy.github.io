---
layout: post
title: 'Two ways: Masking latency and optimizing for fairness'
date: 2006-07-02 22:12:52.000000000 -07:00
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
There are two main reasons to use concurrency.

**The first reason is throughput.**  If you have multiple CPUs, then clearly you 
need at least as many threads as CPUs to keep them all busy. It's a little odd 
to talk about client-side workloads in terms of throughput, but we'll have to 
get used to it as multi-core becomes more prevalent. In the best case, there 
would be the same number of active threads as there are CPUs, each of which are 
entirely CPU-bound.

This is a very simplistic view of the world, however, and you typically end up 
needing more than that. The reason? Latency. Whenever you issue an operation 
with a non-zero latency, there will be some number of wasted CPU cycles during 
which computations will not make forward progress. If the latency is high 
enough, you can mask it with concurrency, and instead overlap some of the 
computation that needs to get done. Simply put, this maximizes the amount of 
work that actually gets done in a given amount of time (i.e. throughput).

To illustrate this point, consider Intel's HyperThreading (HT) technology for a 
moment. Any memory access—and particularly those that miss cache entirely and 
go to main memory—have a noticeable latency (e.g. on the order of tens to 
hundreds of cycles). Instruction-level parallelism (ILP) can mask this to some 
degree. But HT also improves instruction-level throughput by overlapping 
adjacent instruction streams as stalls occur due to latency. This is clearly 
concurrency-in-the-small and doesn't incur any noticeable overhead for context 
switching as do coarser grained forms of concurrency. But for many workloads it 
can do a surprisingly good job at masking delays. This technology, by the way, 
is based on technologies pioneered by super-computer makers like Cray and Tera 
years ago; many such architectures actually don't use caches, so the latency of 
accessing main memory is incurred much more frequently, and thus this technique 
is much more beneficial in practice.

To illustrate this idea further, consider coarse-grained IO, such as issuing a 
web service request. The latency here is huge when compared to a simple cache 
miss, often warranting application-level concurrency to mask the latency. Again, 
if your goal is to maximize throughput, then you'd like to use as many 
cycles/time as possible, assuming that ensures you get the most work done. 
Asynchronous overlapped IO via Windows Completion Ports is meant exactly for 
this purpose (e.g. via the Stream.BeginXXX/EndXXX functions combined with the 
thread pool), allowing you to resume the paused "continuation" once the IO 
completes. In the meantime, you can continue performing meaningful work. This 
technique also often leads to better bandwidth utilization; for example, you can 
have several pending network requests which complete as individual responses are 
received, again masking the unpredictable latencies and response times.

A special case is when maximizing throughput of an individual component rather 
than the system as a whole. The UI thread, for example, is a precious resource 
that needs to maximize its message dispatching throughput so that latencies are 
masked from the user. Instead of statistical throughput degradation, failing to 
do this can lead to disastrous user experiences. This typically involves 
dispatching events to a separate worker thread whenever any IO might occur 
during the event's execution. And it may mean sacrificing the throughput of the 
entire system so that you can maximize throughput and remove waiting from the 
single component. Other systems with finite resources often exhibit this same 
characteristic.

**The second major reason to use concurrency is fairness.** If you are 
performing some work and suddenly some new work arrives, it often makes sense to 
start the computations associated with the new work as soon as possible. This 
allows round-robin servicing (e.g. at thread quantum intervals), ensuring that 
multiple pieces of work make progress at somewhat equivalent speeds. 
Anti-starvation of pending requests can often mandate this technique. For 
example, if you have a shared hosted web server whose pages just block 
indefinitely, you may end up starving other sites if you don't create more 
threads to service them. In some cases, you may actually want to preempt the 
existing work if the new work is a higher priority. Windows thread priorities 
are good for that.

For compute-intensive workloads, optimizing for fairness will typically decrease 
throughput. That's because you often need to create more threads than you have 
CPUs to accommodate the new work, and therefore more time is spent context 
switching and damaging locality. What may not be obvious is that this can 
actually lead to better throughput for many workloads, because IO can be 
overlapped and therefore as instruction streams stall, other threads can overlap 
progress.

**Locking messes with all of this.** Today's locking mechanisms aren't conducive 
to optimizing for throughput. The latency involved with racing with other 
concurrent workers is unpredictable but measurable at best. It is very difficult 
to systematically design to hide such latencies. And of course most locks have 
no idea of fairness or priority. Because context switches can happen while a 
lock is held, it may be the case that every thread about to be scheduled tries 
to acquire that same lock. Bam, you suddenly have a lock convoy on your hands. 
And priorities and threads don't mix very well, priority inversion can happen 
unexpectedly, leading to substantial loss in throughput at best and deadlock at 
worst. STM is a glimmer of hope in both regards.

