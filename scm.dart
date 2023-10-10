#!/usr/bin/env dart
// @dart=2.9
// A Little Scheme in Dart 2.7, v0.5 H31.03.23/R02.04.15 by SUZUKI Hisao

import 'dart:io';

const intBits = 63; // 53 for dart2js

/// Converts [a] into an int if possible.
Object normalize(BigInt a) => (a.bitLength <= intBits) ? a.toInt() : a;

/// Is [a] a number?
bool isNumber(Object a) => a is num || a is BigInt;

/// Calculates [a] + [b].
Object add(Object a, Object b) {
  if (a is int) {
    if (b is int) {
      if (a.bitLength < intBits && b.bitLength < intBits) {
        return a + b;
      } else {
        return normalize(BigInt.from(a) + BigInt.from(b));
      }
    } else if (b is double) {
      return a + b;
    } else if (b is BigInt) {
      return normalize(BigInt.from(a) + b);
    }
  } else if (a is double) {
    if (b is num) {
      return a + b;
    } else if (b is BigInt) {
      return a + b.toDouble();
    }
  } else if (a is BigInt) {
    if (b is int) {
      return normalize(a + BigInt.from(b));
    } else if (b is double) {
      return a.toDouble() + b;
    } else if (b is BigInt) {
      return normalize(a + b);
    }
  }
  throw ArgumentError("$a, $b");
}

/// Calculates [a] - [b].
Object subtract(Object a, Object b) {
  if (a is int) {
    if (b is int) {
      if (a.bitLength < intBits && b.bitLength < intBits) {
        return a - b;
      } else {
        return normalize(BigInt.from(a) - BigInt.from(b));
      }
    } else if (b is double) {
      return a - b;
    } else if (b is BigInt) {
      return normalize(BigInt.from(a) - b);
    }
  } else if (a is double) {
    if (b is num) {
      return a - b;
    } else if (b is BigInt) {
      return a - b.toDouble();
    }
  } else if (a is BigInt) {
    if (b is int) {
      return normalize(a - BigInt.from(b));
    } else if (b is double) {
      return a.toDouble() - b;
    } else if (b is BigInt) {
      return normalize(a - b);
    }
  }
  throw ArgumentError("$a, $b");
}

/// Compares [a] and [b].
/// Returns -1, 0 or 1 as [a] is less than, equal to, or greater than [b].
num compare(Object a, Object b) {
  if (a is int) {
    if (b is int) {
      if (a.bitLength < intBits && b.bitLength < intBits) {
        return (a - b).sign;
      } else {
        return (BigInt.from(a) - BigInt.from(b)).sign;
      }
    } else if (b is double) {
      return (a - b).sign;
    } else if (b is BigInt) {
      return (BigInt.from(a) - b).sign;
    }
  } else if (a is double) {
    if (b is num) {
      return (a - b).sign;
    } else if (b is BigInt) {
      return (a - b.toDouble()).sign;
    }
  } else if (a is BigInt) {
    if (b is int) {
      return (a - BigInt.from(b)).sign;
    } else if (b is double) {
      return (a.toDouble() - b).sign;
    } else if (b is BigInt) {
      return (a - b).sign;
    }
  }
  throw ArgumentError("$a, $b");
}

/// Calculates [a] * [b].
Object multiply(Object a, Object b) {
  if (a is int) {
    if (b is int) {
      if (a.bitLength + b.bitLength < intBits) {
        return a * b;
      } else {
        return normalize(BigInt.from(a) * BigInt.from(b));
      }
    } else if (b is double) {
      return a * b;
    } else if (b is BigInt) {
      return BigInt.from(a) * b;
    }
  } else if (a is double) {
    if (b is num) {
      return a * b;
    } else if (b is BigInt) {
      return a * b.toDouble();
    }
  } else if (a is BigInt) {
    if (b is int) {
      return a * BigInt.from(b);
    } else if (b is double) {
      return a.toDouble() * b;
    } else if (b is BigInt) {
      return a * b;
    }
  }
  throw ArgumentError("$a, $b");
}

/// Calculates [a] / [b] (rounded quotient).
double divide(a, b) {
  if (a is int) {
    if (b is num) {
      return a / b;
    } else if (b is BigInt) {
      return BigInt.from(a) / b;
    }
  } else if (a is double) {
    if (b is num) {
      return a / b;
    } else if (b is BigInt) {
      return a / b.toDouble();
    }
  } else if (a is BigInt) {
    if (b is int) {
      return a / BigInt.from(b);
    } else if (b is double) {
      return a.toDouble() / b;
    } else if (b is BigInt) {
      return a / b;
    }
  }
  throw ArgumentError("$a, $b");
}


