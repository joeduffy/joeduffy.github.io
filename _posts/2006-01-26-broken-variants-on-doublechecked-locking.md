---
layout: post
title: Broken variants on double-checked locking
date: 2006-01-26 11:37:58.000000000 -08:00
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
Vance Morrison's excellent [MSDN
article](http://msdn.microsoft.com/msdnmag/issues/05/10/MemoryModels) from a
few months back talks about why double checked locking is guaranteed to work on
the CLR v2.0, and why it is one of the few safe lock-free mechanisms on the
runtime. He also sent [an
email](http://discuss.develop.com/archives/wa.exe?A2=ind0203B&L=DOTNET&P=R375)
to the develop.com mailing list a while back explaining why this pattern wasn't
guaranteed to work on the ECMA memory model. We did quite a bit of
implementation work and testing to tame the crazy memory model of IA-64 on 2.0.
(Note that none of this is in the ECMA specification, so if you're worried
about CLI compatibility, beware.)

These modifications not only enable the double checked locking pattern, but
also prevent constructors from publishing the newly allocated object before
their state has been initialized, as I mentioned in my PDC presentation on
concurrency last year. We accomplish this by ensuring writes have 'release'
semantics on IA-64, via the `st.rel` instruction. A single `st.rel x` guarantees
that any other loads and stores leading up to its execution (in the physical
instruction stream) must have appeared to have occurred to each logical
processor at least by the time `x`'s new value becomes visible to another
logical processor. Loads can be given 'acquire' semantics (via the `ld.acq`
instruction), meaning that any other loads and stores that occur after a
`ld.acq x` cannot appear to have occurred prior to the load. The 2.0 memory
model does not use `ld.acq`'s unless you are accessing volatile data (marked w/
the `volatile` modifier keyword or accessed via the `Thread.VolatileRead` API).
This can lead to some subtle problems.

For example, a slight variant of the double checked lock will not work under
our model:

    class Singleton
    {
      private static object slock = new object();
      private static Singleton instance;
      private static bool initialized;

      private Singleton() {}
      public Instance
      {
        get
        {
          if (!initialized)
          {
            lock (slock)
            {
              if (!initialized)
              {
                instance = new Singleton();
                initialized = true;
              }
            }
          }
          return instance;
        }
      }
    }

You might have decided to use this pattern to determine whether to initialize a
value-type, since checking the variable for null isn't possible. If you had
some more complex set of state, perhaps you want to use a single `Boolean` rather
than checking, say, 10 separate variables to see if they have each been
initialized. Whatever your reasoning, as written the above code is prone to a
subtle race condition.

The problem here is that both reads of `initialized` and `instance` do not have
'acquire' semantics. Thus, instance could appear to have been read before
initialized, e.g. as follows:

| **Time** | **Thread A** | **Thread B** |
-----------|--------------|--------------|
| 0        |                                  | Reads instance as null    |
| 1        | Reads initialized as false       |
| 2        | Sets instance to ref to new obj  |
| 3        | Sets initialized to true         |
| 4        | Uses instance (initialized)      |
| 5        |                                  | Reads initialized as true |
| 6        |                                  | Uses instance (null!)     |

Thread B ends up returning a null reference. If a caller tried to use it, they
might encounter a spurious `NullReferenceException`, the cause of which is
incredibly hard to debug. For example:

    void f()
    {
      Singleton s = Singleton.Instance;
      s.DoSomething(); // Boom!
    }

For this to have happened, Thread B would have had to read instance entirely
out of order. It might have done so for any number of reasons. If it recently
executed some code that pulled it into cache—either directly or due to
locality—it isn't required to invalidate the cache with non-acquire reads,
even though it observed a new write with release semantics, because it's as if
the load was moved before the load of initialized. Or superscalar execution
might perform branch prediction and retrieve the value of instance, assuming
that initialized will be false, pulling it into cache ahead of the read of
initialized. Again, because it is a non-acquire read, this is a valid thing to
do. If it reads `initialized` as `true`, its prediction was actually correct, and
it just returns the `null` value that was pre-fetched. It might even be the case
that a compiler along the way moved the read, which is also entirely legal with
our memory model.

One possible solution for this is to employ a volatile-read on the first read
of the initialized variable, prohibiting the read of instance from moving prior
to the read of initialized. Control dependency prevents us from having to use a
volatile-read for the reads of both variables.

    class Singleton
    {
      private static object slock = new object();
      private static Singleton instance;
      private static int initialized;

      private Singleton() {}
      public Instance
      {
        get
        {
          if (Thread.VolatileRead(ref initialized) == 0)
          {
            lock (slock)
            {
              if (initialized == 0)
              {
                instance = new Singleton();
                initialized = 1;
              }
            }
          }
          return instance;
        }
      }
    }

You could have instead inserted a call to `Thread.MemoryBarrier` instead, which
is a two way memory-fence, in between if-block and the read of instance, but
the cost of a barrier is generally higher than both a `st.rel` and `ld.acq` because
it affects surrounding instructions and movement in both directions.

The take-away here is not that you must understand the specifics of how cache
coherency, speculative execution, and our memory model interact. Rather, it
should be that once you venture even slightly outside of the bounds of the few
"blessed" lock-free practices mentioned in the article mentioned above, you are
opening yourself up to the worst kind of race conditions. Using locks is a
simple way to avoid this pain. And hopefully someday in the future,
transactional memory will enable performant execution of code with lock elision
techniques that lead to the performance of lock-free code, but without any of
the mental illness that such techniques have been proven to cause.

