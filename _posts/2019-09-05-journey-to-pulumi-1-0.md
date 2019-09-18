---
layout: post
title: 'Journey to Pulumi 1.0'
date: 2019-09-05 05:00:00.000000000 -07:00
categories: [Pulumi]
tags: [Pulumi]
status: publish
type: post
published: true
author:
  display_name: joeduffy
  first_name: Joe
  last_name: Duffy
  email: joeduffy@acm.org
---

We started Pulumi a little over two years ago with an ambitious mission: to enable as many people on the planet to harness as much of the modern cloud as possible. The raw capabilities of modern cloud platforms are astonishing and are growing at an unbelievable pace. Yet they remain out of reach or hard to use for most of us. Pulumi's mission starts by helping those who are already using the cloud &mdash; operations and infrastructure teams, as well as developers doing infrastructure &mdash; with an eye to empowering the growing number of over 20 million developers in our industry. I'm happy today that [we've reached our first 1.0](https://www.pulumi.com/blog/pulumi-1-0/) milestone and would love to share a bit of background into why we're so excited about the release and what comes next.

## Before Pulumi

I arrived at cloud infrastructure somewhat accidentally, coming from a developer tools background where, for a decade, my teams helped build .NET, C#, and operating system platforms. Productivity, sharing and reuse, and collaboration were paramount in these domains. Along the way, I got excited by the opportunity in modern cloud platforms, with the ubiquity of powerful managed infrastructure services and new service-based architectures. But the state of the art that I encountered when taking the leap in 2016 was far from what I expected.

Most engineering teams struggle to function in the modern cloud world. Developers usually don't stand up their own infrastructure (or, if they do, can't do so in a production-ready way). And operations teams toil with aging tools and rudimentary capabilities in precisely those areas that we usually prioritize highly for developer tools (productivity, sharing and reuse, etc). As we spoke to customers, we found multiple roles born to help bridge the gaps between these two "sides of the house": infrastructure engineers, systems engineers, site reliability engineers, and DevOps engineers, to name just a few. Nobody was happy with the tools and silos.

We wondered why this could be. If we rewound the clock to even just 2010, it seemed we had things better. Application developers largely focused on building N-tier applications with tried and true stacks. The IT organization could easily provision machine capacity &mdash; increasingly virtualized &mdash; on-demand, image the machines, and configure them without needing to know much about the applications themselves. Over time, operators picked up new tools in the toolbelt to automate these tasks, and DevOps was born. Everything seemed to make sense.

What changed?

## Modern speed of innovation

The speed of business and technology innovation is much greater than even just 5 years ago, and demands a level of agility previously unheard of. Modern dot-coms like Amazon, Uber, and Airbnb have displaced entire industries and major enterprises across a broad range of industries such as FinTech, energy, and retail have reshaped their businesses by out-innovating their competition. There is a virtuous cycle here, whereby the rapid availability of innovative cloud capabilities, and one's ability to leverage it, can mean life or death for your business.

How are the leading companies evolving in response to this? We see a few core capabilities:

* An ability to deliver new application functionality quickly, and adjust dynamically to a changing customer base, and/or as you learn more about your customers' needs.
* An infrastructure that is provisioned and can scale dynamically in support of these application needs, and is aligned with the applications to minimize friction.
* A team that is highly functional, productive, and can innovate together as a group.

All of this must be done with fundamentals in mind &mdash; particularly security &mdash; so that the cloud software being built is secure, reliable, and delivers the desired quality of end user experience. That's not so easy when the entire cloud foundation is being rebuilt out from underneath you!

## Modern applications

All applications are cloud applications these days. Virtually no application exists today that doesn't leverage cloud compute, rich data services, hosted infrastructure, or a 3rd party REST API, in some capacity &mdash; whether big or small. New service-oriented architectures are now available, involving increasingly finer grained services that use cloud capabilities like containers or serverless, pay-as-you-go, compute.

There has been a gradual modernization of our entire application stack that has now hit the tipping point where everything is suddenly different, seemingly overnight. The problem I realized when starting on the Pulumi journey was that our overall engineering practices hadn't had a serious end-to-end relook in quite some time. We tiptoed into VM-based application development, because the model mirrored machine based provisioning so closely, and so our approaches only had to change in small ways. We are now trying to gradually ease into the modern cloud application architectures, however, and it isn't working very well &mdash; the change and opportunity to harness new capabilities is too great.

