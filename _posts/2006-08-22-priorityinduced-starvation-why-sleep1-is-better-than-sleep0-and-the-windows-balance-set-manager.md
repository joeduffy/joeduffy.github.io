---
layout: post
title: 'Priority-induced starvation: Why Sleep(1) is better than Sleep(0) and the
  Windows balance set manager'
date: 2006-08-22 22:18:05.000000000 -07:00
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
A common technique to avoid giving up your time-slice on multi-CPU machines is to
use a hand-coded spin wait. This is appropriate when the cost of a context switch
(4,000+ cycles) and ensuing cache effects are more expensive than the possibly wasted
cycles used for spinning, which is to say not terribly often. When used properly,
however, very little time is spent spinning, and the spin wait is only ever
invoked rarely when very specific cross-thread state is seen, such as lock-free
code observing a partial update. There are some best practices that must be followed
when writing such a spin wait to guarantee good behavior across different machine
configurations, i.e. HT, single-CPU, and multi-CPU systems.

A correct wait must issue a yield/pause instruction on each loop iteration to work
well on Intel HT machines:

```
while (!cond) {
    Thread.SpinWait(20);
}
```

Many implementations should also fall back to a more expensive wait on, say, a Windows
event or CLR monitor after spinning a while. This handles the worst case situation
in which the thread that is destined to make 'cond' true is not making forward progress
as quickly as you'd hoped. A complementary and alternative technique is to simply
give up the time-slice in such cases using the Thread.Sleep API:

```
uint loops = 0;
while (!cond) {
    if ((++loops % 100) == 0) {
        Thread.Sleep(0);
    } else {
        Thread.SpinWait(20);
    }
}
```

This approach ensures that, if the machine is saturated, the spin wait doesn't prevent
the thread which will set the event from being scheduled and making forward progress.

All of this is pure nonsense and ludicrousness on single-CPU machines. If you're
waiting for another thread to set an event... well... it clearly isn't going to do
that if you're actively using the one and only CPU to waste cycles spinning! Therefore
a natural extension to the above approach is to check for a single-CPU machine and
respond by yielding to another thread:

```
uint loops = 0;
while (!cond) {
    if (Environment.ProcessorCount == 1 || (++loops % 100) == 0) {
        Thread.Sleep(0);
    } else {
        Thread.SpinWait(20);
    }
}
```

OK, this is looking rather nice now. But wait. There's a subtle but nasty problem
lurking here.

Sleep(0) actually only gives up the current thread's time-slice if _a thread at equal
priority_ is ready to run. Don't believe me? [Check out the MSDN docs](http://msdn.microsoft.com/library/default.asp?url=/library/en-us/dllproc/base/sleepex.asp).
If you're writing a reusable API that will be called by a user app, they might decide
to drop a few of their threads' priorities. Messing with priorities is actually a
very dangerous practice, and this is only one illustration of what can go wrong.
(Other illustrations are topics for another day.) In summary, plenty of people do
it and so reusable libraries need to be somewhat resilient to it; otherwise, we get
bugs from customers who have some valid scenario for swapping around priorities,
and then we as library developers end up fixing them in service packs. It's less
costly to write the right code in the first place.

Here's the problem. If somebody begins the work that will make 'cond' true on a lower
priority thread (the producer), and then the timing of the program is such that the
higher priority thread that issues this spinning (the consumer) gets scheduled, the
consumer will starve the producer completely. This is a classic race. And even
though there's an explicit Sleep in there, issuing it doesn't allow the producer
to be scheduled because it's at a lower priority. The consumer will just spin forever
and unless a free CPU opens up, the producer will never produce. Oops!

You can solve this problem by changing the Sleep to use a parameter of 1:

```
uint loops = 0;
while (!cond) {
    if (Environment.ProcessorCount == 1 || (++loops % 100) == 0) {
        Thread.Sleep(1);
    } else {
        Thread.SpinWait(20);
    }
}
```

