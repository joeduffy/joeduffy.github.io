---
layout: post
title: 'Program the Cloud with 12 Pulumi Pearls'
date: 2018-07-25 12:00:00.000000000 -07:00
categories: [Pulumi]
tags: [Pulumi, AWS, Containers, Serverless]
status: publish
type: post
published: true
author:
  display_name: joeduffy
  first_name: Joe
  last_name: Duffy
  email: joeduffy@acm.org
---

In this post, we'll look at 12 "pearls" -- bite-sized code snippets -- that demonstrate some fun ways you can program the cloud using Pulumi. In my introductory post, I mentioned [a few of my "favorite things"]( http://joeduffyblog.com/2018/06/18/hello-pulumi/#my-favorite-things). Now let's dive into a few specifics, from multi-cloud to cloud-specific, spanning containers, serverless, and infrastructure, and generally highlighting why using real languages is so empowering for cloud scenarios. Since Pulumi lets you do infrastructure-as-code from the lowest-level to the highest, we will cover a lot of interesting ground in short order.

If you want to follow along and try some of this out, Pulumi is [open source on GitHub](https://github.com/pulumi/pulumi), free to download and use from https://pulumi.io, and [the tour](https://pulumi.io/tour) will acquaint you with the CLI. Most of the examples are directly runnable and available in [our examples repo](https://github.com/pulumi/examples), and are just a `pulumi up` away, unlike other approaches that require you to point-and-click around in your cloud's console, and/or author reams of yucky YAML. And you get to use real languages!

Here is an index of the pearls in case you want to dive straight into one in particular:

[**Infrastructure**](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearls-infra):

1.	[Declare cloud infra using a real language (with loops!)](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-1)
2.	[Make a reusable component out of your cloud infra](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-2)

[**Serverless**](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearls-serverless):

3.	[Go serverless without the YAML](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-3)
4.	[Capture state in your serverless funcs, like real lambdas](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-4)
5.	[Simple serverless cron jobs](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-5)
6.	[Run Express-like serverless SPAs and REST APIs at near zero cost](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-6)

[**Containers**](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearls-containers):

7.	[Deploy production containers without the fuss](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-7)
8.	[Use containers without Dockerfiles](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-8)
9.	[Invoke a long-running container as a task](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-9)

[**General Tips and Tricks**](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearls-tips):

10.	[Use code to avoid hard-coding config](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-10)
11.	[Use config to enable multi-instantiation and code reuse](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-11)
12.	[Give your components runtime APIs](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls#pearl-12)

Even if you're uninterested in low-level infrastructure, it can be fun to work through these examples; it's "turtles all the way down" with Pulumi and doing so can help understand how the system works. And similarly, it can be fun to see the high-level scenarios these building blocks facilitate, even if you just want to stand up containers and functions.

And with that, let's dive in.

To continue reading, [head on over to the Pulumi blog](https://blog.pulumi.com/program-the-cloud-with-12-pulumi-pearls)...