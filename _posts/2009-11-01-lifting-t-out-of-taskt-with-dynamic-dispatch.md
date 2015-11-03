---
layout: post
title: Lifting T out of Task with dynamic dispatch
date: 2009-11-01 13:49:28.000000000 -08:00
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
Say you've got a Task&lt;T&gt;. Well, now what?

You know that eventually a T will become available, but until then you're out of
luck.  You could go ahead and be a naughty little devil by calling Wait on it
-- blocking the current thread (eek!) -- or you could call ContinueWith on the task
to get back a new Task&lt;U&gt;, representing the work you _would_ do to create some new
U object if only you presently had a T in hand.  And then perhaps you will find
yourself in the same situation for that U.

These are those dataflow graphs I mentioned in the previous blog post.  Things
of beauty.

To be more concrete about the situation I describe, imagine you've got the following
IFoo interface:

```
interface IFoo
{
    int Bar();
    string Baz(int x);
}
```

Now, given a Task&lt;IFoo&gt;, you can't do anything related to an IFoo.  And yet
presumably that's why you've got the task in the first place: because you care about
the IFoo.  What if you ultimately want to invoke the Bar method, for example?

```
Task<IFoo> task = ...;
```

You can of course block the thread:

```
// Option A: block the thread.
int resultA = task.Result.Bar();
...
```

Or you can choose to program in a very clunky way:

```
// Option B: use dataflow.
Task<int> resultB = task.ContinueWith(t => t.Result.Bar());
```

But what if, instead, you could do something like this?

```
// Option C: magic.
Task<int> resultC = task.Bar();
```

Whoa, wait a minute.  We're calling Bar() on a Task<IFoo>?  Neat, but how
can that be?

This is obviously a trick.  All of the members of T are somehow being made available
on the Task&lt;T&gt; object, so that they can be called before the task has actually been
resolved to a concrete value.  Of course, were we to allow this, what you get
back to represent the result of such calls would need to be task objects too: hence
we get back a Task<int> from the call on Bar(), instead of an int.  This is
similar to call streams in Barbara Liskov's Argus language (her primary focus immediately
after CLU).

