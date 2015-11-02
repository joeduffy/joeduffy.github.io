---
layout: post
title: Life lessons from Mr. COM STA
date: 2007-10-09 10:32:25.000000000 -07:00
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
When COM came onto the scene in the early 90's, Symmetric Muiltiprocessor (SMP)
architectures had just been introduced into the higher end of the computer market.
"Higher end" in this context basically meant server-side computing, a market
in which the increase in compute power promised increased throughput for heavily
loaded backend systems.  Parallelism per se—that is, breaking apart large
problems into smaller ones so that multiple processors can hack away to solve the
larger problem more quickly—was still limited to the domain of specialty computing,
such as high-end supercomputing and high-performance computing communities.
The only economic incentive for Windows programmers to use multithreading, therefore,
was limited mostly to servers.  Heck, parallelism is still pretty much limited
to those domains, but the economic incentives are clearly in the midst of a fundamental
change.

As is already well established, server-side computing is highly parallel for several
reasons.  The most obvious is the steady stream of work a server farm usually
enjoys, meaning there is seldom a shortage of compute work to do.  Even if work
is IO bound, there's typically at least some work that could use a CPU waiting
in the arrival queue to overlap execution with.  Moreover, sever workloads are
usually isolated except for some select and small amount of application-wide state.
Each user has his own account, order history, bank transaction information, etc.,
and therefore the interaction between sessions can be carefully controlled and nearly
non-existent, leading (once again) to a good cost/benefit tradeoff, due to the large
scalability wins.

Human productivity has always been markedly more important than other software features,
like performance, reliability, and security, unless the domains in which programs
are being developed require an intense focus on certain attributes.  I'm sure
the DOA prioritizes security far above productivity, but the same isn't true of
most of the industry.  This was true back in the COM days, and is still true
to this day (perhaps more so).  So it's safe to conclude that the designers
of COM had "ease of development" at the forefront of their minds when creating
it.  That coupled with the kind of multithreading in use back then on Windows
machines (servers), putting an emphasis on lack of sharing, lead to the development
of the Single Threaded Apartment (STA) model.  And, related, were COM+'s addition
of explicit [synchronization contexts](http://www.ddj.com/architect/184405771) which
took the STA auto-synchronization idea and generalized it to make synchronization
policies more customizable.

These features made synchronization, an often-impossible task, and less important
to be precise about when isolation is pervasive, much simpler.  Instead of having
to test a million different machine configurations, various difficult-to-predict-ahead-of-time
component interactions, and so on, a component got the STA stamp and was guaranteed
safe in a multithreaded environment.  The alternative then is the alternative
today: go free-threaded (MTA or NTA) and deal with all of the nasty synchronization
problems that arise "the old fashioned way."  In other words, use locks
and events, and run the risk of race conditions, deadlocks, and various other latent
bugs that would ruin the composability and reliability of any less-than-bulletproof
component.  Sadly, "the old fashioned way" is still "the state of the
art" until we build a better mousetrap.

Now, the STA's gotten a really bad rap over the years.  (I'll ignore synchronization
contexts for the time being but just about everything I say applies to them too.)
It's true that STAs cause us a lot of problems when thinking about legacy compatibility,
and will make it just that much more difficult to migrate legacy Windows apps over
to a massively parallel world, but I'm going to stick my neck out and make a claim
that won't win me friends (and in fact might lose me some): STAs aren't entirely
evil, and are an interesting idea that we as a community can learn a lot from.
What's more, we have years of experience using them.  I see a lot of people
basically reinventing the STA model, often without realizing it due either to a lack
of understanding of (or interest in) COM or simply a lack of pattern matching abilities.
"History will repeat itself, because nobody was listening the first time."

