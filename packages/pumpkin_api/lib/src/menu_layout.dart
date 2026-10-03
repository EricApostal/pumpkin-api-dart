/// Binding-free layout maths for chest menus. Everything here works on plain
/// slot numbers, so it can be unit-tested on the Dart VM.
///
/// A chest menu is a grid of 9 columns and 1 to 6 rows. Slot `n` sits at row
/// `n ~/ 9` and column `n % 9`, both counted from 0 at the top left.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Number of columns of every chest menu.
const int menuColumns = 9;

/// Smallest and largest number of rows of a chest menu.
const int minMenuRows = 1, maxMenuRows = 6;

/// Helpers to turn grid positions into slot numbers and back.
abstract final class MenuLayout {
  /// The slot at [row] and [column] (both from 0).
  ///
  /// ```dart
  /// MenuLayout.slot(1, 4); // 13
  /// ```
  static int slot(int row, int column) {
    if (column < 0 || column >= menuColumns) {
      throw RangeError.range(column, 0, menuColumns - 1, 'column');
    }
    if (row < 0) throw RangeError.value(row, 'row');
    return row * menuColumns + column;
  }

  /// The row of [slot].
  static int rowOf(int slot) => slot ~/ menuColumns;

  /// The column of [slot].
  static int columnOf(int slot) => slot % menuColumns;

  /// Total number of slots of a menu with [rows] rows.
  static int size(int rows) => rows * menuColumns;

  /// All slots of [row].
  static List<int> rowSlots(int row) =>
      [for (var c = 0; c < menuColumns; c++) row * menuColumns + c];

  /// All slots of [column] in a menu with [rows] rows.
  static List<int> columnSlots(int column, int rows) =>
      [for (var r = 0; r < rows; r++) r * menuColumns + column];

  /// The slots on the outer edge of a menu with [rows] rows, in ascending
  /// order. With one or two rows that is every slot.
  static List<int> borderSlots(int rows) => [
    for (var s = 0; s < size(rows); s++)
      if (isBorder(s, rows)) s,
  ];

  /// Whether [slot] is on the outer edge of a menu with [rows] rows.
  static bool isBorder(int slot, int rows) {
    final r = rowOf(slot), c = columnOf(slot);
    return r == 0 || r == rows - 1 || c == 0 || c == menuColumns - 1;
  }

  /// The slots inside the border, in reading order.
  static List<int> innerSlots(int rows) => [
    for (var s = 0; s < size(rows); s++)
      if (!isBorder(s, rows)) s,
  ];

  /// Every slot of a menu with [rows] rows.
  static List<int> allSlots(int rows) => [for (var s = 0; s < size(rows); s++) s];
}

/// How a paged menu spreads its entries over pages.
///
/// The bottom row is reserved for the previous/next buttons, the other rows
/// hold entries. [contentSlots] are the slots entries are put in.
final class PageLayout {
  /// Number of rows of the whole menu (2 to 6).
  final int rows;

  /// Slots that hold entries, in reading order.
  final List<int> contentSlots;

  /// Slot of the "previous page" button.
  final int previousSlot;

  /// Slot of the "next page" button.
  final int nextSlot;

  /// Slot where the page indicator goes.
  final int indicatorSlot;

  PageLayout._(this.rows, this.contentSlots, this.previousSlot, this.nextSlot, this.indicatorSlot);

  /// A layout for a menu with [rows] rows (at least 2).
  factory PageLayout(int rows) {
    if (rows < 2 || rows > maxMenuRows) {
      throw RangeError.range(rows, 2, maxMenuRows, 'rows');
    }
    final bottom = (rows - 1) * menuColumns;
    return PageLayout._(
      rows,
      [for (var s = 0; s < bottom; s++) s],
      bottom + 3,
      bottom + 5,
      bottom + 4,
    );
  }

  /// Entries per page.
  int get pageSize => contentSlots.length;

  /// Number of pages needed for [total] entries; at least 1.
  int pageCount(int total) => total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  /// The index range `[start, end)` of the entries on [page] out of [total].
  (int, int) range(int page, int total) {
    final start = (page * pageSize).clamp(0, total);
    final end = (start + pageSize).clamp(0, total);
    return (start, end);
  }

  /// Clamps [page] to a valid page for [total] entries.
  int clampPage(int page, int total) => page.clamp(0, pageCount(total) - 1);
}

/// Encoders for the binary values `ItemStack.setComponent` expects: the
/// network (protocol) encoding of an item data component. Binding-free so it
/// can be tested on the VM.
abstract final class ComponentBytes {
  /// A protocol VarInt: 7 bits per byte, low bits first. Negative numbers
  /// take five bytes (32-bit two's complement).
  static List<int> varInt(int value) {
    var v = value & 0xffffffff;
    final out = <int>[];
    while (true) {
      if (v & ~0x7f == 0) {
        out.add(v);
        return out;
      }
      out.add((v & 0x7f) | 0x80);
      v >>>= 7;
    }
  }

  /// A protocol string: VarInt byte length, then UTF-8.
  static List<int> string(String value) {
    final bytes = _utf8(value);
    return [...varInt(bytes.length), ...bytes];
  }

  /// A big-endian IEEE 754 single.
  static List<int> float32(double value) {
    final data = ByteData(4)..setFloat32(0, value, Endian.big);
    return data.buffer.asUint8List().toList();
  }

  /// A big-endian 32-bit integer.
  static List<int> int32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    return data.buffer.asUint8List().toList();
  }

  /// The `custom-model-data` component with one float entry [value].
  static List<int> customModelData(num value) => [
    ...varInt(1), ...float32(value.toDouble()), // floats
    ...varInt(0), // flags
    ...varInt(0), // strings
    ...varInt(0), // colors
  ];

  static List<int> _utf8(String s) => utf8.encode(s);
}
