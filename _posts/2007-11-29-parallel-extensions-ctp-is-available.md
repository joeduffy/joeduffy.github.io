---
layout: post
title: Parallel Extensions CTP is available!
date: 2007-11-29 17:32:35.000000000 -08:00
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
Today is an extraordinarily exciting day for me.  After about two years of work
by several great people across the company, the first Parallel Extensions (a.k.a.
Parallel FX) CTP has been [posted to MSDN](http://www.microsoft.com/downloads/details.aspx?FamilyID=e848dc1d-5be3-4941-8705-024bc7f180ba).
Check out [Soma's blog post](http://blogs.msdn.com/somasegar/archive/2007/11/29/parallel-extensions-to-the-net-fx-ctp.aspx)
for an overview, and [the new MSDN parallel computing dev center](http://msdn2.microsoft.com/en-us/concurrency/)
for more details.  Keep an eye on [the team's new blog](http://blogs.msdn.com/pfxteam/)
too, as we'll be posting a lot of content there as we make progress on the library;
in fact, thanks to [Steve](http://blogs.msdn.com/toub/) (who writes blog posts in
his sleep), there's already a [bunch](http://blogs.msdn.com/pfxteam/archive/2007/11/29/6558413.aspx)
of [reading](http://blogs.msdn.com/pfxteam/archive/2007/11/29/6558570.aspx) to [catch](http://blogs.msdn.com/pfxteam/archive/2007/11/29/6558557.aspx)
[up](http://blogs.msdn.com/pfxteam/archive/2007/11/29/6558543.aspx) [on](http://blogs.msdn.com/pfxteam/archive/2007/11/29/6558508.aspx)!

I began kicking the tires on PLINQ back in October of 2005.  In September of
2006, [I described PLINQ](http://www.bluebytesoftware.com/blog/2006/09/13/HelloPLINQ.aspx)
as "a fully functional prototype" and "research."  Well, it's come
a long way since then, and we're finally ready for real human beings to start hammering
on it.  Not only that, but we've expanded the scope of the original project
significantly, from PLINQ to Parallel FX, to include new imperative data parallel
APIs (for situations where expressing a problem in LINQ is unnatural), powerful task
APIs that offer waiting and cancelation, all supported by a common work scheduler
based on [CILK-style](http://supertech.csail.mit.edu/cilk/) work-stealing techniques
developed in collaboration with Microsoft Research.  And there's even more
to come.  Daniel Moth spilled some beans in [his screencast on Channel9](http://channel9.msdn.com/Showpost.aspx?postid=361088)
when he described the additional data structures, like synchronization primitives
and scalable collections, which will come online later.  Some of them are even
in the new CTP, but have remained internal for now.

The shift to parallel computing will have an industry-wide impact, and will undoubtedly
take several phases and many years to tame completely.  We have focused on the
lowest hanging fruit and the most important foundational shifts in direction we can
incite—like encouraging the over-representation of latent parallelism to aid in
future scalability—but there are [certainly things](http://www.bluebytesoftware.com/blog/2007/11/11/ImmutableTypesForC.aspx)
that the current CTP doesn't fully address.  [GPGPU](http://research.microsoft.com/research/pubs/view.aspx?tr_id=1040)s,
verifiable thread safety, automatic parallelism, great tools support, etc., are all
topics that are of great interest to us.  We have a lot of work to do for the
final release of Parallel FX, and expect a whole lot of feedback from the community
on specific features and general direction.  So let us have it!  You
can use our [Connect](https://connect.microsoft.com/site/sitehome.aspx?SiteID=516)
site, or even just email me directly at joedu AT you-know-where DOT com.

Consider this an early Christmas present.  Now you have something fun to do,
in the privacy of your own office, when trying to avoid family members during the
holidays.  Whoops—did I say that out loud?  Enjoy!