/// Tries to parse a string as an int, a BigInt or a double.
/// Returns null if [s] was not parsed successfully.
Object tryParse(String s) {
  var r = BigInt.tryParse(s);
  return (r == null) ? double.tryParse(s) : normalize(r);
}

//----------------------------------------------------------------------

/// Cons cell
class Cell extends Iterable<Object> {
  final Object car;
  dynamic cdr;

  Cell(this.car, this.cdr);

  /// Yields car, cadr, caddr and so on.
  Iterator<Object> get iterator => _CellIterator(this);
}

class _CellIterator extends Iterator<Object> {
  Cell j = null;
  dynamic k;

  _CellIterator(this.k);

  Object get current => j?.car;

  bool moveNext() {
    if (k == null) {
      return false;
    } else if (k is Cell) {
      j = k as Cell;
      k = k.cdr;
      return true;
    } else {
      throw ImproperListException(k);
    }
  }
}

/// Exception which means that the last tail of the list is not null
class ImproperListException implements Exception {
  final Object tail;

  ImproperListException(this.tail);
}

//----------------------------------------------------------------------

/// Scheme's symbol
class Sym {
  final String name;

  /// Constructs a symbol that is not interned yet.
  const Sym.notInterned(this.name);

  @override
  String toString() => name;

  /// The table of interned symbols
  static final Map<String, Sym> symbols = {};

  /// Constructs an interned symbol.
  factory Sym(String name) =>
    symbols.putIfAbsent(name, () => Sym.notInterned(name));
}

final quoteSym = Sym('quote');
final ifSym = Sym('if');
final beginSym = Sym('begin');
final lambdaSym = Sym('lambda');
final defineSym = Sym('define');
final setqSym = Sym('set!');
final applySym = Sym('apply');
final callccSym = Sym('call/cc');

//----------------------------------------------------------------------

typedef void Setter(Object val);

/// List of frames which map symbols to values
class Environment {
  List<Sym> _names;
  List<Object> _values;
  Environment _next;

  /// Construct a new frame on the [next] (= current) environment or null.
  Environment(Cell symbols, Cell data, Environment next) {
    var names = symbols?.map((e) => (e as Sym))?.toList() ?? [];
    var values = data?.toList() ?? [];
    if (names?.length != values?.length)
      throw 'arity not matched: $names and $values';
    _names = names;
    _values = values;
    _next = next;
  }

  /// Searches the environment for [symbol] and returns its setter.
  Setter lookForSetter(Sym symbol) {
    var frame = this;
    do {
      int i = frame._names.indexOf(symbol);
      if (i >= 0)
        return (Object val) { frame._values[i] = val; };
      frame = frame._next;
    } while (frame != null);
    throw 'name to be set not found: $symbol';
  }

  /// Searches the environment for [symbol] and returns its value.
  Object lookForValue(Sym symbol) {
    var frame = this;
    do {
      int i = frame._names.indexOf(symbol);
      if (i >= 0)
        return frame._values[i];
      frame = frame._next;
    } while (frame != null);
    throw 'name not found: $symbol';
  }

  /// Defines [symbol] as [value] in the current frame.
  void defineSymbol(Sym symbol, Object value) {
    int i = _names.indexOf(symbol);
    if (i >= 0) {
      _values[i] = value;
    } else {
      _names.add(symbol);
      _values.add(value);
    }
  }

  /// Symbols in the current frame
  Iterable<Sym> get names => _names;

  @override
  String toString() {
    var ss = <String>[];
    var frame = this;
    do {
      ss.add(frame._names.toString());
      frame = frame._next;
    } while (frame != null);
    return '#<' + ss.join('|') + '>';
  }
}

//----------------------------------------------------------------------

/// Operations in continuations
enum ContOp {
  THEN,
  BEGIN,
  DEFINE,
  SETQ,
  APPLY,
  APPLY_FUN,
  EVAL_ARG,
  CONS_ARGS,
  RESTORE_ENV
}

/// Scheme's step in a continuation
class Step {
  final ContOp op;
  final Object val;

  Step(this.op, this.val);
}

// Scheme's continuation as a stack of steps
class Continuation extends Iterable<Step> {
  final List<Step> _stack = [];

  bool get isEmpty => _stack.isEmpty;
  int get length => _stack.length;

  Iterable<Step> _iter() sync* {
    for (var step in _stack)
      yield step;
  }

  /// Yields each step.
  Iterator<Step> get iterator => _iter().iterator;

  /// Appends a step to the tail of the continuation.
  void push(ContOp op, Object value) => _stack.add(Step(op, value));

