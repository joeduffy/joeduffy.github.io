---
layout: post
title: A few thoughts on the role of software architects
date: 2008-10-02 08:47:17.000000000 -07:00
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
The word "architect" means different things to different people in the context
of software engineering.  And it varies wildly depending on the kind of organization
you're in.  An architect at a medium sized IT shop might focus on connecting
disparate business systems together at a high level, but without diving down into
code.  An architect at a startup may be more like a tech lead, checking in code
like mad, but also keeping the rest of the team in check.  And a software architect
at Microsoft can play an even varied number of roles because the company is so large
and diversity of projects so great.

A colleague and mentor of mine who I respect greatly says that an architect is the
guy (or gal) who is in charge of making those decisions which, if made incorrectly,
could sink the project.

There is a lot to be said for this.  These decisions are those with the broadest,
deepest, and longest lasting impact.  The decisions themselves are often made
by team members initially, but the architect is responsible for providing constant
and rigorous technical oversight.  Architects set the high level technical agenda,
look ahead several releases, and keep the team on course.  They are ultimately
to blame if the technical foundation is unsound and/or final solution fails to meet
expectations.  Their butt is on the line.

On one hand, an architect is the lead engineer with most at stake in the project.
On the other hand, an architect is more like a member on the project's board of
directors, providing high level guidance and meddling as little as possible (but
as much as is necessary) in the day-to-day details.

An architect's success is measured by what he or she ships to customers, and not
by the amazing ideas that were ultimately never realized.  This necessarily
means an architect's success is deeply rooted in the team's culture, work ethic,
and ability.  He or she needs to work through others to get things done.

There have been some great architects throughout the course of computer science,
but who may not have been labeled as such.  Linus Torvalds is the architect
of Linux, and David Cutler the architect of Windows NT.  John Backus was arguably
the architect of FORTRAN, Niklaus Wirth the architect of Pascal, Bjarne Stroustrup
the architect of C++, James Gosling the architect of Java, and Anders Hejlsberg the
architect of C#.  Bill Gates was the architect of Microsoft BASIC, and Charles
Simonyi the architect of the initial versions of Microsoft Office (Word and Excel).
In each case, you can see that the end result is very reflective of one person's
value system and ideas, but took a lot more than just that person to be successful.
Each of these people learned to let go of their project just enough that it could
achieve the scale that it was meant to achieve, but not so much that the project
veered off course.  Some projects have multiple architects, but the successful
ones usually have one who is really in charge.

Already you can see some subjective opinion being thrown into the mix, and some of
it is apt to be controversial.  Although not comprehensive, I've put together
seven guiding principles that I personally aspire to.  I've certainly not
mastered them all, but have always looked up those people around me who seem to have.
Why seven?  No reason, really.  Over the past few years, I've tried to
spend as much time as possible learning from successful architects, and these stand
out in my mind as being the key common attributes that appear to be common among
them.

**0. Inspire and empower people to do their best work.**

Architects ultimately succeed or fail based on the quality of people on their team.
Knowing how to inspire and empower these people, so that they can do their best work,
is therefore one of the most important skills an architect needs in order to be successful.

You can't do it all yourself.  This can be frustrating at times, and at times
you might think that you can (particularly in times of frustration).  I've
personally hacked together 1,000s of lines of code that I'm incredibly proud of
in a weekend, and that would have taken weeks or months to get done if I had to instead
explain the idea to somebody else and wait for them to write those same 1,000s of
lines of code.  And the 1,000s of lines they write of course wouldn't end
up being the same as the ones you'd have written.  And they may decide that
they don't like the design after all, start discussing it with colleagues, stage
a mutiny, and ultimately overthrow what once seemed like a great idea.  This
is a tough pill to swallow.  But it's a sad fact of life that you need to
learn to be comfortable with.

The same thing would have happened if you were the one to implement the idea, of
course; the difference is that somebody else needs to be empowered to take the kernel
of an idea, and run with it.  That entails reshaping it as necessary to make
it realistic and successful.

