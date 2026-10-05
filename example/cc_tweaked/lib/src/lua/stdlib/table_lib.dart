// The `table` library. Like CC: Tweaked's, it respects metamethods.
import '../value.dart';
import '../vm.dart';
import 'args.dart';
import 'base_lib.dart';

void installTable(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('table', lib);

  Object? get(Object? table, int index) => table is LuaTable && table.meta == null
      ? table.getInt(index)
      : vm.index(table, index.toDouble());

  void set(Object? table, int index, Object? value) {
    if (table is LuaTable && table.meta == null) {
      table.setInt(index, value);
    } else {
      vm.setIndex(table, index.toDouble(), value);
    }
  }

  LuaTable checkTable(Args args, int index) {
    final value = args[index];
    if (value is LuaTable) return value;
    args.wrongType(index, 'table');
  }

  define(lib, 'insert', (list) {
    final args = Args('insert', list);
    final table = checkTable(args, 0);
    final n = lengthOf(vm, table);
    switch (list.length) {
      case 2:
        set(table, n + 1, list[1]);
      case 3:
        final position = args.integer(1);
        if (position < 1 || position > n + 1) {
          args.bad(1, 'position out of bounds');
        }
        for (var i = n; i >= position; i--) {
          set(table, i + 1, get(table, i));
        }
        set(table, position, list[2]);
      default:
        throw LuaError.message("wrong number of arguments to 'insert'");
    }
    return noValues;
  });

  define(lib, 'remove', (list) {
    final args = Args('remove', list);
    final table = checkTable(args, 0);
    final n = lengthOf(vm, table);
    var position = args.optInteger(1, n);
    if (position != n && (position < 1 || position > n + 1)) {
      args.bad(1, 'position out of bounds');
    }
    final removed = get(table, position);
    for (; position < n; position++) {
      set(table, position, get(table, position + 1));
    }
    set(table, position, null);
    return one(removed);
  });

  define(lib, 'concat', (list) {
    final args = Args('concat', list);
    final table = checkTable(args, 0);
    final separator = args.optString(1, '');
    final first = args.optInteger(2, 1);
    final last = args.isNone(3) ? lengthOf(vm, table) : args.integer(3);
    final out = StringBuffer();
    for (var i = first; i <= last; i++) {
      final value = get(table, i);
      if (value is String) {
        out.write(value);
      } else if (value is double) {
        out.write(formatNumber(value));
      } else {
        throw LuaError.message(
          "invalid value (at index $i) in table for 'concat'",
        );
      }
      if (i < last) out.write(separator);
      if (out.length > vm.maxStringLength) {
        throw LuaError.message('not enough memory');
      }
    }
    return one(out.toString());
  });

  define(lib, 'unpack', (list) => unpackTable(vm, Args('unpack', list)));

  define(lib, 'pack', (list) {
    final table = LuaTable();
    for (var i = 0; i < list.length; i++) {
      table.setInt(i + 1, list[i]);
    }
    table.setString('n', list.length.toDouble());
    return one(table);
  });

  define(lib, 'maxn', (list) {
    final table = checkTable(Args('maxn', list), 0);
    var max = 0.0;
    var entry = table.next(null);
    while (entry != null) {
      final key = entry.$1;
      if (key is double && key > max) max = key;
      entry = table.next(key);
    }
    return one(max);
  });

  define(lib, 'getn', (list) => one(lengthOf(vm, checkTable(Args('getn', list), 0)).toDouble()));

  define(lib, 'create', (_) => one(LuaTable()));

  define(lib, 'move', (list) {
    final args = Args('move', list);
    final source = checkTable(args, 0);
    final from = args.integer(1);
    final end = args.integer(2);
    final to = args.integer(3);
    final target = args.isNone(4) ? source : checkTable(args, 4);
    if (end >= from) {
      if (to > end || to <= from || source != target) {
        for (var i = 0; i <= end - from; i++) {
          set(target, to + i, get(source, from + i));
        }
      } else {
        for (var i = end - from; i >= 0; i--) {
          set(target, to + i, get(source, from + i));
        }
      }
    }
    return one(target);
  });

  define(lib, 'foreach', (list) {
    final args = Args('foreach', list);
    final table = checkTable(args, 0);
    final function = args.function(1);
    var entry = table.next(null);
    while (entry != null) {
      final result = vm.call(function, [entry.$1, entry.$2]);
      if (result.isNotEmpty && result.first != null) return one(result.first);
      entry = table.next(entry.$1);
    }
    return noValues;
  });

  define(lib, 'foreachi', (list) {
    final args = Args('foreachi', list);
    final table = checkTable(args, 0);
    final function = args.function(1);
    final n = lengthOf(vm, table);
    for (var i = 1; i <= n; i++) {
      final result = vm.call(function, [i.toDouble(), get(table, i)]);
      if (result.isNotEmpty && result.first != null) return one(result.first);
    }
    return noValues;
  });

  define(lib, 'sort', (list) {
    final args = Args('sort', list);
    final table = checkTable(args, 0);
    final comparator = args.isNone(1) ? null : args.function(1);
    final n = lengthOf(vm, table);
    final items = <Object?>[for (var i = 1; i <= n; i++) get(table, i)];
    bool less(Object? a, Object? b) {
      if (comparator != null) {
        final result = vm.call(comparator, [a, b]);
        return result.isNotEmpty && isTruthy(result.first);
      }
      return lessThan(vm, a, b);
    }

    _mergeSort(items, less);
    for (var i = 0; i < n; i++) {
      set(table, i + 1, items[i]);
    }
    return noValues;
  });
}

/// `a < b` as the `<` operator does it, for library code.
bool lessThan(LuaVm vm, Object? a, Object? b) {
  if (a is double && b is double) return a < b;
  if (a is String && b is String) return a.compareTo(b) < 0;
  final handler = vm.metamethod(a, '__lt') ?? vm.metamethod(b, '__lt');
  if (handler != null) {
    final result = vm.call(handler, [a, b]);
    return result.isNotEmpty && isTruthy(result.first);
  }
  final ta = luaTypeName(a);
  final tb = luaTypeName(b);
  throw LuaError.message(
    ta == tb ? 'attempt to compare two $ta values' : 'attempt to compare $ta with $tb',
  );
}

/// A stable merge sort that never throws for inconsistent comparators.
void _mergeSort(List<Object?> items, bool Function(Object?, Object?) less) {
  if (items.length < 2) return;
  var source = List<Object?>.of(items);
  var target = List<Object?>.filled(items.length, null);
  for (var width = 1; width < items.length; width *= 2) {
    for (var start = 0; start < items.length; start += 2 * width) {
      final middle = start + width < items.length ? start + width : items.length;
      final end = start + 2 * width < items.length ? start + 2 * width : items.length;
      var i = start;
      var j = middle;
      var k = start;
      while (i < middle && j < end) {
        if (less(source[j], source[i])) {
          target[k++] = source[j++];
        } else {
          target[k++] = source[i++];
        }
      }
      while (i < middle) {
        target[k++] = source[i++];
      }
      while (j < end) {
        target[k++] = source[j++];
      }
    }
    final swap = source;
    source = target;
    target = swap;
  }
  for (var i = 0; i < items.length; i++) {
    items[i] = source[i];
  }
}
