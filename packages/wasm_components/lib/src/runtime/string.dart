// ignore: import_internal_library
import 'dart:_wasm';

import 'package:meta/meta.dart';

import '../embedder/libc.dart';
import '../embedder/string.dart';

/// A string stored in linear memory.
final class AllocatedString {
  final WasmI32 ptr;
  final WasmI32 packedLength;

  AllocatedString(this.ptr, this.packedLength);

  void free() {
    dartFree(ptr, (2 * packedLength.toIntSigned()).toWasmI32(), _alignment);
  }

  static AllocatedString allocateUtf16(String dartString) {
    final length = dartString.length;
    final ptr = mallocAligned(_alignment, (2 * length).toWasmI32());
    final dartPtr = ptr.toIntSigned();
    final packedLength = length.toWasmI32();

    for (var i = 0; i < length; i++) {
      memory.storeInt16(
        dartPtr + 2 * i,
        WasmI32.int16FromInt(dartString.codeUnitAt(i)),
        align: 1,
      );
    }

    return AllocatedString(ptr, packedLength);
  }

  /// Reads a UTF-16 string the host lowered into linear memory at [ptr] with
  /// [length] code units, releasing the buffer afterwards (per the canonical
  /// ABI the host allocated it through our `realloc`, so we own it).
  static String read(WasmI32 ptr, WasmI32 length) {
    final dartLength = length.toIntUnsigned();
    final dartPtr = ptr.toIntUnsigned();
    final codeUnits = List<int>.filled(dartLength, 0);

    for (var i = 0; i < dartLength; i++) {
      codeUnits[i] = memory.loadInt16(dartPtr + 2 * i, align: 1).toIntUnsigned();
    }

    AllocatedString(ptr, length).free();
    return String.fromCharCodes(codeUnits);
  }

  @internal
  WasmStringImplementation readRaw() {
    final length = packedLength.toIntUnsigned();
    final array = WasmArray<WasmI16>(length);
    final dartPtr = ptr.toIntUnsigned();

    for (var i = 0; i < length; i++) {
      array.write(
        i,
        memory.loadInt16(dartPtr + 2 * i, align: 1).toIntUnsigned(),
      );
    }

    return Utf16String.unsafeWrap(array);
  }

  static const _alignment = WasmI32(2);
}

/// A `char` value in the WebAssembly component model.
extension type const CharCode(int value) implements int {}
