Climbu
======

## What is this?
Good question. Climbu is a programming language, which is focusing in the result, not in speed or something else. So you can (you should) use Climbu just for testing mathematics' formules, testing algoritms and other cool stuffs.

Climbu is interpreted (and maybe it's fast, I don't know). Climbu is a super side effect, imperative programming language, but it can be just functional programming language, you choose your form.

Well, when I say 'super side effect', I actually mean this:

```haskell
    foo(a, b) = a + b;

    bar = foo 1;

    do x = bar 2,
       foo = 2
    in x + foo;
```

Yeap, this prints ``5``. Okay, until now, this isn't too side effect, is it? Yeah, is not. But check it out:

```haskell
    foo(x) = x 2;

    bar(x) = x + 2;

    foo (do bar(x) = x in bar); -- returns 2

    foo bar; -- returns 4

    bar = 8; -- bar now is 8
```

Okay, okay, not too side effect... And now, it comes hard:

```haskell
    foo1 = foo(x) = x + x;
    foo2 = foo(x) = x / 2;

    do foo1,
       x = foo 4,
       foo2,
       y = foo 4

     in (x, y) -- prints (8, 2)
```

Wow! Do we just made... Declarators? Yes, we made it. It's too much complex for explainations here. Go to the doc and check it out!

## Documentation?
It's coming yet. Not finished. However, you can see the progress here: [Climbu documentation](http://climbu.readthedocs.org/en/latest/)

## The versions
Climbu has named versions (since v1.3) where the first named version is "I'm a zygote". This is just for fun. You can find all versions in the ``versions`` file.

## The license
This project is lincensed under GPLv3, so you are free to do everything (or almost everything) with my language.