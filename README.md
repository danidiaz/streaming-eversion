## What's in this library?

Functions that turn pull-based stream operations from the pipes/streaming
ecosystem into push-based, iteratee-like stream operations. 

Inspired by the blog post [Programmatic translation to iteratees from pull-based code](http://pchiusano.blogspot.com.es/2011/12/programmatic-translation-to-iteratees.html).

## Could you go into more detail?

There are three streaming libraries that often go together:
[pipes](http://hackage.haskell.org/package/pipes),
[streaming](http://hackage.haskell.org/package/streaming), and
[foldl](http://hackage.haskell.org/package/foldl).

Of these, the first two are pull-based: you take some (possibly effectful)
source of values and keep extracting stuff until the source is exhausted and/or
you have obtained all the info you need.

Meanwhile, foldl is push-based: foldl folds are not directly aware of any
source, they are like little state machines that keep running as long as
someone feeds them input. 

Usually, defining stream transformations in pull-based mode is easier and feels
more natural. The pipes ecosystem already provides a lot of them:
[parsers](http://hackage.haskell.org/package/pipes-parse),
[decoders](http://hackage.haskell.org/package/pipes-text),
[splitters](http://hackage.haskell.org/package/pipes-group)...

However, push-based mode also has advantages. Push-based abstractions are not
tied to a particular type of source because data is fed externally. And foldl
folds have very useful Applicative and Comonad instances. 

Also, sometimes a library will only offer a push-based interface. 

Wouldn't it be nice if you could adapt already existing pull-based operations
to work on push-based consumers? For example, using a decoding function from
[Pipes.Text.Encoding](http://hackage.haskell.org/package/pipes-text-0.0.2.4/docs/Pipes-Text-Encoding.html#g:6)
to preprocess the inputs of a
[Fold](http://hackage.haskell.org/package/foldl-1.2.1/docs/Control-Foldl-Text.html).

This library provides that.

## Why so many newtypes?

To avoid having to enable [-XImpredicativeTypes](https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#impredicative-polymorphism).

## Is it fast?

I haven't benchmarked or optimized it. It is likely to be slow.

