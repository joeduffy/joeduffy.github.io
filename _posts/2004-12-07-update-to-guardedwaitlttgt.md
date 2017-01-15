---
layout: post
title: Update to GuardedWait<T>
date: 2004-12-07 12:53:04.000000000 -08:00
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
I made a couple small improvements to [my brain dump from last night](http://joeduffyblog.com/2004/12/06/a-simple-guardedwaitlttgt-class/).
I added a few continuation-ish constructor and `Wait(...)` overloads that take a consequent and alternate `Action<T>` (a new delegate type in Whidbey).
`Action<T>` is just a `void(T)` function that executes a set of statements (with no return value).
If the guarded condition is met, the wait class just executed your consequent from within a locked context;
if not, it will execute the alternate from the same context.

For example, here is the new definition of `GuardedWait<T>` (sorry--it's gotten a bit lengthy):

    public class GuardedWait<T>
    {
      // fields
      private Predicate<T> predicate;
      private Action<T> consequent;
      private Action<T> alternate;

      // ctors
      public GuardedWait(Predicate<T> p) : this(p, null)
      {
      }

      public GuardedWait(Predicate<T> p, Action<T> c) : this(p, c, null)
      {
      }

      public GuardedWait(Predicate<T> p, Action<T> c, Action<T> a)
      {
        this.predicate = p;
        this.consequent = c;
        this.alternate = a;
      }

      // methods
      public bool IsTrue(T on)
      {
        return predicate(on);
      }

      private bool WaitImpl(T on, int millisecondsTimeout)
      {
        int counter = millisecondsTimeout;

        while (true)
        {
          long beginTick = DateTime.Now.Ticks;

          if (!Monitor.Wait(on, counter))
            return false;

          if (IsTrue(on))
            return true;

          counter -= (int)new TimeSpan(
            DateTime.Now.Ticks - beginTick).TotalMilliseconds;

          if (counter <= 0)
            return false;
        }
      }

      public bool Wait(T on)
      {
        return Wait(on, -1);
      }

      public bool Wait(T on, int millisecondsTimeout)
      {
        return Wait(on, millisecondsTimeout, consequent, alternate);
      }

      public bool Wait(T on, Action<T> consequent)
      {
        return Wait(on, consequent, null);
      }

      public bool Wait(T on, int millisecondsTimeout, Action<T> consequent)
      {
        return Wait(on, millisecondsTimeout, consequent, null);
      }

      public bool Wait(T on, Action<T> consequent, Action<T> alternate)
      {
        return Wait(on, -1, consequent, alternate);
      }

      public bool Wait(T on, int millisecondsTimeout, Action<T> consequent, Action<T> alternate)
      {
        lock (on)
        {
          if (WaitImpl(on, millisecondsTimeout))
          {
            if (consequent != null)
              consequent(on);

            return true;
          }
          else
          {
            if (alternate != null)
              alternate(on);
            return false;
          }
        }
      }
    }

Fairly boring boilerplate, but it means we can now write simplified consumer code, such as:

    static void Consumer(Queue<int> q, int count)
    {
      Thread t = new Thread(delegate()
      {
        GuardedWait<Queue<int>> wait = ProduceQueueConsumer<int>(count, 0.5f);

        while (true)
        {
          wait.Wait(q);
        }
      });

      t.IsBackground = true;
      t.Start();
    }

Notice we no longer have to worry about locking ourselves and in fact can even abstract away the process of consumption.
In this case, we have implemented a somewhat reusable static factory method, `ProduceQueueConsumer`:

    static GuardedWait<Queue<T>> ProduceQueueConsumer<T>(int threshold, float fillFactor)
    {
      int target = (int)(fillFactor * threshold);

      return new GuardedWait<Queue<T>>(
        delegate(Queue<T> tq) { return tq.Count >= threshold; },
        delegate(Queue<T> tq) {
          while (tq.Count >= target)
          {
            T consumed = tq.Dequeue();
            Console.WriteLine("Consumed {0} [{1}]", consumed, tq.Count);
          }
        });
    }

This method just takes an absolute threshold, a fill factor (between 0.0f and 1.0f)
that represents the percent of the threshold to reduce the queue to when it reaches the threshold.
Fairly esoteric I suppose, but I think it's cool. :)

