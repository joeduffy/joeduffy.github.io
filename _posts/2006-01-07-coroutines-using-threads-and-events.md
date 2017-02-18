---
layout: post
title: Coroutines using threads and events
date: 2006-01-07 10:32:13.000000000 -08:00
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
I've posted before about [how you might use C# enumerators to simulate
coroutines](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=71235c5a-3753-4bab-bdb0-334ab439afaf).
Enumerators are a very powerful feature, but unfortunately have one big
drawback vis-à-vis their attempt at coroutines: you can yield only from one
stack frame deep. The C# compiler state-machine transforms enough information
for a single function, but obviously doesn't do that for the entire stack.
[Real coroutines](http://en.wikipedia.org/wiki/Coroutine) can yield from an
arbitrarily nested callstack, and have that entire stack restored when they are
resumed.

There are other techniques. If you're willing to spend an entire thread to keep
the stack alive, for example, you can use events to model coroutines with a
standard producer/consumer relationship. The benefit to this approach is that
you are in fact able to yield from arbitrarily nested frames. The clear
drawback is the performance overhead. Each coroutine will eat up 1MB of
reserved stack space from the virtual address space. But, probably worse, each
time a new item is requested, an OS context switch is required; and similarly,
whenever a new item becomes available (i.e. yielded), a context switch occurs
again. This back-and-forth switching is pure overhead that could be eliminated
with true coroutines.

(Note: [this article describes how to use Fibers to avoid this context switch
penalty](http://msdn.microsoft.com/msdnmag/issues/03/09/CoroutinesinNET/).
Fibers are dynamite on the CLR, however, so tread with caution if you even
contemplate using this approach. Furthermore, you can easily dream up ways to
serialize the physical stack, a la continuations. You do have access to the
current CONTEXT, via GetThreadContext, on Windows and can use the thread's
stack base and context ESP to determine the boundaries. But so many things in
Windows rely on the TEB, from the CRT to exception handling to GetLastError to
arbitrary usage of the TLS, like the way the CLR maintains a list of frame
transitions. Nevermind having to accurately report roots back to the GC. These
nightmares make real coroutines on Windows almost unapproachable, at least for
the faint of heart.)

I hacked up a little Coroutine class this morning that uses the
thread-per-coroutine approach mentioned above. Up front, I have to warn you: I
spent 30 minutes on this thing. It's bound to be buggy, and I took some
shortcuts (like not implementing the respective collections interfaces). Rather
than walking through bit-by-bit, I've tried to comment the source code to
plain how it works:

    using System;
    using SD = System.Diagnostics;
    using System.Threading;

    public delegate void CoroutineStart();
    
    public class Coroutine<T> : IDisposable
    {
      // Fields
      private CoroutineStart start;
      private Thread thread;
      private AutoResetEvent computeNextEvent;
      private AutoResetEvent nextAvailableEvent;
      private ManualResetEvent doneEvent;
      private T current;

      // We have a thread-static here so the coroutine needn't track the Coroutine<T> object
      // manually. The Yield function is static, so they can just call Coroutine.Yield(v);
      [ThreadStatic]
      private static Coroutine<T> coroutine

      // Constructors
      public Coroutine(CoroutineStart start)
      {
          this.start = start;
          this.thread = new Thread(Worker);
          this.computeNextEvent = new AutoResetEvent(false);
          this.nextAvailableEvent = new AutoResetEvent(false);
          this.doneEvent = new ManualResetEvent(false);
      }

      // Properties
      public T Current
      {
          // TODO: we could add some error checking here, e.g. if somebody tries to
          // read past the end-of-stream.
          get { return current; }
      }

      // Methods
      public bool MoveNext()
      {
        if (thread.ThreadState == ThreadState.Unstarted)
          thread.Start();
        else
          computeNextEvent.Set();

        // We wait on the 'next available' and 'done' events simultaneously. And then
        // we use this to determine whether the coroutine has finished ornot. The consumer
        // will typically use this in a loop, e.g. while (c.MoveNext()) {f(c.Current); }.
        return (0 == WaitHandle.WaitAny(new WaitHandle[] { nextAvailableEvent, doneEvent }));
      }

      private void Worker()
      {
        try
        {
          // Stash the coroutine object in TLS and start the CoroutineStart routine.
          coroutine = this;
          start();
        }
        catch (ThreadInterruptedException)
        {
          // Ignore the interrupt request. We use this as the 'proper' way to shut-down
          // a couroutine. This is really a hack. Needs to be revisited.
        }
        finally
        {
          // Lastly, signal to the caller that the coroutine is done producing. Note that
          // we'd ideally just use the thread executive object directly. But unfortunately the
          // managed thread class doesn't expose this WaitHandle. :(
          doneEvent.Set();
        }
      }

      public static void Yield(T value)
      {
        Coroutine<T> c = coroutine;

        // First, ensure we're on a coroutine thread.
        if (c == null)
          throw new InvalidOperationException("You can only yield from a coroutine thread");

        // Now, set the coroutine's current value to the argument, signal to the consumer
        // that we have a new item, and go to sleep until we're asked to compute the next item.

        c.current = value;
        c.nextAvailableEvent.Set();
        c.computeNextEvent.WaitOne();
      }

      public void Dispose()
      {
        // We ensure the thread has stopped here. We use a really ugly interrupt to bring
        // it down if not.
        if (thread.ThreadState != ThreadState.Aborted &&
            thread.ThreadState != ThreadState.Stopped &&
            thread.ThreadState != ThreadState.Unstarted)
        {
          SD.Trace.TraceWarning(
            "Coroutine thread has not stopped when Disposing, in state {0}",
            thread.ThreadState);

          thread.Interrupt();

          // Joining here is questionable at best. It could lead to deadlocks.
          thread.Join();
        }

        // Close out all of the events.
        computeNextEvent.Close();
        nextAvailableEvent.Close();
        doneEvent.Close();
      }
    }

    public static class Coroutine
    {
      // This is a trick. The C# compiler will infer the method argument <T>, enabling
      // us to shunt right over to the Coroutine<T> implementation. This is nice because
      // the user can just write Coroutine.Yield(n) instead of Coroutine<T>.Yield(n). The
      // annoying part is that you can easily yield something of the wrong type, leading to
      // an IllegalOperationException because C<T>.Yield will look in TLS and not find anything.
      public static void Yield<T>(T t) { Coroutine<T>.Yield(t); }
    }

Now let's see it in action. Given a function `Fibonacci`, which continuously
yields the next item in the Fibonacci sequence:

    void Fibonnaci()
    {
      long n0 = 0;
      long n1 = 1;
      long n;

      while (true)
      {
        n = n0 + n1;
        n0 = n1;
        n1 = n;

        Coroutine.Yield(n);
      }
    }

We can form a coroutine over it and scroll through the first 10 numbers:

    using (Coroutine<long> c = new Coroutine<long>(Fibonnaci))
    {
      int i = 0;

      while (c.MoveNext() && i++ < 10)
        Console.WriteLine(c.Current);
    }

And of course, we can create a coroutine over a function that yields from
functions deep in the call stack:

    void a()
    {
      Coroutine.Yield("a");

      b();
      e();
    }

    void b()
    {
      Coroutine.Yield("a.b");
      c();
    }

    void c()
    {
      Coroutine.Yield("a.b.c");
      d();
    }

    void d()
    {
      Coroutine.Yield("a.b.c.d");
    }

    void e()
    {
      Coroutine.Yield("e");
    }

And iterate over it:

    using (Coroutine<string> c = new Coroutine<string>(a))
    {
      while (c.MoveNext())
        Console.WriteLine(c.Current);
    }

A neat extension to this whole idea might be a `BeginMoveNext` function that
follows the asynchronous programming model. You could then exploit the fact
that the consumer and producer are on separate threads to make progress while
the producer is calculating the next item in line. Assuming you're on a
multi-hardware-thread machine, this would cut down on the context switch
penalty by as much as half.

