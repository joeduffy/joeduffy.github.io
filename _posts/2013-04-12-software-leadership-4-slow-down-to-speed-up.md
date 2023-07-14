---
layout: post
title: 'Software Leadership #4: Slow Down to Speed Up'
date: 2013-04-12 11:06:33.000000000 -07:00
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
I am naturally drawn to teams that work at an insane pace. The momentum, and persistent
drive to increase that momentum, generates amazing results. And it's crazy fun.

In such environments, however, I've found one thing to be a constant struggle for
everybody on the team -- leaders, managers, and individual doers alike: remembering
to take the necessary time to do the right thing. This sounds obvious, but it's very
easy to lose sight of this important principle when deadlines loom, customers and
managers and shareholders demand, and the overall team is running ahead at a breakneak
pace.

A nice phrase I learned from a past manager of mine was, "sometimes you need to slow
down to speed up."

By taking shortcuts today, though attractive in that they help meet that next closest
deadline, you almost always pay for them down the road. You might subsequently become
quagmired in bugs because quality was comprimised from the outset. You may create
a platform that others build upon, only to realize later that the architecture is
wrong in need of revamping, incurring a ripple effect on an entire software stack.
You may realize that your whole system performs poorly under load, such that just
when your startup was beginning to skyrocket to success, users instead flee due to
the poor experience. The manifestation differs, but the root cause is the same.

The level of quality you need for a project is very specific to your technology and
business. I'll admit that working on systems software demands different quality standards
than web software, for example. And the quality demands change as a project matures,
when the focus shifts from writing reams of new code to modifying existing code...
although the early phases are in fact the most challenging: this is when the most
critical cultural traits are not yet set but are developing, when things have the
highest risk of getting set off in the wrong direction, and is when you are most
likely to scrimp on quality due to the need to make rapid progress on a broad set
of problems all at once.

So how do you ensure people end up doing the right thing? Well, I'd be lying if I
didn't say it is a real challenge.

As a leader, it is important to create a culture where individuals get rewarded for
doing the right thing. Nothing beats having a team full of folks that "self-police"
themselves using a shared set of demanding principles.

To achieve this, leaders needs to be consistent, demanding, and hyper-aware of what's
going on around them. You need to be able to recognize quality versus junk, so that
you can reward the right people. You need to set up a culture where critical feedback
when shortcuts are being taken is "okay" and "expected." I've made my beliefs pretty
evident in prior articles, however I simply don't believe you can do this right in
the early days without being highly technical yourself. As a team grows, your attention
to technical detail may get stretched thin, in which case you need to scale by adding
new technical leaders that share, recognize, and maintain or advance these cultural
traits.

You also can't punish people for getting less done than they could have if they took
those shortcuts. Many cultures reward those who hammer out large quantities of poorly
written code. You get what you reward.

In fact, you must do the opposite, by making an example out of the people who check
in crappy code.

Facebook has this slogan "move fast and break things." It may seem that what I'm
saying above is at odds with that famous slogan. Indeed they are somewhat contradictory,
however paradoxically they are also highly complementary. Although you need to slow
down to do the right thing, you do also need to keep moving fast. If that seems impossible,
it's not; but it sure is difficult to find the right balance.

I have a belief that I'm almost embarassed to admit: I believe that most people are
incredibly lazy. I think most quality comprimise stems from an inherent laziness
that leads to details being glossed over, even if they are consciously recognized
as needing attention. The best developers maintain this almost supernatural drive
that comes from somewhere deep within, and they use this drive to stave off the laziness.
If you're moving fast and writing a lot of code, strive to utilize every ounce of
intellectual horsepower you can muster -- sustained, for the entire time you are
writing code. Even if that's for 16 hours straight. If at any moment a thought occurs
that might save you time down the road, stop, ponder it, course correct on the fly.
This is a way of "slowing down to speed up" but in a way where you can still be moving
fast. Many lazier people let these fleeting thoughts go without exploring them fully.
They will consciously do the wrong thing because doing the right thing takes more
time.

I've developed odd habits over the years. As a compile runs, I literally pore over
every modified line of code, wondering if there's a better way to do it. If I see
something, I push it on the stack and make sure to come back to it. By the time I've
actually commited some new code -- regardless of whether it's 10,000 lines of freshly
written code, or a 10 line modification to some existing stuff -- chances are that
I've read each line of code at least three times. I disallow any detail I see to
slip through the cracks. And my mind obsesses over all aspects of my work, even during
"off times" (e.g., eating dinner, walking down the hallway, etc). Each of these opportunities
represents a chance to slow down, reflect, and course correct.

Do I still miss things? Sure I do. But that's why it's so critical to have a team
around you who shares the same principles and will help to identify any shortcomings
that I've missed.

Another practice I encourage on my team is fixing broken windows. I'm sure folks
are aware of the so-called [broken windows theory](http://en.wikipedia.org/wiki/Fixing_Broken_Windows),
where neighborhoods in which broken windows are tolerated tend to accumulate more
and more broken windows with time. It happens in code, too. If people are discouraged
from stopping to fix the broken windows, you will end up with lots of them. And guess
what, each broken window actually slows you down. As more and more accumulate, it
can become a real chore to get anything meaningful done. I guarantee you will not
be able to move very fast if too many broken windows pile up and start needing attention.
Slowing down to fix them incrementally, as soon as they are noticed, speeds you up
down the road.

Building a quality-focused team isn't easy. But creating a culture that slows down
to do the right thing, while simultaneously moving fast, provides an enormous competitive
advantage. It's not as common as you might think.

