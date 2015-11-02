---
layout: post
title: 'Software Leadership #5: Blur the Line Between Research and Engineering'
date: 2013-07-13 17:15:34.000000000 -07:00
categories:
- Technology
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
What I am about to say admittedly flies in the face of common wisdom. But I grow
more convinced of it by the day. Put simply, there ought not to be a distinction
between software research and software engineering.

I'll admit that I've seen Microsoft struggle with this at times, and that this is
partly my motivation for writing this essay. An artificial firewall often exists
between research and product organizations, a historical legacy more than anything
else, having been the way that many of our industry's pioneers have worked (see
Xerox PARC, Bell Labs, IBM Research, etc). This divide has a significant cultural
impact, however. And although I have seen the barriers being broken down in most
successful organizations over time, we still have a long way to go. The reality is
that the most successful research happening in the industry right now is happening
in the context of real products, engineering, and measurements.

The cultural problem manifests in different ways, but the end result is the same:
research that isn't as impactful as it could be, and products that do not reach
their full innovation potential.

One pet peeve of mine is the term "tech transfer." This very phrase makes me cringe.
It implies that someone has built a technology that must then be "transferred" into
a different context. Instead of doing this, I would like to see well-engineered research
being done directly within real products, in collaboration with real product engineers.
Those doing research can run tests, measure things, and see whether -- in an actual
product setting -- the idea worked well or not. By deferring this so-called "transfer",
in contrast, the research is always a mere approximation of what is possible. It
may or may not actually work in practice.

Often product groups attempt to integrate so-called "incubation" efforts within their
team, however it is seldom effective. The idea is to take research and morph it into
a real product. I actually think that by doing joint research and engineering, we
can fail faster on the ideas that sounded good on the tin but didn't quite pan out,
while ensuring that the good ideas come to life quicker and with higher quality and
confidence.

A common argument against this model is that "researchers have different skillsets
than engineers." It's an easy thing to say, and almost believable, however I really
couldn't disagree more.

This mindset contributes to the cultural divide. I'll be rude for a moment, and depict
what happens in the extreme of total separation between research and engineering.
Should that happen, people on the product side of things see researchers as living
in an ivory tower, where ideas -- though they make for interesting papers -- never
work out in practice. And people on the research side naturally prefer that they
can more rapidly prototype ideas and publish papers, so that they can more quickly
move to the next iteration of the idea. They can sometimes view the engineers as
lacking brilliant ideas, or at least not recognizing the importance of what was written
in papers. Unfortunately, though this characterization is oozing with cynicism, both
parties may both actually be correct! Because the research is done outside of real
product, the ideas need some "interpretation" in order to work. And of course it's
usually in the best interest of the engineers to stick to their own (admittedly less
ambitious) ideas, given that they are more pragmatic and naturally constrained by
the realities of the codebase they are working in.

Back in the age of think-tank software research organizations -- such as Xerox PARC
and Bell Labs -- there truly was a large intellectual horsepower divide between
the research and engineering groups. This was intentional. And so the split made
sense. These days, however, the Microsofts and Googles of the world have just as
many bright engineers with research-worthy qualifications (PhDs from MIT, CMU, Harvard,
UCLA, etc.) as they have working in the research-oriented groups. The line is blurrier
than ever.

Now, I do divide computer science research activities broadly into two categories.
The first is theoretical computer science, and the second is applied computer science.
I actually do agree that they require two very different skills. The former is mathematics.
The latter isn't really science per se; rather, it's really about engineering.
I also understand that the time horizon for the former is often unknowable, and does
not necessarily require facing the realities of software engineering. It's about
creating elegant solutions to mathematical problems that can form the basis of software
engineering in the future. There is often no code required -- at most just a theoretical
model of it. And yet this work is obviously incredibly important for the long-term
advancement our industry, just as theoretical mathematics is important to all industries
known to mankind. This is the kind of science that has led to modern processor architecture,
natural language processing, machine learning, and more, and is undoubtedly what
will pave the way for enormous breakthroughs in the future like quantum computing.

But if you're doing applied research and aren't actively writing code, and as a
result aren't testing your ideas in a real-world setting, I seriously doubt the research
is any good. It certainly isn't going to advance the state of the art very quickly.
Best case, the ideas really are brilliant, and -- often a few years down the road
-- someone will discover and implement them. Worst case, and perhaps more likely,
the paper will get filed underneath the "interesting ideas" bucket but never
really change the industry. This is clearly not the most expedient way to impact
the world, when compared to just building the thing for real.

Coding, put simply, is the great equalizer.

Academia is, of course, a little different than industry, as there are frequently
no "software assets" of long lasting value within a particular university, and therefore
certainly no easy way to directly measure the success of those assets. But I still
think it is critical to engineer real systems when doing academic research. For academics,
there are options. You can partner with a software company or contribute to open
source, for example. Both offer a glimpse into real systems which will help to validate,
refine, and measure the worth of a good idea as realized in practice.

I absolutely adore the story of how Thad Starner managed to walk this line perfectly.
While researching wearable computing, he partnered with a company with ample resources
(Google) to build a truly innovative product that was years ahead of the competition
(Google Glass).

As you read on, I hope you agree that dichotomy is beginning to make a bit less sense...

Now I love the idea of writing papers. Doing so is critical for sharing knowledge
and growing our industry as a whole. We do far less of this than other industries,
and as a result I believe the rate of advancement is slower than it could be. And
as a company, I believe that Microsoft engineering groups do a very poor job of sharing
their valuable learnings, whereas our research groups do an amazing job. I truly
believe the usefulness of those papers would grow by an order of magnitude, however,
if they covered this research in a true product setting. I believe that sharing information
and sharing code is essential to the future growth of our industry, as it helps us
all collectively learn from one another and enables us to better stand on the shoulders
of giants. And if an idea fails in practice, we should understand why.

A lot of research organizations value code and building real things, but still keep
the group separate from the engineering groups. The building real things part is
a step in the right direction, however the tragedy is that most of the time such
research ends with a "prototype"; at best, some number of months (or years!) later,
the product team will have had a chance to incorporate those results. Perhaps it
happened friction-free, but in most cases, changes in course are needed, new learnings
are discovered, etc. What great additions these would make to the paper.

And, man, how painful is it to realize that you could have delivered real customer
value and become a true technological trendsetter, but instead sat idle, in the worst
case never delivering the idea beyond a paper, and in the best case delaying the
delivery and thus giving your competitors an easy headstart and blueprint for cloning
the idea. Even if you disagree with everything I say above, I doubt anybody would
argue with me that the pace of innovation can be so much greater when research and
engineering teams work more closely with one another.

The good news is that I see a very forceful trend in the opposite direction of the
classical views here. With online services and an ecosystem where innovation is being
delivered at an increasingly rapid pace, I do believe that mastering this lesson
really will be a "life or death" thing for many companies.

Next time somebody says the word "research", I encourage you to stop and ponder the
distinction from engineering they are really trying to draw. Most likely, I assert,
you will find that it's unnecessary. And that by questioning it, you may find a creative
way to get that innovative idea into the hands of real human beings faster.

