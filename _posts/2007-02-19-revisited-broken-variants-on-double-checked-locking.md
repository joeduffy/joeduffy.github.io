---
layout: post
title: 'Revisited: Broken variants on double checked locking'
date: 2007-02-19 15:58:00.000000000 -08:00
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
A reader asked for clarification on [a past article of mine](http://www.bluebytesoftware.com/blog/PermaLink,guid,543d89ad-8d57-4a51-b7c9-a821e3992bf6.aspx),
regarding my claim that one particular variant of the double checked locking pattern
won't work on the .NET 2.0 memory model.  The confusion was caused because my
advice seems to contradict [Vance's MSDN article on the topic](http://www.bluebytesoftware.com/blog/ct.ashx?id=543d89ad-8d57-4a51-b7c9-a821e3992bf6&url=http%3a%2f%2fmsdn.microsoft.com%2fmsdnmag%2fissues%2f05%2f10%2fMemoryModels).

The problem is with variants of double checked locking that use a flag to indicate
that a variable has or has not been initialized, versus using the presence of null
to indicate this.  This can come in handy if null is a valid initialized value,
when the value is a value type, and/or if multiple variables are involved in the
initialization.

After following up with a few Microsoft and Intel folks about this, I still believe
this to be an issue.  Here is what I claim:

- Because standard Intel processors (X86/IA32, EM64T) use non-binding speculative
reads, the problem will not happen due to speculation.  And because processor
consistency memory models don't permit loads to freely reorder, this won't happen
because of cache hits.

- However, on IA64, non-volatile loads can be freely reordered, and therefore a cache
hit can cause the load of the value to pass the load of the flag.  I have not
been given a clear answer yet on the nature of IA64's speculation model, but I
suspect IA64 is non-binding too, and therefore this cannot occur as a sole result
of branch prediction (though that is pretty much immaterial because of cache reordering).

- In talking with some compiler folks here, they also agree that legal compiler transformations
(according to .NET 2.0's memory model) can break the code.

  - With that said, no Microsoft compiler we know of will actually make the transformation.

  - With some simple (though unlikely) modifications, existing compilers could
find it more attractive to apply CSE/PRE, causing the read to move and break the
code pattern.

The take-away is not necessarily the specific details, though perhaps those are interesting
too.  Rather, the primary take-away is that you really ought to use the _volatile
_modifier whenever you aren't 100% certain that the default memory model will prevent
these kinds of reorderings.  (And even then, volatile is still a good idea,
to declare your intent to other programmers looking at the code.)

As I mentioned in the original article, the use of volatile is enough to ensure this
particular example works correctly.

