---
layout: post
title: A simple GuardedWait<T> class
date: 2004-12-06 22:31:40.000000000 -08:00
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
A guarded wait is a locking primitive which enters an object's monitor and
performs some processing once a certain predicate condition arises. You could
imagine a buffer which refills itself once its contents have been consumed, a
consumer which empties a buffer once it reaches a certain capacity, and so on.

Using the new `Predicate<T>` class in the Framework 2.0, the following is a
pretty straightforward implementation of such a construct:

    public class GuardedWait<T>
    {
      private Predicate<T> predicate;

      public GuardedWait(Predicate<T> p)
      {
        predicate = p;
      }

      public bool IsTrue(T on)
      {
        return predicate(on);
      }

      public bool Wait(T on)
      {
        return Wait(on, -1);
      }

      public bool Wait(T on, int millisecondsTimeout)
      {
        int counter = millisecondsTimeout;

        while (true)
        {
          long beginTick = DateTime.Now.Ticks;

          lock (on)
          {
            if (!Monitor.Wait(on, counter))
              return false;

            if (IsTrue(on))
              return true;
          }

          counter -= (int)new TimeSpan(
            DateTime.Now.Ticks - beginTick).TotalMilliseconds;

          if (counter <= 0)
            return false;
        }
      }
    }

As you can see, the public contract is very simple and familiar. It has a
constructor which takes a predicate operation. This is the condition to guard
on, that is, when waiting this is the condition that must be true for the lock
to be considered successful. Then we have two simple `bool Wait(...)` operations
which are very much like the `Monitor.Wait(...)` methods. This relies on the use
of `Monitor.Notify*()` in order to wake up the wait class to check for its
predicate condition.

Lastly, consider a simple example of its use. In this snippet, we share a queue
between a producer and a consumer. Assume there is a contract in place that the
consumer never lets the queue get beyond a certain threshold, and will deplete
the buffer to half of its capacity each time it reaches such a threshold. This
code effectively accomplishes this:

    class GuardedWaitTest
    {
      public static void Main(string[] args)
      {
        Queue<int> q = new Queue<int>();

        Producer(q);
        Consumer(q, 150);

        Thread.Sleep(5000);
      }

      static void Producer(Queue<int> q)
      {
        Thread t = new Thread(delegate()
        {
          Random r = new Random();
          while (true)
          {
            lock (q)
            {
              int next = r.Next();
              q.Enqueue(next);
              Console.WriteLine("Produced {0} [{1}]", next, q.Count);
              Monitor.Pulse(q);
            }
          }
        });

        t.IsBackground = true;
        t.Start();
      }

      static void Consumer(Queue<int> q, int count)
      {
        Thread t = new Thread(delegate()
        {
          GuardedWait<Queue<int>> wait = new GuardedWait<Queue<int>>(
            delegate(Queue<int> tq) { return tq.Count >= count; });

          while (true)
          {
            lock (q)
            {
              if (wait.Wait(q))
              {
                while (q.Count >= (count / 2))
                {
                  int consumed = q.Dequeue();
                  Console.WriteLine("Consumed {0} [{1}]", consumed, q.Count);
                }
              }
            }
          }
        });

        t.IsBackground = true;
        t.Start();
      }
    }

This code is relatively straightforward, albeit verbose because I am trying to
carefully orchestrate the interaction between threads. `Producer` simply
generates random numbers and `Enqueue()`s them into the shared `Queue`. `Consumer`
uses the `GuardedWait<T>` class to "wake up" when (in this case) 150 items have
been placed into the queue. It then consumed half of these, and relinquishes
the lock back to the Producer. Obviously a simple example, but it should give
you a good idea of when such a construct might be useful.

