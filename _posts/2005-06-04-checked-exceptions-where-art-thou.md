---
layout: post
title: Checked exceptions, where art thou?
date: 2005-06-04 21:59:52.000000000 -07:00
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
I remember the distinct feeling I got the first time I entered 'csc.exe' at the
command line and realized that the C# compiler wasn't doing any exception
checking for me. Surely I had done something incorrectly. Or so I thought.
After a bit of time searching around, asking around, and banging my head
against the wall (still got the fracture in my skull), I came to the
realization that C# had chosen not to support checked exceptions. Hmm.

### Surprised? Sure. Confused? Yep. Sad? Quite.

Once I began to understand the implications of this design choice, I just
became more and more confused. How the hell do I know in what manner this
method could fail?! Trial and error? Manually fuzzing an API and interpreting
the errors it throws? Wow, that seems like a great process, eh? Guessing? Not
caring? And nevermind the problem of it changing the exceptions it decides to
throw in the next version once I managed to figure it all out. (Remember:
exceptions aren't a static part of a method's signature like they are in Java,
so the implementation is free to silently alter its exception throwing policy
without notice.) The horridness of this situation seemed to spiral into a
rotting pit of smelly bannana peels.

The next phase of my surprise, disgust, confusion, <insert word here> was to
scour the tools and documentation. How could a hole this huge be left gaping
open? Surely either the Object Browser in VS or the SDK documentation would
fully expose this data, or maybe a magical IntelliSense switch that revealed
the Truth. Well, the answer was a resounding no. The SDK did an OK job (they're
getting better over time, but not nearly as good as JavaDoc can do with the
information stored in metadata), but they weren't complete, had to be grokked
out of band, and were free to change silently (all still significant problems
IMHO). And it didn't do much good for my own code and its exceptions!

I learned the ropes programming in x86 ASM and C, when I was ~13 and into
hacking MUDs and other games on Amiga, Linux, and then DOS. Then I moved to
C++. And then I moved to Java, and I stayed there for 5-ish years. Along the
way I experimented with LISP and Smalltalk, but never to a large degree. My
first professional programming experience was with C++ and COM, but by and
large I've written more lines of real project/product code in Java.

So my move to C# was one made with a lot of expectations around how things
worked, and it took me some time to get through a whole slew of these little
gotchas—small discrepancies between the JVM/Java and CLI/C#. But you know
what? There's only one that stands out in my mind today, and continues to
bother the hell out of me: _Checked exceptions_.

### Arguments against checked exceptions

If you haven't already, you should read this interview
[[http://www.artima.com/intv/handcuffs.html](http://www.artima.com/intv/handcuffs.html)]
with Anders Hejlsberg, the topic of which is C#'s decision not to support
checked exceptions. I keep referencing C# as being the decision maker; while
it's true that the CLI could have natively support them and thus it's in part
their decision too, I have little doubt they'd be there if C# 1.0 wanted them.
Further, Java's implementation is compiler-specific, and has no JVM support
other than the metadta, so it's not clear the CLI would have even had to
provide support.

Anders is a smart guy, one of very few Distinguished Engineers at Microsoft,
and has his head more than screwed on right and tight. The article sounds
reasonable, although a number of times I'm left thinking the data is
incomplete. Maybe my head's not quite right. Or maybe Java has corrupted my
mind.

I honestly see this debate as another incarnation of the static vs. dynamic
typing debate that often plagues the language space. There's not a right answer
in principle, but there's certainly an answer to what's right for the majority
of users of your language. Anders' certainly understands the target audience of
C# more than I do, so his call was probably right. But I'm left feeling
neglected, poor little Java programmer man.

Many people jump on the anti-checked exceptions bandwagon without ever having
done significant programming in Java. I'm sure Anders isn't in this camp. But a
lot of folks are. And until you've done significant programming and maintenance
on a complex system with checked exceptions, you are probably not going to
appreciate the safety and self-documentation of intent that it provides. You
absolutely cannot understand the benefits of checked exceptions by just writing
a 10-20 line program.

Some common claims made against checked exceptions come down to:

* Most developers subvert them.
* They make it difficult to version code.
* You usually don't want to catch an exception, you want to let it leak.

I disagree wholeheartedly with each of these statements. And here's why.

### Most developers subvert them

Based on a decent amount of Java experience, this is incorrect by a long shot.
In those 10-20 line programs I mentioned, yes a lot of folks write "throws
Exception" at the end of their methods, swallow exceptions, or generally
subvert the checked exceptions system. But do we really want to tune the C#
language for such small programs? I would argue Python, Perl, or a lighter
weight language that doesn't even do static type checking (since that's another
similar "annoyance" which prevents programs from compiling) for this category
of programs. When checked exceptions are understood or provide value,
subversion is unnecessary. I admit some users don't understand them (and hence
use them incorrectly in the way somebody might use any language feature
incorrectly), and that they don't provide value in the small, simple,
script-ish program cases.

### They make it difficult to version code

