#!/usr/bin/env dart
// A little Scheme in Dart 2.3 v0.2 H31.03.23/R01.06.07 by SUZUKI Hisao

import 'dart:io';

/// Cons cell
class Cell extends Iterable<dynamic> {
  dynamic car;
  dynamic cdr;

  Cell(this.car, this.cdr);

  Iterable<dynamic> _iter() sync* {
    dynamic j = this;
    while (j is Cell) {
      yield j.car;
      j = j.cdr;
    }
    if (j != null) throw ImproperListException(j);
  }

  /// Yield car, cadr, caddr and so on.
  Iterator<dynamic> get iterator => _iter().iterator;
}

class ImproperListException implements Exception {
  final dynamic tail;

  ImproperListException(this.tail);
}

//----------------------------------------------------------------------

/// Scheme's symbol
class Sym {
  final String name;

  /// Construct a symbol that is not interned yet.
  Sym.notInterned(this.name);

  @override
  String toString() => name;

  /// The table of interned symbols
  static final Map<String, Sym> symbols = {};

  /// Construct an interned symbol.
  factory Sym(String name) {
    return symbols.putIfAbsent(name, () => Sym.notInterned(name));
  }
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

/// Linked list of bindings mapping symbols to values
class Environment extends Iterable<Environment> {
  final Sym sym;
  dynamic val;
  Environment next;

  Environment(this.sym, this.val, this.next);

  Iterable<Environment> _iter() sync* {
    var env = this;
    while (env != null) {
      yield env;
      env = env.next;
    }
  }

  /// Yield each binding.
  Iterator<Environment> get iterator => _iter().iterator;

  /// Search the bindings for a symbol.
  Environment lookFor(Sym symbol) {
    for (var env in this) if (identical(env.sym, symbol)) return env;
    throw 'name not found: $symbol';
  }

  /// Build an environment prepending the bindings of symbols and data.
  Environment prependDefs(Cell symbols, Cell data) {
    if (symbols == null) {
      if (data != null) {
        throw 'surplus arg: ${stringify(data)}';
      }
      return this;
    } else {
      if (data == null) {
        throw 'surplus param: ${stringify(symbols)}';
      }
      return Environment(
          symbols.car, data.car, prependDefs(symbols.cdr, data.cdr));
    }
  }
}

//----------------------------------------------------------------------

/// Operations in continuations
enum ContOp {
  thenOp,
  beginOp,
  defineOp,
  setqOp,
  applyOp,
  applyFunOp,
  evalArgOp,
  pushArgOp,
  restoreEnvOp
}

/// Scheme's step in a continuation
class Step {
  ContOp op;
  dynamic val;

  Step(this.op, this.val);
}

// Scheme's continuation as a stack of steps
class Continuation extends Iterable<Step> {
  final List<Step> _stack = [];

  bool get isEmpty => _stack.isEmpty;
  int get length => _stack.length;

  Iterable<Step> _iter() sync* {
    for (var step in _stack) yield step;
  }

  /// Yield each step.
  Iterator<Step> get iterator => _iter().iterator;

  /// Append a step to the tail of the continuation.
  void push(ContOp op, dynamic value) => _stack.add(Step(op, value));

  /// Pop a step from the tail of the continuation.
  Step pop() => _stack.removeLast();

  /// Copy a continuation.
  void copyFrom(Continuation other) {
    _stack.clear();
    _stack.addAll(other._stack);
  }

  /// Push restoreEnvOp unless on a tail call.
  void pushRestoreEnv(Environment env) {
    int len = _stack.length;
    if (len == 0 || _stack[len - 1].op != ContOp.restoreEnvOp) {
      push(ContOp.restoreEnvOp, env);
    }
  }
}

//----------------------------------------------------------------------

/// Lambda expression with its environment
class Closure {
  Cell params;
  Cell body;
  Environment env;

  Closure(this.params, this.body, this.env);
}

typedef dynamic IntrinsicBody(Cell args);

/// Built-in function
class Intrinsic {
  final String name;
  final int arity;
  final IntrinsicBody fun;