This made us seriously question the approach. Shouldn't these cloud architectures be front and center when we architect modern applications? We thought the answer was a resounding Yes!

It didn't seem that "Yes!" had a chance of happening if we continued to assume a silo existed between developer and operations teams. Instead, what if we tried to break down those silos, empowering both developers and operators to innovate as rapidly as possible &mdash; and work more effectively together &mdash; while still retaining strong fundamentals like reliability and security? Doesn't that seem like the path forward to highly collaborative and productive teams, with a line of sight to equipping all 20 million developers on the planet to harness the power of cloud computing?

## Modern infrastructure

The secret sauce behind modern applications is the availability of an increasingly rich set of cloud infrastructure services. Amazon Web Services alone offers over 150 such services. Add in what Microsoft Azure, Google Cloud Platform, Digital Ocean, CloudFlare, and others provide, and one thing is clear &mdash; if you can dream it up, a service to get it up and running in minutes almost certainly exists. The shift to "many cloud" architectures &mdash; leveraging the best of what all of the clouds have to offer &mdash; means it can all be at your fingertips.

Unfortunately, the classical IT organization division of responsibilities, where developers ignore infrastructure, and operators do all that heavy lifting for them, isn't the path to rapid innovation. The most innovative companies that use the cloud as competitive advantage simply do not operate this way anymore. Those looking to out-innovate their competition and supercharge their teams to rapidly deliver value to customers will need to embrace and seek out change.

The approach we took with Pulumi was twofold:

1. Give developers technology they can use to rapidly provision infrastructure.
2. Give operators this same technology, and allow them to put in place guardrails.

The idea is that developers can run full speed ahead on certain aspects of infrastructure that makes sense to them (containers, serverless, managed services) &mdash; and operators are able to do the hardcore infrastructure architecture work (clustering, networking, security). And furthermore, the operations team can ensure appropriate policies govern the whole team.

Existing technologies fell short on both of these. First, most technologies out there fail the "developer lovability" test &mdash; put simply, YAML and limited domain specific languages (DSLs) do not offer the rich capabilities that developers have come to expect from their tools (productivity, sharing and reuse, etc). Second, because of this, operators are left handling tickets, toiling away with subpar tools, and getting unfairly blamed for being the organization's innovation bottleneck.

We simply didn't see collaboration happening &mdash; and even within a given silo, there was plenty of copy and paste, and security mistakes being made, due to the rudimentary tools in use.

## Modern teams

There is great value in job specialization. Application developers won't become experts in low level infrastructure concepts &mdash; and we don't want them to, we want them focused on innovating in business logic. Similarly, operators aren't going to want to learn about the latest application frameworks or UI technologies &mdash; which is also fine, because we want them building secure, manageable, and cost effective infrastructures that the entire company can run reliably on.

That said, despite this specialization, modern teams need to work together collaboratively in order to have any shot at moving at the pace of the modern environment. At the end of the day, the whole team's mission is shared and is clear: to deliver value to customers.

Breaking down these walls isn't an easy option for us today, because of the dichotomy between legacy applications and infrastructure silos. Most teams we work with to modernize are employing different tools, terminologies, and cultural approaches to delivering software in these two domains &mdash; and, worse, it often differs by cloud. Why is that? Is it truly necessary?

I sometimes cite a change we made at Microsoft to help developers and test engineers work better together. These used to be entirely distinct organizations. However, this divide had unintended consequences: developers would write the code, test it very little (if at all), and then hand it to the test team. Testers were talented when it came to figuring out how to break software, and had eagle-eyes for quality, and certainly found a lot of bugs. But this "throw it over the wall" culture led to problems all around &mdash; lower quality code on one hand, and ineffective tests on the other. By combining these organizations, we empowered these two very different kinds of engineers to coexist and innovate more rapidly together. Teams became significantly more happy and effective, and the software's quality rapidly improved too. Every modern organization works this way now.

There are a few essential ingredients to being able to harmonizing a modern cloud engineering team:

