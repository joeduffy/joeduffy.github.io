---
layout: post
title: 'Hello, Pulumi!'
date: 2018-06-18 10:30:00.000000000 -07:00
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

Today we launched Pulumi, a new open source cloud development platform.  Using Pulumi, you author cloud programs using
your favorite language, spanning low-level infrastructure-as-code to highly productive and modern container- and
serverless-powered applications.  We started on Pulumi a little over a year ago and I'm blown away by the progress we've
made.  This is our first step on the journey, and it's a huge one, and I'm eager to share what we've built.

Pulumi is multi-language, multi-cloud, and fully extensible.  On day one, it supports JavaScript, TypeScript, Python,
and Go languages, and AWS, Azure, and GCP clouds, in addition to Kubernetes targeting any public, private, or hybrid
cloud.  Pulumi delivers a single, consistent programming model and set of tools to program and manage any of these
environments, supported by a rich ecosystem of reusable packages.  Using real languages changes everything.

TL;DR, with Pulumi, [38 pages of manual instructions](https://serverless.com/blog/serverless-application-for-long-running-process-fargate-lambda/)
become [38 lines of code](http://blog.pulumi.com/build-a-video-thumbnailer-with-lambdas-containers-and-infrastructure-with-pulumi).
25,000 lines of YAML configuration becomes 500 lines in a real programming language.

The entire Pulumi runtime, CLI, and supporting libraries are [available on GitHub](https://github.com/pulumi) and
available for download at [https://pulumi.io](https://pulumi.io).  The team is on tenterhooks
[awaiting your feedback](https://slack.pulumi.io). In the meantime, allow me to tell you a bit more about Pulumi, and
how and why we got here.

## Why Pulumi?

My background is 100% developer tools.  I was an early engineer on .NET, architected its concurrency and asynchrony
support, led the programming platform for a distributed OS, and managed Microsoft's languages groups, including open
sourcing and taking .NET Core cross-platform.  Because of this background, I came to cloud with a unique perspective.

And what I found was frankly not very appealing to me.

I started exploring Pulumi during late 2016 with my friend and co-founder Eric Rudder, when containers and serverless
were far enough along to show incredible promise, but early enough to be very difficult to use "for real."  The
capabilities of the cloud are incredible, but far too difficult to use, still to this day a year and a half later.

For every serverless function, I had dozens of lines of JSON or YAML configuration.  To connect that to an API endpoint,
I needed to learn obscure concepts and perform copy-and-paste grunge work.  Docker was great when I was running a little
cluster on my machine, but running it in production required manually managing etcd clusters, setting up networks and
iptable routes, and a whole host of things that were leagues away from my application domain.  Kubernetes at least let
me do this once and reuse it across clouds, but felt alien and distracting.

I thought I was a reasonably experienced engineer, having worked 20 years in this industry, but trying to get my code
into the cloud made me feel dumb.  And frustrated!  I knew that if I could just master these new capabilities, the world
would be at my fingertips.  All the time I spent wading through that complexity should have been time spent creating
business value.

Many aspects of programming have gone through a similar transition:

* In the early 80s, we programmed microprocessors using assembly language.  Eventually, compiler technology advanced,
  and we simultaneously settled on common architectures.  Low-level programming languages like FORTRAN and C flourished.
* In the early 90s, we programmed directly against low-level OS primitives, whether those were POSIX syscalls or Win32
  APIs, and did manual memory and resource management.  Eventually, language runtime technology and processor speeds
  advanced to the state where we could use higher level languages, like Java.  This trend has accelerated, and gave way to
  the web, where JavaScript reigns, in addition to dynamic languages.
* In the early 2000s, shared memory concurrency in our programming models was primitive at best.  (I spent
  [a considerable amount of time on this problem](http://joeduffyblog.com/2016/11/30/15-years-of-concurrency/).)
  These days, we simply assume the OS has advanced thread pooling, scheduling, and async IO capabilities, and program
  to much higher level APIs, such as tasks and promises.

I believe we are amidst a similar transition for cloud software.  We are right in the middle of a sea change from
building monolithic applications to building true cloud-first distributed systems.  And yet, of course, the thing about
sea changes is that you seldom know it's happening until after it has happened.

The "configuration" situation, when viewed in the above light, makes sense.  In the early days of VMs, we took our
existing applications and tossed them over the fence for someone to add a little bit of INI or XML glue to get them
running inside a VM for more flexible management.  This approach to configuration stayed with us as we "lifted and
shifted" these same VMs into the cloud.  And it worked, because we got the boundaries approximately correct.

Expressing the relationships between container-based microservices, serverless functions, and fine-grained hosted
services using this same style of configuration has led to incredible accidental complexity.  Turning an application
into a distributed system can't be an afterthought.  The cloud, it turns out, pervades your architecture and design.
And the way that we know how to best express architecture and design in our programs is using code, written in real
programming languages with abstractions, reuse, and great tooling.

Early on, Eric and I interviewed a few dozen customers.  What we found was universal disillusionment from developers and
DevOps engineers alike.  We discovered extreme specialization, and even within the same team, engineers didn't speak the
same language.  I've been hearing this even more in recent weeks, and I expect a NoYAML movement any day now.

Specialization is a good thing, and we want our best and brightest cloud architects elevated into senior DevOps and SRE
roles, but teams must be able to speak the same language when collaborating.  Not having a common lingua franca
introduces a hard, physical separation between teams rather than divvying up the work based on policy and circumstances.
Pulumi aims to give all of us the tools we need to solve this problem too.

## What is Pulumi?

Pulumi is a multi-language and multi-cloud development platform.  It lets you create all aspects of cloud programs
using real languages and real code, from infrastructure on up to the application itself.  Just write programs and run
them, and Pulumi figures out the rest.

At the center of Pulumi is a cloud object model, coupled with an evaluation runtime that understands how to take
programs written in any language, understand the cloud resources necessary to execute them, and then plan and manage
your cloud resources in a robust way. This cloud runtime and object model is inherently language- and cloud-neutral,
which is how we can support so many languages and clouds out of the gate. More are on their way.

Pulumi's approach takes the familiar concept of infrastructure-as-code, coupled with immutable infrastructure, and lets
you reap the automation and repeatability benefits from your favorite languages instead of YAML or DSLs.  You can diff
changes before deploying them and we keep a perfect audit trail of who changed what and when.  The core model is
therefore declarative.

Using real languages unlocks tremendous benefits:

* **Familiarity**: no need to learn new bespoke DSLs or YAML-based templating languages
* **Abstraction**: as we love in our languages, we can build bigger things out of smaller things
* **Sharing and reuse**: we leverage existing language package managers to share and reuse these abstractions, either
  with the community, within your team, or both
* **Expressiveness**: use the full power of your language, including async, loops, and conditionals
* **Toolability**: by using real languages, we instantly gain access to IDEs, refactoring, testing, static analysis and
  linters, and so much more
* **Productivity**: add all of the above together, and you get things done faster, with more joy

These benefits of course matter at the lowest layer, when provisioning raw cloud resources, but we've found here on the
team that you just can't help but use abstraction.  That includes wrapping things in functions to eliminate boilerplate
and creating custom classes that introduce higher level concepts, often packaging them up for reuse time and time again.

For example, this code provisions a DynamoDB database in AWS:

```typescript
import * as aws from "@pulumi/aws";
let music = new aws.dynamodb.Table("music", {
    attributes: [
        { name: "Album", type: "S" },
        { name: "Artist", type: "S" },
    ],
    hashKey: "Album",
    rangeKey: "Artist",
});
```

And [this code](https://github.com/pulumi/examples/tree/master/cloud-js-thumbnailer) creates a container-based task and
serverless function, triggered by a bucket:

```typescript
import * as cloud from "@pulumi/cloud";
let bucket = new cloud.Bucket("bucket");
let task = new cloud.Task("ffmpegThumbTask", {
    build: "./path_to_dockerfile/",
});
bucket.onPut("onNewVideo", bucketArgs => {
    let file = bucketArgs.key;
    return task.run({
        environment: {
            "S3_BUCKET":   bucket.id.get(),
            "INPUT_VIDEO": file,
            "TIME_OFFSET":  file.substring(file.indexOf('_')+1, file.indexOf('.')).replace('-',':'),
            "OUTPUT_FILE": file.substring(0, file.indexOf('_')) + '.jpg',
        },
    });
});
```

Better yet, this code can be deployed to any public or private cloud, based on your needs.

And, finally, [this example](https://github.com/pulumi/examples/tree/master/cloud-ts-url-shortener-cache) creates a
Redis cache.  How do we know?  We don't need to.  The cache component is an abstraction that encapsulates unimportant
details we can safely ignore:

```typescript
import {Cache} from "./cache";
let cache = new Cache("url-cache");
```

After using Pulumi for a bit, you'll stop thinking about infrastructure the same way.  Instead of a distinct "thing,"
entirely independent from your application, your brain will start thinking about distributed cloud systems as a core
part of your program's architecture, not an afterthought.

Because of abstraction, we've been able to offer some powerful libraries.  Libraries are an excellent way to distill and
enforce best practices.  Of course, there's nothing particularly special about our own libraries, since they are just
functions and classes and code, and we look forward to seeing the ones you build for yourself, your team, or the
community.

Our most sophisticated library -- the Pulumi Cloud Framework -- offers an early preview of some exciting work in
progress, demonstrating how you can create abstractions that span cloud providers' own views on such core concepts as
containers, serverless functions, and storage buckets.  In the same way you can write powerful applications in Node.js,
Python, Java, .NET, et al., that leverage processes, threads, and filesystems, no matter whether it is macOS, Linux, or
Windows, this approach lets you create modern multi-cloud applications that can target any cloud provider.  Technologies
like Kubernetes and the rest of the CNCF portfolio are helping to drive this inevitable outcome, as they democratize and
yield agreement on basic compute abstractions across the entire cloud substrate.

Pulumi is not a PaaS, despite it offering PaaS-like productivity; your programs always run directly against your cloud
of choice, and the full power of that underlying cloud is always accessible.  Even if you opt to use higher level
components, it's turtles all the way down, and you can always use the raw resources directly if you wish.  It's like any
sophisticated modern piece of software: sometimes the whole thing must be written in C(++), so as to access the full
power of the underlying platform, but for most common scenarios, 70-100% can be platform independent code, with 30-0%
specialization required to really make it sing on the target OS.

I have a dozen blog posts queued up to go into more details on all aspects of Pulumi.  To keep this post reasonably
short, however, I will close with a some of my favorite aspects of Pulumi.

## My Favorite Things

It's hard to choose, but here are some of my favorite things about Pulumi:

**Open Source**.  I am a huge believer that all developer tools should be open source.  Sure, Pulumi is a company too,
but there are ample opportunities to build a business model by adding true convenience.  (Think Git versus GitHub.)
Because we bet so big on open source, I am excited to see where the community takes us, especially in the area of
higher-level packages.

**Multi-Language**.  Just as with Java and .NET, the Pulumi runtime was architected to support many languages, and to
do so in an idiomatic way for all aspects of a target language (style, syntax, packages, etc).  Because we are open
source, anyone can contribute their own.

**Multi-Cloud**.  Our cloud object model is a powerful foundation that can support any cloud provider.  This delivers a
unified programming model, tools, and control plane for managing cloud software anywhere.  There's no need to learn
three different YAML dialects, and five different CLIs, just to get a simple container-based application stood up in
production.

**Cloud Object Model**.  This underlying cloud object model offers a rich view into how your cloud programs are
constructed. The resulting objects form a DAG using dependencies from your program that the system can analyze and
understand to deliver insights, a capability we intend to build on over time to unlock sophisticated static analysis
and visualizations.

**Reusable Components**.  Thanks to having a real language, we can build higher level abstractions.  One of my favorite
examples that has helped us to regularly eliminate 1,000s of lines of YAML from our customers' deployments is our AWS
Infrastructure package.  It takes the AWS best practices for setting up a Virtual Private Cloud, with private subnets
and multi-Availability Zone support, and turns it into a few lines of code to provision an entire network:

```typescript
import * as awsinfra from "@pulumi/aws-infra";
let network = new awsinfra.Network(`${prefix}-net`, {
    numberOfAvailabilityZones: 3, // Create subnets in many AZs
    usePrivateSubnets: true,      // Run inside private per-AZ subnets
});
```

My favorite success story so far has been taking 25,000 lines of a customer's AWS CloudFormation YAML files -- using
serverless, containers, infrastructure, and three custom deployment pipelines -- and replacing them all with 500 lines
of TypeScript and a single continuously deployed architecture using Pulumi.  Not only is this far less code that all
engineers in the company can understand, so that they can build new things in an afternoon where it used to take weeks,
but the result can also now run in Kubernetes on any cloud or on-premises, in addition to lighting up in AWS.  Instead
of one overloaded engineer managing the team's CloudFormation stack, the entire team is empowered to move faster.

**Unified Container Build/Publish Pipeline**.  An aspect of trying to get containers into production that frustrated me
early on was trying to synchronize my application, container, and infrastructure management, each of which tended to use
different tools.  Our Cloud Framework demonstrates an integrated workflow where simply running pulumi up build, diffed,
pushed, and pulled a new container image, all orchestrated carefully so as to eliminate downtime.

**Serverless Functions as Lambdas**.  AWS got the name exactly right: Lambda.  In Pulumi, I can now write my serverless
functions using lambdas in my favorite language, without a single line of YAML:

```typescript
import * as aws from "@pulumi/aws";
import * as serverless from "@pulumi/aws-serverless";
let topic = new aws.sns.Topic("topic");
serverless.cloudwatch.onEvent("hourly", "rate(60 minutes)", event => {
    const sns = new (await import "aws-sdk").SNS();
    return sns.publish({
        Message: JSON.stringify({ event: event }),
        TopicArn: topic.id.get(),
    }).promise();
});
```

This capability allows you to capture references to variables: constants, configuration settings or encrypted secrets,
or even references to other resources so that I can communicate with them.  I may have buried the lede here; the first
time you experience this, I guarantee you'll have an "ah hah" moment, connecting serverless to every single event-driven
piece of code you've ever written.

**Resources with APIs**.  Because I can capture references to other cloud resources, I can create APIs on top of them to
make them easier to use in my runtime code.  This enables an "actor-like" programming model without having to deal with
configuration and service discovery.

**Stacks**.  A core concept in Pulumi is the idea of a "stack."  A stack is an isolated instance of your cloud program
whose resources and configuration are distinct from all other stacks.  You might have a stack each for production,
staging, and testing, or perhaps for each single-tenanted environment.  Pulumi's CLI makes it trivial to spin up and
tear down lots of stacks.  This opens up workflows you might not have previously even attempted, like each developer
having her own stack, spinning up (and tearing down) a fresh stack to test out each Pull Request, or even splitting
tiers of your service into many stacks that are linked together.

I could keep going on and on, and I shall do so in future blog posts.  Now that Pulumi is out of stealth, expect to hear
a lot more from me in the days and weeks to come.  I hope that this gives you a better idea of the overall platform,
approach, and unique strengths.

## What's Next?

Our hope is that with Pulumi, developers and DevOps teams alike will experience a cloud renaissance.  Building powerful
cloud software will be more enjoyable, more productive, and more collaborative.  Modern cloud software will shift from
being islands of code with an equal amount of configuration glue in between, to being elegant distributed systems.

This is a hard problem.  I am in no way saying we've solved it.  I do believe that Pulumi is the closest thing to this
future cloud development platform that I've personally seen and wanted.  Betting on languages will enable us all to
"stand on the shoulders of giants" during this exciting time, which gives me optimism; languages are always a safe bet.

Today is quite possibly the most exciting day of my career.  I'd like to thank the team and everybody who helped out
along the way, indulging our crazy ideas.  Get Pulumi now at [https://pulumi.io](https://pulumi.io), or simply run:

```bash
$ curl -fsSL https://get.pulumi.com | sh
```

I can't wait to see all the incredible things you will build using Pulumi.

Joe

***

P. S.  I'd be remiss if I did not thank my late mentor, and best friend, Chris Brumme.  Although Chris is not with us to
celebrate this moment, I have wondered, at every step, "what would Chris do."  Pulumi is the Hawaiian word for "broom"
and, though it is a complete mispronunciation of his name, I am proud to have built Pulumi in his honor nonetheless.
