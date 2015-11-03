---
layout: post
title: Hooking CLR blocking calls with SynchronizationContext
date: 2008-02-27 14:47:47.000000000 -08:00
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
I've [mentioned before](http://www.bluebytesoftware.com/blog/2006/11/10/FibersAndTheCLR.aspx)
that the CLR has a central wait routine that is used by any synchronization waits
in managed code.  This covers WaitHandles (AutoResetEvent, ManualResetEvent,
etc.), CLR Monitors (Enter, Wait), Thread.Join, any APIs that use such things, and
the like.  This routine even gets involved for waits that are internal to the
CLR VM itself.  This is primarily done so that the runtime can [pump appropriately
on STAs](http://blogs.msdn.com/cbrumme/archive/2004/02/02/66219.aspx), and was later
used to experiment with fiber-mode scheduler in SQL Server.  Two years ago I
showed how to use these capabilities to [build a deadlock detection tool via the
CLR's hosting APIs](http://msdn.microsoft.com/msdnmag/issues/06/04/Deadlocks/default.aspx).
Sadly IO-based waits (like FileStream.Read) do not route through this.

The System.Threading.SynchronizationContext class has a very cool (but not widely
known) feature that enables you to extend this central wait routine.  To do
so requires four steps: subclass SynchronizationContext; call base.SetWaitNotificationRequired; override
the virtual Wait method to contain some custom wait logic; and then register
your SynchronizationContext via the static SynchronizationContext.SetSynchronizationContext
method.  After you do this, most waits that occur on that thread will be
redirected through your custom Wait method.

Here's a very simple example of this:

```
using System;
using System.Threading;

class BlockingNotifySynchronizationContext : SynchronizationContext {
    public BlockingNotifySynchronizationContext() {
        SetWaitNotificationRequired();
    }

    public override int Wait(
            IntPtr[] waitHandles, bool waitAll, int millisecondsTimeout) {

        Console.WriteLine("Begin wait: {0} handles for {1} ms",
            waitHandles.Length, millisecondsTimeout);
        int ret = base.Wait(waitHandles, waitAll, millisecondsTimeout);
        Console.WriteLine("Finished wait");

        return ret;
    }
}

class Program {
    public static void Main() {
        SynchronizationContext.SetSynchronizationContext(
            new BlockingNotifySynchronizationContext());

        ManualResetEvent mre = new ManualResetEvent(false);

        mre.WaitOne(1000, false);
    }
}
```

If you run this, you'll see some messages printed to the console to do with beginning
and finishing waits.

A few things are worth noting:

- The Wait signature looks a lot like WaitForMultipleObjects.  In fact, it's
fairly trivial to turn around and call it via a P/Invoke.  Recovering from APCs
is a tad tricky however, and you'd have to do all of your own timeout management,
message pumping, and the like.

- You receive an IntPtr[], making it incredibly difficult to correlate the objects
being waited on with the actual synchronization objects from which they came (e.g.
Monitors, EventWaitHandles, etc.).

- The code that runs inside Wait is the wait itself.  In other words, when you
return, whatever code initiated the wait is going to assume that the API is being
honest and truthful.

Another subtlety is that this code, as written, is subject to stack overflow.
Why is that?  In this particular instance, Console.WriteLine may need to block
internally because it automatically serializes access to the output stream.
Well, when that blocks, it just goes through the same central wait routine, which
calls back out, and so on and so forth.  Obviously this extends to any code
that uses locks, including CLR services like cctors.  So the code you write
here needs to be very carefully written so as not to ever block recursively.

Notice that some waits do not call out.  The reason is that the callout stems
from a routine deep inside the CLR VM itself.  Some waits may occur while a
GC is in progress, at which point it's illegal to invoke managed code.  The
CLR just reverts to using its own default wait logic in such cases.

Lastly this is not a foolproof mechanism.  Other components can register their
own SynchronizationContexts, replacing the context you've installed completely.
This may mean you miss some blocking calls.  If you are building a ThreadPool,
you can always reset it each time the thread is returned, or even use your own ExecutionContexts when
running them.  It is also possible that such a context will exist by the time
you get around to installing your own.  For example, ASP.NET, WinForms, and
WPF use custom SynchronizationContexts.

If such a context exists already when you install this custom one, you can always
defer to it for things like CreateCopy, Send, Post, and Wait.  For example,
here's a SynchronizationContext implementation that allows custom before/after
wait actions, but otherwise relies on the existing SynchronizationContext (if any)
for things like Send, Post, and Wait:

```
using System;
using System.Threading;

delegate object PreWaitNotification(
    IntPtr[] waitHandles, bool WaitAll, int millisecondsTimeout);

delegate void PostWaitNotification(
    IntPtr[] waitHandles, bool WaitAll, int millisecondsTimeout,
    int ret, Exception ex, object state);

class BlockingNotifySynchronizationContext : SynchronizationContext
{
    private SynchronizationContext m_captured;
    private PreWaitNotification m_pre;
    private PostWaitNotification m_post;

    public BlockingNotifySynchronizationContext(
            PreWaitNotification pre, PostWaitNotification post) :
        this(SynchronizationContext.Current, pre, post) { }

    public BlockingNotifySynchronizationContext(
            SynchronizationContext captured, PreWaitNotification pre,
            PostWaitNotification post) {
        SetWaitNotificationRequired();

        m_captured = captured;
        m_pre = pre;
        m_post = post;
    }

    public override SynchronizationContext CreateCopy() {
        return new BlockingNotifySynchronizationContext(
            m_captured == null ? null : m_captured.CreateCopy(), m_pre, m_post);
    }

    public override void Post(SendOrPostCallback cb, object s) {
        if (m_captured != null)
            m_captured.Post(cb, s);
        else
            base.Post(cb, s);
    }

    public override void Send(SendOrPostCallback cb, object s) {
        if (m_captured != null)
            m_captured.Send(cb, s);
        else
            base.Send(cb, s);
    }

    public override int Wait(IntPtr[] waitHandles,
            bool waitAll, int millisecondsTimeout) {
        object s = m\_pre(waitHandles, waitAll, millisecondsTimeout);
        int ret = 0;
        Exception ex = null;
        try {
            if (m_captured != null)
                ret = m_captured.Wait(waitHandles, waitAll, millisecondsTimeout);
            else
                ret = base.Wait(waitHandles, waitAll, millisecondsTimeout);
        }
        catch (Exception e) {
            ex = e;
            throw;
        }
        finally {
            m_post(waitHandles, waitAll, millisecondsTimeout, ret, ex, s);
        }
        return ret;
    }
}

class Program {
    public static void Main()
    {
        SynchronizationContext.SetSynchronizationContext(
            new BlockingNotifySynchronizationContext(
                delegate { Console.WriteLine("PRE"); return null; },
                delegate { Console.WriteLine("POST"); }
            )
        );
        ManualResetEvent mre = new ManualResetEvent(false);

        mre.WaitOne(1000, false);
    }
}
```

That's a fair bit of code, but it's mostly boilerplate.  It allows you to
easily specify a pre/post action to be invoked upon each blocking call, and will
work on ASP.NET, GUI threads, and the like.  The pre action can return an
object for the post action to inspect.  And the post action is given the
return value and exception (if any).  If no SynchronizationContext was
present when installed, it just defers to the base SynchronizationContext implementation
of Send, Post, and Wait.

Now what you actually do inside those callbacks, I suppose, is entirely your
business ...