  /// Pops a step from the tail of the continuation.
  Step pop() => _stack.removeLast();

  /// Copies a continuation.
  void copyFrom(Continuation other) {
    _stack.clear();
    _stack.addAll(other._stack);
  }

  /// Pushes [ContOp.RESTORE_ENV] unless on a tail call.
  void pushRestoreEnv(Environment env) {
    int len = _stack.length;
    if (len == 0 || _stack[len - 1].op != ContOp.RESTORE_ENV)
      push(ContOp.RESTORE_ENV, env);
  }
}

//----------------------------------------------------------------------

/// Lambda expression with its environment
class Closure {
  final Cell params;
  final Cell body;
  final Environment env;

  Closure(this.params, this.body, this.env);
}

typedef Object IntrinsicBody(Cell args);

/// Built-in function
class Intrinsic {
  final String name;
  final int arity;
  final IntrinsicBody fun;

  Intrinsic(this.name, this.arity, this.fun);
  @override
  String toString() => '#<$name:$arity>';
}

/// Exception thrown by error procedure of SRFI-23
class ErrorException implements Exception {
  final Object reason;
  final Object arg;

  ErrorException(Object this.reason, Object this.arg);
  @override
  String toString() => stringify(reason, false) + ': ' + stringify(arg);
}

//----------------------------------------------------------------------

