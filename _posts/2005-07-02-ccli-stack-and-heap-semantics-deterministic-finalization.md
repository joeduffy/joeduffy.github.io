---
layout: post
title: C++/CLI, stack and heap semantics, deterministic finalization, ...
date: 2005-07-02 10:48:50.000000000 -07:00
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
[Those](http://pluralsight.com/blogs/hsutter/)
[guys](http://blogs.msdn.com/slippman/) on the VC++ team have been busy
workers. In the Whidbey release of C++/CLI (was Managed C++), they've added [a
whole big batch of new
features](http://msdn.microsoft.com/visualc/homepageheadlines/ecma/default.aspx).
The best part? Some of these are things you simply can't do in C#. Put another
way, C++/CLI exposes a larger set of the underlying features that the CTS/CLI
has to offer.

For example, want to create a ref type on the stack? Fine.

> MyType mt("Foo");

On the GC heap? Alright.

> MyType^ mt = gcnew MyType("Foo");

(Note if you're wondering "how'd they do that?" The answer is that the first
case only has stack _semantics_. It still lives on the GC heap. In other words,
it acts very similar to 'using' in C#, but it maps nicely to the C++
programmer's existing understanding of stack versus heap semantics.)

Similarly, did you want to maintain a typed reference to a boxed value type?
Ok.

> int^ i = gcnew int(5);

This compiles to IL which uses modopts to store typing and boxing information
so that the runtime/JIT know how to treat it, and for the verifier so that it
knows it's being used in a type-sound manner. Did you need a Nullable<int>?
Nonsense! Just set your reference to null and you've got it:

> int^ i = nullptr; // now it's null i = gcnew int(5); // now it's not

Furthermore, with stack semantics for ref types, deterministic finalization is
simple. Just write a destructor for your type (it gets compiled down to a
Dispose method), and it gets invoked for you when leaving the scope. Just like
the old C++ days. This means you can say:

> { StreamReader sr(...); // do some stuff with stream }

And sr gets disposed just prior to leaving the block scope. You can also create
your own standard resource mgmt wrappers like that come with TR1 (e.g.
tr1::shared\_ptr<>). Using the terms that Rico Mariani came up with in a
meeting a while back, you've got "the bang" and "the twiddle"...

> !MyType() {} // the bang: a finalizer ~MyType() {} // the twiddle: a Dispose
> method

They've also [implemented
STL](http://msdn.microsoft.com/visualc/?pull=/library/en-us/dnvs05/html/stl-netprimer.asp?frame=true)
with full interoperability with Whidbey's generics.

They've also implemented [OpenMP](http://www.openmp.org/), a fairly ubiquitous
shared memory parallelism library that I've been using a lot for research
recently. Now they just need
[MPI](http://www-unix.mcs.anl.gov/mpi/tutorial/gropp/talk.html) and the world
would be complete.

I'm using C++ for many things lately (mostly due to my Rotor work), and I have
to say: as I use it more and more, I am starting to miss it. But admittedly I
do sometimes prefer the cozy confines of managed code. C++/CLI enables me to
nicely sit in between the two worlds, getting the best of both (and leaving
behind the worst). There's a hell of a lot more to it than this post surfaces.
Check it out.

Happy hacking!

