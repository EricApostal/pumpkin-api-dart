// Installs the standard libraries CraftOS expects into a VM.
import 'value.dart';
import 'vm.dart';
import 'stdlib/base_lib.dart';
import 'stdlib/bit32_lib.dart';
import 'stdlib/coroutine_lib.dart';
import 'stdlib/debug_lib.dart';
import 'stdlib/math_lib.dart';
import 'stdlib/string_lib.dart';
import 'stdlib/table_lib.dart';
import 'stdlib/utf8_lib.dart';

export 'stdlib/args.dart' show Args, define, one;

/// Adds the base functions, `string`, `table`, `math`, `coroutine`, `bit32`,
/// `utf8` and `debug` to the VM's globals. `os`, `io` and the rest of
/// CraftOS are provided by the machine and the ROM.
void installStandardLibrary(LuaVm vm) {
  installBase(vm);
  installString(vm);
  installTable(vm);
  installMath(vm);
  installCoroutine(vm);
  installBit32(vm);
  installUtf8(vm);
  final registry = installDebug(vm);

  // `package.loaded` of CraftOS programs is seeded from `registry._LOADED`.
  final loaded = LuaTable();
  for (final name in const [
    'string',
    'table',
    'math',
    'coroutine',
    'bit32',
    'utf8',
    'debug',
  ]) {
    loaded.setString(name, vm.globals.getString(name));
  }
  registry.setString('_LOADED', loaded);
}
