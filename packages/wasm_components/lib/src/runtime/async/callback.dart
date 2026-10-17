// ignore: import_internal_library
import 'dart:_wasm';

import 'task.dart';

/// The callback of every async-lifted export. The host calls it, with the
/// event that woke the task, whenever a task that returned `wait` has something
/// to continue with.
@pragma('wasm:export')
WasmI32 callback(WasmI32 eventCode, WasmI32 p1, WasmI32 p2) {
  return resumeAsyncTask(eventCode, p1, p2);
}