I'm not suggesting architects don't write code (quite the opposite: see #3 below),
but you can't write it all (except for very small projects).  If you buy the
argument that an architect is just the leading senior engineer on the project, then
by definition the architect is probably qualified to write quality code quickly.
But what about the code they don't write?  Other people on the team need to
write it, and the architect needs to have enough time (where he or she isn't hacking
code) to inspire those people to write the right code.  This takes energy and
effort.  You need to paint a compelling picture of the future, but with enough
open-endedness such that the team can flex their creative muscles and fill in the
details.

This is the only way to scale.  And architects need to scale to achieve broad
impact.

Architects should also welcome all ideas with open arms.  You want to foster
an open and energetic environment on your team, where intellectual debate is the
norm.  All ideas are fair game.

That's not to say all ideas are good ones, and ultimately the bad ones need to
die a quick and painless death before going too far, but an architect who won't
even entertain new ideas from the team (typically because of NIH syndrome (i.e.,
Not Invented Here)) often drive away the best engineers.  Great engineers hate
to be told what to do.  They don't want to feel like they are walking in the
shadows of somebody else.  They want to use the skills that make them so great,
which involves inventing bigger, badder, and more impactful designs.  And you
want them to use these skills too, because that's why you hired them: these skills
are crucial to the success of your project.  Part of your role as the team's
architect is to recognize who on the team has the most potential, and to arrange
for them to have as much leeway and creative freedom as possible.  You don't
want to end up with a bunch of lackeys whose job is to "just implement" your
ideas, because you'll get what you paid for.

It's a true sign of success when the culture you impart unto your team allows them
to invent things in the spirit of your own design principles, but without you needing
to do it yourself.  Jim Gray, for example, inspired countless people to do great
things.  Does he get credit for each of those ideas?  Of course not.
But was he indirectly responsible for them to some degree, and do they all have a
little Jim Gray in them?  Absolutely.  Being an architect on a team is
similar; not every idea has to be your own.  In fact, it's far more powerful
if few of them are.

**1. Oversight, but not dictatorship.**

That brings me to technical oversight.  Because an architect is typically not
a manager for his or her project (although in some cases he or she may be), arms-length
influence needs to be used to get things done.  In fact, the architect may have
very little to say over specific project management, scheduling, and budget decisions,
but is typically on the senior leadership team for the project.  So when I talk
about "leeway" above, I'm talking about the degree to which an architect monitors
and attempts to meddle with the progress of the team.  While it's tempting
for an architect to set the ship sailing to sea, and then turn around to work on
the next big thing, this almost never works.  The initial vision and idea is
far from a shipping solution, and software engineering only gets interesting once
you actually try to build something.  Ideas are cheap.  The architect needs
to help the team work through the ramifications of certain technical decisions that
were made up front, and help with the continual course correction.

Because an architect's butt is ultimately on the line, he or she needs to work
as fast as possible to correct problems when something goes wrong.  This implies
the architect is involved enough to notice when something goes wrong, hopefully well
in advance of anybody else seeing it.  I've seen many models that work, ranging
from the architect being the approver for all major design decisions, to the architect
simply reviewing all major design decisions after-the-fact, to the architect delegating
this responsibility to trusted advisers.  For example, Linus Torvalds for the
longest time required that all checkins to the Linux code base be reviewed by him.
Anders Hejlsberg still effectively approves each C# language design change.
In my opinion, the closer to each major decision the architect can afford to be,
the better.

Left to its own devices, the team would veer off course in no time.  That's
not because of malicious intent, but rather because of the sheer diversity of software
engineers.  This diversity is present on many levels: in skill level, taste
(which is hard to measure: more on that in #2 below), motivation, work ethic, interpretation
of the vision, personal beliefs and experience, and so on.  An architect acts
as a low-pass signal filter, smoothing out any irregularities that deviate too far
from the core design principles.

In Tony Hoare's ACM Turing Award paper of 1981, The Emperor's Old Clothes, he
explains the risk of not providing this kind of architectural oversight:

"'You know what went wrong?' he shouted - he always shouted -- 'You let
your programmers do things which you yourself do not understand.' I stared in astonishment.
He was obviously out of touch with present day realities. How could one person ever
understand the whole of a modern software product like the Elliott 503 Mark II software
system? I realized later that he was absolutely right; he had diagnosed the true
cause of the problem and he had planted the seed of its later solution."

Sadly, this responsibility often entails being "the bad guy".  Sometimes
you need to mercilessly kill an idea because it would put certain parts of the project
at risk.  Other times you need to let somewhat bad (but not too impactful) ideas
go.  There's a tradeoff here, because each time you kill an idea you're
going to leave somebody feeling burned.  And you may waste peoples' time,
depending on how much time has already been invested in that idea.  Some battles
are best left unfought.  There is an art to be learned here: if you can get
those with the idea to firmly believe that there has to be a better way, you can
avoid being seen as the bad guy.  "Sit back and wait" can work in some cases,
but it can backfire too.

The deep involvement in the technical design details unfortunately means that the
architect can become the bottleneck if he or she is not careful.  This can slow
the team down.  Some slowdown can admittedly be a good thing, because it has
the effect of forcing more thoughtfulness in each and every decision.  But as
the team grows, the granularity of decision oversight necessarily has to change to
ensure the team is empowered to make progress.  In order for this to work, you
need to have trusted individuals who are involved at a finer granularity and will
use the same principles and values.  This takes trust and time.

**2. Taste is a hard thing to measure, but is invaluable.**

Software engineers like to measure.  Many people try to make design decisions
based on quantitative data, even though they know that engineering is more of an
art than a science.  But there is one common trait that, as far as I can tell,
is impossible to measure, and yet common to all of the great software architects
I know: good taste.  And because it's impossible to measure, those who lack
it have a hard time understanding the difference between a design with good taste
and one with bad taste.

There is a certain elegance and beauty to the designs created by architects with
good taste.  When you see it from a distance, you know it, but when viewed under
a microscope—the kind of microscope used when debating the finer points with other
engineers on the team—it is much harder to detect.  Often it's incredibly
difficult to articulate why some particular design has good taste, which makes it
even harder to justify.  Eventually people are willing to trust your judgment
because they begin to see it too.

In fact, good taste is perhaps one of the most important skills an architect needs
to have.  Bad taste leads to clunky designs that nobody likes to use.
Steve Jobs knows this.  And yet taste is probably the most difficult skill for
an architect to develop, and one of the subtler ones that few people recognize as
being necessary.  Many managers think that throwing more engineers at a design
problem will solve it, when in reality often all that is necessary is one person
with very good taste and an eye for detail.

I'm not certain where taste comes from: an innate skill?  Perhaps, but not
exclusively.  In my best estimation, good taste can be learned from paying close
attention to the right things, taking a step back and viewing designs from afar often
enough, being learned in what kinds of software has been built and was successful
in the past, and having a true love of the code.  That last part sounds cheesy,
but is true enough to reemphasize: if you don't feel a certain passion for your
code and project, it's a lot easier to let bad taste run rampant, because your
care level isn't as intense as it needs to be.

**3. Write code and get your hands dirty.**

The best architects realize that code is king.  It rules all else.  At
the end of the day, Visio diagrams, high level vision documents, whiteboard works
of art, design documents, emails, functional specifications, and so on, are all a
means to an end, not the end itself.  The code is your product, and if you don't
understand the code, you don't understand the state of the project.  And if
you don't understand that, you're not in a position to know what's working
well, what isn't working, and you can't possibly have the deep understanding
necessary to influence the engineers on the team.  You've lost control.

The worst architects couldn't code themselves out of a cardboard box.  If
you're not writing actual product code, you're not an architect: you're an
ivory tower has-been, and probably doing more damage than you are helping matters.
Do your team a favor and move into management as quickly as possible.

Writing code also has the benefit of ensuring that you maintain credibility with
the team.  It's easy to dictate crazy and grandiose ideas, but if you're
the one who has to implement such a grandiose idea, you're apt to be more sympathetic
with and mindful of the other engineers of the team.  You need to keep yourself
grounded and writing real product code will help to ensure your technical decision
making carefully considers the implementability and down-to-Earth ramifications of
your decisions.

Moreover, you need to be a programming expert.  People need to respect your
abilities, and you want your team to look up to you.  You want them to come
and ask for your advice because they want it, and enjoy it, and not force them to
deal with you simply because of your position on the team.  All of the great
architects I've worked with have inspired me to grow simply because they know so
damn much, and because I learn something new every time I interact with them.
If they didn't write code and understand the nitty gritty technical esoterica,
this relationship would have been a shallow one.

**4. The power of the dyad: know your weaknesses.**

Architects need to play a dual role in understanding both business and technical
needs and strategy.  The degree of business savviness varies greatly among architects,
although the best architects I know have a unique ability to understand both sides
of the coin.  But at the end of the day, they are first and foremost technology
wonks, and the business angle is more of a curious hobby.  In music, two notes
sounding together form dyad, while three or more form a chord.  The best architects
I know realize their relative weakness on the business end of things and partner
up with another senior leader with complementary skills, to fill in the gaps: this
forms a harmonic interval.  A dyad.

The partnership needn't entirely be "business" vs. "technical", although
in commercial software that's more often than not the two opposing forces.
For example, my impression of the development of Scheme is that Guy Steele played
the role of the architect while Gerald Sussman was the more business-oriented advisor,
looking at how Scheme might be used to advance the broader research agenda but not
necessarily meddling in the technical design details of the project.

If an architect is 80% technology and 20% business, partnering with somebody who
is 20% technology and 80% business can be a killer combination.  This allows
you to bounce ideas off one another, and to get a certain level of objective feedback
from a different perspective.  If you've got a great technical idea, and bounce
it off another techno-nerd, you might spend hours or days debating technical details
that ultimately boil down to a matter of taste.  But if you take that same idea
and bounce it off your business partner, he or she is likely to provide more pertinent
feedback: does it make sense from a business perspective, will customers need it,
will it open up new product or revenue opportunities, are there more pressing matters
to focus the team on, etc.  These are things that, being a technology guy (or
gal), wouldn't immediately come to mind.  But remember: it's all about the
customer.

**5. It's for the customer, not you.**

The best engineers often succeed because they focus on scratching a personal itch.
That's what Linus Torvalds, Bjarne Stroustrup, and countless others did.
This is why Donald Knuth created TeX.  The idea for a new technology thus begins
as a very personal and selfish act.  "Build something you'd use yourself,
and the customers will come" is a common (cliché) idiom.  Although there
is certainly truth to this, it's true only because the very fact that it is bothersome
to the founding engineer is likely indicative that it's bothersome to a broader
set of people.  It's an example, where an example is just one element in a
set that is used to demonstrate some common attribute among all elements in that
set.  Those people are your customers.

As a technology matures, it's important to realize—particularly when building
commercial software—that actual human beings will want to use the technology.
It's important to understand and respect their needs.  It's important to,
at some point, realize that you're not, in fact, building a system entirely for
your own personal use.  Not realizing this point can blind you and make you
neglect the need to partner with somebody who understands the business angle of things.
It can also lead to a feeling of needing to develop the perfect idealized solution
and never ship to customers.  Hey, when there are endless technical problems
to work on, who would want to ship anyway?  By its very definition, shipping
software means that you've solved all of the major technical problems within a
certain scope.  What fun is that?

The fun is that you're able to make an impact on your customers' lives, hopefully
for the better.  Your initial technical vision has come to fruition, and you
can move on.  You get to prove your ideas by having real human beings to use
the end product.  If you never get to that state, then you've done some possibly
interesting research—which is hopefully documented and used by somebody someday
in the future to actually impact people by delivering a system based on those ideas—but
you haven't architected a product.  You're a researcher, not an architect.

**6. Admit when you're wrong, fall on your sword, and then fix it.**

You are going to be wrong sometimes.  Trying to do big and bold things necessarily
involves some risk.  Being an architect requires a careful balance between sticking
to your guns—your guiding principles and technical vision—and realizing when
things aren't working out and course correcting before it's too late.  It's
hard to tell when things are beginning to go off course, but when they've already
gone off course it's usually obvious.  A common telltale sign that things
are in trouble is when the team no longer believes in the vision.  This may
translate into attrition (often of your best engineers first), or just hallway grumblings.
Listen carefully.  If you're not involved in the design decisions, writing
code, and actually playing a significant role in your team's daily lives, then
you're apt to miss this.  As the architect, you are responsible for responding
as quickly as possible to such situations before the shit hits the fan.

Some architects can fall into the trap of using dogma over intellect.  Firm
principles are of course something I've stressed throughout this article.
But you need to be honest with yourself and admit when things are not going well.
An architect who stands at the helm of a sinking ship, proclaiming that the ship
stay its course because the brave new world lies ahead, will only drown (alone) when
the ship finally goes underwater.  Although this architect can then go around
blaming his team for the failure ("if they had only seen the vision and stuck around,
we would have succeeded"), the project will be long gone by then.  It's
harder, but more noble, to recognize the problems proactively and do your best to
fix them.

For example, Tony Hoare describes in the same ACM Turing Award paper mentioned above,
how he felt responsible for the failure of the Elliot 503 Mark II project:

"There was no escape: The entire Elliott 503 Mark II software project had to be
abandoned, and with it, over thirty man-years of programming effort, equivalent to
nearly one man's active working life, and I was responsible, both as designer and
as manager, for wasting it."

It can be particularly disturbing to realize that a large number of people have been
going off in the wrong direction on your watch.  Yes, you wasted their time.
But you have to learn what went wrong, internalize it, and commit to never making
the same mistake twice.  You owe it to them to respond promptly.  Everybody
on the team will have learned and grown from the circumstances, and if you're lucky
the situation is salvageable.  Sometimes it won't be.  But in any case
you will gain the respect of many around you by making the right decision; particularly
if you're the only person with the broad technical responsibility, understanding,
and insight necessary to make such a decision, people will feel relieved when you
make it.  And if you don't make it, people will curse you for it.

**In conclusion**

I'm sure there are many other laundry lists of skills people might come up with
that are necessary to be an effective architect, but these are a few of
the things I see and respect in the people I look up to.  I've named
some of these people throughout this article.  The most common trait is that
they have done great things and left their mark on the industry.  Being
an architect, in the end, is all about helping others to succeed.  If you're
a really good architect, you'll inspire people and rub off on them.  You'll
gain a certain level of respect that is unmistakable and priceless.  And that,
in my opinion, is far more fulfilling than anything you could accomplish on your
own working in a vacuum.

