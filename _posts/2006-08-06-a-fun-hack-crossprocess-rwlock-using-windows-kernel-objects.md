---
layout: post
title: 'A fun hack: Cross-process RWLock using Windows kernel objects'
date: 2006-08-06 16:29:13.000000000 -07:00
categories:
- Miscellaneous
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
This falls into the "fun hacks" category, meaning the result is not necessarily
something you'd want to use in your everyday life. To go a step further, I strongly
recommend you **don't use the code shown here as-is** ; read the summary at the end
for some rationale behind that statement. Enough with the disclaimer. On with the
show...

**Some requirements for our cross-process RWLock**

Imagine you had the need for:

1. A managed reader/writer lock
2. that runs on down-level (pre-Vista) operating systems,
3. and that optionally works across process boundaries and AppDomains.

What do we already have that might fit the bill? The existing ReaderWriterLock type
in the System.Threading namespace works fine for 1 and 2, but not 3. I suppose you
could share it across AppDomains--or even processes--with some form of messaging
scheme, but let's ignore that for a moment. It's a little \*too\* clever for my taste.
Windows Vista of course comes with [a new slim reader/writer lock](http://www.bluebytesoftware.com/blog/PermaLink,guid,17433c64-f45e-40f7-8772-dedb69ab2190.aspx).
It's a close cousin of the Win32 CRITICAL\_SECTION, and can be used for cross-AppDomain
synchronization. Unfortunately, you have to P/Invoke to get at it from managed code,
it won't run on pre-Vista operating systems, and doesn't work for cross-process scenarios.

**Let's build it out of duct tape and barbed wire**

It turns out that you can build a type that meets our requirements out of existing
Windows kernel objects. All it takes is a little imagination. Here's what you need:

1. A semaphore to count the number of readers inside the lock.
2. A mutex to ensure only one writer can be in the lock at a time.
3. (Optionally) a manual-reset event used by writers to ensure no new readers enter
the lock while it waits.

The scaffolding for one such implementation--which I will call the IpcReaderWriterLock--is
as follows:

```
public class IpcReaderWriterLock : IDisposable
{
    /** Fields **/
    private const int DEFAULT_MAX_READER_COUNT = 25;
    private const string NAME_PREFIX = @"IpcRWL#";

    private readonly int m_maxReaderCount;
    private Semaphore m_readerSemaphore;
    private EventWaitHandle m_blockReadsEvent;
    private Mutex m_writerMutex;
    private int m_writerRecursionCount;

    /** Constructors **/

    public IpcReaderWriterLock() :
        this(null, DEFAULT_MAX_READER_COUNT){ }

    public IpcReaderWriterLock(string name) :
        this(name, DEFAULT_MAX_READER_COUNT) { }

    public IpcReaderWriterLock(int maxReaderCount) :
        this(null, maxReaderCount) { }

    public IpcReaderWriterLock(string name, int maxReaderCount)
    {
        m_maxReaderCount = maxReaderCount;

        string blockReadsEventName = null;
        string writerMutexName = null;
        string readerSemaphoreName = null;

        if (name != null)
        {
            blockReadsEventName =
                string.Format("{0}{1}#{2}", NAME_PREFIX, name, "RdEv");
            writerMutexName =
                string.Format("{0}{1}#{2}", NAME_PREFIX, name, "WrMtx");
            readerSemaphoreName =
                string.Format("{0}{1}#{2}", NAME_PREFIX, name, "RdSem");
        }

        m_blockReadsEvent = new EventWaitHandle(
            true, EventResetMode.ManualReset, blockReadsEventName);
        m_writerMutex = new Mutex(false, writerMutexName);
        m_readerSemaphore = new Semaphore(
            maxReaderCount, maxReaderCount, readerSemaphoreName);
    }

    /** Methods **/
    public void Dispose()
    {
        // Just close all of the kernel objects we opened during construction.
        // Note: this method is not thread-safe. If threads race with
        // one another to call Dispose, some nasty bugs will arise.
        if (m_blockReadsEvent != null)
        {
            m_blockReadsEvent.Close();
            m_blockReadsEvent = null;
        }

        if (m_writerMutex != null)
        {
            m_writerMutex.Close();
            m_writerMutex = null;
        }

        if (m_readerSemaphore != null)
        {
            m_readerSemaphore.Close();
            m_readerSemaphore = null;
        }
    }

    public void EnterReadLock() { ... }

    public void ExitReadLock() { ... }

    public void EnterWriteLock()  { ... }

    public void ExitWriteLock() { ... }
}
```

Notice that we allow naming of the lock. Any name given flows into the kernel objects
used underneath, enabling cross-process and cross-AppDomain communication. You just
create the same IpcReaderWriterLock with the same name in multiple processes or AppDomains,
and they will magically interact with one another (whether you want them to or not).
An unnamed lock is isolated inside of the AppDomain in which it was created. Notice
also that there's a maximum number of simultaneous readers, the default for which
is 25. This isn't terribly important, but any override does impact performance (as
described below).