Hell yes they do! But it's "difficult" in a good way, the same way that it's
"difficult" to change the semantics or signature of a piece of code which is
relied on throughout a complex system. If you could change it without compiler
help, well, you'd be working in a dynamic language (and we ain't going there
right now buddy).

There are two basic cases to consider: versioning public APIs consumed by
somebody else and internal methods.

The API case is just like any other static feature of an API. Can you change
the signature of your method after you ship it? Yes you can, if you want to
break people. The same is true of checked exceptions. If you don't have a
statically checked list of exceptions you can throw, you're going to break
somebody anyhow.

If my API does this today:

    object Foo() {
      // …
      if (theNetworkIsUnavailable) throw new FooException();
      // … 
    }

And tomorrow it does:

    object Foo(int x) {
      // …
      if (theNetworkIsUnavailable) throw new NetworkConnectionUnavailable();
      // …
    }

Your code that used to say:

    try { 
      object o = Foo();
    } catch (FooException e) { 
      // Do something with it
    }

Will no longer catch the error condition, since `NetworkConnectionUnavailable`
will just head right past the `FooException` catch block. Hopefully your program
has a backstop to catch this and respond accordingly, but depending on your
error handling logic, this is likely to result in bugs either way. Is this the
type of thing you want silently slipping past a compiler? Probably not. If
you're writing an API, error conditions are like any other pre-/post-condition,
and should be treated as such. If the type system can enforce this, all the
better for program correctness I say. (Static vs. dynamic languages again,
ugh...)

The implementation case is simply not a problem. An implementation, by its
definition, is a method which other programs or units don't get to see or
use—i.e. non-public—and thus any problems are caught at compile time. You
don't have to recompile dependencies, for example, which you may or may not
have access to. This is just like changing the type or parameter list for a
method… You make the change, see where things fall out, and fix them. It's
the ordinary static language "beat the compiler" game. This is ordinarily a
good thing, as it forces you to take a look at the exception handling code at
the call sites to ensure they remain correct with the new exception behavior.

### You usually don't want to catch an exception, you want to let it leak

I would argue about the use of "usually" here, a more correct word being
"sometimes." And because this is a less-than-average situation, I don't think
the language should be tuned for it. It needs to support it, sure, but I am
arguing it's not the common case.

Note that Java supports unchecked exceptions in the type system. Basically,
anything that derives from `RuntimeException` needn't be checked. These are
common errors like `OutOfMemory`, `StackOverflow`, `NullRef`, and so on, which a
program almost never catches. Note that it does derive from `Exception`, so they
don't escape past general error handling code. These are by and large the
errors that developers merely want to leak, so the checked exception subsystem
doesn't get in your way here at all!

I also believe the style of coding which has a main entrypoint wrapped in an
exception handler is not the best way to do exceptions management. Perhaps I'm
whacked, but in most Java systems I've worked on, letting an exception rip up
the callstack to the toplevel is not the preferred approach, and wouldn't make
it past a single code review. Usually there's a common function used to publish
an error (e.g. pop UI, write to the log, and so on) once it gets caught, but
unless we need to tear down the application, the exception never shoots through
the entire program to the top, leaving holes in the brains of your callers.
Sure we have a handler at the top in case something escapes, but it's not
relied on as a crutch when we might be able to recover.

### But it ain't perfect

I agree that Java's implementation of checked exceptions isn't perfect. But I
feel much more comfortable in it than I do in C#'s fully unchecked system. Both
suffer from a common problem of code duplication or over-catching in the
handlers. My experience also shows that Java's exceptions class hierarchy is
better in the JSE (I know for sure at least two other smart people agree with
this), and its users tend to get their own exception hierarchies right. Without
a good factoring, a scaling problem ensues as you need to deal with a larger
quantity of exceptions. Your catch block has to either have 10 incarnations of
similar code for each exception type that can get thrown, you over-catch, or
you give up and subvert the system. But provided that the factoring is clean,
you can easily skirt this issue.

Still, having a

    catch (Exception ex) where ex : FooException, BarException,
                                    FooBarException
    {

    }

syntax which caught any instance of those three and stored
it into an Exception-typed variable would help to eliminate some of the
nastiness of exception handling code. An implementation of this using exception
filters in CLI would be trivial.

Having to deal with checked exceptions when you don't care would be a nice
thing to be able to express, for example, in the case of smaller programs. A
compiler switch would suffice here so long as the runtime doesn't actually
enforce the "handle everything but what you've said you're going to throw"
policy. The JVM itself doesn't do this check, that it's a compiler-only
enforced policy, so it's reasonable to expect that a CLI implementation would
be a compiler deicision. This JVM behavior exists so that versioning can occur
without recompilation.

There are other possible improvements, and certainly a whole category of other
statically-detectable things (pre-/post-conditions, invariants), but I'll stop
here. Since this is mostly a language decision, it's interesting to see some
approaches to solving the problem. For example, check out Spec#
[[http://research.microsoft.com/specsharp/](http://research.microsoft.com/specsharp/)]
a nifty rifty roo MSR project.

Checked exceptions as implemented in Java ain't perfect, but sufficiently close
that I miss it.

