#!/usr/bin/env dart
// A little Scheme in Dart 2.2 v0.1 H31.03.23/R01.05.06 by SUZUKI Hisao

import 'dart:io';

/// Empty List of Scheme
class ScmList extends Iterable<dynamic> {
  Iterable<dynamic> _iter() sync* {}

  /// Yield none.
  get iterator => _iter().iterator;
}

final nil = ScmList();

/// Cons cell
class Cell extends ScmList {
  dynamic car;
  dynamic cdr;

  Cell(this.car, this.cdr);

  Iterable<dynamic> _iter() sync* {
    dynamic j = this;
    while (j is Cell) {
      yield j.car;
      j = j.cdr;
    }
    if (!(identical(j, nil))) throw ImproperListException(j);
  }

  /// Yield car, cadr, caddr and so on.
  Iterator<dynamic> get iterator => _iter().iterator;
}

class ImproperListException implements Exception {
  final dynamic tail;

  ImproperListException(this.tail);
}

dynamic fst(ScmList x) => (x as Cell).car;
dynamic snd(ScmList x) => (x as Cell).cdr.car;

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
  Environment prependDefs(ScmList symbols, ScmList data) {
    if (identical(symbols, nil)) {
      if (!identical(data, nil)) {
        throw 'surplus arg: ${stringify(data)}';
      }
      return this;
    } else {
      if (identical(data, nil)) {
        throw 'surplus param: ${stringify(symbols)}';
      }
      return Environment((symbols as Cell).car, (data as Cell).car,
          prependDefs((symbols as Cell).cdr, (data as Cell).cdr));
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
  ScmList params;
  Cell body;
  Environment env;

  Closure(this.params, this.body, this.env);
}

typedef dynamic IntrinsicBody(ScmList args);

/// Built-in function
class Intrinsic {
  final String name;
  final int arity;
  final IntrinsicBody fun;

  Intrinsic(this.name, this.arity, this.fun);
  @override
  String toString() => '#<$name:$arity>';
}

//----------------------------------------------------------------------

/// Convert an expression to a string.
String stringify(dynamic exp, [bool quote = true]) {
  if (identical(exp, true)) {
    return '#t';
  } else if (identical(exp, false)) {
    return '#f';
  } else if (exp is ScmList) {
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
ScmList _globals(ScmList x) {
  var j = nil;
  var env = globalEnv.next; // Take next to skip the marker.
  for (var e in env) j = Cell(e.sym, j);
  return j;
}

Environment _(String name, int arity, IntrinsicBody fun, Environment next) =>
    Environment(Sym(name), Intrinsic(name, arity, fun), next);

Environment _g1 = 
  _('display', 1,
      (ScmList x) { stdout.write(stringify(fst(x), false)); return null; },
      _('newline', 0,
          (ScmList x) { stdout.writeln(); return null; },
          _('read', 0,
              (ScmList x) => readExpression('', ''),
              _('eof-object?', 1,
                  (ScmList x) => identical(fst(x), #EOF),
                  _('symbol?', 1,
                      (ScmList x) => fst(x) is Sym,
                      _('+', 2,
                          (ScmList x) => fst(x) + snd(x),
                          _('-', 2,
                              (ScmList x) => fst(x) - snd(x),
                              _('*', 2,
                                  (ScmList x) => fst(x) * snd(x),
                                  _('<', 2,
                                      (ScmList x) => fst(x) < snd(x),
                                      _('=', 2,
                                          (ScmList x) => fst(x) == snd(x),
                                          _('globals', 0,
                                              _globals,
                                              null)))))))))));

Environment globalEnv = Environment(
    null, null, // marker of the frame top
    _('car', 1,
        (ScmList x) => fst(x).car,
        _('cdr', 1,
            (ScmList x) => fst(x).cdr,
            _('cons', 2,
                (ScmList x) => Cell(fst(x), snd(x)),
                _('eq?', 2,
                    (ScmList x) => identical(fst(x), snd(x)),
                    _('eqv?', 2,
                        (ScmList x) => fst(x) == snd(x),
                        _('pair?', 1,
                            (ScmList x) => fst(x) is Cell,
                            _('null?', 1,
                                (ScmList x) => identical(fst(x), nil),
                                _('not', 1,
                                    (ScmList x) => identical(fst(x), false),
                                    _('list', -1,
                                        (ScmList x) => x,
                                        Environment(callccSym, callccSym,
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
            if (!(identical(kdr.cdr, nil))) {
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
            if (identical(exp, false)) {
              if (identical(x.cdr, nil)) {
                exp = null;
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
            if (!identical(x.cdr, nil)) {
              k.push(ContOp.beginOp, x.cdr); // unless on a tail call
            }
            exp = x.car;
            break Loop2;
          case ContOp.defineOp: // x = v
            assert(identical(env.sym, nil)); // Check for the frame top.
            env.next = Environment(x, exp, env.next);
            exp = null;
            break;
          case ContOp.setqOp: // x = Environment(v, e, ...)
            x.val = exp;
            exp = null;
            break;
          case ContOp.applyOp: // x = arg...; exp = function
            if (identical(x, nil)) {
              var pair = applyFunction(exp, nil, k, env);
              exp = pair.result;
              env = pair.env;
            } else {
              k.push(ContOp.applyFunOp, exp);
              while (!identical(x.cdr, nil)) {
                k.push(ContOp.evalArgOp, x.car);
                x = x.cdr;
              }
              exp = x.car;
              k.push(ContOp.pushArgOp, nil);
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
    dynamic fun, ScmList arg, Continuation k, Environment env) {
  for (;;) {
    if (identical(fun, callccSym)) {
      k.pushRestoreEnv(env);
      fun = fst(arg);
      var cont = Continuation();
      cont.copyFrom(k);
      arg = Cell(cont, nil);
    } else if (identical(fun, applySym)) {
      fun = fst(arg);
      arg = snd(arg);
    } else {
      break;
    }
  }
  if (fun is Intrinsic) {
    if (fun.arity >= 0 && arg.length != fun.arity)
      throw 'arity not matched: $fun and ${stringify(arg)}';
    return ResultEnvPair(fun.fun(arg), env);
  } else if (fun is Closure) {
    k.pushRestoreEnv(env);
    k.push(ContOp.beginOp, fun.body);
    return ResultEnvPair(
        null,
        Environment(
            null, null, // marker of the frame top
            fun.env.prependDefs(fun.params, arg)));
  } else if (fun is Continuation) {
    k.copyFrom(fun);
    return ResultEnvPair(fst(arg), env);
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
        ss.add('"' + e); // e is a string literal.
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
      Cell z = Cell(nil, nil);
      var y = z;
      while (tokens[0] != ')') {
        if (tokens[0] == '.') {
          tokens.removeAt(0);
          y.cdr = readFromTokens(tokens);
          if (tokens[0] != ')') throw ') is expected';
          break;
        }
        var e = readFromTokens(tokens);
        var x = Cell(e, nil);
        y.cdr = x;
        y = x;
      }
      tokens.removeAt(0);
      return z.cdr;
    case ')':
      throw 'unexpected )';
    case "'":
      var e = readFromTokens(tokens);
      return Cell(quoteSym, Cell(e, nil)); // 'e => (quote e)
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
      if (identical(exp, #EOF)) {
        print('Goodbye');
        return;
      }
      var result = evaluate(exp, globalEnv);
      if (result != null) {
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