This fixes the problem, albeit with the disadvantage that the thread is unconditionally
removed from the scheduler temporarily. (We also call SleepEx with an alertable flag
which is more expensive due to APC checks, but I digress.) It's unfortunate that
a quick 5 minute audit turns up plenty of Sleep(0)'s in the .NET Framework. I hope
to get an FxCop rule created to catch this.

The kernel32!SwitchToThread API doesn't exhibit the problems that Sleep(0) and Sleep(1)
do. Unfortunately, you can't reliably get at it from managed code. You can P/Invoke,
but it's actually dangerous to do if you end up running in a host. We've overridden
thread yielding behavior on the CLR such that we can call out to a host for notification
purposes. This was used primarily for fiber mode in SQL Server (which was cut), so
that it could use this as an opportunity to switch fibers, but other hosts are free
to do what they please. If you don't care about working in a host, then feel free
to do this, but please document it clearly and use the following HPA signature so
people don't use your type incorrectly unknowingly:

```
[DllImport("kernel32.dll"), HostProtection(SecurityAction.LinkDemand, ExternalThreading=true)]
static extern bool SwitchToThread();
```

We're looking at adding a Thread.Yield API in the next rev of the CLR that does this
in a host-friendly way. For now, you'll have to rely on Sleep(1).

Thankfully, the starvation problem is not quite \*that\* bad. The Windows scheduler
combats this problem. It uses a _balance set manager_: a system daemon thread whose
responsibility it is to wake up once a second to check for threads that are being
starved because of a lower priority than other runnable threads. The goal
of this service is to prevent CPU starvation and to minimize the impact of priority
inversion. If any threads are found by the balance set manager which have been
starved for ~3-4 seconds, those starved threads enjoy a temporary _priority
boost_ to priority 15 ("time critical"), virtually ensuring the thread will be scheduled.
(Although this won't strictly _guarantee _it: if your other threads have
real-time priorities, i.e. >15, then starvation will continue indefinitely... you're
playing with dynamite once you enter that realm.) And once the thread does get scheduled,
it also enjoys a _quantum boost_: its next quantum is stretched to 2x its normal
time on client SKUs, and 4x its normal time on server SKUs. The priority decays as
each quantum passes, continuing until the thread reaches its original lower priority.

In our example above when Sleep(0) is used, we hope this will unstick the machine
and let the producer produce and finally the consumer to consume. Indeed with some
testing, we see it unstick after a little more than 3 seconds. This is still long
enough, however, to kill performance on a server application, cause a noticeable
perf degradation on the client, and destroy responsiveness in a GUI app. Here's
a simple test that exposes the problem (on a single-CPU machine):

```
using System;
using System.Diagnostics;
using System.Threading;

class Program {
    public static volatile int x = 0;

    public static void Main() {
        Stopwatch sw = new Stopwatch();
        sw.Start();

        SpawnWork();
        while (x == 0) {
            Thread.Sleep(0);

        }

        sw.Stop();
        Console.WriteLine("Sleep(0) = {0}", sw.Elapsed);

        x = 0;

        sw.Reset();
        sw.Start();

        SpawnWork();
        while (x == 0) {
            Thread.Sleep(1);

        }

        sw.Stop();
        Console.WriteLine("Sleep(1) = {0}", sw.Elapsed);
    }

    private static void SpawnWork() {
        ThreadPool.QueueUserWorkItem(delegate {
            Thread.CurrentThread.Priority = ThreadPriority.BelowNormal;
            x = 1;
        });
    }
}
```

And here's some example output which is quite consistent from run to run:

```
Sleep(0) = 00:00:03.8225238
Sleep(1) = 00:00:00.0000678
```

As we can see, in the case of Sleep(0), the balance set manager stepped in and boosted
our producer thread after ~3-4 seconds as promised. We avoid the problem altogether
with Sleep(1).

The moral of the story? Priorities are evil, don't mess with them. Always use Sleep(1)
instead of Sleep(0). The Windows balance set manager is cool.