  Intrinsic(this.name, this.arity, this.fun);
  @override
  String toString() => '#<$name:$arity>';
}

/// A unique value which means the expression has no value.
final none = Object();

//----------------------------------------------------------------------

/// Convert an expression to a string.
String stringify(dynamic exp, [bool quote = true]) {
  if (exp == true) {
    return '#t';
  } else if (exp == false) {
    return '#f';
  } else if (exp == none) {
    return '#<VOID>';
  } else if (exp == null) {
    return '()';
  } else if (exp is Cell) {
    var ss = <String>[];
    try {
      for (var e in exp) ss.add(stringify(e, quote));
    } on ImproperListException catch (ex) {
      ss.add('.');
      ss.add(stringify(ex.tail, quote));
    }
    return '(' + ss.join(' ') + ')';
  } else if (exp is Environment) {
    var ss = <String>[];
    for (var env in exp) {
      if (identical(env, globalEnv)) {
        ss.add('GlobalEnv');
        break;
      } else if (env.sym == null) // marker of the frame top
        ss.add('|');
      else
        ss.add('${env.sym}');
    }
    return '#<' + ss.join(' ') + '>';
  } else if (exp is Continuation) {
    var ss = <String>[];
    for (var step in exp) ss.add('${step.op} ${stringify(step.val)}');
    return '#<' + ss.join('\n\t  ') + '>';
  } else if (exp is Closure) {
    var p = stringify(exp.params);
    var v = stringify(exp.body);
    var e = stringify(exp.env);
    return '#<$p:$v:$e>';
  } else if ((exp is String) && quote) {
    return '"' + exp + '"';
  }
  return "$exp";
}

//----------------------------------------------------------------------

/// Return a list of symbols of the global environment.
Cell _globals(Cell x) {
  Cell j = null;
  Environment env = globalEnv.next; // Skip the marker.
  for (Environment e in env) j = Cell(e.sym, j);
  return j;
}

Environment _(String name, int arity, IntrinsicBody fun, Environment next) =>
    Environment(Sym(name), Intrinsic(name, arity, fun), next);

Environment _g1 = 
  _('display', 1,
      (Cell x) { stdout.write(stringify(x.car, false)); return none; },
      _('newline', 0,
          (Cell x) { stdout.writeln(); return none; },
          _('read', 0,
              (Cell x) => readExpression('', ''),
              _('eof-object?', 1,
                  (Cell x) => x.car == #EOF,
                  _('symbol?', 1,
                      (Cell x) => x.car is Sym,
                      _('+', 2,
                          (Cell x) => x.car + x.cdr.car,
                          _('-', 2,
                              (Cell x) => x.car - x.cdr.car,
                              _('*', 2,
                                  (Cell x) => x.car * x.cdr.car,
                                  _('<', 2,
                                      (Cell x) => x.car < x.cdr.car,
                                      _('=', 2,
                                          (Cell x) => x.car == x.cdr.car,
                                          _('globals', 0,
                                              _globals,
                                              null)))))))))));

Environment globalEnv = Environment(
    null, // marker of the frame top
    null,
    _('car', 1,
        (Cell x) => x.car.car,
        _('cdr', 1,
            (Cell x) => x.car.cdr,
            _('cons', 2,
                (Cell x) => Cell(x.car, x.cdr.car),
                _('eq?', 2,
                    (Cell x) => identical(x.car, x.cdr.car),
                    _('eqv?', 2,
                        (Cell x) => x.car == x.cdr.car,
                        _('pair?', 1,
                            (Cell x) => x.car is Cell,
                            _('null?', 1,
                                (Cell x) => x.car == null,
                                _('not', 1,
                                    (Cell x) => x.car == false,
                                    _('list', -1,
                                        (Cell x) => x,
                                        Environment(
                                            callccSym,
                                            callccSym,
                                            Environment(applySym, applySym,
                                                _g1))))))))))));

//----------------------------------------------------------------------

/// Evaluate an expression in an environment.
Object evaluate(dynamic exp, Environment env) {
  var k = Continuation();
  try {
    for (;;) {
      for (;;) {
        if (exp is Cell) {
          dynamic kar = exp.car;
          dynamic kdr = exp.cdr;
          if (identical(kar, quoteSym)) {
            // (quote e)
            exp = kdr.car;
            break;
          } else if (identical(kar, ifSym)) {
            // (if e1 e2 e3) or (if e1 e2)
            exp = kdr.car;
            k.push(ContOp.thenOp, kdr.cdr);
          } else if (identical(kar, beginSym)) {
            // (begin e...)
            exp = kdr.car;
            if (kdr.cdr != null) {
              k.push(ContOp.beginOp, kdr.cdr);
            }
          } else if (identical(kar, lambdaSym)) {
            // (lambda (v...) e...)
            exp = Closure(kdr.car, kdr.cdr, env);
            break;
          } else if (identical(kar, defineSym)) {
            // (define v e)
            exp = kdr.cdr.car;
            k.push(ContOp.defineOp, kdr.car);
          } else if (identical(kar, setqSym)) {
            // (set! v e)
            exp = kdr.cdr.car;
            k.push(ContOp.setqOp, env.lookFor(kdr.car));
          } else {
            // (fun arg...)
            exp = kar;
            k.push(ContOp.applyOp, kdr);
          }
        } else if (exp is Sym) {
          exp = env.lookFor(exp).val;
          break;
        } else {
          // a number, #t, #f etc.
          break;
        }
      }
      Loop2:
      for (;;) {
        // stdout.write(' _${k.length}');
        if (k.isEmpty) {
          return exp;
        }
        var step = k.pop();
        var op = step.op;
        dynamic x = step.val;
        switch (op) {
          case ContOp.thenOp: // x = (e2 e3)
            if (exp == false) {
              if (x.cdr == null) {
                exp = none;
              } else {
                exp = x.cdr.car; // e3
                break Loop2;
              }
            } else {
              exp = x.car; // e2
              break Loop2;
            }
            break;
          case ContOp.beginOp: //  x = (e...)
            if (x.cdr != null) {
              k.push(ContOp.beginOp, x.cdr); // unless on a tail call.
            }
            exp = x.car;
            break Loop2;
          case ContOp.defineOp: // x = v
            assert(env.sym == null); // Check for the frame top.
            env.next = Environment(x, exp, env.next);
            exp = none;
            break;
          case ContOp.setqOp: // x = Environment(v, e, ...)
            x.val = exp;
            exp = none;
            break;
          case ContOp.applyOp: // x = arg...; exp = function
            if (x == null) {
              var pair = applyFunction(exp, null, k, env);
              exp = pair.result;
              env = pair.env;
            } else {
              k.push(ContOp.applyFunOp, exp);
              while (x.cdr != null) {
                k.push(ContOp.evalArgOp, x.car);
                x = x.cdr;
              }
              exp = x.car;
              k.push(ContOp.pushArgOp, null);
              break Loop2;
            }
            break;
          case ContOp.pushArgOp: // x = evaluated arg...
            var args = Cell(exp, x);
            var step = k.pop();
            op = step.op;
            exp = step.val;
            switch (op) {
              case ContOp.evalArgOp: // exp = the next arg
                k.push(ContOp.pushArgOp, args);
                break Loop2;
              case ContOp.applyFunOp: // exp = evaluated function
                var pair = applyFunction(exp, args, k, env);
                exp = pair.result;
                env = pair.env;
                break;
              default:
                throw 'unexpected op: $op';
            }
            break;
          case ContOp.restoreEnvOp: // x = Environment(...)
            env = x;
            break;
          default:
            throw 'bad op: $op';
        }
      }
    }
  } catch (ex) {
    if (k.isEmpty) rethrow;
    throw '${ex}\n\t${stringify(k)}';
  }
}

class ResultEnvPair {
  dynamic result;
  Environment env;