* We need to celebrate the differences and what each discipline brings to the table. The developer mindset is very much about customer-facing functionality and the latest and greatest advances in application tools and frameworks, while the operator mindset is focused on doing great on infrastructure fundamentals (manageability, cost, reliability, security) and harnessing the latest and greatest cloud platform innovations.
* We need tools and processes that work for both skill-sets and backgrounds and leads to 1+1=3 in terms of maximizing the team's output.
* Any solution needs to assume that there will be division of responsibility that is often dynamically shifting &mdash; sometimes a developer will want to provision their own database, and sometimes that needs to be done by an operator. The answer might even differ within the same organization based on whether it's a test versus production environment.
* Although productivity is paramount, security is even more important and needs to be everyone's responsibility &mdash; any solution needs to have adequate controls to ensure "security by default" and that the same mistakes aren't made time and time again.

This idea of a highly functioning cloud engineering team wasn't immediately obvious to us at the outset. It began to make sense as we saw the new workflows it unlocked. Over time, we've worked with more customers and having seen it in practice, I am a true believer.

## A modern foundation &mdash; Pulumi 1.0

That leads me to today's announcement. Two years ago, we began work on Pulumi, a modern take on infrastructure as code. Just one year ago, [we open sourced it](/2018/06/18/hello-pulumi/). Since then we've helped teams of all sizes go into production across a vast array of clouds and application architectures, adding new capabilities along the way to help tame modern cloud software complexity and break down team silos. Today marks a very important milestone for our team and community.

We took a contrarian view on infrastructure as code. Most VM configuration tools from a decade ago used general purpose languages. But more recent provisioning tools did not, instead using YAML (with templating) or limited DSLs. We chose instead to stand on the shoulders of giants and embrace general purpose languages, including TypeScript, JavaScript, Python, and Go.

The most magical thing about Pulumi, however, is that you get all the same predictability guarantees of an infrastructure as code tool, while still embracing general purpose languages. The tool works for the first project deployment, as well as subsequent updates, and you always get full preview diffs, history, and the ability to evolve infrastructure over time.

Why was using familiar languages so important to us? For two major reasons:

* The technical. General purpose languages offer rich features like for loops, functions, classes, async, and more. Using them also unlocks instant access to decades of great tools: IDEs, test frameworks, static analysis tools, linters, package managers, and more.
* The cultural. Many developers and operators already understand at least one of these languages. These languages deliver access to existing communities, training, and knowledge bases. Most importantly, this establishes a shared language and understanding for the whole organization.

Beyond languages, we were also inspired by how GitHub has become a sort of "watering hole" for teams to gather around and collaborate on application code. We saw an opportunity to enable a similar watering hole for both developers and operators to gather around for all aspects of their cloud software. That's why we created the Pulumi Console &mdash; a modern SaaS web application that the SDK can easily use to enable teams to collaborate on creating, deploying, and managing cloud software. There's a free version and additional tiers with advanced functionality for bigger teams. End to end continuous delivery has never been so easy!

This approach has been essential to harmonizing the two sides of the house. The open source SDK is easy &mdash; and fun, even &mdash; to use, whether you're a developer, operator, or somewhere in between &mdash; and the SaaS lets you go to production reliably and securely, and even divvy up responsibilities across your team. I sometimes say that the combination of these "empowers operators to empower developers" … without giving away the keys to the entire kingdom.

The second order effects we're seeing happen with our customers are what makes the journey all worthwhile. We can genuinely say that people adopting Pulumi are seeing step function increases in how fast they can ship software with confidence, and that is simply awesome.

## Pulumi = modern apps+infrastructure+teams

The "1.0" label is something we take very seriously, and signals confidence in what we've built. It is complete, high quality, and we intend to stand behind its compatibility.

More than anything, we think and hope you will like it :-)

I'm humbled by the amazing team that has worked so hard to build this technology and product. I look back and can't believe it's only been two years since starting. I also want to thank the community and our customers for believing in us. This milestone would not have been possible without their passionate belief in the mission.

Although Pulumi 1.0 is a major milestone for all of us, we are just as excited about what comes next. Pulumi 1.0 lays a solid foundation to continue making it even easier than before to go to production with modern application architectures, while also going deeper ensuring great fundamentals when doing so.

You can [read more about the 1.0 release here](https://www.pulumi.com/blog/pulumi-1-0/). Pulumi is [open source](https://github.com/pulumi/pulumi) and I hope you will [check it out](https://www.pulumi.com/docs/get-started). [Join our Community Slack](https://slack.pulumi.com/) and let us know what you think!
