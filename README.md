## What's in this library?

Basically, functions for turning pull-based stream operations defined within
the "pipes" ecosystem into push-based, iteratee-like stream operations. 

Inspired by the blog post [Programmatic translation to iteratees from pull-based code](http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html).

## Could you go into more detail?

There are three related but independent streaming libraries that often go
together: [pipes](http://hackage.haskell.org/package/pipes), [streaming](http://hackage.haskell.org/package/streaming), and [foldl](http://hackage.haskell.org/package/foldl).

Of these, the first two are pull-based: you take some (possibly effectful)
source of values and keep extracting stuff until the source is exhausted and/or
you have extracted all the info you need.

Meanwhile, foldl is push-based: foldl folds are not directly aware of any
source, they are like little state machines that keep running as long as
someone feeds them input. 

Usually, defining stream transformations in pull-based mode is easier and feels
more natural. The pipes ecosystem provides a lot of them:
[parsers](http://hackage.haskell.org/package/pipes-parse),
[decoders](http://hackage.haskell.org/package/pipes-text),
[splitters](http://hackage.haskell.org/package/pipes-group)...

However, push-based mode also has advantages. Push-based abstractions are not
tied to a particular type of source because data is fed externally. And foldl
folds have very useful Applicative and Comonad instances. 

Also, sometimes, a library will only offer a push-based interface. 

Wouldn't it be nice if you could adapt already existing pull-based operations
to work on push-based consumers? For example, a function that maps
(covariantly) over the values produced by a stream could become a function that
maps (contravariantly) over the inputs received by a fold. 

This library provides that.

## When to use this library?

As already mentioned, when you want to apply a pull-based transformation
provided by streaming or pipes to a fold from foldl.

## Why so many newtypes?

To avoid having to enable [-XImpredicativeTypes](https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#impredicative-polymorphism).

## Is it fast?

I haven't benchmarked or optimized it. It is likely to be slow.

## What about [foldl-transduce](http://hackage.haskell.org/package/foldl-transduce)?

I wrote that package to be able to define stateful transformations on the
inputs of foldl folds. But those transformations must be defined in a push-like
fashion.

## What about [pipes-transduce](http://hackage.haskell.org/package/pipes-transduce)?

That package was an outgrowth of
[process-streaming](http://hackage.haskell.org/package/pipes-transduce). It can
be used elsewhere but it mainly serves the needs of process-streaming. Among
other things, it provides a way consuming two pipes producers concurrently.

