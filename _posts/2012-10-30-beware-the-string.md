---
layout: post
title: Beware the string
date: 2012-10-30 19:43:31.000000000 -07:00
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
.NET has a lovely property: it's got a single string type.

What's not to love about that? Anybody who has done more than an hour's worth of
Windows programming in C++ should appreciate this feature. No more zero-terminated
char\* vs. length-prefixed char\* vs. BSTR vs. wchar\_t vs. CStringA vs. CStringW
vs. CComBSTR. Just System.String. Hurray!

There's one very specific thing not to love, however: The ease with which you can
allocate a new one.

I've been working in an environment where performance is critical, and everything
is managed code, for several years now. That might sound like an oxymoron, but our
system can in fact beat the pants off all the popular native programming environments.
The key to success? Thought and discipline.

We, in fact, love our single string type. And yet our team has learned (the hard
way) that string allocations, while seemingly innocuous and small, spell certain
death.

It may seem strange to pick on string. There are dozens of other objects you might
allocate, like custom data types, arrays, lists, and whatnot. But there tend to be
many core infrastructural pieces that deal with string manipulation, and if you build
atop the wrong abstractions then things are sure to go wrong.

Imagine a web stack. It's all about string parsing and processing. And anything
to do with distributed processing of data is most likely going to involve strings
at some level. Etc.

There are landmine APIs lurking out there, like String.Split and String.Substring.
Even if you've got an interned string in hand (often rare in a server environment
where strings are built from dynamically produced data), using these APIs will allocate
boatloads of tiny little strings. And boatloads of tiny little strings means collections.

For example, imagine I just want to perform some action for each substring in a comma-delimited
string. I could of course write it as follows:

```
void Process(string s) { ... }

string str = ...;
string[] substrs = str.Split(',');
foreach (string subtr in substrs) {
    Process(substr);
}
```

Or I could write it as follows:

```
void Process(string s, int start, int end) { ... }

string str = ...;
int lastIndex = 0;
int commaIndex;
while ((commaIndex = str.IndexOf(',', lastIndex)) != -1) {
    Process(str, lastIndex, commaIndex);
    lastIndex = commaIndex + 1;
}
```

The latter certainly requires a bit more thought. That's primarily because .NET
doesn't have an efficient notion of substring -- creating one requires an allocation.
But the performance difference is night and day. The first one allocates an array
and individual substrings, whereas the second performs no allocations. If this is,
say, parsing HTTP headers on a heavily loaded server, you bet it's going to make
a noticeable difference.

Honestly, I've witnessed programs that should be I/O bound turn into programs that
are compute-bound, simply due to use of inefficient string parsing routines across
enormous amounts of data. (Okay, the developers also did other sloppy allocation-heavy
things, but string certainly contributed.) Remember, many managed programs must compete
with C++, where developers are accustomed to being more thoughtful about allocations
in the context of parsing. Mainly because it's such a pain in the ass to managed
ad-hoc allocation lifetimes, versus in-place or stack-based parsing where it's
trivial.

"But gen0 collections are free," you might say. Sure, they are cheaper than gen1
and gen2 collections, but they are most certainly not free. Each collection is a
linked list traversal that executes a nontrivial number of instructions and trashes
your cache. It's true that generational collectors minimize the pain, but they
do not completely eliminate it. This, I think, is one of the biggest fallacies that
plagues managed code to this day. Developers who treat the GC like their zero-cost
scratch pad end up creating abstractions that poison the well for everybody.

Crank up .NET's XmlReader and profile loading a modest XML document. You'll be
surprised to see that allocations during parsing add up to approximately 4X the document's
size. Many of these are strings. How did we end up in such a place? Presumably because
whoever wrote these abstractions fell trap to the fallacy that "gen0 collections
are free." But also because layers upon layers of such things lie beneath.

It doesn't have to be this way. String does, after all, have an indexer. And it's
type-safe! So in-place parsing at least won't lead to buffer overruns. Sadly, I
have concluded that few people, at least in the context of .NET, will write efficient
string parsing code. The whole platform is written to assume that strings are available,
and does not have an efficient representation of a transient substring. And of course
the APIs have been designed to coax you into making copy after copy, rather than
doing efficient text manipulation in place. Hell, even the HTTP and ASP.NET web stacks
are rife with such inefficiencies.

In certain arenas, doing all of this efficiently actually pays the bills. In others
arenas, it doesn't, and I suppose it's possible to ignore all of this and let
the GC chew up 30% or more of your program's execution time without anybody noticing.
I'm baffled that such software is written, but at the same time I realize that
my expectations are out of whack with respect to common practice.

The moral of the story? Love your single string type. It's a wonderful thing. But
always remember: An allocation is an allocation; make sure you can afford it. Gen0
collections aren't free, and software written to assume they are is easily detectible.
String.Split allocates an array and a substring for each element within; there's
almost always a better way.

