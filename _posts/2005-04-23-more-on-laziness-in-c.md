---
layout: post
title: More on laziness in C#
date: 2005-04-23 23:44:14.000000000 -07:00
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
[Don's](http://pluralsight.com/blogs/dbox/archive/2005/04/23/7682.aspx)
[kicking](http://pluralsight.com/blogs/dbox/archive/2005/04/23/7683.aspx)
[butt](http://pluralsight.com/blogs/dbox/archive/2005/04/23/7685.aspx) over
there with lots of experimentation with closures and iterators in C#.
[Sam](http://www.intertwingly.net/blog/2005/04/18/Blocks-for-Box) has commented
and seems to be impressed with C#'s new evolutionary direction. I am too.

Inspired, I went back to a couple posts I did mid last year. I did some playing
around with
[thunks](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=ce8e15bf-c038-48af-b6e1-1d90c03e671c)
and
[streams](http://www.bluebytesoftware.com/blog/PermaLink.aspx?guid=1c2de644-a85b-4b70-b605-d3fbdecaf1d0).
I didn't do a great job explaining back then, and I think it might be
appreciated a little more now. Further, a commenter on [Brad's recent
post](http://blogs.msdn.com/brada/articles/409081.aspx) talked about using
streams in Scheme to implement the Sieve of Erastosthenes. So I did one in C#.

**Streams and laziness**

A stream uses lazy data structures in order to represent an infinite list. It's
a recursive data structure, generally consisting of a pair of two elements: the
first element is a value, and the second is a promise that, when forced,
returns a likewise pair. A promise is just a suspended computation, also known
as a thunk. When you need the value it represents, you force it. Many promises
are "memoized," meaning they remember the value they calculate. This helps to
avoid performing the same calculation more than once.

_Note: Functional programmers are quite familiar with the notion of using
recursive data structures to represent lists. For example, consider a Pair<T,U>
type which has two fields, one of type T and another of type U. A List can be
defined as List<T> : Maybe<Pair<T, List<T>>>. Maybe is much like Nullable<T>,
although it handles ref types, too. So a list is simply defined as either null
or an element followed by a list. This, I think, is a topic for an entire
post._

Streams are a bit more general purpose than the above explanation. But I've
simplified in order to explain the concept without too many special cases. It's
entirely reasonable to have a fixed size stream, or a stream which isn't
calculated in sequential order, for example (consider a calculation which
generates elements in a tree-like structure; you might want to sporadically
populate the list both before and ahead of your current position). Further,
languages like Haskell and Standard ML support laziness as a 1st class language
construct. All recursive computations and data structures are lazy by default.
This is quite nice, although difficult to accomplish in imperitive languages
due to their strict ordering and side-effecting nature.

In Scheme, laziness is exposed through the functions 'delay' and 'force'. So if
we wanted to represent a lazy Fibonacci calculation, we might do something like
this:

> (define (mk-fibs) (cons 1 (delay (fibs-next 0 1))))
>
>
>
> (define (fibs-next n0 n1) (let ((n (+ n0 n1))) (cons n (delay (fibs-next n1
> n)))))

We just treat the result of (mk-fibs) as though it were a list. A minor detail
is that we need to force the cdr before using it. Promises in Scheme are
memoized internally, so although you have to call force, it won't actually
perform the calculation if it has already done so. It will just return the
remembered value. I wrote a little function that "takes" the nth element from a
lazy stream (derived from Haskell's Standard Prelude function), and actually
patches up the stream as it goes.

Although promises are memoized automatically, you won't be able to pretty print
them at the toplevel. By replacing the cdr with the result of a force in my
function, it looks a little nicer when printed. Purely asthetics.

> (define (take nth list) (if (<= nth 0) (car list) (take (- nth 1) (begin
> (set-cdr! list (force (cdr list))) (cdr list)))))

**Umm... What does this have to do with C#?**

Well, as C# moves more and more towards the world where 1st class functions are
used pervasively, a lot of what Scheme (and Haskell and Standard ML and ...)
can do is becoming available to C#-ites. A lot of people have been coming to
this realization lately. The next couple years are very exciting for C#
programmers. I hope people's heads don't explode. (Well, only a couple, OK?)

Here's my somewhat, almost general purpose Stream<T> class. It's a bit lengthy,
and relies on an array of other data structures. I'll introduce those in a
minute. And then I'll show how to use this to create a lazy version of
Fibonacci and the Sieve of Erastosthenes:

> **class** Stream<T> : IEnumerable<T>
>
>
>
> {
>
>
>
>     **private** StreamNext<T> start;
>
>
>
>
>
>
>
>     // Ctors
>
>
>
>
>
>
>
>     **public** Stream(StreamNext<T> start) { **this**.start = start; }
>
>
>
>     **public** Stream(StreamPair<T> pair) : **this** ( **new**
>     StreamNext<T>(pair)) { }
>
>
>
>     **public** Stream(StreamFunction<T> function) : **this** ( **new**
>     StreamNext<T>(function)) { }
>
>
>
>
>
>
>
>     // Properties
>
>
>
>
>
>
>
>     **public** T **this** [**int** n]
>
>
>
>     {
>
>
>
>         **get**
>
>
>
>         {
>
>
>
>             // Note: the performance of this method isn't great. It allocates
>             a
>
>
>
>             // new enumerator upon each invocation, and does a linear walk
>             from
>
>
>
>             // 0..n, forcing promises along the way, in order to locate the
>             desired
>
>
>
>             // element.
>
>
>
>
>
>
>
>             // Just walk ahead 'n' steps (inclusive), forcing if we must.
>
>
>
>             IEnumerator<T> enumerator = GetEnumerator( **true** );
>
>
>
>             **for** ( **int** i = 0; i <= n; i++)
>
>
>
>                 enumerator.MoveNext();
>
>
>
>             **return** enumerator.Current;
>
>
>
>         }
>
>
>
>     }
>
>
>
>
>
>
>
>     // Methods
>
>
>
>
>
>
>
>     IEnumerator IEnumerable.GetEnumerator()
>
>
>
>     {
>
>
>
>         **return** ((IEnumerable<T>) **this** ).GetEnumerator();
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** IEnumerator<T> GetEnumerator()
>
>
>
>     {
>
>
>
>         **return** GetEnumerator( **true** );
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** IEnumerator<T> GetEnumerator( **bool** forcePromises)
>
>
>
>     {
>
>
>
>         StreamNext<T> last = **null** ;
>
>
>
>         StreamNext<T> current = start;
>
>
>
>
>
>
>
>         **while** ( **true** )
>
>
>
>         {
>
>
>
>             **if** (current.IsSecond())
>
>
>
>             {
>
>
>
>                 // This is a suspended computation--i.e. a promise.
>
>
>
>                 **if** (forcePromises)
>
>
>
>                 {
>
>
>
>                     // Apply the function to get the next pair.
>
>
>
>                     current = **new** StreamNext<T>(current.Second());
>
>
>
>
>
>
>
>                     // Memoize the changes we've made.
>
>
>
>                     **if** (last == **null** )
>
>
>
>                         start = current;
>
>
>
>                     **else**
>
>
>
>                         last.First.Tail = current;
>
>
>
>                 }
>
>
>
>                 **else**
>
>
>
>                 {
>
>
>
>                     // If we aren't forcing promises, we're done.
>
>
>
>                     **break** ;
>
>
>
>                 }
>
>
>
>             }
>
>
>
>
>
>
>
>             // Yield the next value, and move on to the next.
>
>
>
>             **yield**  **return** current.First.Head;
>
>
>
>             last = current;
>
>
>
>             current = current.First.Tail;
>
>
>
>         }
>
>
>
>     }
>
>
>
>
>
>
>
>     **public**  **override**  **string** ToString()
>
>
>
>     {
>
>
>
>         StringBuilder sb = **new** StringBuilder("(");
>
>
>
>
>
>
>
>         IEnumerator<T> enumerator = GetEnumerator( **false** );
>
>
>
>         **while** (enumerator.MoveNext())
>
>
>
>         {
>
>
>
>             sb.Append(enumerator.Current);
>
>
>
>             sb.Append(" . ");
>
>
>
>         }
>
>
>
>
>
>
>
>         sb.Append("#promise)");
>
>
>
>
>
>
>
>         **return** sb.ToString();
>
>
>
>     }
>
>
>
> }

Some highlights of this class:

- The default enumerator forces values as it goes. This means if you do a
  foreach over it, it won't ever terminate (in theory; if you're not careful,
you'll end up overflowing and probably failing in some unpredictable way)! This
is one of the great features of the Stream... it generates a neverending list
of values as fast as you can consume 'em. If you pass false to GetEnumerator,
it won't force, and will instead just give you what's already been calculated.

- ToString is overridden to show you only the forced values thus far. It prints
  data in a dotted-list-like form, just because I think it's shnazzy.

- The indexer gets you the nth element of the list. This is cool because you
  don't have to worry about whether it's calculated or not--the indexer handles
it for you. It also memoizes, so the next time 'round the value will be cached.
This is very much like my 'take' function above in Scheme.

**Fibonacci stream**

Writing a Fibonacci stream is quite nice and easy with this new class. I
already showed the Scheme version above. Here it is in C#:

> **internal**  **class** FibonacciStream : Stream< **long** >
>
>
>
> {
>
>
>
>     **internal** FibonacciStream() : **base** (
>
>
>
>         **new** StreamPair< **long** >(1, **delegate** { **return** Next(0,
>         1); }))
>
>
>
>     {
>
>
>
>     }
>
>
>
>
>
>
>
>     **private**  **static** StreamPair< **long** > Next( **long** n0,
>     **long** n1)
>
>
>
>     {
>
>
>
>         **long** n = n0 + n1;
>
>
>
>         **return**  **new** StreamPair< **long** >(n, **delegate** {
>         **return** Next(n1, n); });
>
>
>
>     }
>
>
>
> }

I derived from Stream<T>, although this isn't strictly necessary. So we start
off by saying that the 1st fib is 1, and the second is a promise for "Next(0,
1)". Next is a function which generates the next pair in the sequence. In this
case, it adds 0+1 and uses that as the first part of the pair, and recursively
gives a promise to "Next(1, 1)". And so on.

You can foreach over it, e.g. to print the numbers in the series up to 1,000:

> FibonacciStream fib = **new** FibonacciStream();
>
>
>
> **foreach** ( **long** l **in** fib)
>
>
>
> {
>
>
>
>     **if** (l > 1000)
>
>
>
>         **break** ;
>
>
>
>     Console.WriteLine("{0}", l);
>
>
>
> }

Or even ask for a specific number in the series, e.g. the 50th Fibonacci
number:

> Console.WriteLine(fib[49]);

And as already noted, this is cumulative. So if you then decide to ask for the
51st number, it just does a linear walk through its memory, and forces the next
value.

**Sieve of Erastosthenes stream**

Now, there are a couple ways to implement the Sieve. I'm not sure if there are
better ways to do this with infinite streams (the standard approach is to mark
from k..sqrt(n), where k is the prime and n is the length of the list; but with
an infinite stream, we don't know n!), but this seems to be alright. Its
performance is degraded proportional to the amount of primes it has found thus
far, so when you get a ways into the list it could slow down. I ran it to
compute all 0..int.MaxValue primes, and it didn't exhibit any prohibitive
slowdown:

> **internal**  **class** SieveOfErastosthenesStream : Stream< **bool** >
>
>
>
> {
>
>
>
>
>
>
>
>     // This might look strange, but we special case the first two iterations;
>     0 and 1 are not
>
>
>
>     // prime. So, our actual calculations start at 2.
>
>
>
>     **internal** SieveOfErastosthenesStream() : **base** (
>
>
>
>         **new** StreamPair< **bool** >( **false** ,
>
>
>
>         **new** StreamPair< **bool** >( **false** ,
>
>
>
>         **delegate** { **return** Next(2, **new** List< **int** >()); })))
>
>
>
>     {
>
>
>
>     }
>
>
>
>
>
>
>
>     **private**  **static** StreamPair< **bool** > Next( **int** current,
>     List< **int** > primes)
>
>
>
>     {
>
>
>
>         **bool** isComposite = **false** ;
>
>
>
>
>
>
>
>         **int**  sqrt = Math.Sqrt(current) + 1;
>
>
>
>         **foreach** ( **int** p **in** primes)
>
>
>
>         {
>
>
>
>             **if** (p > sqrt) **break** ;
>
>
>
>             isComposite = current % p == 0;
>
>
>
>             **if** (isComposite)
>
>
>
>                 **break** ;
>
>
>
>         }
>
>
>
>
>
>
>
>         **if** (!isComposite)
>
>
>
>         {
>
>
>
>             // We make a copy here because we're avoiding side effects. If we
>             just added
>
>
>
>             // it to the 'primes' instance passed in, we can munge suspended
>             calculations
>
>
>
>             // that get forced more than once (i.e. non-memoized).
>
>
>
>             primes = **new** List< **int** >(primes);
>
>
>
>             primes.Add(current);
>
>
>
>         }
>
>
>
>
>
>
>
>         **return**  **new** StreamPair< **bool** >(!isComposite,
>
>
>
>             **delegate** { **return** Next(current + 1, primes); });
>
>
>
>     }
>
>
>
> }
>
>

Fairly straight forward. It's a little complicated to get started since we need
to special case 0 and 1, but after that the algorithm "just works." Notice that
we copy the list of primes before we memoize the second computation. This gets
deeper than I want to go right now, but suffice it to say that side effects are
eeeevil. So now if we want to, say, print which numbers from 0..10,000 are
prime, we can do it like this:

> SieveOfErastosthenesStream sieve = **new** SieveOfErastosthenesStream();
>
>
>
> IEnumerator< **bool** > sieveEnum = sieve.GetEnumerator();
>
>
>
> **for** ( **int** i = 0; i < 10000; i++)
>
>
>
> {
>
>
>
>     sieveEnum.MoveNext();
>
>
>
>     **if** (sieveEnum.Current)
>
>
>
>         Console.WriteLine("{0}", i);
>
>
>
> }

A naive implementation might have just used sieve's indexer for each call. This
would be too horrible in reality. But since I know that it's performance is
linear with respect to the size of the calculations performed thus far, I've
gone with the slightly more verbose approach above. This isn't too much unlike
working with a linked list.

But the indexer does come in handy. Say we wanted to check to see if a certain
number is prime. Well, according to
[this](http://www.utm.edu/research/primes/lists/small/1000.txt), the 1,000th
prime is 7919. So this should print 'True' (and indeed it does, very quickly I
might add... actually it's entirely based on memory if you ran the above code
first):

> Console.WriteLine(sieve[7919]);

**Hey: I don't like smoke and mirrors!**

An astute reader will have noticed the abundance of types in Stream<T> above
that I made no mention of. Yep, there's a bit of plumbing underneath to make
this work. Some of this is to be expected, while some isn't. (For example, I've
griped many a time that we don't have a Pair<T,U> type in the BCL.) Most of
this is uninteresting, so I won't do a lot of explainin'.

> **delegate** StreamPair<T> StreamFunction<T>();
>
>
>
>
>
>
>
> **class** StreamPair<T> : Pair<T, StreamNext<T>>
>
>
>
> {
>
>
>
>     **public** StreamPair(T current, StreamPair<T> memo) : **base** (current,
>     **new** StreamNext<T>(memo)) { }
>
>
>
>     **public** StreamPair(T current, StreamFunction<T> promise) : **base**
>     (current, **new** StreamNext<T>(promise)) { }
>
>
>
>
>
>
>
>     **public** T Current { **get** { **return** Head; } }
>
>
>
>     **public** StreamNext<T> Next { **get** { **return** Tail; } }
>
>
>
>     **public**  **bool** IsMemoized() { **return** Next.IsMemoized(); }
>
>
>
>     **public**  **bool** IsPromise() { **return** Next.IsPromise(); }
>
>
>
> }
>
>
>
>
>
>
>
> **class** StreamNext<T> : Choice<StreamPair<T>, StreamFunction<T>>
>
>
>
> {
>
>
>
>     **public** StreamNext(StreamPair<T> first) : **base** (first) { }
>
>
>
>     **public** StreamNext(StreamFunction<T> second) : **base** (second) { }
>
>
>
>     **public**  **bool** IsMemoized() { **return** IsFirst(); }
>
>
>
>     **public**  **bool** IsPromise() { **return** IsSecond(); }
>
>
>
> }

StreamFunction<T> is a delegate which represents lazy promises. Evaluating one
returns a StreamPair<T>. This is a pair of the real T value (which was computed
by evaluating the promise), and the next promise in the series. The promise is
represented as a StreamNext<T>. I lied a little: StreamNext<T> can be either a
StreamPair<T> (notice the recursion), or a StreamFunction<T>. The former is
used when you might want to precalculate more than one value in a list, while
the second is used for promising future values.

And of course, these build on other types not listed. Namely, Pair<T,U> and
Choice<TF,TS>. I admit, this stuff is a hack. If has a pretty ugly interface.

> **class** Pair<T, U>
>
>
>
> {
>
>
>
>     **public** T Head;
>
>
>
>     **public** U Tail;
>
>
>
>
>
>
>
>     **public** Pair(T head, U tail)
>
>
>
>     {
>
>
>
>         **this**.Head = head;
>
>
>
>         **this**.Tail = tail;
>
>
>
>     }
>
>
>
> }
>
>
>
>
>
>
>
> **class** Choice<TF, TS>
>
>
>
> {
>
>
>
>     **private**  **bool** isFirstType;
>
>
>
>     **private** TF first;
>
>
>
>     **private** TS second;
>
>
>
>
>
>
>
>     **public** Choice(TF first)
>
>
>
>     {
>
>
>
>         **this**.isFirstType = **true** ;
>
>
>
>         **this**.first = first;
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** Choice(TS second)
>
>
>
>     {
>
>
>
>         **this**.isFirstType = **false** ;
>
>
>
>         **this**.second = second;
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** TF First
>
>
>
>     {
>
>
>
>         **get** { **return** first; }
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** TS Second
>
>
>
>     {
>
>
>
>         **get** { **return** second; }
>
>
>
>     }
>
>
>
>
>
>
>
>     **public**  **bool** Is<T>()
>
>
>
>     {
>
>
>
>         **return** isFirstType ?
>
>
>
>             **typeof** (T) == **typeof** (TF) :
>
>
>
>              **typeof** (T) == **typeof** (TS);
>
>
>
>     }
>
>
>
>
>
>
>
>     **public** T As<T>()
>
>
>
>     {
>
>
>
>         **return** isFirstType ?
>
>
>
>             (T)( **object** )first :
>
>
>
>             (T)( **object** )second;
>
>
>
>     }
>
>
>
>
>
>
>
>     **public**  **bool** IsFirst()
>
>
>
>     {
>
>
>
>         **return** isFirstType;
>
>
>
>     }
>
>
>
>
>
>
>
>     **public**  **bool** IsSecond()
>
>
>
>     {
>
>
>
>         **return**!isFirstType;
>
>
>
>     }
>
>
>
>
>
> }