/// Converts an expression to a string.
String stringify(Object exp, [bool quote = true]) {
  if (exp == true) return '#t';
  if (exp == false) return '#f';
  if (exp == #NONE) return '#<VOID>';
  if (exp == #EOF) return '#<EOF>';
  if (exp == #CALLCC) return '#<call/cc>';
  if (exp == #APPLY) return '#<apply>';
  if (exp == null) return '()';
  if (exp is Cell) {
    var ss = <String>[];
    try {
      for (var e in exp)
        ss.add(stringify(e, quote));
    } on ImproperListException catch (ex) {
      ss.add('.');
      ss.add(stringify(ex.tail, quote));
    }
    return '(' + ss.join(' ') + ')';
  }
  if (exp is Continuation) {
    var ss = <String>[];
    for (var step in exp)
      ss.add('${step.op} ${stringify(step.val)}');
    return '#<' + ss.join('\n\t  ') + '>';
  }
  if (exp is Closure) {
    var p = stringify(exp.params);
    var v = stringify(exp.body);
    var e = stringify(exp.env);
    return '#<$p:$v:$e>';
  }
  if ((exp is String) && quote) {
    return '"' + exp + '"';
  }
  return "$exp";
}

//----------------------------------------------------------------------

/// Scheme's global environment
Environment globalEnv = (() {
  var env = Environment(null, null, null);
  var _ = (String name, int arity, IntrinsicBody fun) {
    env.defineSymbol(Sym(name), Intrinsic(name, arity, fun));
  };

  _('car', 1, (Cell x) => (x.car as Cell).car);
  _('cdr', 1, (Cell x) => (x.car as Cell).cdr);
  _('cons', 2, (Cell x) => Cell(x.car, x.cdr.car));
  _('eq?', 2, (Cell x) => identical(x.car, x.cdr.car));
  _('pair?', 1, (Cell x) => x.car is Cell);
  _('null?', 1, (Cell x) => x.car == null);
  _('not', 1, (Cell x) => x.car == false);
  _('list', -1, (Cell x) => x);
  _('display', 1, (Cell x) {
    stdout.write(stringify(x.car, false));
    return #NONE;
  });
  _('newline', 0, (Cell x) {
    stdout.writeln();
    return #NONE;
  });
  _('read', 0, (Cell x) => readExpression('', ''));
  _('eof-object?', 1, (Cell x) => x.car == #EOF);
  _('symbol?', 1, (Cell x) => x.car is Sym);

  env.defineSymbol(callccSym, #CALLCC);
  env.defineSymbol(applySym, #APPLY);

  _('+', 2, (Cell x) => add(x.car, x.cdr.car));
  _('-', 2, (Cell x) => subtract(x.car, x.cdr.car));
  _('*', 2, (Cell x) => multiply(x.car, x.cdr.car));
  _('/', 2, (Cell x) => divide(x.car, x.cdr.car));
  _('<', 2, (Cell x) => compare(x.car, x.cdr.car) < 0);
  _('=', 2, (Cell x) => compare(x.car, x.cdr.car) == 0);
  _('number?', 1, (Cell x) => isNumber(x.car));
  _('error', 2, (Cell x) => throw ErrorException(x.car, x.cdr.car));
  _('globals', 0, (Cell x) {
    Cell j = null;
    for (Sym symbol in globalEnv.names)
      j = Cell(symbol, j);
    return j;
  });
  return env;
})();

//----------------------------------------------------------------------

/// Evaluates an expression in an environment.
Object evaluate(dynamic exp, Environment env) {
  var k = Continuation();
  try {
    for (;;) {
      for (;;) {
        if (exp is Cell) {
          Object kar = exp.car;
          dynamic kdr = exp.cdr;
          if (identical(kar, quoteSym)) { // (quote e)
            exp = kdr.car;
            break;
          } else if (identical(kar, ifSym)) { // (if e1 e2 e3) or (if e1 e2)
            exp = kdr.car;
            k.push(ContOp.THEN, kdr.cdr);
          } else if (identical(kar, beginSym)) { // (begin e...)
            exp = kdr.car;
            if (kdr.cdr != null)
              k.push(ContOp.BEGIN, kdr.cdr);
          } else if (identical(kar, lambdaSym)) { // (lambda (v...) e...)
            exp = Closure(kdr.car as Cell, kdr.cdr as Cell, env);
            break;
          } else if (identical(kar, defineSym)) { // (define v e)
            exp = kdr.cdr.car;
            k.push(ContOp.DEFINE, kdr.car);
          } else if (identical(kar, setqSym)) { // (set! v e)
            exp = kdr.cdr.car;
            k.push(ContOp.SETQ, env.lookForSetter(kdr.car as Sym));
          } else {              // (fun arg...)
            exp = kar;
            k.push(ContOp.APPLY, kdr);
          }
        } else if (exp is Sym) {
          exp = env.lookForValue(exp as Sym);
          break;
        } else {                // a number, #t, #f etc.
          break;
        }
      }
      Loop2:
      for (;;) {
        // stdout.write('_${k.length}');
        if (k.isEmpty)
          return exp;
        var step = k.pop();
        var op = step.op;
        dynamic x = step.val;
        switch (op) {
          case ContOp.THEN:     // x is (e2 e3) of (if e1 e2 e3).
            if (exp == false) {
              if (x.cdr == null) {
                exp = #NONE;
              } else {
                exp = x.cdr.car; // e3
                break Loop2;
              }
            } else {
              exp = x.car;      // e2
              break Loop2;
            }
            break;
          case ContOp.BEGIN:    //  x is (e...) of (begin e...).
            if (x.cdr != null)
              k.push(ContOp.BEGIN, x.cdr); // unless on a tail call.
            exp = x.car;
            break Loop2;
          case ContOp.DEFINE:   // x is a Sym to be defined.
            env.defineSymbol(x as Sym, exp);
            exp = #NONE;
            break;
          case ContOp.SETQ:     // x is a Setter.
            x(exp);
            exp = #NONE;
            break;
          case ContOp.APPLY:    // x is a list of arguments to be eval'ed.
            if (x == null) {
              var pair = applyFunction(exp, null, k, env);
              exp = pair.result;
              env = pair.env;
            } else {
              k.push(ContOp.APPLY_FUN, exp);
              while (x.cdr != null) {
                k.push(ContOp.EVAL_ARG, x.car);
                x = x.cdr;
              }
              exp = x.car;
              k.push(ContOp.CONS_ARGS, null);
              break Loop2;
            }
            break;
          case ContOp.CONS_ARGS: // x is the evaluated arguments to be cons'ed.
            var args = Cell(exp, x);
            var step = k.pop();
            op = step.op;
            exp = step.val;
            switch (op) {
              case ContOp.EVAL_ARG: // exp is the next argument to be eval'ed.
                k.push(ContOp.CONS_ARGS, args);
                break Loop2;
              case ContOp.APPLY_FUN: // exp is the evaluated function.
                var pair = applyFunction(exp, args, k, env);
                exp = pair.result;
                env = pair.env;
                break;
              default:
                throw 'unexpected op: $op';
            }
            break;
          case ContOp.RESTORE_ENV: // x is an Environment.
            env = x as Environment;
            break;
          default:
            throw 'bad op: $op';
        }
      }
    }
  } catch (ex) {
    if (ex is ErrorException) rethrow;
    if (k.isEmpty) rethrow;
    throw '${ex}\n\t${stringify(k)}';
  }
}

class REPair {
  final Object result;
  final Environment env;

  REPair(this.result, this.env);
}

/// Applies a function to arguments with a continuation.
/// [env] will be referred to push [ContOp.RESTORE_ENV] to the continuation.
REPair applyFunction(Object fun, Cell arg, Continuation k, Environment env) {
  for (;;) {
    if (fun == #CALLCC) {
      k.pushRestoreEnv(env);
      fun = arg.car;
      var cont = Continuation();
      cont.copyFrom(k);
      arg = Cell(cont, null);
    } else if (fun == #APPLY) {
      fun = arg.car;
      arg = arg.cdr.car as Cell;
    } else {
      break;
    }
  }
  if (fun is Intrinsic) {
    if (fun.arity >= 0) {
      if (arg == null ? fun.arity > 0 : arg.length != fun.arity)
        throw 'arity not matched: $fun and ${stringify(arg)}';
    }
    return REPair(fun.fun(arg), env);
  } else if (fun is Closure) {
    k.pushRestoreEnv(env);
    k.push(ContOp.BEGIN, fun.body);
    return REPair(#NONE, Environment(fun.params, arg, fun.env));
  } else if (fun is Continuation) {
    k.copyFrom(fun);
    return REPair(arg.car, env);
  } else {
    throw 'not a function: ${stringify(fun)} with ${stringify(arg)}';
  }
}

//----------------------------------------------------------------------

final _anySpaces = RegExp(r'\s+');

/// '(a 1)' => ['(', 'a', '1', ')']
List<String> splitStringIntoTokens(String source) {
  var result = <String>[];
  for (var line in source.split('\n')) {
    var x = <String>[];
    var ss = <String>[];        // to store string literals
    int i = 0;
    for (var e in line.split('"')) {
      if (i % 2 == 0) {
        x.add(e);
      } else {
        ss.add('"' + e);        // Stores a string literal.
        x.add('#s');
      }
      i++;
    }
    var s = x.join(' ').split(';')[0]; // Ignores ;-comment.
    s = s.replaceAll("'", " ' ").replaceAll(')', ' ) ').replaceAll('(', ' ( ');
    x = s.split(_anySpaces);
    for (var e in x)
      if (e == '#s')
        result.add(ss.removeAt(0));
      else if (e != '')
        result.add(e);
  }
  return result;
}

/// Reads an expression from [tokens].
/// [tokens] will be left with the rest of token strings, if any.
Object readFromTokens(List<String> tokens) {
  String token = tokens.removeAt(0);
  switch (token) {
    case '(':
      Cell z = Cell(null, null);
      var y = z;
      while (tokens[0] != ')') {
        if (tokens[0] == '.') {
          tokens.removeAt(0);
          y.cdr = readFromTokens(tokens);
          if (tokens[0] != ')')
            throw ') is expected';
          break;
        }
        var e = readFromTokens(tokens);
        var x = Cell(e, null);
        y.cdr = x;
        y = x;
      }
      tokens.removeAt(0);
      return z.cdr;
    case ')':
      throw 'unexpected )';
    case "'":
      var e = readFromTokens(tokens);
      return Cell(quoteSym, Cell(e, null)); // 'e => (quote e)
    case '#f':
      return false;
    case '#t':
      return true;
  }
  if (token[0] == '"') {
    return token.substring(1);
  }
  return tryParse(token) ?? Sym(token);
}

//----------------------------------------------------------------------

/// Loads a source code from a file.
void load(String fileName) {
  var file = File(fileName);
  String source = file.readAsStringSync();
  List<String> tokens = splitStringIntoTokens(source);
  while (tokens.isNotEmpty) {
    var exp = readFromTokens(tokens);
    evaluate(exp, globalEnv);
  }
}

/// Tokens from the standard-in.
var stdInTokens = <String>[];

/// Reads an expression from the standard-in.
Object readExpression([String prompt1 = '> ', String prompt2 = '| ']) {
  for (;;) {
    var old = List<String>.from(stdInTokens);
    try {
      return readFromTokens(stdInTokens);
    } on RangeError {
      stdout.write(old.isEmpty ? prompt1 : prompt2);
      var line = stdin.readLineSync();
      if (line == null)         // EOF
        return #EOF;
      stdInTokens = old;
      stdInTokens.addAll(splitStringIntoTokens(line));
    } on String {
      stdInTokens.clear();      // Discards the erroneous tokens.
      rethrow;
    }
  }
}

/// Repeats read-eval-print until End-of-File.
void readEvalPrintLoop() {
  for (;;) {
    try {
      var exp = readExpression();
      if (exp == #EOF) {
        print('Goodbye');
        return;
      }
      var result = evaluate(exp, globalEnv);
      if (result != #NONE)
        print(stringify(result, true));
    } catch (ex) {
      print(ex);
    }
  }
}

void main(List<String> args) {
  if (args.length > 0) {
    load(args[0]);
    if (!(args.length > 1 && args[1] == '-'))
      exit(0);
  }
  readEvalPrintLoop();
}
