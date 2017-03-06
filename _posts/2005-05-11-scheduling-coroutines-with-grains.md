---
layout: post
title: Scheduling coroutines with grains
date: 2005-05-11 00:34:40.000000000 -07:00
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
I was on an email thread with a customer earlier today, and the topic of fibers
came up. More generally, the need to schedule lightweight tasks for simulated
concurrent execution. The thread pool is fairly heavyweight, doesn't offer much
flexibility in the way of scheduling, and admittedly just doesn't quite cut it
for many scenarios. We're looking hard at how best to improve the thread pool
support in Orcas (that's Whidbey + 1)--especially in the area of better control
over the scheduling policy--so I'd love to get any feedback you might have.

This discussion got me thinking about how you can do some fancy shmancy hacks
using C# 2.0 iterators to cook up a mutated form of simulated concurrent task
execution.

### Iterators & Coroutines

Coroutines enable coordination between multiple logical tasks all running in
lock step in a manner quite similar to fibers. Tasks can run on the same
physical thread, but operate as though they were concurrent units of execution,
and mostly rely on good citizenship to avoid one unit starving another. A
coroutine will execute for a small period of time, and finally yield a value of
interest. Sometimes this value is just void/nil/etc, for example in cases where
the coroutine is just running some side-effecting code and then yielding back
to its caller to let it decide what the next step should be.

C# 2.0 ships with a form of coroutines. The iterator feature, described
[here](http://www.theserverside.net/articles/showarticle.tss?id=IteratorsWithC2),
[here](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=846594bb-7003-499f-b918-2fcfe6abdbd7)
and [here](http://pluralsight.com/blogs/dbox/archive/2005/04/17/7467.aspx), is
an impressive piece of beautiful compiler hackery. It closure-transforms a
block of code into a mini state machine—pushing locals into instance
variables on the closure—so that an instance will "suspend" (or "yield")
itself and can be "resumed" at well defined breakpoints. This is the
traditional definition of a coroutine, although the implementation technique
differs from many. There might be a few odd cases it doesn't support, but it's
quite close. We can use these as a starting point.

### Scheduling Tasks

If you're willing to trust that a coroutine will yield often enough, we can
schedule a bunch of them so that they are able to run somewhat concurrently. Of
course, this is "concurrent" in the sense that processes and threads on a
single processor machine are concurrent. With enough coroutines that are doing
interesting work, this starts to look attractive. Especially if the code inside
of them is willing to yield just before doing a blocking operation, and
generally abide by some courteous rules like not eating up too much time before
yielding.

We would need a scheduler that maintains a queue of active coroutines, and some
form of policy for letting them execute. Using a braindead simple algorithm, it
could just walk the queue sequentially and execute, a form of round robin
scheduling. At each step, it would dequeue the head coroutine, runs it until it
yields, and then re-queue it and move to the next—unless it is done, in which
case we just skip the re-queueing.

The fact that this is possible (and pretty simple) relies on a whole array of
abstractions underneath us, all of which are easy to take for granted:

* The "data stack" and "activation frame" for the coroutine is automatically
  saved and restored for us by the C# compiler's iterator transforms, almost
  like a mini thread preemption routine. This is awesome. Obviously, it's not the
  same in reality (only conceptually), and the call stack responds as though it
  were an ordinary function call.

* The scheduler is running on a thread like any other piece of code which gets
  timesliced accordingly. We could have multiple pools of coroutines that are
  all executing concurrently, and in lockstep with each other.

* The OS is conceptually doing a very similar thing below us, but at an
  extremely finer grained level.

One of the major downsides to using coroutines is this fashion that you can't
preempt, and thus your ability to fairly timeslice is limited. The scheduling
algorithm could use a heuristic which took into account average time allotment
per yield for any given coroutine, and throttle time accordingly. If you knew a
certain coroutine took 3x longer than most others last time, for example, you
might only permit it to run 1/3 as much next time. But there's nothing to
prevent a single coroutine from blocking indefinitely or hogging time from
other tasks. A simple round robin algorithm probably wouldn't suffice for most
requirements.

### A First Cut Implementation: Grains

I wrote a whole bunch of code to implement what I describe above, and it works
surprisingly well. I tried to produce a nice interface, but it still feels a
little rough in some areas. I'm not sure whether anybody will benefit from
seeing my arbitrary code postings (comments please!... I seem to get very few
comments on these types of posts), but I'll share some of it. If folks want to
see more, I'll post the whole bucket of code. I was thinking this would make a
nice "official" whitepaper, too. I named these things grains—get it: threads,
fibers, grains, … clever, eh?—but they're really just scheduled coroutines.

So I'll try to walk through this quickly. We start with a simple `Grain` class.
You can think of this as a parallel to the `Thread` class. It takes a start
argument, and has a state (Stopped, Ready, Sleeping). This is the thing that's
used to encapsulate a single activation of a grain which gets manipulated over
time.

    public class Grain
    {
      // Fields
      private GrainState _lastKnownState = GrainState.Stopped;
      private GrainNext _suspendedState;
      private IEnumerator<GrainNext> _executor;
      private ManualResetEvent _completedWaitEvent = new ManualResetEvent(false);
      private GrainStart _start;
      private ParameterizedGrainStart _parameterizedStart;
      private IEnumerable<GrainNext> _enumerableStart;

      // Constructors
      public Grain(GrainStart start)
      {
        _start = start;
      }

      public Grain(ParameterizedGrainStart parameterizedStart)
      {
        _parameterizedStart = parameterizedStart;
      }

      public Grain(IEnumerable<GrainNext> enumerableStart)
      {
        _enumerableStart = enumerableStart;
      }

      public Grain(IEnumerator<GrainNext> executor)
      {
        _executor = executor;
      }

      // Properties
      public GrainState LastKnownState
      {
        get { return _lastKnownState; }
        internal set { _lastKnownState = value; }
      }

      public GrainNext SuspendedState
      {
        get { return _suspendedState; }
        internal set { _suspendedState = value; }
      }

      internal IEnumerator<GrainNext> Executor
      {
        get { return _executor; }
      }

      internal EventWaitHandle CompletedWaitEvent
      {
        get { return _completedWaitEvent; }
      }

      // Methods
      public void Start()
      {
        Start(null);
      }

      public void Start(object state)
      {
        // If one of the delegate starts were passed in, detect and execute to
        // get our IEnumerable<GrainNext> instance.
        if (_start != null)
          _enumerableStart = _start();
        else if (_parameterizedStart != null)
          _enumerableStart = _parameterizedStart(state);

        // Just create a new enumerator and use that as our "executor".
        if (_enumerableStart != null)
          _executor = _enumerableStart.GetEnumerator();

        // Lastly, if executor is null, we're hosed. Just fail now.
        if (_executor == null)
          throw new ArgumentNullException(
            "Executor is null. Either your start method returned null or you passed in null.");
      }

      public void Join()
      {
        _completedWaitEvent.WaitOne();
      }
    }

In that code, I reference a couple things. First, the `GrainStart` and
`ParameterizedGrainStart` types are delegates which are quite similar to the
`ThreadStart` and `ParameterizedThreadStart` types. They refer to a method used to
kick off a coroutine as soon as it gets run by the scheduler.

    public delegate IEnumerable<GrainNext> GrainStart();
    public delegate IEnumerable<GrainNext> ParameterizedGrainStart(object obj);

These delegates return `IEnumerable<GrainNext>`, which is the target iterator
function. `GrainNext` is a little tricky to get your head around at first. It's a
delegate that, when executed, tells the scheduler what to do next. It tells the
schedule whether the grain is ready to run, is sleeping waiting for an event,
or is done executing. This state is represented by the `GrainState` enum. There's
also a `GrainStateFactory` static class that helps to generate the simple `Ready`
and `Stopped` cases. Remember I said coroutines can sometimes yield a void when
it has nothing of interest to report? Well, the coroutine is simply yielding an
instruction to the scheduler as to what it wants to do next. If the iterator
just exits normally, the scheduler will assume this means it is normally
terminating. Also one quick thing to note: if an unhandled exception escapes a
grain, it tears down the whole scheduler. Not sure the best approach to handle
this.

    public delegate GrainState GrainNext();

    public enum GrainState
    {
      Ready,
      Sleeping,
      Stopped
    }

    public static class GrainStateFactory
    {
      public static readonly GrainNext Ready = delegate { return GrainState.Ready; };
      public static readonly GrainNext Stopped = delegate { return GrainState.Stopped; };
    }

You might be wondering why this is done through a delegate. It seems odd, I
agree. Why doesn't the enumerator just return GrainNext? Well, for one I'm a
functional junkie and I'm imposing my preference for lazy evaluation on my
readers. ;) But truthfully, I thought it was a cool feature that you could use
the return delegate to inspect some predicate and determine the next step based
on that. This way if you are sleeping a grain, you can check for the wake up
condition in the returned delegate and, if it's true, return `Ready`; otherwise,
you just return `Sleeping`, and the same predicate gets checked next time the
scheduler is ready to run the grain. Would love feedback here.

### The Round Robin Grain Scheduler

So obviously the `Grain` doesn't do much good without some form of scheduler. So
I wrote a lot of code here, too. Basically, a scheduler gets hosted in its own
thread (hmm, or perhaps it, too, could be a grain!). It is basically a big
`while(true)` loop that consumes things off the queue as they arrive.

So we start with an abstract `GrainPool` class with some common methods, but is
void of any specific scheduling policy. We'll skip this guy for now, it's not
terribly interesting. On to the actual implementation. The idea is that we can
have a whole bunch of scheduling policies out of the box, but I'm tired right
now… So I only spent time to implement a round robin scheduler.

The code here is fairly lengthy. But it should be pretty easy to follow. It
just loops round and round, processing grains in the queue until it gets shut
down.

    public class RoundRobinGrainPool : GrainPool
    {
      private Queue<Grain> _queue = new Queue<Grain>();

      protected override void SchedulerLoop()
      {
        try
        {
          bool exitRequested = false;

          while (!exitRequested)
          {
            Grain g = null;

            // Dequeue the first item in the queue, or wait until one arrives.
            while (g == null && !_isInterruptionRequested)
            {
              lock (_poolLock)
              {
                if (_queue.Count == 0)
                {
                  if (_isShutdownRequested)
                  {
                    // The queue has been emptied, process shutdown now.
                    break;
                  }
                  else
                  {
                    // Wait for a new item to arrive. 250ms might need tuning...
                    // it could be overly "spinny".
                    Monitor.Wait(_poolLock, 250);
                  }
                }
                else
                {
                  // Dequeue the item at the head, and jump out of the loop.
                  g = _queue.Dequeue();
                  break;
                }
              }
            }

            // HACK: Due to shutdown, g could be null. If there are ever other new ways
            // to exit the block w/out setting g, this code will catch it.
            if (g == null)
            {
              exitRequested = true;
              continue;
            }

            // If we last knew that the grain was asleep, give it a chance to indicate
            // whether it is ready to run or not.
            if (g.LastKnownState == GrainState.Sleeping)
            {
              g.LastKnownState = g.SuspendedState();

              if (g.LastKnownState == GrainState.Stopped)
              {
                // It reported that it has stopped--move on to the next grain.
                g.CompletedWaitEvent.Set();
                continue;
              }
            }

            // So long as the grain isn't sleeping, we give it a chance to run.
            if (g.LastKnownState != GrainState.Sleeping)
            {
              if (g.Executor.MoveNext())
              {
                // The grain reported that it's either sleeping or ready to be
                // run again. This is fine & dandy, just update its state and prepare
                // it for its next round of execution.

                g.SuspendedState = g.Executor.Current;
                g.LastKnownState = g.SuspendedState();
              }
              else
              {
                // It's done executing. Update its state and prepare to ditch it.
                g.SuspendedState = GrainStateFactory.Stopped;
                g.LastKnownState = GrainState.Stopped;
              }

              if (g.LastKnownState == GrainState.Stopped)
              {
                // It reported that it was done. Move on to the next one.
                g.CompletedWaitEvent.Set();
                continue;
              }
            }

            // If we got here, the grain still has execution left in it. Schedule it up
            // for the next loop.
            lock (_poolLock)
            {
              _queue.Enqueue(g);
            }
          }
        }
        finally
        {
          // Notify waiter that we saw the interruption request.
          _shutdownEvent.Set();
        }
      }

      public override void QueueGrain(Grain g)
      {
        // Check that our grain is in a ready state.
        if (g.LastKnownState == GrainState.Stopped)
        {
          // Start will throw an exception if the grain is corrupt. We let
          // it fly, no problems here.
          g.Start();
        }

        // Put 'em in the queue and notify the scheduler that it's ready.
        lock (_poolLock)
        {
          _queue.Enqueue(g);
          Monitor.PulseAll(_poolLock);
        }
      }

      public override void DequeueGrain(Grain g)
      {
        // Just copy our internal queue to a new version, leaving out the grain
        // which was requested to be removed.
        lock (_poolLock) // BUGBUG: This coarse lock sucks big time.
        {
          Queue<Grain> copy = new Queue<Grain>(_queue.Count * 2);

          while (_queue.Count != 0)
          {
            Grain deq = _queue.Dequeue();
            if (!deq.Equals(g))
              copy.Enqueue(deq);
          }

          _queue = copy;
        }
      }

      public override IEnumerator<Grain> GetEnumerator()
      {
        // Lock to ensure consistency in the data structure while we
        // snapshot the enumerator.
        lock (_poolLock)
        {
          return _queue.GetEnumerator();
        }
      }
    }

Should really spend more time discussing this bit, but if you have specific
questions or items which aren't clear, please ask!

### Usage Example

Again, running out of steam, so I didn't cook up any realistic examples. But
this little snippet does demonstrate how it works from a user's perspective. I
did try to make the APIs half-decent and at least a little straightforward to
use.

I create a new thread that owns running the grain scheduler, and then send off
a couple coroutines for execution. I ask for a normal shutdown (not an
interruption, so it waits for the grains to complete), and then we're done. I'm
going to try and get some better examples over the next couple days.

    class Program
    {
      static void Main()
      {
        GrainPool pool = GrainPool.DefaultPool;

        // Create a new Thread which hosts the grain pool.
        Console.WriteLine("### Starting grain host...");

        Thread t = new Thread(pool.Start);
        t.Start();

        // Now schedule some work for the grain pool.
        Console.WriteLine("### Scheduling grains...");

        pool.QueueGrain(new Grain(GrainFuncs.Fibonacci));
        pool.QueueGrain(new Grain(GrainFuncs.Random));

        // Lastly, wait for our grains to be done.
        Console.WriteLine("### Waiting for completion & shutting down the pool...");

        pool.Shutdown(true);

        Console.WriteLine("### Joining the thread...");
        t.Join();

        Console.WriteLine("### Exited normally");
      }
    }

    static class GrainFuncs
    {
      internal static IEnumerable<GrainNext> Fibonacci()
      {
        int n0 = 0;
        int n1 = 1;
        int n;

        do
        {
          n = n0 + n1;
          n0 = n1;
          n1 = n;

          Console.WriteLine("[Fib: {0}]", n);

          yield return GrainStateFactory.Ready;
        }
        while (n < 1000);

        Console.WriteLine("[Fib: {0}**FINAL**]", n);
      }

      internal static IEnumerable<GrainNext> Random()
      {
        Random r = new Random();

        for (int i = 0; i < 15; i++)
        {
          Console.WriteLine("[Rand: {0}]", r.Next());

          yield return new GrainNext(delegate
          {
            if (r.Next(2) == 1)
              return GrainState.Ready;
            else
              return GrainState.Sleeping;
          });
        }
      }
    }
