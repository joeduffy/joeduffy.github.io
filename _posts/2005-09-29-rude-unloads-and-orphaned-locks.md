---
layout: post
title: Rude unloads and orphaned locks
date: 2005-09-29 14:49:37.000000000 -07:00
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
I've talked about Thread Aborts
[before](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=c1898a31-a0aa-40af-871c-7847d98f1641).
And I [spoke briefly at
PDC](http://216.55.183.63/pdc2005/slides/FUN405_Duffy.ppt)about why you
shouldn't lock on objects shared across AppDomains (ADs). But I wanted to spend
a brief moment fusing the two together to illustrate the point. There are some
interesting factors at play here.

**The Guidance**

To begin with, [our Design
Guidelines](http://www.amazon.com/exec/obidos/ASIN/0321246756/bluebytesoftw-20)
advise:

> **Do not** lock on any public types, or on instances you do not control.
> Notice that the common constructs lock (this), lock (typeof (Type)), and lock
> ("myLock") violate this guideline.

Most people don't intuitively understand the why behind not locking on Types
and Strings. I'll leave the public type discussion off the table for this post.

**The Reasons**

To understand why this is problematic, first you have to understand that we
share objects across ADs. And you need to understand when we do it. Various
Reflection bits and bytes—such as instances of the Type class—are one such
case, when they refer to a domain neutral assembly. mscorlib always gets loaded
domain neutral, for example; other assemblies can fall into this category too,
based on Hosting policies. Interned strings are also shared across ADs, so a
"Hello, World" literal in AD #A is the same precise object as that "Hello,
World" in AD #B in the same process. All of the above are called cross-AD bled
objects or AD-agile instances, something [discussed in reasonable detail
here](http://blogs.msdn.com/cbrumme/archive/2003/06/01/51466.aspx).

A conclusion that you can make right away is that locking on an object shared
across ADs #A and #B can interfere with each other, even if it's only by
coincidence. Subtle timing oddities might arise—including starving another
AD's completely unrelated opaque body of code for a seemingly unknown
reason—but in many cases the effects won't be so catastrophic. And in some
rare situations it might even be intentional. But let's take it a step further.

Next, you need to know a little about how we perform AD unloads. If you want to
know a lot about this, go read Chris's [excellent post on the
subject](http://blogs.msdn.com/cbrumme/archive/2003/06/01/51466.aspx) (the same
as above). But I will try to summarize, and in doing so will paint a naïve
picture of the world. During ordinary AD unloads we are careful to ensure that
threads are unwound in an orderly fashion. That is to say, finally blocks
lexically surrounding the instruction pointer are run, and of course objects in
that AD are given a chance to run their Finalizers. This happens because a
ThreadAbortException is generated at the current point of execution in each
thread which actively has a stack in the AD.

Assuming you've written your code to use a lock statement (or at least to
release the Monitor in a finally block), this orderly thread unwinding permits
you to release any locks held. You may catch a Thread Abort, but it is a
so-called undeniable exception, meaning it will be reraised at the end of your
catch blocks. This is quite visible during an ordinary unload. And of course,
Aborts are suspended in the case that you're in a CER, unmanaged chunk of code
that isn't polling for aborts, a finally block, and so on. Lastly, if you see
an Abort happen when your code holds a Monitor, you can be assured the entire
AD is being ripped—not just a single Thread; this assumption is safe because
we work with Hosts (via Begin- and EndCriticalRegion) to let them know when the
whole AD could become corrupt as the result of a single ThreadAbort.

But if you piss SQL Server off by taking too long in one of your finally blocks
(for example), it will get a tad snippy. Specifically, it can respond by
escalating to a rude AD unload. A rude unload does not tear the AD down by
injecting ThreadAbortExceptions and enabling them to percolate back to the top
of the call-stack. Rather, it rips it down very aggressively, bypassing
lexically relevant finally blocks, only giving a best effort attempt at running
CERs, and executing critical finalizers (CFOs) only. Of course, this isn't
nearly as aggressive as a P/Invoke to kernel32!TerminateProcess, but it's not
quite as polite as an ordinary unload.

This means, as a very specific example, that a finally block wishing to execute
Monitor.Exit won't even get run. And if the Exit doesn't run, that Monitor will
be permanently left stamped with the Thread's ID as the owner. But the Thread
has gone bye-bye. Orphaned. Until you've created 4,294,967,295 threads such
that the Thread IDs wrap around and the old ID gets assigned to a new Thread,
and that thread spuriously decides to Exit the Monitor without acquiring it
first, your system is going to be locked up for a bit. In other words,
deadlocked.

> _Side Note: Arguably this behavior in any case; if two ADs were intentionally
> coordinating work, an orphaned lock is better than observing corrupt data
> structures. But for accidentally shared objects, perhaps it's overly
> draconian. But I digress._

In fact, any host might do this based on a variety of policies. Some might
choose to perform rude AD unloads all of the time, while others might not do it
at all. Most of them will use an escalation policy rather than doing it
outright—such as SQL Server—but anything's fair game when the host is in
control. A matrix of which hosts do what would be nice, but I don't have one.
We have a nifty tool internally that allows simulation of any of these
policies, but you can just as "easily" do it yourself by [navigating the
Hosting APIs](http://blogs.msdn.com/cbrumme/archive/2004/02/21/77595.aspx). The
general idea is described in more detail in Stephen Toub's recent [excellent
MSDN
article](http://msdn.microsoft.com/msdnmag/issues/05/10/Reliability/default.aspx),
and in gory detail in the [Customizing the
CLR](http://www.amazon.com/exec/obidos/ASIN/0735619883/bluebytesoftw-20)book.

**A Demonstration**

Let's first take a look at and observe the effects of a scenario which locks on
cross-AD objects:

> using System; using System.Threading;
>
> class Program { static void Main() { // Start up a new AppDomain that hogs a
> lock.  AppDomain ad = AppDomain.CreateDomain("FooDomain");
> ad.DoCallBack(delegate { Thread t = new Thread(delegate() {
> lock(typeof(string)) { try { Console.WriteLine("AD#B: Got it.");
> Thread.Sleep(10000); } catch (Exception e) { Console.WriteLine("AD#B: {0}",
> e); //Thread.Sleep(5000); // provoke a rude unload?  } } }); t.Start(); });
>
>         // Pause briefly.  Thread.Sleep(500);
>
>         // This will fail because AD#B owns the shared lock.  bool b =
>         Monitor.TryEnter(typeof(string), 500); if (b) {
>         Console.WriteLine("AD#A: Got it."); Monitor.Exit(typeof(string)); }
>
>         // Kill the other AppDomain.  AppDomain.Unload(ad);
>         Console.WriteLine("AD#A: AD#B is dead.");
>
>         // Is the lock orphaned? If we provoked a rude unload, this should
>         hang.  lock(typeof(string)) { Console.WriteLine("AD#A: I got in!"); }
>         } }

I hope the code is simple enough to be obvious. A brief explanation is
warranted:

1. From an existing Thread T1 in AD #A, we create a new AD #B, and start a new
   Thread of execution T2 running inside of it;

2. T1 resumes and waits briefly to ensure T2 can make forward progress first;

3. T2 locks on typeof(String), and then goes to sleep for a while;

4. Meanwhile, T1 resumes, attempts to acquire the lock, and fails (because the
   lock is held by T2 because the String type is shared across ADs);

5. T1 then initiates an Unload on AD #B;

6. The result is a ThreadAbort in T2, the finally block releases the Monitor,
   and AD #B is successfully unloaded;

7. T1 in AD #A successfully acquires the lock.

Throughout all of this, there is some nice text being printed to the console. I
see the following:

> AD#B: Got it.  AD#B: System.Threading.ThreadAbortException: Thread was being
> aborted.  at System.Threading.Thread.SleepInternal(Int32 millisecondsTimeout)
> at Program.<Main>b\_\_1() AD#A: AD#B is dead.  AD#A: I got in!

**Looks Fine, Eh?**

Well that works just fine in unhosted scenarios, as we might have expected it
to. The lock-protected bits of code stomp on each other, but at least AD #B
happily gives up the lock during an ordinary unload. Note that if the code
running in AD #B were careless, it might not have protected the lock
acquisition/release in a try/finally, in which case AD #A would be screwed. It
would deadlock when it attempted to acquire the lock.

But things get worse. More subtle deadlocks can occur, even if AD #B were
written correctly through the use of the C# 'lock' statement. As we've already
established, this might happen if the code were run inside a host that employed
rude AD unloads, such as SQL Server. If a thread initiated a rude AD unload in
AD #B while it held the lock, the same exact code that worked in the unhosted
case would deadlock as soon as AD #A's last attempt to acquire the lock
executed. Presumably SQL Server would notice this deadlock and kill the
code—perhaps leading to both ADs ultimately being unloaded—but I am not
100% certain about this.

**A Possible Refinement**

Through a combination of CERs, we can get our code working again. Note
that—if it's not obvious by now—the real solution is to avoid locking on
cross-AD bled objects! Just don't do it and you won't get into this trouble.
But of course, the geek inside instigates more fun…

[Brian Grunkemeyer](http://blogs.msdn.com/bclteam/), a developer on our team,
wrote a great piece of code sometime between Beta2 of Whidbey and now. It's a
method on Monitor called ReliableEnter, and it permits you to acquire a Monitor
and know reliably whether it succeeded. It does so with a Boolean byref
parameter which is set inside of a ThreadAbort-safe region of native code. This
means that you can actually rely on the value of the Boolean in a cleanup CER,
for example, to indicate whether the Monitor was successfully acquired or not,
while at the same time not actually suspending ThreadAborts by wrapping the
whole acquisition in a CER.

Unfortunately, we were unable to make it accessible in Whidbey. It's an
internal method, and it got added too late. We'll probably do that in the
future. To make calling it cheap and possible, I wrote a little hack that uses
a DynamicMethod to bind to it. In fact I did a little more than just that. I'm
not going to analyze it in detail. Feel free to ask questions if you wonder how
it works:

> delegate void MonitorAction(); class ReliableMonitor { class Holder<T> {
> internal Holder() { this.value = default(T); } internal Holder(T value) {
> this.value = value; } internal T value; }
>
>
>
>     delegate void ReliableEnterDelegate(object obj, Holder<bool> taken);
>     private static ReliableEnterDelegate monReliableEnter;
>
>
>
>     static ReliableMonitor() { MethodInfo reMi =
>     typeof(Monitor).GetMethod("ReliableEnter", BindingFlags.Static |
>     BindingFlags.NonPublic); DynamicMethod dm = new
>     DynamicMethod("Mon\_ReliableEnter", null, new Type[] { typeof(object),
>     typeof(Holder<bool>) }, typeof(Program), true); ILGenerator ilg =
>     dm.GetILGenerator(); ilg.Emit(OpCodes.Ldarg\_0);
>     ilg.Emit(OpCodes.Ldarg\_1); ilg.Emit(OpCodes.Ldflda,
>     typeof(Holder<bool>).GetField("value", BindingFlags.Instance |
>     BindingFlags.NonPublic)); ilg.Emit(OpCodes.Call, reMi);
>     ilg.Emit(OpCodes.Ret); monReliableEnter =
>     (ReliableEnterDelegate)dm.CreateDelegate(typeof(ReliableEnterDelegate));
>     }
>
>
>
>     internal static void Enter(object obj) { Monitor.Enter(obj); }
>
>
>
>     internal static void RunWithLock(object obj, MonitorAction action) {
>     Holder<bool> taken = new Holder<bool>();
>
>
>
>         System.Runtime.CompilerServices.RuntimeHelpers.ExecuteCodeWithGuaranteedCleanup(
>         delegate { monReliableEnter(obj, taken); action(); }, delegate { if
>         (taken.value) { Monitor.Exit(obj); taken.value = false; } }, null); }
>
>
>
>     internal static void Exit(object obj) { Monitor.Exit(obj); } }

Notice the RunWithLock method. It uses a great method
RuntimeHelpers.ExecuteCodeWithGuaranteedCleanup located in the
System.Runtime.CompilerServices namespace. We call it SRCSRHECWGC—pronounced
"shreek shreck woogy-cuck"—for short around here. Well, we don't really call
it that, but I think I will from now on. SRCSRHECWGC runs the first delegate
and uses some CER magic to guarantee that the cleanup code passed as the second
argument executes in the face of rude AD unloads. At least the type of failures
we're concerned about here. It might not do its job very well if you pull the
plug on your computer, for example.

If we were to rewrite our code above to use the RunWithLock method, it could
survive a rude AD unload and skirt the frightening onset of a deadlock:

> class Program {
>
>
>
>     static void Main() { // Start up a new AppDomain that hogs a lock.
>     AppDomain ad = AppDomain.CreateDomain("FooDomain");
>     ad.DoCallBack(delegate { Thread t = new Thread(delegate() {
>     ReliableMonitor.RunWithLock(typeof(string), delegate { try {
>     Console.WriteLine("AD#B: Got it."); Thread.Sleep(10000); } catch
>     (Exception e) { Console.WriteLine("AD#B: {0}", e); //Thread.Sleep(5000);
>     // provoke a rude unload } }); }); t.Start(); });
>
>         // Pause briefly.  Thread.Sleep(500);
>
>         // This will fail because AD#B owns the shared lock.  bool b =
>         Monitor.TryEnter(typeof(string), 500); if (b) {
>         Console.WriteLine("AD#A: Got it."); Monitor.Exit(typeof(string)); }
>
>         // Kill the other AppDomain.  AppDomain.Unload(ad);
>         Console.WriteLine("AD#A: AD#B is dead.");
>
>         // Is the lock orphaned? If we provoked a rude unload, this should
>         hang.  lock(typeof(string)) { Console.WriteLine("AD#A: I got in!"); }
>         } }

This has the effect that we wanted. When run in a situation where the
RunWithLock method guarantees that we release the lock even in the face of a
rude unload. The result? AD #A does not deadlock.

Hoorah.

And they all rejoiced.

