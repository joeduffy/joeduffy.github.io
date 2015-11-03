---
layout: post
title: Sencha and XML processing
date: 2005-03-30 14:17:58.000000000 -07:00
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
I now have some level of platform interop working with Sencha. By "platform
interop," I mean writing code that uses functions defined elsewhere (i.e. not
Scheme built-ins and not custom written stuff). The gunk that enables this
usually ends up making a best guess at binding, in some cases performing
operations to bridge the type system gap that exists.

One of the interesting things I noticed along the way was how easy it is to
work with XML inside Scheme. I do some marshalling back and forth using
factories so that, when you're in Scheme, you see S-expressions which can be
processed and transformed as ordinary lists of data. When you're using
Framework APIs that expect XmlReaders, Documents, and the like, however, they
see what they expect. It's admittedly dangerous to perform this style of
conversion implicitly, but for the time being it's been the source of some fun
experimentation.

For example, generating SOAP is quite simple, etc.:

> '(Envelope (:ns s) (@xmlns:s "http://www.w3.org/2003/05/soap-envelope")
> (@xmlns:wsa "http://schemas.xmlsoap.org/ws/2004/08/addressing") (@xmlns:f123
> "http://www.fabrikam123.example/svc53") (Header (:ns s) (MessageID (:ns wsa)
> "uuid:aaaabbbb-cccc-dddd-eeee-ffffffffffff") (ReplyTo (:ns wsa) (Address (:ns
> wsa) "http://business456.example/client1")) (To (@mustUnderstand "1") (:ns
> wsa) "mailto:joe@fabrikam123.example") (Action (:ns wsa) (@mustUnderstand
> "1") "http://fabrikam123.example/mail/Delete")) (Body (:ns s) (Delete (:ns
> f123) (maxCount 42))))

Similar to what's possible in C-omega, quasiquotations enable you to embed
calculations in the message. For example, the body node could have been:

> '(Body (:ns s) ,(generateSoapBody ,42))

Which has the nice effect of substituting the return value of the
generateSoapBody function, passing 42 as its argument.

As I said, the greatest thing about this is that you can use all of the list
processing techniques that Lisp langauges are good for, existing libraries, and
so on, and then easily convert the result back into XML. Parsing, schema and
namespace validation, resource resolution (e.g. DTDs) is all done for you by
the existing System.Xml Framework libraries.

I know that the linkage between the two technologies has been observed in the
past, but it seems like there's a lot of room for innovation in the future.
_Update: just noticed [this page](http://okmij.org/ftp/Scheme/xml.html). Some
interesting stuff._

