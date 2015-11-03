---
layout: post
title: 'Sending messages: reentrancy vs. deadlocks'
date: 2006-12-29 11:27:31.000000000 -08:00
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
Deadlocks aren't always because you've taken locks in the wrong order.

In many systems, tasks communicate with other tasks through shared buffers.
In a concurrent shared memory system, these buffers might be simple queues shared
between many threads.  In COM and Windows GUI programs these buffers might take
the form of a window's message queue.  In any case, if some task A performs
a synchronous message send to task B, and task B does a synchronous send to task
A, near simultaneously, and if neither task continues to process incoming messages,
both will be blocked forever.

This is the classic reentrancy versus deadlock problem.  Ensuring that both
A and B continue to process incoming messages while blocked on a send will eliminate
the deadlock, albeit at the cost of possible reentrancy headaches.  Better yet,
you could just send messages asynchronously.

Things can get quite a bit more complicated than this, of course.  Imagine that
we have three operations, A, B, and C, being run over N concurrent streams of data.
We use data parallelism to partition the input data into and replicate the operations
over the N streams, such that we have A0…AN-1, B0…BN-1, and C0…CN-1 operating
on disjoint input.  A0 produces data for B0 which produces data for C0, and
so on.  Elements are pulled on demand from the leaves (A0…AN-1) to the root
(C0…CN-1), using a single execution resource (like a thread) per stream, i.e. E0…EN-1.

This is quite a bit like many real data parallel systems, including stream processing.

Imagine that sometimes AN finds that some input data must be given to BM instead
of BN (where N != M); there is a similar story for B and C too.  We might be
tempted to use some form of shared buffer to perform the inter-task communication
here.  In other words, when A0 finds something for B1, it sends the data to
it by placing it into B1's input buffer.  This might be done asynchronously,
i.e. A0 needn't wait for B1 to actually consume the message, hence avoiding the
sort of deadlock we noted earlier.

Unfortunately, since it might take some unknowable amount of time for B1 to process
its input, we might worry about excessive memory usage for these buffers.  So
we could put a bound on its maximum size using an ordinary bounded buffer… but
once we've done that, we have turned what was an asynchronous send into a possibly-synchronous
one, and in doing so introduced the same deadlock problem with which I began this
whole discussion.

We could solve this by ensuing that, whenever a task must block because the destination
buffer is full, it also processes incoming messages in its own buffer.  In other
words, we use reentrancy.  Sadly, things are not always quite so simple.

Imagine this case: A0 has found data for B1, but B1's buffer has become full.
So A0 is now waiting for B1 to process messages from its buffer to make room.
Nobody else will produce data for A0 at this point, so it's stuck waiting.
Sadly, B1 has too become blocked trying to send a message that it has found for C0.
Because the same execution resource E0 that must free space in C0's buffer is currently
blocked in A0 waiting for B1 to free space from its buffer, and because the execution
resource E1 is also waiting for E0, we now have a very convoluted deadlock on our
hands.

The solution?  There's no reason to keep the execution resource E0 occupied
in A0 waiting for B1 in this case.  E0 could instead be freed up to run C0,
freeing space for B1, and untangling the system.  Reentrancy strikes again,
but this time, in a good way.  Note that in a heterogeneous system where these
buffers are not controlled by the same resource, this solution is difficult to realize
in practice.  Maybe A uses a custom bounded buffer written in C# to communicate,
B uses SendMessages and COM message queues, and C uses GUI messages.  In this
case, orchestrating the waiting to be deadlock free becomes a real challenge.

