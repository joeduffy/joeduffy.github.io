---
layout: post
title: Hacking away at STM on Rotor
date: 2005-05-28 13:20:06.000000000 -07:00
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
My implementation of Software Transactional Memory (STM) on Rotor is coming
along nicely. I've taken a different approach than most, actually taking
advantage of the JIT and EE to do my dirty work for me. Some prefer to stay
inside the cozy confines of managed code, but I'd like to understand better the
impact that my design might have on the non-transactional runtime. I admit that
my approach is likely not viable for real commercial use mostly due to its
intrusive nature. Unless all code were transactional, which it's not. But this
is partly what I'd like to understand better.

Most people confuse the idea of memory transactions with, say, database
transactions. The concepts are very similar, but memory transactions are about
dealing with concurrency at a much finer grained level (just your machine).
Rather than using locks to protect shared memory, STM prefers to enable
possibly conflicting operations to happen (inside a transaction), and then to
resolve them by comparing transaction records to memory at commit time. The
theory behind this work has been heavily influenced by database software, and
the techniques it uses for its own memory consistency models. You can read more
about STM on [Tim Harris](http://research.microsoft.com/~tharris)'s site (MSR
"smart dude"), e.g. these
[research](http://research.microsoft.com/~tharris/papers/2005-ppopp-composable.pdf)
[papers](http://research.microsoft.com/%7Etharris/papers/2003-oopsla.pdf).

My particular STM design affects the JIT, some core parts of the EE, requires
new managed classes, and also a bunch of new FCalls. I'm writing up a paper on
this project as I go, but in a few bullets here are the main points:

- Blocks of code can be marked as "atomic", along with options such as what
  style of locking (optimistic, pessimistic), granularity (memory
location/field, object), and retry semantics (0..n).

  - Atomic blocks get hoisted into methods of their own and annotated with a
    System.Threading.AtomicTransactionAttribute. This requires a hack to the C#
compiler; for now, I've simply required that people write the method and tag it
with [AtomicTransaction] on their own.

  - The runtime knows about [AtomicTransaction] and treats these methods
    differently (details below).

  - Note: I would like to understand how best to take advantage of and
    integrate with System.Transactions, but haven't gotten around to it yet.

- The MethodTable in the EE now contains a second set of vtable slots.

  - This second vtable contains atomic versions of the JITted code. We'll see
    what this means later.

  - All of the atomic vtable slots get pre-populated with a special JIT stub
    that invokes the JIT with a flag to indicate it desires atomic semantics.
If you never call a method atomically, the stub will never get replaced with
the JITted code, so this might not be as heavyweight as you first thought.

  - Any methods marked with [AtomicTransaction] get the atomic JIT stub for
    their ordinary vtable slot too.

- When the JIT is called with the atomic flag, it does a couple things out of
  the ordinary:

  - Method calls dispatch using the atomic vtable instead of the plain ole'
    vanilla vtable.

  - Any calls to ldfld, ldsfld, ldelem, ... get routed through a runtime
    helper. This helper knows about previous reads/writes in the same
transaction by consulting our transaction records in TLS. If we have written,
it retrieves that. Otherwise, it reads the underlying memory, records the value
read, and loads the value.

  - Any calls to stfld, stsfld, stelem, ... get run through a similar runtime
    helper. This simply records the written value in the active transaction.

- Then there are Commit/Rollback APIs which resolve conflicting read/writes,
  and actually writes any updates to the memory. It does this through a
nonblocking algorithm (assuming optimistic locking) which is guaranteed to
never deadlock.

  - If conflicts are found (memory value is different than the recorded read),
    it consults the transaction's retry options. If we haven't spent our
retries left count, we loop back and attempt the transaction over again.

  - Otherwise, we blit any writes to memory, mark the transaction as committed,
    and move on.

  - Note: I also support nested transactions which changes the behavior of
    commit slightly. Firstly, when a new [AtomicTransaction] method is reached,
we allocate a child transaction. Any reads must consult the parent chain for
writes that parent transactions have recorded. Then during commits for
children, we simply copy the contents of child reads/writes to the parent. The
parent is then responsible for detecting consistency with memory when it
decides to commit.

