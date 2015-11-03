---
layout: post
title: Bjarne on exception safety
date: 2005-05-21 13:20:57.000000000 -07:00
categories:
- Miscellaneous
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
Structured exception handling and all of the challenges associated with it
aren't new topics about which developers must worry. I was flipping through my
copy of [The C++ Programming Language (3rd
Edition)](http://www.amazon.com/exec/obidos/ASIN/0201700735/bluebytesoftw-20)
this morning and ended up rediscovering Appendex E on C++ Standard-Library
Exception Safety. Understanding what consistency and failure guarantees you
intend to make with your library and then actually making them, knowing what to
expect from a pre-written library and when and how to program defensively
against it, and all such related topics were challenging with C++ and remain a
challenge with C#. It's amazing how many of these things are directly
transferrable between technologies.

He mentions in the book that all of the appendices are available on the web, so
I did [a quick
search](http://www.google.com/search?hl=en&q=c%2B%2B+stroustrup+exception+safety&btnG=Google+Search).
Voila! [Here it is [PDF].](http://www.research.att.com/~bs/3rd_safe.pdf)

Even if you're not a C++-er, you'll find a ton of great information in that
article. Enjoy. I did (again).

