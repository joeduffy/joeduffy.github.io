---
layout: post
title: A plethora of programming languages
date: 2004-07-21 17:40:54.000000000 -07:00
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
[Microsoft Research](http://research.microsoft.com/) has a number of very
interesting programming languages currently baking in the oven. I find most of
them extremely interesting, and will probably be babbling on about some of them
in the coming weeks. Here's a quick breakdown of what appears to be available:

[AsmL](http://research.microsoft.com/fse/asml/): Stands for the Abstract State
Machine Language, and is an "executable specification language." It was
designed to allow people to write executable, verifiable design blueprints
through the use of abstract state machines. This one is a CLI language, and
sounds like it integrates nicely with the rest of the Framework.

[Cw](http://research.microsoft.com/Comega/): X#, then Xen, and now Cw
(C-Omega). Based on C#, but extends it in some particularly cool ways. It
enables first class support for XML and data manipulation. The core concept is
discussed in good detail within a number of very well known essays (_
[Programming with Rectangles, Triangles, and
Circles](http://www.cl.cam.ac.uk/~gmb/Papers/vanilla-xml2003.html)_, and _
[Unifying Tables, Objects, and Documents
[PDF]](http://research.microsoft.com/users/schulte/Papers/UnifyingTablesObjectsAndDocuments(DPCOOL2003).pdf)_).
A managed language.

[F#](http://research.microsoft.com/projects/ilx/fsharp.aspx): A great mixed
language (functional and imperative) based on ML and Caml. This one is also
CLI-based, and as such one of its primary goals was to function nicely with the
rest of the Framework. That said, it implements many of the OCaml libraries so
it remains autonomous if that's what you're looking for.

[Pan](http://conal.net/pan/): An odd little one. A Haskell-based functional
language, whose primary goal is to enable image manipulation and pretty nifty
graphical effects. Looks like a fun language (and would be even better if it
was implemented against Avalon!). It ships with its own interpreter, so it's
definitely not CLI-based.

[Vault](http://research.microsoft.com/vault/): A C-like grammar which adds to
the classic language some syntactic sugar and many managed-code-ish features.
It also uses the notion of API interfaces which, in addition to defining
logical groupings of functionality, supports some contract-driven features. For
example, compile-enforced pre-conditions are a core language facet. While it
isn't a CLI language, it still looks to be scrumbibilyunctious.

