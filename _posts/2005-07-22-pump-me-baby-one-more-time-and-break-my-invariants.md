---
layout: post
title: Pump me baby one more time (and break my invariants)
date: 2005-07-22 16:42:37.000000000 -07:00
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
The CLR was designed to work very well in a COM world. This design choice is
not at all surprising given the history of programming on Windows, and that the
CLR began life as the COM+ 2.0 Runtime (among other temporary names). When it
comes to concurrency in this world, however, there's a whole host of crap that
can go wrong. Thankfully most of the time it doesn't.

Before moving on, if you have a finite amount of time, I'd recommend reading
Chris Brumme's weblog on [_Apartments and
Pumping_](http://blogs.msdn.com/cbrumme/archive/2004/02/02/66219.aspx). It's
exponentially more worth your time than this post. I'm going to assume you have
been introduced to at least a few of the concepts there. Most mortals on this
planet haven't. You'll also want to come to my Programming w/ Concurrency talk
at PDC, where I'll discuss such "to the metal" details.

OK. I've hyped it up. But I don't really have that much to say.

**Using monitors for critical sections**

When somebody accesses a shared piece of memory from multiple units of parallel
execution, some form of locking is usually necessary. For a very small class of
programmers, avoiding locks and retaining correctness is possible, but it's
rocket science. Most people give up quickly if they even think to try in the
first place (except for double checked locking, which is often copied from some
book or website on the topic). If it's a simple primitive operation,
interlocked operations might work. But in other cases, you need a coarser
grained critical section-ish lock. For manager programmers, this is Monitor
(i.e. 'lock' keyword in C#).

A class that has a private shared static variable, for example, would lock on
it before mutating its contents. Imagine we have a class Coords:

> class Coords { public int x; public int y; }

Our program decides it needs to maintain the invariant that x == y (don't ask
why), and here's the code a developer might write:

> class MyComponent : ServicedComponent { private static Coords c = new
> Coords(); void DoWork() { lock (myCoords) { myCoords.x++; DoMoreWork();
> myCoords.y++; } } void DoMoreWork() { /\* code that tolerates broken
> invariants \*/ } }

So long as we never leak the myCoords instance (raising the risk somebody
accesses it w/out locking), we're safe. Right?

Not quite.

**Enter STA**

You might not have noticed that MyComponent derives from ServicedComponent.
This is a ContextBoundObject that lives by all of the standard COM component
rules. If it's instantiated inside an STA (Single Threaded Apartment), all
access is serialized, as is the case with ordinary COM components. Now, this
might seem a tad esoteric, but consider if you have a class that's called by a
user who wrote their own ServicedComponent. It might seem more real, and is
equally as problematic.

Chris's article above talks at great length about message pumping. STAs have to
pump messages, otherwise queued messages could get starved. For UI
applications, this pisses users off. For other applications, it can lead to
fairness issues at best and incorrect code at worst. We pump for you so you
don't need to worry about it, but we might do it in places you might not
expect. This ends up being nearly anywhere you can block.

Let's pretend DoMoreWork above did this:

> void DoMoreWork() { Thread.CurrentThread.Join(0); }

Join waits for the target thread to complete execution or the timeout to
expire, whichever comes first. Since we call it on our own thread, it should be
clear which occurs first. (You _are _still awake, right?)

When you pump, code can reenter on top of your existing stack. Let's look at
the entire snippet of code:

> [ComVisible(true)] public class MyComponent : ServicedComponent { private
> static Coords c = new Coords();
>
>
>
>     public void DoWork(int n) { Console.WriteLine("{0}->", n);
>
>
>
>         lock (c) { // Check invariant x==y upon entry int x = c.x, y = c.y;
>         Console.WriteLine("{0}:{1},{2}", n, x, y); Debug.Assert(x == y,
>         string.Format("Broken invariant on entry (#{0}, {1}!={2})", n, x,
>         y));
>
>
>
>             c.x++; DoMoreWork(); c.y++;
>
>
>
>             // Ensure invariant x==y upon exit x = c.x; y = c.y;
>             Debug.Assert(x == y, string.Format("Broken invariant on exit
>             (#{0}, {1}!={2})", n, x, y)); }
>
>
>
>         Console.WriteLine("{0}<-", n); }
>
>     private void DoMoreWork() { Thread.CurrentThread.Join(0); } }

Recap: The call to DoMoreWork from the DoWork function occurs while invariants
are broken. And DoMoreWork (or a function that DoMoreWork calls, e.g. some
opaque inside the Framework) pumps. This is a recipe for bad things.

I also added some Console.WriteLines and Debug.Asserts in there so you can
watch the world fall down.

**Breaking monitors with reentrancy**

The situation we need to get into in order to show off this neat parlor trick
is as follows:

- A bunch of MyComponents are created inside an STA server;

- We try to make a load of calls to DoWork on those components from an MTA
  client;

- This requires that the MTA code reenter the STA to execute;

- Our STA thread pumps while invariants are broken, thus reentering another set
  of work (and enabling it to see us in an inconsistent state).

It's not quite as difficult as it sounds, thanks to the CLR's accomodating
interaction with the world of COM.

> class Program { const int threadCount = 5;
>
>
>
>     [STAThread] static void Main() { // Create our components in our STA
>     server (note the STAThread on Main) MyComponent[] components = new
>     MyComponent[threadCount]; for (int i = 0; i < threadCount; i++)
>     components[i] = new MyComponent();
>
>
>
>         // Instantiate a bunch of MTA threads to work on the STA component
>         List<Thread> threads = new List<Thread>(threadCount); for (int i = 0;
>         i < threadCount; i++) { int v = i; Thread t = new Thread(delegate ()
>         { components[v].DoWork(v); });
>         t.SetApartmentState(ApartmentState.MTA); // default--here for
>         illustration threads.Add(t); }
>
>
>
>         // Let 'em loose threads.ForEach(delegate (Thread t) { t.Start(); });
>
>
>
>         // If you haven't Aborted by now, wait for completion
>         threads.ForEach(delegate (Thread t) { t.Join(); }); } }

This glob of code does exactly what my bullets indicate. The whole thing can be
downloaded [here](http://www.bluebytesoftware.com/code/05/07/serviced.txt).
Note: ensure you compile this with the DEBUG symbol defined, otherwise your
calls to Debug.Assert won't be present and you won't get the desired effect of
being bombarded with assert dialogs.

It's quite nice that the CLR goes out of its way to marshal across contexts,
moving our code over from the MTA to the thread in the STA, executing it, and
marshaling back. And furthermore, the pumping it is doing is in good faith.
It's trying to make our application responsive and fair.

Unfortunately, I see the following output when I run the code:

> Constructing components in a STA server...  Instantiating 5 MTA threads to
> operate on our components...  Starting up MTA threads...  Waiting for MTA
> completion...  3-> 3:0,0 3<- 2-> 2:1,1 2<- 1-> 1:2,2 0-> 0:3,2 4-> 4:4,2 4<-
> 0<- 1<-

Notice the "3,2" line. That prints out "x,y"... and does so at a point in the
program where they should always be equal. Unfortunately, we've got reentrant
code inside our lock, and it now has access to broken invariants! Your mileage
may vary based on the inherent race condition. To be fair, this is also a
byproduct of our decision to make monitors reentrant. But this decision was
made for _recursion_, not _reentrancy_. It turns out we don't recognize the
difference.

Of course, the above example doesn't demonstrate anything too terrible. But if
you happened to apply some sensitive thread wide state that you intended to
roll back before enabling other code to run, for example, it means you
absolutely want to avoid pumping inside a critical section. That means mostly
avoiding opaque method calls, even if you suspect they don't pump. In the
future, they could. In practice, this is tough to acheive. And in practice, it
usually doesn't matter.

