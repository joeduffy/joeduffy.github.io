---
layout: post
title: Vista SRWLock acquires during shutdown
date: 2006-11-18 20:14:27.000000000 -08:00
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
I was surprised to find out that attempting to acquire an orphaned native "slim"
reader/writer lock (SRWL) on the shutdown path hangs on Windows Vista.
Unlike orphaned critical section acquisitions during shutdown on Windows -- which,
[in Vista cause the process to terminate immediately, and pre-Vista enjoyed "weakening"
to avoid deadlocking at the risk of seeing corrupt state](http://www.bluebytesoftware.com/blog/PermaLink,guid,86195ce0-3e2d-4477-9739-896862c8c08d.aspx) --
SRWL's AcquireSRWLockXXX methods are not shutdown aware.

This is actually pretty dangerous, and effectively means you should stay as far away
from SRWLs during shutdown as possible.  Avoiding synchronization and any
sort of cross-thread coordination in DllMain is generally a good rule of
thumb anyway, since it runs under the protection of the loader lock, has to tolerate
very harsh conditions, and often runs w/out the presence of other active threads.

But this means something even stronger and sets SRWLs distinctly apart from Win32
critical sections.  If you're writing a reusable native library whose functionality
somebody might conceivably want to use on the shutdown path, you really ought not
to be using SRLWs internally.  If app developers don't realize you
employ internal SRWL synchronization, they might call you and, every so often when
the stars align, their users will experience a random hang during shutdown.
Library authors might consider giving TryXXX variants of their APIs so that developers
can at least deal with the case in which a SRWL has been orphaned.

Notice that hanging is similar to [managed code's approach to lock acquisitions during
shutdown](http://www.bluebytesoftware.com/blog/PermaLink,guid,c3993fa3-4d71-414c-bfa3-bca600869018.aspx).
There's a big difference, though: the CLR anoints a shutdown watchdog thread
that kills the process after 2 seconds when a hang occurs, whereas native code won't.
The native hang persists indefinitely.

I'd be a much happier guy if SRWLs mirrored the new Vista orphaned critical
section shutdown behavior.

