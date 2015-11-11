---
layout: post
title: 'Objects as Secure Capabilities'
date: 2015-11-10 16:03:00.000000000 -08:00
categories: []
tags: []
status: publish
type: post
published: true
author:
  display_name: joeduffy
  first_name: Joe
  last_name: Duffy
  email: joeduffy@acm.org
---
[Last time](http://joeduffyblog.com/2015/11/03/a-tale-of-three-safeties/), we
saw how Midori built on a foundation of type, memory, and concurrency safety.
This time, we will see how this enabled some novel approaches to security.
Namely, it let our system eliminate [ambient authority and access control](
https://en.wikipedia.org/wiki/Ambient_authority) in favor of [capabilities](
https://en.wikipedia.org/wiki/Capability-based_security) woven into the fabric
of the system and its code.  As with many of our other principles, the
guarantees were delivered "by-construction" via the programming language and its
type system.

# Capabilities

First and foremost: what the heck are capabilities?

In the security systems most of us know and love, i.e. UNIX and Windows,
permission to do things is granted based on concepts like users and groups.
Certain objects like files and system calls can be protected by access controls
that restrict what users and groups can do things with said objects.  At
runtime, checks are performed to enforce these access controls, using ambient
identity like what user the current process is running as.

To illustrate this concept, consider a simple C call to the `open` API:

	void MyProgram() {
		int file = open("filename", O_RDONLY, 0);
		// Interact with `file`...
	}

Internally, this call is going to look at the identity of the current process,
the access control tables for the given file object, and permit or reject the
call accordingly.  There are various mechanisms for impersonating users, like
`su` and `setuid` on UNIX and `ImpersonateLoggedOnUser` on Windows.  But the
primary point here is that `open` just "knew" how to inspect some global state
to understand the security implications of the action being asked of it.

Well, what's wrong with this?

It's imprecise.  And thanks to its imprecision, it's easy to get wrong, and
going here wrong means security attacks.  Specifically, it's easy to trick a
program into doing something on behalf of a user that it was never intended to
do.  This is called the ["confused deputy problem"](
http://c2.com/cgi/wiki?ConfusedDeputyProblem).  All you need to do is trick the
shell or program into impersonating a superuser, and you're home free.

Capability-based security, on the other hand, isn't reliant on global authority
in this same manner.  It uses so-called "unforgeable tokens" to represent
capabilities to perform operations.  No matter how the decision is made, if the
software isn't meant to perform some operation, it simply never receives the
token necessary to do said operation.  Since tokens are unforgeable, the program
cannot even attempt the operation.  In a system like Midori's, type safety meant
that not only could the program not perform the operation, it would often be
caught at compile-time.

The hypothetical `open` API from earlier, as you may have guessed, would look
very different:

	void MyProgram(File file) {
		// Interact with `file`...
	}

I've just passed the buck.  *Someone else* has to show up with a File object.
How do they get one?  That's up to them.  But if they *do* show up with one,
they must have been authorized to get it, because object references in a type
safe system are unforgeable.  The matter of policy and authorization are now
pushed to the source.

I'm over-simplifying a little bit, since most of the interesting questions just
evaporated from the conversation.  Let's keep digging deeper.

How does anyone actually produce a File object?  The code above neither knows
nor cares whether where it came from.  All it knows is it is given an object
with a File-like API.  It might have been `new`'d up.  More likely, it was
obtained by consulting a separate entity, like a Filesystem or a Directory:

	Filesystem fs = ...;
	Directory dir = ... something(fs) ...;
	File file = ... something(dir) ...;
	MyProgram(file);

You might be getting really angry at me now.  Where did `fs` come from?  How did
I get a Directory from `fs`, and how did I get a File from `dir`?  One could
reasonably claim I've just squished all the interesting topics around, and
answered very few.

The reality is that those are all the interesting questions you encounter now
when you try to design a filesystem using capabilities.  You probably don't want
to permit free enumeration of the entire filesystem hierarchy, because if you
get access to a Filesystem object -- or the system's root Directory -- you can
access everything, transitively.  That's the sort of thinking you do when you
begin dealing with capabilities.  You think hard about information encapsulation
and exposure, because all you've got are objects to secure your system.
Probably, you'll have a way that a program requests access to some state
somewhere on the Filesystem, declaratively, and then the "capability oracle"
decides whether to give it to you.  This is the role our application model
played.  From that point onwards it's just objects.  The key is that nowhere in
the entire system will you find the classical kind of ambient authority, and so
none of these abstractions can "cheat" in their construction.

A classic paper, [Protection](
http://research.microsoft.com/en-us/um/people/blampson/08-Protection/Acrobat.pdf),
by Butler Lampson clearly articulates some of the key underlying principles.  In
a sense, each object in our system is its own "protection domain."  I also love
[Capability Myths Demolished](http://srl.cs.jhu.edu/pubs/SRL2003-02.pdf)'s way
of comparing and contrasting capabilities with classical security models, if you
want more details (or incorrectly speculate that they might be isomorphic).

Midori was by no means the first to build an operating systems with object
capabilities at its core.  In fact, we drew significant inspiration from
[KeyKOS](http://www.cis.upenn.edu/~KeyKOS/NanoKernel/NanoKernel.html) and its
successors [EROS](https://en.wikipedia.org/wiki/EROS_(microkernel)) and
[Coyotos](http://www.coyotos.org/docs/misc/eros-comparison.html).  These
systems, like Midori, leveraged object-orientation to deliver capabilities.  We
were lucky enough to have some of the original designers of those projects on
the team.

Before moving on, a warning's in order: some systems confusingly use the term
"capability" even though aren't true capability systems.  [POSIX defines such a
system](http://c2.com/cgi/wiki?PosixCapabilities) and so [both Linux and Android
inherit it](https://www.kernel.org/pub/linux/libs/security/linux-privs/kernel-2.2/capfaq-0.2.txt).
Although POSIX capabilities are nicer than the typical classical ambient state
and access control mechanisms -- enabling finer-grained controls than usual --
they are closer to them than the true sort of capability we're discussing here.

# Objects and State

A nice thing about capabilities simply being objects was that could apply your
existing knowledge of object-orientation to capabilities, and hence the domain
of security and authority.

Since objects represented capabilities, they could be as fine or coarse as you
wish.  You could make new ones through composition, or modify existing ones
through subclassing.  Dependencies were managed just like any dependencies in an
object-oriented system: by encapsulating, sharing, and requesting references to
objects.  You could leverage all sorts of [classic design patterns](
https://en.wikipedia.org/wiki/Design_Patterns) suddenly in the domain of
security.  I do have to admit the simplicity of this idea was jarring to some.

One fundamental idea is [revocation](http://c2.com/cgi/wiki?RevokableCapabilities).
An object has a type and some systems -- like ours did -- let you substitute one
implementation in place of another.  That means if you ask me for a Clock, I
needn't give you access to a clock for all time.  Or even the real one for that
matter.  Instead, I could give you my own subclass of a Clock that delegates to
the real one, and rejects your attempts after an event occurs.  You've got to
either trust the source of the clock, or explicitly safe-guard yourself against
it, if you aren't sure.

Another concept is state.  In our system, we banned mutable statics, by-
construction, in our programming language.  That's right, not only could a
static field only be written to once, but the entire object graph it referred to
could only be written to during construction.  It turns out mutable statics are
really just a form of ambient authority, and this approach prevents someone
from, say, caching a Filesystem object in a global static variable, and sharing
it freely, thereby creating something very similar to the classical security
models we are seeking to avoid.  It also had many benefits in the area of safe
concurrency and even gave us performance benefits, because statics simply became
rich constant object graphs.

The total elimination of mutable statics had an improvement to our system's
reliability that is difficult to quantify, and difficult to understate.  This is
one of the biggest things I miss.

Notice that I mentioned Clock above.  This is an extreme example, however, yes,
that's right, there was no global function to read time, like C's `localtime` or
C#'s `DateTime.Now`.  To get the time, you needed to explicitly request a Clock
capability.  This had the effect of eliminating non-determinism from an entire
class of functions.  A static function that didn't do IO -- something we could
ascertain in our type system (think Haskell monads) -- now became purely
functional, memoizable, and even something we could evaluate at compile-time (a
bit like [`constexpr`](http://en.cppreference.com/w/cpp/language/constexpr) on
steroids).

I'll be the first to admit, there was a maturity process that developers went
through, as they learned about the design patterns in an object capability
system.  It was common for "big bags" of capabilities to grow over time, and/or
for capabilities to be requested at an inopportune time.  For example, imagine
a Stopwatch API.  It probably needs the Clock.  Do you pass the Clock to every
operation that needs to access the current time, like Start and Stop?  Or do you
construct the Stopwatch with a Clock instance up-front, thereby encapsulating
the Stopwatch's use of the time, making it easier to pass to others (recognizing,
importantly, that this essentially grants the capability to read the time to the
recipient).  Another example, if your abstraction requires 15 distinct
capabilities to get its job done, does its constructor take a flat list of 15
objects?  What an unwieldy, annoying constructor!  Instead, a better approach is
to logically group these capabilities into separate objects, and maybe even use
contextual storage like parents and children to make fetching them easier.

The weaknesses of classical object-oriented systems also rear their ugly heads.
Downcasting, for example, means you cannot entirely trust subclassing as a means
of information hiding.  If you ask for a File, and I supply my own CloudFile
that derives from File and adds its own cloud-like functions to it, you might
sneakily downcast to CloudFile and do things I didn't intend.  We addressed this
with severe restrictions on casting and by putting the most sensitive
capabilities on an entirely different plan altogether...

# Distributed Objects and IO

I'll briefly touch on an area that warrants a lot more coverage in a future
post: our asynchronous programming model.  This model formed the foundation of
how we did concurrent, distributed computing; how we performed IO; and, most
relevant to this discussion, how capabilities could extend their reach across
these critical domains.

In the Filesystem example above, our system often hosted the real object behind
that Filesystem reference in a different process altogether.  That's right,
invoking a method actually dispatched a remote call to another process, which
serviced the call.  So, in practice, most, but not all, capabilities were
asynchronous objects; or, more precisely, unforgeable tokens that permit one to
talk with them, something we called an "eventual" capability.  The Clock was a
counter-example to this.  It was something we called a "prompt" capability:
something that wrapped a system call, rather than a remote call.  But most
security-related capabilities tended to be remote, because most interesting
things that require authority bottom out on some kind of IO.  It's rare you need
authority to simply perform a computation.  In fact, the filesystem, network
stack, device drivers, graphics surfaces, and a whole lot more took the form of
eventual capabilities.

This unification of overall security in the OS and how we built distributed, and
highly concurrent, secure systems, was one of our largest, innovative, and most
important accomplishments.

I should note, like the idea of capabilities in general, similar ideas were
pioneered well before Midori.  Although we didn't use the languages directly,
the ideas from the [Joule](
https://en.wikipedia.org/wiki/Joule_(programming_language)) language and, later,
[E](https://en.wikipedia.org/wiki/E_(programming_language)), laid some very
powerful foundations for us to build upon.  [Mark Miller's 2006 PhD thesis](
http://www.erights.org/talks/thesis/markm-thesis.pdf) is a treasure trove of
insights in this entire area.  We had the privilege of working closely with one
of the brightest minds I've ever worked alongside, who happened to have been a
chief designer of both systems.

# Wrapping Up

There is so much to say about the benefits of capabilities.  The foundation of
type safety let us make some bold leaps forward.  It led to a very different
system architecture than is commonplace with ambient authority and access
controls.  This system brought secure, distributed computing to the forefront in
a way that I've never witnessed before.  The design patterns that emerged really
embraced object-orientation to its fullest, leveraging all sorts of design
patterns that suddenly seemed more relevant than ever before.

We never did get much real-world exposure on this model.  The user-facing
aspects were under-explored compared to the architectural ones, like policy
management.  For example, I doubt we'd want to ask my mom if she wants to let
the program use a Clock.  Most likely we'd want some capabilities to be granted
automatically (like the Clock), and others to be grouped, through composition,
into related ones.  Capabilities-as-objects thankfully gives us a plethora of
known design patterns for doing this.  We did have a few honey pots, and none
ever got hacked (well, at least, we didn't know if we did), but I cannot attest
for sure about the quantifiable security of the resulting system.  Qualitatively
I can say we felt better having the belts-and-suspenders security at many layers
of the system's construction, but we didn't get a chance to prove it at scale.

In the next article, we'll dig deeper into the asynchronous model that ran deep
throughout the system.  These days, asynchronous programming is a hot topic,
with `await` showing up in [C#](
https://msdn.microsoft.com/en-us/library/hh156528.aspx), [ECMAScript7](
http://tc39.github.io/ecmascript-asyncawait/), [Python](
https://www.python.org/dev/peps/pep-0492/), [C++](
http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2014/n4134.pdf), and more.
This plus the fine-grained decomposition into lightweight processes connected by
message passing were able to deliver a highly concurrent, reliable, and
performant system, with asynchrony that was as easy to use as in all of those
languages.  See you next time!

