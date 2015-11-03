---
layout: post
title: Tasks and asynchronous control flow
date: 2009-10-31 21:06:24.000000000 -07:00
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
Well, Visual Studio 2010 Beta 2 is [out on the street](http://msdn.microsoft.com/en-us/vstudio/dd582936.aspx).
It contains plenty of neat new things to keep one busy for at least a rainy Saturday.
I proved this today.

Of course, Parallel Extensions is in the box.  .NET 4.0's Task and Task&lt;T&gt; abstractions
are used to implement such things as PLINQ and Parallel.For loops, but of course
they are great for representing asynchronous work too.  The FromAsync adapters
move you from the dark ages of IAsyncResult to the glitzy new space age of tasks.

Not only are tasks tastier than hamburgers, but they enable complex dataflow graphs
of asynchronous work to unfold dynamically at runtime, thanks to the ContinueWith
method.  From a Task&lt;T&gt; you can get a Task&lt;U&gt; that was computed based on
the T; ad infinitum.  We like dataflow.  It is the key to unlocking
parallelism, or more accurately, boiling away all else _except for_ dataflow is
the key.  But what about control flow, you might ask?  We like it less.
But you can do it, so long as you put in some work.  F#'s async workflows make
this sort of thing a tad easier, but the raw libraries in .NET 4.0 don't come with
any sort of loops or conditional capabilities.  Perhaps in the future they will.
Nevertheless, in this post I shall demonstrate how to build a couple simple ones.

Not because the lack of them is going to cause unprecidented and unheard of horrors,
but rather because in doing so we'll see some neat features of tasks.

The two methods I will illustrate in this post are:

```
public static class 
{
    public static Task For(int from, int to, Func<int, Task> body, int width);
    public static Task While(Func<int, bool> condition, Func<int, Task> body, int width);
}
```

Notice that each body is given the iteration index and is expected to launch asynchronous
work and return a Task.  The parameters that these methods take are probably
obvious.  Well, except for the last one.  The "width" indicates how many
outstanding asynchronous bodies should be in flight at once.  The Task returned
by For and While won't be considered done until all iterations are done, and any
exceptions will be propagated as you might hope.  It would be pretty useless
otherwise.

For example, we could write a while loop that does something very silly:

```
TaskControlFlow.While(
    i => i < 100,
    i => { return CreateTimerTask(250).ContinueWith(_ => Console.WriteLine(i)); },
).Wait();
```

This just prints returns a "timer task" that completes after 250ms and prints out
the iteration to the console. We pass a width of 4, so only four tasks will be outstanding
at any given time.  Notice we call Wait at the end, since both For and While
return tasks representing the in flight work.  This could have instead been
written using a For loop as follows:

```
TaskControlFlow.For(0, 100,
    i => { return CreateTimerTask(250).ContinueWith(_ => Console.WriteLine(i)); },
).Wait();
```

The CreateTimerTask method, by the way, looks like this:

```
private static Task CreateTimerTask(int ms) {
    var tcs = new TaskCompletionSource<bool>();
    new Timer(x => ((TaskCompletionSource<bool>)x).SetResult(true), tcs, ms, -1);
    return tcs.Task;
}
```

As something more realistic, imagine we wanted to do something with a large number
of files, and don't want to block a whole bunch of threads in the process.
The following "simple" expression will count up all of the bytes for all of the files
in a particular directory, without once blocking the thread -- well, except for the
initial call to Directory.GetFiles:

```
string win = "c:\\...\\";
string[] files = Directory.GetFiles(win);
int total = 0;

TaskControlFlow.For(0, files.Length,
    i => {
        bool eof = false;
        int offset = 0;
        byte[] buff = new byte[4096];
        FileStream fs = File.OpenRead(files[i]);

        return TaskControlFlow.While(
            j => !eof,
            j => Task<int>.Factory.FromAsync<byte[],int,int>(
                    fs.BeginRead, fs.EndRead,
                    buff, offset, buff.Length, null, TaskCreationOptions.None).
                ContinueWith(v => {
                    if (eof = v.Result < buff.Length) {
                        fs.Close();
                    }
                    offset += v.Result;
                    Interlocked.Add(ref total, v.Result);
                }),
            
        );
    },
).Wait();

Console.WriteLine(total);
```

Pretty neat.  We've somewhat arbitrarily chosen a width of 8 for this loop.
And notice something very subtle but important here: we've chosen a width of 1 for
the inner loop that plows through the bytes of a file.  This is because we're
sharing state, and it would not be safe to launch numerous iterations at once.
The same byte[], eof variable, and so forth, would become corrupt.  I will mention
in passing that it's unfortunate that we've got that interlocked stuck in there to
add to the total.  Refactoring this so that we could just do a LINQ reduce over
the whole thing would be nice.  Indeed, it can be done.

We can do away with the For implementation very quickly.  It is just implemented
in terms of While:

```
public static Task For(int from, int to, Func<int, Task> body, int width) {
    return While(i => from + i < to, body, width);
}
```

And it turns out that the While implementation is not terribly complicated either.
Here it is:

```
public static Task While(Func<int, bool> condition, Func<int, Task> body, int width) {
    var tcs = new TaskCompletionSource<bool>();
    int currIx = -1; // Current shared index.
    int currCount = width; // The number of outstanding tasks.
    int canceled = 0; // 1 if at least one body was cancelled.
    ConcurrentBag<Exception> exceptions = null; // A collection of exceptions, if any.

    // Generate a continuation action: this fires for each body that completes.
    Action<Task> fcont = null;
    fcont = tsk => {
        if (tsk.IsFaulted) {
            // Accumulate exceptions.
            LazyInitializer.EnsureInitialized(ref exceptions);
            foreach (Exception inner in tsk.Exception.InnerExceptions) {
                exceptions.Add(inner);
            }
        }
        else if (tsk.IsCanceled) {
            // Mark that cancellation has occurred.
            canceled = 1;
        }
        else if (canceled == 0 && exceptions == null) {
            // If no cancellations / exceptions are found, attempt to kick off more work.
            int ix = Interlocked.Increment(ref currIx);
            if (condition(ix)) {
                // Generate a new body task, handling exceptions.  Then make sure 
                // tack on the continuation on that new task, so we can keep on going...
                // If the condition yielded 'false', we'll simply fall through and try to finish.
                Task btsk;
                try {
                    btsk = body(ix);
                }
                catch (Exception ex) {
                    btsk = AlreadyFaulted(ex);
                }
                btsk.ContinueWith(fcont);
                return;
            }
        }

        // If this is the last task, signal completion.
        if (Interlocked.Decrement(ref currCount) == 0) {
            if (exceptions != null) {
                tcs.SetException(exceptions);
            }
            else if (canceled == 1) {
                tcs.SetCanceled();
            }
            else {
                tcs.SetResult(true);
            }
        }
    };

    // Fire off the right number of starting tasks.
    for (int i = 0; i < width; i++) {
        AlreadyDone.ContinueWith(fcont);
    }
    return tcs.Task;
}
```

I've commented the code inline to illustrate what is going on.  The only other
part that isn't shown are the AlreadyDone and AlreadyFaulted members, which simply
give Tasks that are already in a final state.  This isn't strictly necessary,
but come in handy in a number of situations:

```
internal static Task AlreadyDone;

static TaskControlFlow() {
    var tcs = new TaskCompletionSource<bool>();
    tcs.SetResult(true);
    AlreadyDone = tcs.Task;
}

private static Task AlreadyFaulted(Exception ex) {
    var tcs = new TaskCompletionSource<bool>();
    tcs.SetException(ex);
    return tcs.Task;
}
```

And that's it.  I'm done for now.  Hope you enjoyed it.  I've got
a few other posts in the works, including how to do speculative asynchronous
work for if/else branches, plus a neat example that illustrates how to do
dataflow-based speculation without having to wait for work to complete.  This
combines the new .NET 4.0 dynamic capabilities with parallelism, so I'm pretty excited
to get it working and write about it.

