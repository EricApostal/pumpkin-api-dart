// The `bit32` library CC: Tweaked provides (Lua 5.2 semantics: operations on
// unsigned 32-bit integers).
import '../value.dart';
import '../vm.dart';
import 'args.dart';

const int _mask = 0xFFFFFFFF;

int _toUint32(double x) {
  if (x.isNaN || x.isInfinite) return 0;
  return x.floorToDouble().toInt() & _mask;
}

void installBit32(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('bit32', lib);

  int arg(Args args, int i) => _toUint32(args.number(i));

  int logicalShift(int x, int disp) {
    if (disp <= -32 || disp >= 32) return 0;
    return disp >= 0 ? (x << disp) & _mask : x >> -disp;
  }

  define(lib, 'band', (list) {
    final args = Args('band', list);
    var result = _mask;
    for (var i = 0; i < list.length; i++) {
      result &= arg(args, i);
    }
    return one(result.toDouble());
  });

  define(lib, 'bor', (list) {
    final args = Args('bor', list);
    var result = 0;
    for (var i = 0; i < list.length; i++) {
      result |= arg(args, i);
    }
    return one(result.toDouble());
  });

  define(lib, 'bxor', (list) {
    final args = Args('bxor', list);
    var result = 0;
    for (var i = 0; i < list.length; i++) {
      result ^= arg(args, i);
    }
    return one(result.toDouble());
  });

  define(lib, 'btest', (list) {
    final args = Args('btest', list);
    var result = _mask;
    for (var i = 0; i < list.length; i++) {
      result &= arg(args, i);
    }
    return one(result != 0);
  });

  define(lib, 'bnot', (list) => one((~arg(Args('bnot', list), 0) & _mask).toDouble()));

  define(lib, 'lshift', (list) {
    final args = Args('lshift', list);
    return one(logicalShift(arg(args, 0), args.integer(1)).toDouble());
  });

  define(lib, 'rshift', (list) {
    final args = Args('rshift', list);
    return one(logicalShift(arg(args, 0), -args.integer(1)).toDouble());
  });

  define(lib, 'arshift', (list) {
    final args = Args('arshift', list);
    final x = arg(args, 0);
    final disp = args.integer(1);
    if (disp < 0) return one(logicalShift(x, -disp).toDouble());
    final signed = x >= 0x80000000 ? x - 0x100000000 : x;
    if (disp >= 32) return one((signed < 0 ? _mask : 0).toDouble());
    return one(((signed >> disp) & _mask).toDouble());
  });

  int rotate(int x, int disp) {
    final d = disp & 31;
    if (d == 0) return x;
    return ((x << d) | (x >> (32 - d))) & _mask;
  }

  define(lib, 'lrotate', (list) {
    final args = Args('lrotate', list);
    return one(rotate(arg(args, 0), args.integer(1)).toDouble());
  });

  define(lib, 'rrotate', (list) {
    final args = Args('rrotate', list);
    return one(rotate(arg(args, 0), -args.integer(1)).toDouble());
  });

  (int, int) fieldAndWidth(Args args, int fieldIndex) {
    final field = args.integer(fieldIndex);
    final width = args.optInteger(fieldIndex + 1, 1);
    if (field < 0) args.bad(fieldIndex, 'field cannot be negative');
    if (width <= 0) args.bad(fieldIndex + 1, 'width must be positive');
    if (field + width > 32) {
      throw LuaError.message('trying to access non-existent bits');
    }
    return (field, width);
  }

  define(lib, 'extract', (list) {
    final args = Args('extract', list);
    final n = arg(args, 0);
    final (field, width) = fieldAndWidth(args, 1);
    final mask = width == 32 ? _mask : (1 << width) - 1;
    return one(((n >> field) & mask).toDouble());
  });

  define(lib, 'replace', (list) {
    final args = Args('replace', list);
    final n = arg(args, 0);
    final value = arg(args, 1);
    final (field, width) = fieldAndWidth(args, 2);
    final mask = width == 32 ? _mask : (1 << width) - 1;
    final cleared = n & ~(mask << field) & _mask;
    return one((cleared | ((value & mask) << field)).toDouble());
  });
}