  ResultEnvPair(this.result, this.env);
}

/// Apply a function to arguments with a continuation.
/// [env] will be referred to push [ContOp.restoreEnvOp] to the continuation.
ResultEnvPair applyFunction(
    dynamic fun, Cell arg, Continuation k, Environment env) {
  for (;;) {
    if (identical(fun, callccSym)) {
      k.pushRestoreEnv(env);
      fun = arg.car;
      var cont = Continuation();
      cont.copyFrom(k);
      arg = Cell(cont, null);
    } else if (identical(fun, applySym)) {
      fun = arg.car;
      arg = arg.cdr.car;
    } else {
      break;
    }
  }
  if (fun is Intrinsic) {
    if (fun.arity >= 0) {
      if (arg == null ? fun.arity > 0 : arg.length != fun.arity)
        throw 'arity not matched: $fun and ${stringify(arg)}';
    }
    return ResultEnvPair(fun.fun(arg), env);
  } else if (fun is Closure) {
    k.pushRestoreEnv(env);
    k.push(ContOp.beginOp, fun.body);
    return ResultEnvPair(
        none,
        Environment(
            null, // marker of the frame top
            null,
            fun.env.prependDefs(fun.params, arg)));
  } else if (fun is Continuation) {
    k.copyFrom(fun);
    return ResultEnvPair(arg.car, env);
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
    var ss = <String>[]; // to store string literals
    int i = 0;
    for (var e in line.split('"')) {
      if (i % 2 == 0) {
        x.add(e);
      } else {
        ss.add('"' + e); // Store a string literal.
        x.add('#s');
      }
      i++;
    }
    var s = x.join(' ').split(';')[0]; // Ignore ;-comment.
    s = s.replaceAll("'", " ' ").replaceAll(')', ' ) ').replaceAll('(', ' ( ');
    x = s.split(_anySpaces);
    for (var e in x)
      if (e == '#s')
        result.add(ss.removeAt(0));
      else if (e != '') result.add(e);
  }
  return result;
}

/// Read an expression from [tokens].
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
          if (tokens[0] != ')') throw ') is expected';
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
  } else {
    try {
      return num.parse(token);
    } on FormatException {
      return Sym(token);
    }
  }
}

//----------------------------------------------------------------------

/// Load a source code from a file.
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

/// Read an expression from the standard-in.
Object readExpression([String prompt1 = '> ', String prompt2 = '| ']) {
  for (;;) {
    var old = List<String>.from(stdInTokens);
    try {
      return readFromTokens(stdInTokens);
    } on RangeError {
      stdout.write(old.isEmpty ? prompt1 : prompt2);
      var line = stdin.readLineSync();
      if (line == null) // EOF
        return #EOF;
      stdInTokens = old;
      stdInTokens.addAll(splitStringIntoTokens(line));
    } on String {
      stdInTokens.clear(); // Discard the erroneous tokens.
      rethrow;
    }
  }
}

/// Repeat read-eval-print until End-of-File.
void readEvalPrintLoop() {
  for (;;) {
    try {
      var exp = readExpression();
      if (exp == #EOF) {
        print('Goodbye');
        return;
      }
      var result = evaluate(exp, globalEnv);
      if (result != none) {
        print(stringify(result, true));
      }
    } catch (ex) {
      print(ex);
    }
  }
}

void main(List<String> args) {
  if (args.length > 0) {
    load(args[0]);
    if (!(args.length > 1 && args[1] == '-')) exit(0);
  }
  readEvalPrintLoop();
}
