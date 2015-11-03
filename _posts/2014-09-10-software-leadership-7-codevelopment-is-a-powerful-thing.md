---
layout: post
title: 'Software Leadership #7: Codevelopment is a Powerful Thing'
date: 2014-09-10 06:54:35.000000000 -07:00
categories: []
tags: []
status: publish
type: post
published: true
meta:
  _edit_last: '1'
author:
  login: admin
  email: joeduffy@acm.org
  display_name: joeduffy
  first_name: ''
  last_name: ''
---
I work in a team where the microkernel is developed in close partnership with the
backend code-generator. Where the language is developed in close partnership with
the class libraries. Where it's just as common for a language designer to comment
on the best use of the language style in the implementation of the filesystem, as
it is for such an exchange in the context of the web browser, as it is for a device
driver developer to help influence the overall async programming model's design to
better suit his or her scenarios.

In fact, the developers I love most are those who will go make a change to the language,
ensure the IDE support works great, plumb the change through to the backend code-generator
to ensure optimal code-quality, whip up a few performance tests along the way, deploy
the changes to the class libraries so that they optimally use them (and on up through
to the consumers of those libraries in applications), write the user-facing documentation
for how to use this new language feature, ... and beyond. All in a few days' work.

It takes real guts. The best programmers are absolutely fearless.

I call this "codevelopment." The idea is that you're designing and building the system
as a whole, and ensuring each part works well with all other parts as you go. It's
a special case of " [eat your own dogfood](http://en.wikipedia.org/wiki/Eating_your_own_dog_food)."
Codevelopment is a key part of a startup culture. Big companies can afford to over-compartmentalize
responsibilities, but little companies usually can't. (And those that go overboard
doing so don't last long).

Obviously my present situation is a bit unique. Not everybody works on the development
platform and operating system and everything in between, all at once. But there's
more opportunity for this than one might think; in fact, it's everywhere. It can
be a website or app's UI vs. business logic, hardware vs. software, the engineering
system vs. the product code, operations vs. testing vs. development, etc. Most people
have sacred lines that they won't cross. It saddens me when these lines are driven
by organizational boundaries, when engineers should be knocking the lines down and
collaborating across them.

A great example of wildly successful codevelopment is Apple's products. They have
always developed the hardware in conjunction with the software, focusing on the end-to-end
user experience. Most companies disperse these responsibilities out across disparate
organizations (or even separate companies!) without any one person really in charge
of the end-to-end thing. And it shows.

A good test is: if you're designing some system, or implementing a feature, do you
ever hit an edge where you think you could come up with some great solution, but
intentionally don't because you think "person X is supposed to do this," "that team
over there would never accept it," etc.? Or worse, "that's not my job?" A special
case of the latter is "I'm an X developer, and that is a Y component" (example for
X: compiler, example for Y: networking). What an incredible opportunity to learn
more about Y, and collaborate closely with some new colleagues, that is all-too-often
missed! It's almost like intentionally dumbing oneself down. I am aware of [Conway's
Law](http://en.wikipedia.org/wiki/Conway's_law) -- and teams exist for a reason (to
lump together closely related work) -- but the reality is the organization almost
always lags behind the technology. Technology direction should shape the organization,
not vice versa. Communication structures need to be put in place to facilitate this.

The technology suffers in a compartmentalized world too.

Thinking in terms of a series of black boxes stitched together leaves opportunities
on the floor, whether it is economies of scale or opportunities for innovation, particularly
if nobody is responsible for looking end-to-end across those boundaries to ensure
they make sense. Abstractions afford a degree of independence, but I always regularly
step back and wonder, "what is this abstraction costing me? what is it gaining me?
is the tradeoff right?" Abstractions are great, so long as they are in the right
place, and not organizationally motivated. The biggest sin is to knowingly create
a lesser quality solution, simply for fear of crossing or dealing with the engineers
on the other side of such an abstraction boundary.

Codevelopment is just as much about building the right architecture, as it is validating
that architecture and its implementation as you go. If you are forced to think about
-- and even suffer the consequences of -- the resulting code quality of a language
feature you just wrote, and you are forced to see it in action and get feedback from
its target audience by actually integrating the feature in some "real world" code,
you are less apt to sweep problems under the rug. Especially if you have the right
measures in place. I've been guilty numerous times in the past of hacking together
some cool feature, and then moving on to the next one, only to find out (usually
right before shipping to customers) that it didn't work in the real world. I keep
focusing on developer platform examples, but obviously these ideas extend well beyond
developer platforms.

Another way to think about codevelopment is as a kind of "pre-flighting" for your
changes. If you worked at Facebook, you wouldn't just flip the switch to 100% instantly
on some new timeline view, right? You'd want to do some A/B testing, make sure on
your own that the change is going in the right direction, that its performance meets
your expectations, etc., and to only commit once you've had sufficient telemetric
validation.

Now obviously there is a limit to what's reasonable, even just considering pure engineering
costs. You'd be surprised at how cost effective codevelopment can be, however, even
if there's some ramp-up along the way. By the time you hit one of these boundaries,
you've built up a ton of momentum and context. You probably even have an idea of
how to just do what needs to get done. If you stop and offload that to another group,
then you need to transfer all that momentum and context, which takes considerable
time and energy. Clearly the equation doesn't always work out in codevelopment's
favor, depending on the complexity of the code on the other side of the boundary
and skill of the engineer involved, but it's worth stopping to think. It's just software,
after all.

After doing codevelopment at scale for the past five years, frankly, I couldn't imagine
going back. Always be on the lookout for opportunities to build your system on your
system.

