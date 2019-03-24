# A Little Scheme in Dart

This is a small interpreter of a subset of Scheme.
It implements _almost_ the same language as
[little-scheme-in-python](https://github.com/nukata/little-scheme-in-python)
(and also its meta-circular interpreter, 
[little-scheme](https://github.com/nukata/little-scheme))
in circa 600 lines of Dart 2.2.

As a Scheme implementation, 
it optimizes _tail calls_ and handles _first-class continuations_ properly.


## How to run

```
$ chmod a+x scm.dart
$ ./scm.dart
> (+ 5 6)
11
> (cons 'a (cons 'b 'c))
(a b . c)
> (list
| 1
| 2
| 3
| )
(1 2 3)
> 
```

Press EOF (e.g. Control-D) to exit the session.

```
> Goodbye
$ 
```

You can run it with a Scheme script.
Examples are found in 
[little-scheme](https://github.com/nukata/little-scheme).

```
$ ./scm.dart ../little-scheme/examples/yin-yang-puzzle.scm | head

*
**
***
****
*****
******
*******
********
*********
^C
$ ./scm.dart ../little-scheme/scm.scm < ../little-scheme/examples/nqueens.scm
((5 3 1 6 4 2) (4 1 5 2 6 3) (3 6 2 5 1 4) (2 4 6 1 3 5))
$ 
```

Press INTR (e.g. Control-C) to terminate the yin-yang-puzzle.

Put a "`-`" after the script in the command line to begin a session 
after running the script.

```
$ ./scm.dart ../little-scheme/examples/fib90.scm -
2880067194370816120
> (globals)
(globals = < * - + symbol? eof-object? read newline display apply call/cc list n
ot null? pair? eqv? eq? cons cdr car fibonacci)
> (fibonacci 16)
987
> (fibonacci 1000)
817770325994397771
> 
```

Note the incorrect result of `(fibonacci 1000)`.
Since Dart 2.0.0, `int` does not have inifinite-precision
and arithmetic operations wrap around on overflow.
See "[Dart - Fixed-Size Integers](https://github.com/dart-lang/sdk/blob/master/docs/language/informal/int64.md)".
I am considering using
[BigInt class](https://api.dartlang.org/stable/2.2.0/dart-core/BigInt-class.html)
in some future version of this Scheme.

## The implemented language

| Scheme Expression                   | Internal Representation             |
|:------------------------------------|:------------------------------------|
| numbers `1`, `2.3`                  | `num` (i.e. `int` or `double`)      |
| `#t`                                | `true`                              |
| `#f`                                | `false`                             |
| strings `"hello, world"`            | `string`                            |
| symbols `a`, `+`                    | `class Sym`                         |
| `()`                                | `nil`, a singleton of `ScmList`     |
| pairs `(1 . 2)`, `(x y z)`          | `class Cell extends ScmList`        |
| closures `(lambda (x) (+ x 1))`     | `class Closure`                     |
| built-in procedures `car`, `cdr`    | `class Intrinsic`                   |
| continuations                       | `class Continuation`                |


For expression types and built-in procedures, see
[little-scheme-in-python](https://github.com/nukata/little-scheme-in-python).
