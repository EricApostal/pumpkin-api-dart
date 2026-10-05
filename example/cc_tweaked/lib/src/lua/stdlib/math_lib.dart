// The `math` library, with the 5.0 and 5.1 functions CC: Tweaked keeps.
import 'dart:math' as math;

import '../value.dart';
import '../vm.dart';
import 'args.dart';

void installMath(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('math', lib);
  lib.setString('pi', math.pi);
  lib.setString('huge', double.infinity);

  var random = math.Random(vm.clock.elapsedMicroseconds ^ DateTime.now().microsecondsSinceEpoch);

  void unary(String name, double Function(double) f) {
    define(lib, name, (list) => one(f(Args(name, list).number(0))));
  }

  unary('abs', (x) => x.abs());
  unary('acos', math.acos);
  unary('asin', math.asin);
  unary('ceil', (x) => x.ceilToDouble());
  unary('cos', math.cos);
  unary('cosh', (x) => (math.exp(x) + math.exp(-x)) / 2);
  unary('deg', (x) => x * 180 / math.pi);
  unary('exp', math.exp);
  unary('floor', (x) => x.floorToDouble());
  unary('log10', (x) => math.log(x) / math.ln10);
  unary('rad', (x) => x * math.pi / 180);
  unary('sin', math.sin);
  unary('sinh', (x) => (math.exp(x) - math.exp(-x)) / 2);
  unary('sqrt', math.sqrt);
  unary('tan', math.tan);
  unary('tanh', (x) {
    if (x > 20) return 1;
    if (x < -20) return -1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  });

  define(lib, 'atan', (list) {
    final args = Args('atan', list);
    return one(math.atan2(args.number(0), args.optNumber(1, 1)));
  });
  define(lib, 'atan2', (list) {
    final args = Args('atan2', list);
    return one(math.atan2(args.number(0), args.number(1)));
  });

  define(lib, 'log', (list) {
    final args = Args('log', list);
    final x = args.number(0);
    if (args.isNone(1)) return one(math.log(x));
    final base = args.number(1);
    if (base == 10) return one(math.log(x) / math.ln10);
    if (base == 2) return one(math.log(x) / math.ln2);
    return one(math.log(x) / math.log(base));
  });

  NativeImpl fmod(String name) => (list) {
    final args = Args(name, list);
    return one(args.number(0).remainder(args.number(1)));
  };
  lib.setString('fmod', NativeFunction('fmod', fmod('fmod')));
  lib.setString('mod', NativeFunction('mod', fmod('mod')));

  define(lib, 'pow', (list) {
    final args = Args('pow', list);
    return one(math.pow(args.number(0), args.number(1)).toDouble());
  });

  define(lib, 'modf', (list) {
    final x = Args('modf', list).number(0);
    if (x.isInfinite) return <Object?>[x, 0.0];
    final integral = x >= 0 ? x.floorToDouble() : x.ceilToDouble();
    return <Object?>[integral, x - integral];
  });

  define(lib, 'frexp', (list) {
    final x = Args('frexp', list).number(0);
    if (x == 0 || x.isNaN || x.isInfinite) return <Object?>[x, 0.0];
    var exponent = (math.log(x.abs()) / math.ln2).floor() + 1;
    var mantissa = x / math.pow(2, exponent).toDouble();
    if (mantissa.abs() >= 1) {
      mantissa /= 2;
      exponent++;
    } else if (mantissa.abs() < 0.5) {
      mantissa *= 2;
      exponent--;
    }
    return <Object?>[mantissa, exponent.toDouble()];
  });

  define(lib, 'ldexp', (list) {
    final args = Args('ldexp', list);
    return one(args.number(0) * math.pow(2, args.integer(1)).toDouble());
  });

  NativeImpl extreme(String name, bool wantMax) => (list) {
    final args = Args(name, list);
    var best = args.number(0);
    for (var i = 1; i < list.length; i++) {
      final value = args.number(i);
      if (wantMax ? value > best : value < best) best = value;
    }
    return one(best);
  };
  lib.setString('max', NativeFunction('max', extreme('max', true)));
  lib.setString('min', NativeFunction('min', extreme('min', false)));

  define(lib, 'random', (list) {
    final args = Args('random', list);
    switch (list.length) {
      case 0:
        return one(random.nextDouble());
      case 1:
        final upper = args.integer(0);
        if (upper < 1) args.bad(0, 'interval is empty');
        return one((1 + _randomBelow(random, upper)).toDouble());
      case 2:
        final lower = args.integer(0);
        final upper = args.integer(1);
        if (lower > upper) args.bad(1, 'interval is empty');
        return one((lower + _randomBelow(random, upper - lower + 1)).toDouble());
      default:
        throw LuaError.message("wrong number of arguments");
    }
  });

  define(lib, 'randomseed', (list) {
    random = math.Random(Args('randomseed', list).integer(0) & 0x7FFFFFFF);
    return noValues;
  });
}

int _randomBelow(math.Random random, int bound) {
  if (bound <= 0x7FFFFFFF) return random.nextInt(bound);
  return (random.nextDouble() * bound).floor();
}
