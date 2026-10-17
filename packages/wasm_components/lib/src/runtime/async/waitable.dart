// ignore: import_internal_library
import 'dart:_wasm';

@pragma('wasm:import', 'component.canon.waitable-set.new')
external WasmI32 _waitableSetNew();
@pragma('wasm:import', 'component.canon.waitable-set.drop')
external WasmVoid _waitableSetDrop(WasmI32 set);
@pragma('wasm:import', 'component.canon.waitable.join')
external WasmVoid _waitableJoin(WasmI32 waitable, WasmI32 set);
@pragma('wasm:import', 'component.canon.subtask.drop')
external WasmVoid _subtaskDrop(WasmI32 subtask);

/// A set of waitables (here: subtasks) that a task waits for.
final class WaitableSet {
  final WasmI32 _nativeId = _waitableSetNew();

  /// The index of the set in the component's handle table.
  int get nativeId => _nativeId.toIntUnsigned();

  /// Adds the waitable with the handle [waitable] to this set, taking it out of
  /// the set it was in.
  void join(int waitable) {
    _waitableJoin(WasmI32.fromInt(waitable), _nativeId);
  }

  /// Drops the set. All waitables must have left it.
  void drop() {
    _waitableSetDrop(_nativeId);
  }
}

/// Releases the handle of a subtask that has returned.
void dropSubtask(int subtask) {
  _subtaskDrop(WasmI32.fromInt(subtask));
}
