import 'dart:convert';
import 'dart:typed_data';

/// Hand-assembled core modules routing calls from linked core modules to the
/// Dart module.
///
/// The Dart module imports the linked modules, so those have to be
/// instantiated first. They call back into Dart through [trampoline] (which
/// jumps through a table slot) and [tableInit] fills the slot once the Dart
/// module exists.
const hostCallExport = 'host_call';

/// `(i32, i32, i32, i32) -> i32`, forwarding to table slot 0.
///
/// Exports `call` and `table`.
Uint8List trampoline() {
  final body = [
    0x00, // no locals
    0x20, 0x00, 0x20, 0x01, 0x20, 0x02, 0x20, 0x03, // local.get 0..3
    0x41, 0x00, // i32.const 0
    0x11, 0x00, 0x00, // call_indirect type 0 table 0
    0x0b,
  ];
  return _module([
    _section(1, [1, 0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 1, 0x7f]),
    _section(3, [1, 0]),
    _section(4, [1, 0x70, 0x00, 1]),
    _section(7, [
      2,
      ..._name('call'), 0x00, 0,
      ..._name('table'), 0x01, 0,
    ]),
    _section(10, [1, body.length, ...body]),
  ]);
}

/// Stores the function imported as `dart.host_call` into slot 0 of the table
/// imported as `trampoline.table`.
Uint8List tableInit() {
  return _module([
    _section(1, [1, 0x60, 4, 0x7f, 0x7f, 0x7f, 0x7f, 1, 0x7f]),
    _section(2, [
      2,
      ..._name('dart'), ..._name(hostCallExport), 0x00, 0,
      ..._name('trampoline'), ..._name('table'), 0x01, 0x70, 0x00, 1,
    ]),
    _section(9, [1, 0x00, 0x41, 0x00, 0x0b, 1, 0]),
  ]);
}

List<int> _name(String name) {
  final bytes = utf8.encode(name);
  return [bytes.length, ...bytes];
}

List<int> _section(int id, List<int> content) {
  assert(content.length < 128);
  return [id, content.length, ...content];
}

Uint8List _module(List<List<int>> sections) {
  return Uint8List.fromList([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, //
    for (final section in sections) ...section,
  ]);
}
