---
layout: post
title: 'Dijkstra: My recollection of operating system design'
date: 2006-11-12 10:25:59.000000000 -08:00
categories:
- Miscellaneous
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
I just read Dijkstra's ["My recollection of operating system design"](http://www.cs.utexas.edu/users/EWD/transcriptions/EWD13xx/EWD1303.html),
note #1303. He describes issues with the design and implementation of THE operating
system, written several years afterward in retrospect. Theme-wise, he focuses on
concurrency, resource management and scheduling, fault tolerance, and real-time considerations
for fairness. I found the paper to be quite fascinating and easy to read. I enjoyed
the theme of concurrency woven throughout, particularly reading about both the failed
and successful approaches. The original hand-written note can be [found here](http://www.cs.utexas.edu/users/EWD/ewd13xx/EWD1303.PDF).

Here are some choice quotes that I was drawn to with some inline thoughts:

> "... [with this] we have achieved CCC (= Completely Concealed Concurrency) in
> the sense that our two machines are now functionality equivalent in the sense that,
> fed with the same program, they will produce exactly the same output. As long as
> speed of execution is unobservable, it is impossible to determine which of the two
> machines did execute your program." (pp. 5)
> 
> > [Comment: Although the details are quite different, I was struck by CCC's goal
> > of isolation among tasks running concurrently in the system and its resemblance to
> > STM, at least in terms of overarching design goals.]
> 
> "Thus CCC improved the efficiency ... but the comfortable invisibility of concurrency
> had a high price ... To maximize throughput, we would like each reader to read at
> its maximum speed most of the time ... but with CCC, the calculator has no means
> of identifying that input stream: the invisibility of concurrency has made the notion
> of "first-come-first-served" inapplicable. The moral of the story was that, essentially
> for the sake of efficiency, concurrency should become somewhat visible. It became
> so, and then, all hell broke loose." (pp. 7-8)
> 
> > [Comment: Again, STM often requires breaking this isolation to improve scalability
> > of certain data structures, a la open nesting (see [Moss '06](http://www.cs.utah.edu/wmpi/2006/final-version/wmpi-posters-1-Moss.pdf)).
> > Although there isn't as much practical experience with such things, it is quite
> > clear that open nesting can certainly cause all hell to break loose (see [Agrawal,
> > et. al, '06](http://theory.csail.mit.edu/~kunal/open-mspc.pdf)).)]
> 
> "In retrospect, the problems were in roughly three areas: (i) The basic mechanics
> of switching the central processor from one task to another, (ii) The strategy for
> scheduling the central processor and the scope of its commitment, (iii) The logical
> problems that emerge when a number of resources are shared by a number of competitors
> ... Those years taught me that the ability to detect timely that some theory is needed
> is crucial for successful software design." (pp. 9)
> 
> "We learned to distinguish between "essential urgency," where failure to be in
> time would derail the computation, and "moral urgency," where the failure would only
> hurt the efficiency... [this] taught us that in resource allocation one could (and
> therefore should) separate the concerns of necessity and of desirability." (pp. 18)
> 
> > [Comment: This is a great lesson to learn when it comes to reliability in general.
> > There is a large difference between _statistically_ reliable and _completely_
> > reliable. All software is statistically reliable to a degree, it's only a matter
> > of the statistical details, in particular the statistical frequency of failure, whereas
> > very little software, at least on commercial non-real-time systems like Windows,
> > is completely reliable, in other words, cannot fail.]
> 
> "With the symmetry between CPU and peripheral clearly understood, symmetric synchronizing
> primitives could not fail to be conceived and I introduced the operations P and V
> on semaphores. Initially my semaphores were binary ... When I showed this to Bram
> and Carel, Carel immediately suggested to generalize the binary semaphore to a natural
> semaphore ... How valuable this generalization was we would soon discover." (pp.
> 23-24)
> 
> "Many peripherals could be designed in such a way that they did not confront the
> CPU with real-time obligations ... but the problem was, that these same devices would
> often now confront the CPU with situations of "moral urgency" ... The solution was
> to allow the CPU to build up a queue of commands and to enable the channel to switch
> without CPU intervention to the next command in the queue. Synchronization was controlled
> by two counting semaphores in what we now know as the producer/consumer arrangement
> ..." (pp. 24)
> 
> > [Comment: Obviously when scheduling concurrent tasks, e.g. in a user-mode scheduler,
> > one has to worry about fairness and prioritization too. His writings are generally
> > applicable.]
> 
> "In retrospect I am sorry that I postponed widespread publication until 1967 and
> think that I would have served mankind better if I had enabled The Evil One to improve
> its product." (pp. 27)
> 
> > [Comment: I had to laugh at this. Dijkstra wrote this regarding his design for
> > semaphores and synchronizing channels, referring to IBM as "The Evil One" and IBM/360
> > as "its product". Times have changed things, but not by much: Microsoft is now, I
> > suppose, "The Evil One," at least for many people.]
> 
> "For economic reasons one wants to avoid in a multiprogramming system the so-called
> "busy form of waiting," in which the central processor is unproductively engaged
> in the waiting cycle of a temporarily stopped program, for it is better to grant
> the processor to a program that may actually proceed." (pp. 28)
> 
> "Halfway the multiprogramming project in Eindhoven I realized that we would have
> been in grave difficulties had we not seen in time the possibility of definitely
> unintended deadlocks. From that experience we concluded that a successful systems
> designer should recognize as early as possible situations in which some theory was
> needed. In our case we needed enough theory about deadlocks and their prevention
> to develop what became known as "the banker's algorithm," without which the multiprogramming
> system would only have been possible in a very crude form." (pp. 36)

I hope at least one other person out there finds this interesting. We've certainly
made progress over the past 40+ years, although maybe not as much as we think. As
Dijkstra says in this note several times, perhaps one of the largest improvements
in the state of the art since he worked on THE has been the development of terminology.
It's incredibly hard to build on top of prior work if you haven't the terms to talk
and reason about what has worked and what has failed.

