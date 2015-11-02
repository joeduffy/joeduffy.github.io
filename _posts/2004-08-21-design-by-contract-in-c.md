---
layout: post
title: Design by contract in C#
date: 2004-08-21 03:28:45.000000000 -07:00
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
Simply put, contract based programming formalizes the notion of a program's
input/output constraints, supplying first order language constructs to verify
and prove correctness. This includes, but is not limited to, the expression of
type invariants, pre- and post-conditions, reliability guarantees in the face
of unexpected failures, and side-effecting state modifications. For instance, a
method which performs division certainly does not want to accept a denominator
equal to zero, and an atomic operation producing a return value should always
ensure that certain type invariants and consistent state constraints remain
true at the end of its execution. Similarly, code which affects the environment
in which it executes likely should indicate to callers what to expect should a
failure occur; i.e. does an operation make (verifiable) guarantees regarding
what actions it will take and succeed at to attempt recovery, or does it simply
halt execution and throw an exception? One example of a language which employs
such concepts is Eiffel. ( [I recommend this article for a bit more
detail.](http://archive.eiffel.com/doc/manuals/technology/contract/))

I (along with a number of other people, smarter than myself) assert that
supporting such constructs, effectively embedding program correctness checks
directly into the runtime, results in a more reliable, stable, and bug-free
execution environment. With most mainstream programming languages lacking such
support, proofs and verifications are encoded in manual if(x){throw;}
statements, and proving correctness (hopefully!) captured in hand-crafted unit
tests. Unfortunately, this significantly hampers readability, writability, and
prevents any structured way to discover an operation's implicit contract,
leaving brute force poor-man's-proofs to perform a critical job. In fact,
testing as we know it changes dramatically with contract based programming,
essentially becoming an exercise in validating that the appropriate contract
guarantees have been put in place; the proof part is taken care of by the
execution environment.

While I've certainly not completed the thought process here, I wanted to walk
through some random ideas I have on the subject. To be entirely transparent, my
goal here is to add support to the C# language.

**Language Support**

Type invariants can easily be supported by requiring types to implement a
specific interface, for instance:

  **interface** IContract

  {

    **bool** Invariant();

  }

Specifically, however, my primary focus will be on pre- and post-conditions,
leaving the more difficult reliability and side effect support off the table
for now. Additionally, I explicitly wanted to avoid mandating developers to
sprinkle asserts throughout the main bodies of their code. (There are already
frameworks [out there](http://www.codeproject.com/csharp/designbycontract.asp)
that work in a similar fashion, and indeed System.Diagnostics.Debug.Assert() is
a handy tool for this job.) Because we have not yet devised a means by which to
express these constructs in code yet, the discussion will feel a bit loose to
begin with. Hopefully it comes together as my brain dump progresses…

Given the method:

  **int** divide( **int** a, **int** b)

  {

    **return** a / b;

  }

And its pre-condition: b != 0 and post-condition: returnValue == a / b, for
example.

The following pseudo-code represents one possible version of the desired
automatic expansion. (Note that the question of what specific assembly image
(debug vs. release, etc.), whether these checks occur at the call site or not,
etc. are all interesting questions I will consider below in the Runtime
Verification section. This section simply considers how to enable these
expressions in the C# language.)

  **int** divide( **int** a, **int** b)

  {

    assert(b != 0);

    **int** z = a / b;

    assert(z == a / b);

    **return** z;

  }

More generally and accurately, an expanded operation should look something like
this, ensuring an assignment to returnValue wherever the pre-expanded method
body returns just prior to doing so:

  **T** [...] operation( **T** a[...], ...)

  {

    // pre-condition asserts

    T returnValue;

    **bool** caughtFailure;

    **try**

    {

      // method body

    }

    **catch**

    {

      caughtFailure = **true** ;

      **throw** ;

    }

    **finally**

    {

      **if** (caughtFailure)

        // reliability asserts

      **else**

        // post-condition asserts

    }

  }

My initial approach was to consider using attributes. For example:

  [PreCondition("b != 0")]

  [PostCondition("returnValue == a / b")]

  **int** divide( **int** a, **int** b)

  {

    **return** a / b;

  }

This was attractive due to the reuse of an existing language feature, however
was quickly discarded for a number of reasons. First, expressing constraints
this way is an extraordinarily unnatural thing to do, especially given the
context and scope to which an attribute has access. The most viable option is
to express conditions and the variables to which they apply through very
loosely typed means, e.g. strings. Static verification at compile time is
challenging with this approach, although probably possible with a large amount
of effort. The idea here is that some post-compilation IL-modifier would run,
mangling the IL output by the C# compiler, and expanding it into the
appropriate code. The attributes disappear from the metadata, and leaves a
trace behind only in the form of the expanded pseudo-code above. Perhaps rather
than expressing constraints like a mini-scripting language, it could be
replaced by simple method references,

  **bool** Equal( **int** x, **int** y)

  {

    **return** x == y;

  }

  **bool** NotEqual( **int** x, **int** y)

  {

    **return** x != y;

  }

  [PreCondition("NotEqual(b, 0)")]

  [PostCondition("Equal(returnValue, ???)")]

  **int** divide( **int** a, **int** b)

  {

    **return** a / b;

  }

But this feels very heavyweight and limited (i.e. you'd need to write a method
for each condition; some out of the box ones could be provided, such as
IsGreaterThan(x,y) for example, but custom checks would be awkward to create.
Additionally, achieving composability seems almost as awkward as the
script-like syntax. However, allowing code to be written within strings not
only feels too loosely typed, but is really just a hack. This feels like a dead
end.

So the next natural step was to consider an extension to the C# grammar. While
more complex to implement, it feels like the right way to go about things. The
options are endless (well, almost)… however, after a couple minutes of
playing around, I've become particularly fond of the following syntax,

  **int** [== a / b] divide( **int** a, **int** b[!= 0])

  {

    **return** a / b;

  }

The code within the brackets implicitly adopts the variable it straddles as its
l-value. It isn't too much of a stretch to envision the code within each
bracket either being expanded into the method's body, or perhaps being pulled
out into another operation. This job could be performed by a pre-compiler, and
would result in a very statically typed solution. One problem with this
approach, however, is that the first class notion of a constraint is lost in
the compiled image. No trace is left behind of these checks, removing the
possibility of using the data for static consumption; e.g. documentation,
call-site verification, etc.

A possible solution is to use a combination of the two approaches outlined
above. The attributes could serve as a metadata manifestation of these language
constructs. But then we've come almost full circle… if attributes are good
enough to embed call-site enforcement, then the language support is just
superfluous syntactic sugar. Perhaps not. Remember, one of the primary goals is
to support better readability and writability, which the language support
certainly enables. I think we've got a workable solution!

This has the end result of looking as though you'd written the following code:

  [PreCondition("a != 0")]

  [PostCondition("returnValue == a / b")]

  **int** divide( **int** a, **int** b)

  {

    // pre-condition asserts

    assert(a != 0);

    **int** returnValue;

    **bool** caughtFailure;

    **try**

    {

      // method body

      returnValue = a / b;

    }

    **catch**

    {

      caughtFailure = **true** ;

      **throw** ;

    }

    **finally**

    {

      **if** (!caughtFailure)

        // post-condition asserts

        assert(returnValue == a / b);

    }

  }

Now, just to implement it…

**Runtime Verification**

Some interesting questions arise while considering the implementation. I
haven't thought enough about these problems to surface answers to them all, but
nonetheless they are quite interesting.

Done correctly, each operation will probably accumulate quite a few contract
constraints, many of which might be expensive to actually execute at runtime.
This is perhaps the price you must pay for rock solid, provable reliability,
but optimization is not out of the question. A category of checks can probably
occur only at compilation time, while another category will execute during
runtime. The boundaries of a program are the most obvious pain point on which
to focus first. By performing a transitive proof, and if inputs and outputs are
guaranteed to be within our expectations, then it makes sense that within our
program these constraints must hold true. Mathematic proofs are generally
infallible, and this approach uses the same concepts. Thus runtime verification
should always occur at any input or output boundary, but it's also unlikely
that this is the extent of it due to such dynamic things as late bound
invocations.

Call-site enforcement is also interesting. In many cases, the caller is the one
who cares most about having a reliable, correct program. However, cases also
exist in which APIs have a significant enough stake in the system as a whole
that they would prefer to see such constructs enforced, too, especially when
lacking a certain level of trust with the consumer. (Consider core OS APIs, for
instance, which most likely would prefer that the system stay in a provable and
consistent state at every instant during a program's execution. For other core
OS code which uses it, a given API might just trust that it will do the right
thing; however, for applications executing within an Internet-zone, for
instance, this is unlikely to remain true.) So it seems that a mixture of call-
and called-site enforcement is necessary. Preventing duplicate execution of
checks presents a challenge, as does determining exactly what mixture is
correct.

There are certainly other considerations to make, such as proper subtyping and
variant contracts, for instance, but I'm too tired to think about them right
now. ;)

