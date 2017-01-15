---
layout: post
title: 'Refactoring exception throw patterns: breaking or not?'
date: 2004-08-14 18:18:23.000000000 -07:00
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
Breaking changes are typically thought of as modifications which alter a public
API's surface area. For example, changing a method name from `Foo()` to `Bar()`, or
otherwise changing it's signature, such as adding a required parameter.
Anything else is simply implementation fodder, subject to change as more
efficient and/or appropriate means to compute the same result become available,
yes?

Well, not exactly. There are some subtleties. Depending on your perspective,
implicit semantic constraints - such as pre- and post-conditions - would likely
break existing code if altered behind a client's back. These are slightly less
tangible to understand in this context due to the lack of a standard static
representation of such notions in mainstream .NET languages. This subtlety is
also prevalent with structured exception handling. Consider the following
example.

Say there's a public API defined as such:

    public void DoThrowingOperation()
    {
      throw new CheckExceptionA("Test");
    }

And a client comes along, decides the API's useful enough to take a dependency
on (what, you say, that method's not very useful? bahhh), and adds code which
uses it:

    public void DoCheck()
    {
      CheckDepends cd = new CheckDepends();

      try
      {
        cd.DoThrowingOperation();
      }
      catch (CheckExceptionA e)
      {
        Console.WriteLine("Caught exception: " + e);
      }
    }

Well, it's entirely reasonable for them to expect that catching CheckExceptionA
is sufficient to recover from specific exceptions occurring from their
invocation to `DoThrowingOperation()`. That is, the only way an exception could
leak outside of this method is for a critical system error to occur, or perhaps
other exceptions coming from code upon which the public API depends. This is an
extremely naive viewpoint, and an obvious reason that clients should properly
factor their exception handling code to be resilient against the scenario I
describe (e.g. liberal use of finally clauses).

What if the public API changes its implementation vis-à-vis exception throwing
patterns? No verification errors here, the API surface area remains the same:

    public void DoThrowingOperation()
    {
      Random r = new Random(0, 1);

      if (r.Next() == 0)
        throw new CheckExceptionB("Ha ha");
      else
        throw new CheckExceptionC("You are broken");
    }

The implementers of the old `DoThrowingOperation()` thought it made more sense to
refactor their exception hierarchy, specifically to separate the errors thrown
into two more descriptive classes. Unless these new exceptions derive from the
old one (enabling polymorphic catching), however, any clients could be in for a
surprise if the new API version is deployed and bound at runtime. The client's
catch clause will never fire now, and in fact any of the new exceptions thrown
from this method will propagate freely up the caller's stack. Boom:

> Unhandled Exception: CheckExceptionB: Ha ha at
> CheckDepends.DoThrowingOperation() at CheckTest.DoCheck() at
> CheckTest.Main(String[] args)

One could easily rationalize this problem as a result of C#'s lack of checked
exceptions. And, of course, one would be wrong in doing so. Checked exceptions,
at least in Java's implementation, are nothing but a compiler trick.
Constraints as rich as those necessary to enforce call graph exception checking
are much too expensive to verify at runtime, and as such the situation is the
same in Java.

For example, this API:

    public void DoThrowingOperation() throws CheckExceptionA
    {
      throw new CheckExceptionA("Test");
    }

And this client code:

    public void DoCheck()
    {
      CheckDepends cd = new CheckDepends();

      try
      {
        cd.DoThrowingOperation();
      }
      catch (CheckExceptionA e)
      {
        System.out.println("Caught exception: " + e);
      }
    }

Wouldn't play very nicely if the API were altered slightly, even though the
API's static throws information has been changed correctly:

    public void DoThrowingOperation() throws CheckExceptionB, CheckExceptionC
    {
      if (Math.random() < 0.5)
        throw new CheckExceptionB("Ha ha");
      else
        throw new CheckExceptionC("You're broken");
    }

At least in the case of Java, the compiler would catch this problem the next
time the client recompiles. With C#, the problem could be a bit more difficult
and labor intensive to track down (since there's no easy way to detect this
statically or even report on what exceptions a given API could possibly throw,
a la JavaDocs). Both would likely result in nasty runtime bugs, however. I'd
love to see a feature in Reflector (well, a VS MDA would be even better) which
computes the possible exceptions a method invocation could leak. This is a bit
tricky because a deep call graph traversal needs to occur, but I'd even take a
list of exceptions thrown directly by the method in question.