This kind of lifting from the inner type outward is much like what you get in languages
that allow generic mixins.  C# already has one semi-such type, though you may
not realize it: Nullable&lt;T&gt; actually allows you to directly access interfaces implemented
by T without needing to call Value on it.  It's almost like Nullable&lt;T&gt; was
defined as deriving from T itself which is clearly not actually possible (for numerous
reasons, not the least significant of which is that it's a struct).  Try it.
This works because the type system treats Nullable&lt;T&gt; and T somewhat uniformly (though
you'd be surprised by some dangers lurking within -- effectively Nullable&lt;T&gt; mustn't
implement any interfaces \*ever\* otherwise a type hole would result).  But
I digress...

Unfortunately without deep language changes we can't get this to work the way we'd
like.  I have found numerous occasions where a general lifting capability in
C# would be useful: Lazy&lt;T&gt; is but one example.  That said, each time we run
across an instance, it demands slightly different type system treatment, and it seems
unlikely such a general facility would be as usable as the one off features.

Type systems aside, I am actually using a very dirty trick to make this work: I'm
using the new System.Dynamic features in .NET 4.0 to do it all dynamically.
You may love or hate this, depending on your stance on type systems.  Being
an ML guy, I'll let you figure out what I think.  (Hint: gross hack!)

We can go further.  (Although sadly I won't demonstrate how to do so in this
blog post.  I had wanted to go all the way, but need to get some actual language
work done today, in addition to a little Riemann study, instead of having endless
fun tinkering with Visual Studio 2010.  Shucks.)  Notice that Baz accepts
an int as input.  Well, what if all we've got is a Task&lt;int&gt;?  We can of
course also allow that to get passed in too:

```
Task<string> resultD = task.Baz(42); // Real input.  Fine.
Task<int> arg = ...;
Task<string> resultE = task.Baz(arg); // A task as input!  Cool!
```

But wait, there is more!  It slices and dices too.  The next trick is difficult
-- if not impossible -- to do without far reaching language changes.  But we
could also even bridge the world of ordinary methods too, not just those that have
been accessed by tunneling through a Task&lt;T&gt;.  For example:

```
string f(int x) {...}
...
Task<int> task = ...;
Task<string> result = f(task);
```

Not to even mention:

```
Task<int> x = ...;
Task<int> y = ...;
Task<int> z = x + y;
```

This is deep.  What we are saying is that anywhere a T is expected, we can supply
a Task&lt;T&gt;.  Of course once we've entered the world of tasks, we cannot escape
until values actually begin resolving.  So when we invoke the method f in this
example, we of course get back a Task&lt;string&gt; for its result.  Once we've stepped
onto a turtle's back, well, it's turtles all the way down.

Which reminds me of the well known tale:

> A well-known scientist (some say it was Bertrand Russell) once gave a public lecture
> on astronomy. He described how the earth orbits around the sun and how the sun, in
> turn, orbits around the center of a vast collection of stars called our galaxy. At
> the end of the lecture, a little old lady at the back of the room got up and said:
> "What you have told us is rubbish. The world is really a flat plate supported on
> the back of a giant tortoise." The scientist gave a superior smile before replying,
> "What is the tortoise standing on?" "You're very clever, young man, very clever",
> said the old lady. "But it's turtles all the way down!"

In summary: we'll just rely on dynamic dispatch to do the lifting, thanks to the
new .NET 4.0 DynamicObject class.  This is wildly less efficient than a proper
type system design would yield, not to mention the utter lack of static type checking.
Of course a proper implementation that designed for this from Day One would also
avoid the tremendous amount of object allocation that relying on the current Task&lt;T&gt;
objects and ContinueWith overloads imply.  But nevertheless, this approach will
allow us to at least have a good ole' time and stimulate the creative side of the
noggin.

First, I shall provide an extension method for getting a DynamicTask&lt;T&gt; -- the thing
that actually derives from DynamicObject and implements the custom dynamic binding:

```
public static class DynamicTask
{
    public static dynamic AsDynamic<T>(this Task<T> task) {
        return new DynamicTask<T>(task);
    }
}
```

Notice that this changes our calling conventions ever so slightly.  Namely:

```
// Option C: magic.
Task<int> resultC = task.AsDynamic().Bar();
```

The AsDynamic places the caller into the lifted context.  As invocations are
made, the results become real tasks, and not dynamic ones, such that to continue
the calling will require many AsDynamic()s.  This is a minor inconvenience and
we could certainly automatically wrap the return values in DynamicTask&lt;T&gt; objects
if we wanted to eliminate this problem, i.e. to make chaining less verbose.

Second, we must implement the DynamicTask&lt;T&gt; class.  We will do a very simple
translation.  Given a member access expression 'x.m', where m is either a field
or property of type U, we will morph this into the new expression 'x.Task.ContinueWith(v
=> v.Result.m)', which is of type Task&lt;U&gt;.  Similarly, given a method invocation
'x.M(a1,...,aN)', whose return value is of type U, we will morph it into the new
expression 'x.Task.ContinueWith(v => v.Result.M(a1,...,aN))', which is of type Task&lt;U&gt;
(or just Task if U is the void type).  To support the ability to pass a task
argument where an actual one is expected would require packing the argument with
the target into an array, and doing a ContinueWhenAll on it.

(Perhaps I will illustrate how to do these other tricks in a later post, but I'm
tight for time right now.  I'm only sketching the general idea.  Even in
what I show below, things will be incomplete, because topics such as getting exception
propagation right when tasks begin failing are tricky.  Ideally the whole dataflow
chain will be "broken" by such an exception.  Additionally, I've only implemented
what was necessary to get a few interesting examples working.  The binder, for
example, certainly has a few loose ends.  Blog reader beware.)

Here is the implementation of DynamicTask&lt;T&gt;:

```
public class DynamicTask<T> : DynamicObject
{
    private Task<T> m_task;

    public DynamicTask(Task<T> task) {
        if (task == null) {
            throw new ArgumentNullException("task");
        }
        m_task = task;
    }

    public Task<T> Task {
        get { return m_task; }
    }

    public override DynamicMetaObject GetMetaObject(Expression parameter) {
        if (parameter == null) {
            throw new Exception("parameter");
        }
        return new TaskLiftedObject(this, parameter);
    }

    class TaskLiftedObject : DynamicMetaObject
    {
        ...
    }
}
```

Simple.  All of the dynamic magic resides in the implementation of TaskLiftedObject,
which derives from the DynamicMetaObject class.  It is constructed with an instance
of the DynamicTask&lt;T&gt; along with the expression tree that can be used to dynamically
load up an instance of that task.  All of the dynamic features work with expression
trees.  For example, in response to an attempt to invoke a method M on a DynamicTask&lt;T&gt;,
our binder will need to find the right method M on the underlying T, and then return
an expression tree that does the ContinueWith and so forth.

Let's start cracking open TaskLiftedObject:

```
class TaskLiftedObject : DynamicMetaObject
{
    private DynamicTask<T> m_task;
    public TaskLiftedObject(DynamicTask<T> task, Expression expression) :
            base(expression, BindingRestrictions.Empty, task) {
        m_task = task;
    }
```

We will override two of DynamicMetaObject's functions.  BindGetMember is called
when a member is accessed (like a property or field), whereas BindInvokeMember is
called when a method call is made.  There are several other methods that a proper
binder would need to override in order to make delegate dispatch and such work properly.
But this suffices to get started:

```
    public override DynamicMetaObject BindGetMember(GetMemberBinder binder) {
        // We have a member access:
        //     x.m
        //
        // which must become:
        //     x.Task.ContinueWith(v => { v.Result.m; })
        //
        return new DynamicMetaObject(
            MakeContinuationTask(Bind(binder.Name, -1), null),
            BindingRestrictions.GetInstanceRestriction(Expression, Value),
            Value
        );
    }

    public override DynamicMetaObject BindInvokeMember(
            InvokeMemberBinder binder, DynamicMetaObject[] args) {
        // We have a call:
        //     x.Foo(a1,...,aN)
        //
        // which must become:
        //     x.Task.ContinueWith(v => { v.Result.Foo(a1,...,aN); })
        //
        Expression[] argsEx = new Expression[args.Length];
        for (int i = 0; i < args.Length; i++) {
            argsEx[i] = args[i].Expression;
        }

        return new DynamicMetaObject(
            MakeContinuationTask(Bind(binder.Name, binder.CallInfo.ArgumentCount), argsEx),
            BindingRestrictions.GetInstanceRestriction(Expression, Value),
            Value
        );
    }
```

Clearly the workhorses here are Bind and MakeContinuationTask.  Bind is responsible
for performing dynamic lookup for a matching member on T that has the requested Name
and, if a method call is being made, the proper number of parameters.  For brevity,
I've omitted anything to do with argument type checking, an obvious hole that we'd
want to fix some day:

```
    private static MemberInfo Bind(string name, int argCount) {
        // Lookup the target member on the T, rather than the (Dynamic)Task<T>.
        return
            (from m in typeof(T).GetMembers(BindingFlags.Instance | BindingFlags.Public)
             where m.Name.Equals(name) &&
                (argCount == -1 ?
                    !(m is MethodInfo) :
                    ((MethodInfo)m).GetParameters().Length == argCount)
             select m).
            Single();
    }
```

Nothing too interesting here either -- just a bit of hacky reflection code done with
a fancy LINQ query.  If anything other than exactly one method was found, the
call to Single() will throw an exception.  If you want to see what a "real"
dynamic binder looks like, you won't find it here: check out VB's or IronPython's.

Now for the meat.  The MakeContinuationTask method takes the target member that
we've found dynamically via Bind, as well as an optional array of expression trees,
each representing an argument being passed to the target method (and which will be
null for property and field access), and manufactures the expression tree that represents
the execution of the dynamic call itself:

```
    private Expression MakeContinuationTask(MemberInfo target, Expression[] targetArgs) {
        var lambdaParam = Expression.Parameter(typeof(Task<T>), "v");
        var lambdaParamResult = Expression.Property(lambdaParam, "Result");

        Expression lambdaBody;
        Type lambdaReturnType;
        if (target is MethodInfo) {
            lambdaBody = Expression.Call(lambdaParamResult, (MethodInfo)target, targetArgs);
            lambdaReturnType = ((MethodInfo)target).ReturnParameter.ParameterType;
        }
        else if (target is PropertyInfo) {
            lambdaBody = Expression.Property(lambdaParamResult, (PropertyInfo)target);
            lambdaReturnType = ((PropertyInfo)target).PropertyType;
        }
        else if (target is FieldInfo) {
            lambdaBody = Expression.Field(lambdaParamResult, (FieldInfo)target);
            lambdaReturnType = ((FieldInfo)target).FieldType;
        }
        else {
            throw new Exception("Unsupported dynamic invoke: " + target.GetType().Name);
        }

        return Expression.Call(
            Expression.Property(
                Expression.Convert(this.Expression, typeof(DynamicTask<T>)),
                typeof(DynamicTask<T>).GetProperty("Task")
            ),
            GetContinueWith(lambdaReturnType), // ContinueWith
            new Expression[] {
                // v => { v.Result.M(a0,...,aN) }
                Expression.Lambda(lambdaBody, lambdaParam)
            }
        );
    }
```

You should be able to convince yourself that this code generates the desired transformation
described earlier.  It uses a method to find the overload of Task&lt;T&gt;.ContinueWith
that we want to bind against, and invokes that on the Task&lt;T&gt; contained within the
DynamicTask&lt;T&gt; against which the dynamic call was made.  It is rather unfortunate
that the CLR does not allow the void type as a generic type argument, so we have
to be a little bit inconsistent with our treatment of void returns, by choosing a
different ContinueWith overload.

If the above reflection code was called hacky, the ContinueWith lookup is worse.
It's very inefficient, not to mention fragile (because it depends on the current
layout of Task&lt;T&gt;'s overloads, what with instantiating generic methods and the like).
C'est la vie:

```
    private static MethodInfo GetContinueWith(Type returnType) {
        // @TODO: caching to avoid expensive lookups each time.
        if (returnType == typeof(void)) {
            return typeof(Task<T>).GetMethod(
                "ContinueWith",
                new Type[] { typeof(Action<Task<T>>) }
            );
        }
        else {
            foreach (MethodInfo mif in typeof(Task<T>).GetMethods()) {
                if (mif.Name == "ContinueWith" && mif.IsGenericMethodDefinition) {
                    MethodInfo mifOfT = mif.MakeGenericMethod(returnType);
                    ParameterInfo[] mifParams = mifOfT.GetParameters();
                    if (mifParams.Length == 1 &&
                            mifParams[0].ParameterType ==
                                typeof(Func<,>).MakeGenericType(typeof(Task<T>), returnType)) {
                        return mifOfT;
                    }
                }
            }
        }

        throw new Exception("Fatal error: ContinueWith overload not found");
    }
}
```

And that's it.  With that, we can get dynamic invocations on unresolved T's
via Task&lt;T&gt; objects.  Nifty.

I'm not saying any of this is a really good idea.  Honestly, I'm not.
Of course, there's a kernel of a good idea there and the systems we are working on
take this kernel to its extreme.  By providing a programming model that encourages
deep chains of datafow to be expressed speculatively in a natural and familiar manner,
greater degrees of latent parallelism can lie resident in an application waiting
to be unlocked as more processors become available.  Doing it for real requires
impactful changes to the language, supporting infrastructure, and particularly tooling.
Just imagine what it means to break into a debugger to inspect deep dataflow graphs
that have been constructed by compiler magic underneath you.  And the use of
ContinueWith is a little lame, because of course the target of our call may be something
that can be run speculatively too with first class pipleining, rather than completely
delaying the invocation of it.

So we won't be seeing lifted tasks in .NET anytime soon.  Writing up this blog
post was merely an excuse to toy around with the new C# dynamic features and to have
a little recreational time.   And to generate excitement about what .NET
4.0 holds in store.  I hope you have enjoyed it.  Now back to reality.

