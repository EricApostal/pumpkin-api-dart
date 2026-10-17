// What the Lua layer of an API builder needs from the Lua implementation.
import '../lua/lua.dart';

abstract interface class LuaHost {
  /// Compiles [source]; the result can be passed to [call].
  Object load(String source, String chunkName);

  /// Calls [function]. Tables and functions in the results are kept as
  /// references that can be handed back to the machine as globals.
  List<Object?> call(Object function, List<Object?> args);

  /// The position (`chunk:line: `) of the Lua function at [level] of the
  /// running call stack, or an empty string.
  String where(int level);
}

/// A [LuaHost] over the Dart VM.
final class DartLuaHost implements LuaHost {
  final LuaVm vm;

  DartLuaHost(this.vm);

  @override
  Object load(String source, String chunkName) => vm.load(source, chunkName);

  @override
  List<Object?> call(Object function, List<Object?> args) =>
      vm.call(function, args);

  @override
  String where(int level) => vm.where(level);
}

/// Builds a global that needs a Lua layer.
typedef HostApiBuilder = Object? Function(LuaHost host);
