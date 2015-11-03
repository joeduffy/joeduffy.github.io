---
layout: post
title: A bit more formalism as to why CLR's MM is broken on x86/x64
date: 2008-07-20 01:14:14.000000000 -07:00
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
Here's a slightly more formal approach to demonstrating that the CLR MM is improperly implemented
for the [particular example I showed earlier](http://www.bluebytesoftware.com/blog/2008/07/17/LoadsCannotPassOtherLoadsIsAMyth.aspx).

As the Java MM folks have done, I will use a combination of happens-before and synchronizes-with
relations, which allows order in a properly synchronized program to be describe as
a "flat" sequence with total ordering among elements.  Assume < means synchronizes-with.
If a happens-before b, and a < b, then any writes in a are visible to any loads in
b.  This relation is transitive: if a < b and b < c, then a < c.  Given
this, we can take an observed set of results (the values held in memory locations),
a hypothesized execution order (which we can infer from the observation), and validate
it against the program order (as written in the source); we do this by taking the
MM-specific synchronizes-with relation rules, and see if we can produce the observed
output given our belief of the execution order.  If we find a contradiction
(the execution order required to produce the output could not be produced given the
program order and MM rules), either there is an alternative execution order we failed
to guess, or we have found a violation of the memory model.

Single threaded programs are easy.  Multi threaded programs are hard.
We must manually "sequentialize" the program by constructing an interleaving of all
executed program operations into a single flat sequence, and permute them as needed
to produce the output in order to formulate a hypothesis of the execution order.
This is of course very difficult to do, so it only works with very small programs
(like the one I will show below).

I will try to define the CLR 2.0 MM in terms of synchronizes-with, although I have
to admit it's going to be difficult to do off the top of my head:

1. a < b, given a volatile load a that precedes any other memory operation b.
(Loads are acquire.)

2. a < b, given any memory operation a that precedes any other store b.
(Stores are release.)

3. a < b, given two separate memory operations a which precedes b that work
with the same memory location.  (Data dependence.)

4. a < b, given any memory operation a that precedes a full fence b.  (Cannot
move after a fence.)

5. a < b, given a full fence a that precedes some memory operation b.
(Cannot move before a fence.)

6. a < b, given a lock acquire a that precedes some memory operation b.  (Lock
acquires are acquire fences.)

7. a < b, given a memory operation a that precedes a lock release b.  (Lock
releases are release fences.)

Let's take the disturbing example, assuming all loads and stores are volatile.

```
X = 1;              Y = 1;
R0 = X;             R2 = Y;
R1 = Y;             R3 = X;
```

Let's hypothesize about execution order.

To produce an output in which R1 == R3 == 0, let us observe that it must be the case
that X = 1 and Y = 1 must not happen first.  If one such instruction does occur
first, then any possible outcome leads to R1 and/or R3 holding the value 1.
That is because of rule 3: if X = 1 happened first, then X = 1 < R3 = X, leading
to R3 == 1 and similarly if Y = 1 happened first, then Y= 1 < R1 = Y, leading to
R1 == 1.  So let us try to make X = 1 and Y = 1 not happen first.

Indeed, it is impossible for R0 = X or R2 = Y to happen first.  This is because
of CLR MM rule 3: X = 1; R0 = X leads to data dependence, and thus X = 1 < R0 = X.
Similarly, Y = 1 < R2 = Y.  Dead end.  Let's try the only other route.

The only remaining possibility to produce the output R1 == R3 == 0 is if R1 = Y or
R3 = X occurs first.  Let us try to make R1 = Y occur first.  Ah-hah!
We cannot!  Given CLR MM rule 1, R0 = X < R1 = Y.  And because of transitivity,
this necessarily implies that X = 1 < R1 = Y.  The same holds for the other
thread's instructions: Y = 1 < R3 = X.  The output R1 == R3 == 0 is therefore
a contradiction and disallowed by the CLR MM.

Now, this is light years from a formal proof, but is the reasoning I've been using
in my mind to explain why this new realization is fundamentally very disturbing and
is explicitly **not** allowed by the CLR MM. Thankfully it seems the JIT team agrees
and is willing to fix this for the next release. And, I'm still in search of an example
of code that is broken by this problem ...