**Read and write lock implementation**

Now let's implement the read-lock acquisition and release functions, EnterReadLock
and ExitReadLock. We support more than one reader at a time via the use of a semaphore
(#1 above). We also support preventing blocking new readers from entering the lock
while the writer waits for all readers to exit (#3 above). Thus, both of these functions
are quite trivial to write:

```
public void EnterReadLock()
{
    Thread.BeginCriticalRegion();

    // We first wait on the read blocking event, in case a writer
    // has tried to acquire the lock and wants us to wait.
    m_blockReadsEvent.WaitOne();

    // Now take '1' from the reader semaphore to count the number
    // of simultaneous readers inside the lock.
    m_readerSemaphore.WaitOne();
}

public void ExitReadLock()
{
    // Just release '1' back to the semaphore to let others know
    // the number of simultaneous readers just decreased.
    m_readerSemaphore.Release();

    Thread.EndCriticalRegion();
}
```

Next comes the write-lock acquisition and release functions, EnterWriteLock and ExitWriteLock.
They are slightly more complicated, but not by much. First we acquire the writer
mutex. Once we've done that, we increment the recursion count, and ensure that we
do some other work only the first time a writer lock is acquired on the thread. We
block any new readers from entering, and then we effectively wait for all readers
to exit. We do that by acquiring the semaphore _n_ times, where _n_ is the maximum
number of readers that we support. Releasing the write lock does the reverse of all
of that:

```
public void EnterWriteLock()
{
    Thread.BeginCriticalRegion();

    // We have to first ensure only one writer can get in at a time.
    m_writerMutex.WaitOne();

    // Increment our recursion count.
    m_writerRecursionCount++;

    // For the first writer who enters, we need to block new readers
    // and wait for any existing readers to exit the lock.
    if (m_writerRecursionCount == 1)
    {
        // Next we block any new readers from entering the lock.
        m_blockReadsEvent.Reset();

        // And lastly, we ensure that all readers have exited the lock.
        // We do this by acquiring the semaphore's capacity. It's
        // unfortunate that the Win32 APIs don't support a take-n
        // function for semaphores.
        for (int i = 0; i < m_maxReaderCount; i++)
        {
            m_readerSemaphore.WaitOne();
        }
    }
}

public void ExitWriteLock()
{
    // We have to do everything in the reverse order as we did
    // during acquisition. Not doing so can lead to subtle bugs,
    // including lost resets and deadlocks.
    m_writerRecursionCount--;

    // The last writer to release has to signal readers.
    if (m_writerRecursionCount == 0)
    {
        // We release the semaphore's capacity back, enabling readers
        // to take from it. Note that as soon as we call this, other
        // threads may wake up and race to acquire the semaphore. In
        // fact, simultaneous readers can get in, even though we still
        // have a writer in here!
        m_readerSemaphore.Release(m_maxReaderCount);

        // Unblock any readers that are waiting. Note: ideally we would
        // do this after signaling writers, so that readers can't sneak
        // in before the writer, but that would be more complicated: we
        // keep it simple for now.
        m_blockReadsEvent.Set();
    }

    // And lastly release the mutex.
    m_writerMutex.ReleaseMutex();

    Thread.EndCriticalRegion();
}
```

And that's it. A fully functioning reader/writer lock, for some definition of "functioning."

**The test case**

This example wouldn't be complete with a simple test case to prove that it works.
The sample program included in the IpcReaderWriterLock source code creates 20
threads--10 readers and 10 writers--in 10 AppDomains. Each does a piece of work designed
to expose race conditions via context switching at sensitive points. It prints out
"Success" at the end, assuming it all worked. I see "Success" every time I run it,
so it works on my machine at least. Hooray.

**Summary: Don't use this thing**

OK, OK... this lock is pretty icky and nasty to be honest, and you probably wouldn't
want to use it. Ever. A simple write-lock acquisition incurs 27 kernel transitions
with the default settings. This ends up costing over 1000-times the cost a simple
monitor acquisition! (Yes, there are three 0's in that number... ouch.) Moreover,
the cost increases proportional to the number of simultaneous readers that the lock
instance supports, which is not very good. That's why I've used such a low default:
25. And it's not very reliable either, which, for anything that does cross-AppDomain
or cross-process synchronization can be disastrous. One process that crashes can
lead to machine-wide corruption and a user who needs to reboot the machine. A
much better lock (performant, reliable, etc.) could be built using memory mapped
files, although the implementation would be substantially more complicated.

I almost didn't write this post for all of these reasons. I'm not sure whether I'm
doing a disservice to my readers by doing this. Instead, I hope that showing how
simple Windows kernel objects can be composed together in interesting, powerful,
and non-obvious ways is interesting, if only for trivia reasons. I'd also like
to think that it may inspire you to think about things a little differently, perhaps
helping you to write clever (but useful!) things out of the building blocks you already
have.

