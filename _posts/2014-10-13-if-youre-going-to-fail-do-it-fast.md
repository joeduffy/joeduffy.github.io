---
layout: post
title: If you're going to fail, do it fast
date: 2014-10-13 19:25:47.000000000 -07:00
categories: []
tags: []
status: publish
type: post
published: true
meta:
  _edit_last: '1'
  _wpas_done_all: '1'
author:
  login: admin
  email: joeduffy@acm.org
  display_name: joeduffy
  first_name: ''
  last_name: ''
---
One technique we explored in [my team's language work](
http://joeduffyblog.com/2013/12/27/csharp-for-systems-programming/) is something
we call "fail-fast." The idea is that a program fails as quickly as possible after
a bug has been detected. This idea isn't really all that novel, but the ruthless
application of it, perhaps, was.

There are several sources of fail-fast in our system:

- Contract violation.
- Runtime assertion violation.
- Null dereference.
- Out of memory.
- Stack overflow.
- Divide by zero.
- Arithmetic overflow.

The funny thing is that if you look at 90% of the exceptions thrown in .NET, they
are due to these circumstances.

For example, instead of this (what it looks like in our system):

```
void Foo(int x)
    requires Range.IsValid(x, ...)
{
    ...
```

It ends up encoded like this:

```
void Foo(int x)
{
    if (!Range.IsValid(x, ...))
        throw new ArgumentOutOfRangeException("x");
    ...
```

In my experience, developers usually end up doing one of two things in response to
such a failure condition:

1. Catch and proceed, usually masking a bug and making it harder to detect later
on.
2. Let the process crash. After the stack has unwound, and finallys run, potentially
losing important debugging state.

I suppose there's a third, which is legitimately catch and handle the exception,
but it's so rare I don't even want to list it. These are usually programming errors
that should be caught as early as possible. The "catch and ignore" discipline is
an enormous broken window.

Exceptions have their place. But it's really that 10% scenario, where things operate
on IO, data, and/or are restartable (e.g., parsers).

As we applied fail-fast to existing code-bases, sure enough, we found lots of bugs.
This doesn't just include exception-based mishaps, but it also return-code based
ones. One program we ported was a speech server. It had a routine that was swallowing
HRESULTs for several years, but nobody noticed. Sadly this meant Taiwanese customers
saw a 80% error rate. Fail-fast put it in our faces.

You might question putting arithmetic overflows in this category. Yes, we use checked
arithmetic by default. Interestingly, this was the most common source of stress failures
our team saw. (Thanks largely to fail-fast, but also the safe concurrency model which
eliminated race conditions and deadlocks...but I digress). How annoying, you might
say? No way! Most of the time, a developer really didn't expect overflow to be possible,
and the silent wrap-around would have produced bogus results. In fact, a common source
of security exploits these days can be had by triggering integer overflows. Better
to throw it in the developer's face, and let him/her decide whether to opt-into unchecked.

Out of memory is another case that sits right on the edge. Modern architectures tend
to tolerate failure (e.g., being restartable, journaling state, etc), rather than
going way out of their way to avoid it, so OOM hardening tends to be rarer and rarer
with time. Hence, the default of fail-fast is actually the right one for most code.
But for some services -- like the kernel itself -- this may be inappropriate. It's
a blog post on its own how we handled this.

.NET already uses fail-fast in select cases, like [corrupted state exceptions](
http://msdn.microsoft.com/en-us/magazine/dd419661.aspx).

We are actively investigating applying the fail-fast discipline to C# and .NET more
broadly. For that, please stay tuned. However, even in the absence of broad platform
support, the discipline is an easy one to adopt in your codebase today.

