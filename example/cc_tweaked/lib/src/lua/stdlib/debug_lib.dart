// The part of the `debug` library CraftOS programs use: tracebacks, function
// information and metatable access. Locals and upvalues are not inspectable.
// `installDebug` returns the registry table (`debug.getregistry()`).
import '../lexer.dart';
import '../value.dart';
import '../vm.dart';
import 'args.dart';

LuaTable installDebug(LuaVm vm) {
  final lib = LuaTable();
  vm.globals.setString('debug', lib);
  final registry = LuaTable();

  define(lib, 'getregistry', (_) => one(registry));

  define(lib, 'getmetatable', (list) => one(vm.metatableOf(Args('getmetatable', list).any(0))));

  define(lib, 'setmetatable', (list) {
    final args = Args('setmetatable', list);
    final value = args[0];
    final meta = args[1];
    if (value is LuaTable) value.meta = meta as LuaTable?;
    return one(value);
  });

  define(lib, 'traceback', (list) {
    var offset = 0;
    if (list.isNotEmpty && list[0] is Coroutine) offset = 1;
    final args = Args('traceback', list);
    final message = args[offset];
    if (message != null && message is! String && message is! double) {
      return one(message);
    }
    final level = args.optInteger(offset + 1, 1);
    final text = message is double ? formatNumber(message) : message as String?;
    return one(vm.traceback(text, level));
  });

  define(lib, 'getinfo', (list) {
    final args = Args('getinfo', list);
    var offset = 0;
    Coroutine? thread = vm.current;
    if (list.isNotEmpty && list[0] is Coroutine) {
      thread = list[0]! as Coroutine;
      offset = 1;
    }
    final target = args[offset];
    final info = LuaTable();
    LuaClosure? closure;
    var line = -1;
    if (target is LuaFunction) {
      closure = target is LuaClosure ? target : null;
      info.setString('func', target);
    } else {
      final level = args.integer(offset);
      final frames = thread?.frames ?? const <Frame>[];
      final index = frames.length - level;
      if (level < 0 || index < 0 || index >= frames.length) return one(null);
      final frame = frames[index];
      closure = frame.closure;
      if (closure != null) {
        final pc = frame.pc > 0 ? frame.pc - 1 : 0;
        line = pc < closure.proto.lines.length ? closure.proto.lines[pc] : closure.proto.line;
        info.setString('func', closure);
      }
    }
    if (closure == null) {
      info
        ..setString('source', '=[C]')
        ..setString('short_src', '[C]')
        ..setString('what', 'C')
        ..setString('currentline', -1.0)
        ..setString('linedefined', -1.0)
        ..setString('lastlinedefined', -1.0)
        ..setString('nups', 0.0)
        ..setString('nparams', 0.0)
        ..setString('isvararg', true);
    } else {
      final proto = closure.proto;
      info
        ..setString('source', proto.chunkName)
        ..setString('short_src', chunkDisplayName(proto.chunkName))
        ..setString('what', proto.line == 0 ? 'main' : 'Lua')
        ..setString('currentline', line.toDouble())
        ..setString('linedefined', proto.line.toDouble())
        ..setString('lastlinedefined', proto.line.toDouble())
        ..setString('nups', closure.upvalues.length.toDouble())
        ..setString('nparams', proto.numParams.toDouble())
        ..setString('isvararg', proto.isVararg);
    }
    info.setString('namewhat', '');
    return one(info);
  });

  define(lib, 'getlocal', (_) => one(null));
  define(lib, 'getupvalue', (_) => one(null));
  define(lib, 'sethook', (_) => noValues);
  define(lib, 'gethook', (_) => one(null));
  return registry;
}
