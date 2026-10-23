// ignore_for_file: import_internal_library
//
// The plugin entry point: links the Jolt core module and runs the Sable server
// half, which is the whole plugin.
//
// The module never calls back into Dart, but the component linker always
// instantiates the table-init module, which imports `dart.host_call`, so this
// program must export it (`/tmp/joltspike/ADR.md` §1, `transform.dart:245-254`).
import 'dart:_wasm';

import 'package:pumpkin_api/pumpkin_api.dart' show runPlugin;
import 'package:sable/sable_plugin.dart' show SablePlugin;

/// The trampoline the core module's `host.call` import is routed to.
@pragma('wasm:export', 'host_call')
WasmI32 hostCall(WasmI32 id, WasmI32 a, WasmI32 b, WasmI32 c) => WasmI32.fromInt(0);

void main() => runPlugin(SablePlugin());