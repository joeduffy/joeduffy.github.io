---
layout: post
title: 'Blogging about Midori'
date: 2015-11-03 15:29:00.000000000 -08:00
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
Enough time has passed that I feel safe blogging about my prior project here at
Microsoft, "Midori."  In the months to come, I'll publish a dozen-or-so articles
covering the most interesting aspects of this project, and my key take-aways.

Midori was a research/incubation project to explore ways of innovating
throughout Microsoft's software stack.  This spanned all aspects, including the
programming language, compilers, OS, its services, applications, and the overall
programming models.  We had a heavy bias towards cloud, concurrency, and safety.
The project included novel "cultural" approaches too, being 100% developers and
very code-focused, looking more like the Microsoft of today and hopefully
tomorrow, than it did the Microsoft of 8 years ago when the project began.

I worked on Midori from 2009 until we transitioned the teams to their respective
new homes during 2012-2014.  I led the groups focusing on the developer
experience: language, compilers, core frameworks, concurrency models, and
IDEs/tools.  And I wrote lots of code the whole time.

Although we started with C# and .NET, we were forced to radically depart in the
name of security, reliability, and performance.  Now, I am helping to bring many
of those lessons learned back to the shipping products including, perhaps
surprisingly, C++.  Most of my blog entries will focus on the key lessons that
we're now trying to apply back to the products, like asynchrony everywhere,
zero-copy IO, dispelling the false dichotomy between safety and performance,
capability-based security, safe concurrency, establishing a culture of technical
debate, and more.

I'll be the first to admit, none of us knew how Midori would turn out.  That's
often the case with research.  My biggest regret is that we didn't OSS it from
the start, where the meritocracy of the Internet could judge its pieces
appropriately.  As with all big corporations, decisions around the destiny of
Midori's core technology weren't entirely technology-driven, and sadly, not even
entirely business-driven.  But therein lies some important lessons too.  My
second biggest regret is that we didn't publish more papers.  This blog series
may help to recitify some of this.

I shall update this list as new articles are published:

1. [A Tale of Three Safeties](/2015/11/03/a-tale-of-three-safeties/)
2. [Objects as Secure Capabilities](/2015/11/10/objects-as-secure-capabilities/)
3. [Asynchronous Everything](/2015/11/19/asynchronous-everything/)
4. [Safe Native Code](/2015/12/19/safe-native-code)

Midori was a fascinating journey, and the most fun I've had in my career
to-date.  I look forward to sharing some of that journey with you.