Automatic synchronization is now the holy grail of the new multicore era.  STM
is another attempt at that.  [Active objects](http://g.oswego.edu/dl/cpj/s4.5.html),
however, which have shown up in numerous places are another more closely related
attempt to the STA.  Yet another closely related technology is message passing
in general, where isolated domains of control do not share state and instead communicate
via disconnected message passing.  All strive to attain similar goals, improved
developer productivity and safety, usually with some performance or scaling overhead.
The biggest difference, from my perspective, is that design priorities are now different
due to the environment at the time these things are being created.  It's clear
today that any automatic synchronization technology we invent should scale to hundreds
(perhaps thousands) of processors, not one or two (or, at the extreme, eight), that
fine-grained parallelism will become more and more important, and that the degree
of sharing will be high, whether that means logically (by message exchange) or physically
(in the most literal shared memory sense).

Clearly the worst aspect of COM STAs is that they are obviously not up for the task
of scaling like this at such a fine-grain, because a single thread is responsible
for executing all code for some particular set of objects in the process.  It's
just plain impossible to parallelize finer than the granularity of a single component,
and it's common to glump many components together into one apartment which is worse.
As the number of available processors grows, and/or the number of objects instantiated
inside a particular STA which need to interact, scalability suffers.  Sadly
we've inherited huge hunks of code that have been written in this fashion, with
all of the assumptions about the multithreading environment in which the components
will be deployed as immutable laws.

But there are good things about COM STAs!  They are brain-dead simple in the
most common cases.  Synchronization doesn't take nearly as much brainpower
and development time away from the component creation process, improving developer
productivity and the robustness of the software written.  So long as your STA
component never blocks or performs a cross-apartment invocation, life remains very
simple.  This is an example of a leaky abstraction, however, because it's
not always evident to the programmer when this chasm has been crossed.  Proxies
do attempt to hide the gunk of crossing the chasm, though at the risk of introducing
reentrancy, which itself comes with a lot of baggage.  I'd like to stop and
point out something at this point, perhaps helping to support the "reinventing
the wheel" claim earlier.  Active objects and message passing systems generally
suffer from similar problems.  If one object uses another (by enqueueing a message)
and then, at some point, waits for a response message to arrive, there is the risk
that the thread which is now blocked will need to itself respond to a message coming
from another object.  Ahh, [the classic reentrancy versus deadlock tradeoff](http://blogs.msdn.com/cbrumme/archive/2004/02/02/66219.aspx).
Event-driven, stackless systems like the [Concurrency and Coordination Runtime (CCR)](http://channel9.msdn.com/wiki/default.aspx/Channel9.ConcurrencyRuntime),
etc., mitigate this problem but require a fundamentally different way of programming.
UI programmers are generally more comfortable with this approach.  And [linear
types](http://citeseer.ist.psu.edu/wadler90linear.html) a la [Singularity's exchange
heap](http://research.microsoft.com/users/larus/Talks/U%20Penn%20Singularity.pdf)
also offers a promising way to enable concurrency, but to safely guarantee certain
state will not be shared.

In the end, COM STAs are still an invention I wish we could do away with.  I
think of the technology a bit like a cheap, half-way immitation of  [Hoare's
CSPs](http://www.usingcsp.com/).  But at the same time, I fear we as an industry
will continue to reinvent them, just under a different guise or with subtly different
nuances.  We need to resist the urge to pretend they don't exist just because
they contain the letters C, O, and M and because the sound of STA is known to
trigger feelings of intense nausea.  What's scary to me is that, STM
aside, there doesn't seem to be any super-promising alternative to the automatic
synchronization problem for shared memory, aside from [provable declarative and functional
safety](www.haskell.org).  As I've noted above, true fine-grained message
passing has a lot of similar issues, but I do wonder at the end of the day if [Joe
Armstrong](http://armstrongonsoftware.blogspot.com/) has been right all along.
(Well,  [Tony Hoare](https://research.microsoft.com/~thoare/) really deserves
the credit, and perhaps [David May](http://en.wikipedia.org/wiki/Occam_programming_language)
too, but [Erlang](http://www.erlang.org/)is en vogue currently.)  Time
will tell.

