// Exports of the embedder functions for text: number formatting and parsing,
// string replacement and regular expressions. The algorithms live in
// `../text/` as pure Dart; this file adapts them to the embedder's string
// representation.
library;

// ignore: import_internal_library
import 'dart:_wasm';

import '../text/double_format.dart';
import '../text/regexp.dart';
import 'string.dart';
import 'string_buffer.dart';
import 'utils.dart';

// -- Conversions ------------------------------------------------------------

String _dartString(WasmExternRef? ref) {
  final string = WasmStringImplementation.fromExtern(ref);
  final codeUnits = List<int>.generate(
    string.length,
    string.codeUnitAtUnchecked,
    growable: false,
  );
  return String.fromCharCodes(codeUnits);
}

WasmStringImplementation _wasmStringOf(String value) {
  final buffer = WasmStringBuffer();
  for (var i = 0; i < value.length; i++) {
    buffer.writeCharCode(value.codeUnitAt(i));
  }
  return buffer.renderToString();
}

WasmExternRef _externString(String value) => _wasmStringOf(value).externalize();

final class _WasmCodeUnits implements CodeUnits {
  final WasmStringImplementation _string;

  _WasmCodeUnits(this._string);

  @override
  int get length => _string.length;

  @override
  int operator [](int index) => _string.codeUnitAtUnchecked(index);
}

// -- Numbers ------------------------------------------------------------------

@pragma('wasm:export')
WasmExternRef f64ToString(WasmF64 value) {
  return _externString(doubleToString(value.toDouble()));
}

@pragma('wasm:export')
WasmExternRef f64ToFixed(WasmF64 value, WasmI32 fractionDigits) {
  return _externString(
    doubleToFixed(value.toDouble(), fractionDigits.toIntSigned()),
  );
}

@pragma('wasm:export')
WasmExternRef f64ToPrecision(WasmF64 value, WasmI32 fractionDigits) {
  return _externString(
    doubleToPrecision(value.toDouble(), fractionDigits.toIntSigned()),
  );
}

@pragma('wasm:export')
WasmExternRef f64ToExponential(WasmF64 value) {
  return _externString(doubleToExponential(value.toDouble()));
}

@pragma('wasm:export')
WasmExternRef f64ToExponentialWithFractionDigits(
  WasmF64 value,
  WasmI32 fractionDigits,
) {
  return _externString(
    doubleToExponential(value.toDouble(), fractionDigits.toIntSigned()),
  );
}

final class _ParsedDouble {
  final double value;

  _ParsedDouble(this.value);
}

double? _parse(WasmExternRef? string) {
  final wasmString = WasmStringImplementation.fromExtern(string);
  final codeUnits = List<int>.generate(
    wasmString.length,
    wasmString.codeUnitAtUnchecked,
    growable: false,
  );
  return parseDouble(codeUnits);
}

@pragma('wasm:export')
WasmExternRef? doubleTryParse(WasmExternRef? string) {
  final value = _parse(string);
  return value == null ? null : _ParsedDouble(value).externalize();
}

@pragma('wasm:export')
WasmF64 tryParseResultGetDouble(WasmExternRef? parseResult) {
  final result = parseResult!.internalize().toObject() as _ParsedDouble;
  return WasmF64.fromDouble(result.value);
}

@pragma('wasm:export')
WasmF64 doubleParseInfallible(WasmExternRef? string) {
  return WasmF64.fromDouble(_parse(string) ?? double.nan);
}

// -- Strings ------------------------------------------------------------------

@pragma('wasm:export')
WasmExternRef? stringReplaceRange(
  WasmExternRef? string,
  WasmI32 start,
  WasmI32 end,
  WasmExternRef? replacement,
) {
  final source = WasmStringImplementation.fromExtern(string);
  final inserted = WasmStringImplementation.fromExtern(replacement);
  final buffer = WasmStringBuffer();
  _write(buffer, source, 0, start.toIntUnsigned());
  buffer.writeString(inserted);
  _write(buffer, source, end.toIntUnsigned(), source.length);
  return buffer.renderToString().externalize();
}

void _write(
  WasmStringBuffer buffer,
  WasmStringImplementation source,
  int start,
  int end,
) {
  for (var i = start; i < end; i++) {
    buffer.writeCharCode(source.codeUnitAtUnchecked(i));
  }
}

@pragma('wasm:export')
WasmExternRef? stringReplaceAllString(
  WasmExternRef? string,
  WasmExternRef? needle,
  WasmExternRef? replacement,
) {
  final source = WasmStringImplementation.fromExtern(string);
  final pattern = WasmStringImplementation.fromExtern(needle);
  final inserted = WasmStringImplementation.fromExtern(replacement);
  final buffer = WasmStringBuffer();

  if (pattern.length == 0) {
    // Like Dart, an empty pattern matches between every code unit.
    buffer.writeString(inserted);
    for (var i = 0; i < source.length; i++) {
      buffer.writeCharCode(source.codeUnitAtUnchecked(i));
      buffer.writeString(inserted);
    }
    return buffer.renderToString().externalize();
  }

  var copied = 0;
  var searchFrom = 0;
  while (true) {
    final index = source.indexOfString(pattern, searchFrom);
    if (index < 0) break;
    _write(buffer, source, copied, index);
    buffer.writeString(inserted);
    copied = index + pattern.length;
    searchFrom = copied;
  }
  _write(buffer, source, copied, source.length);
  return buffer.renderToString().externalize();
}

@pragma('wasm:export')
WasmVoid stringToCodeUnits(
  WasmExternRef? string,
  WasmArray<WasmI16> outArray,
  WasmI32 startIndex,
) {
  final source = WasmStringImplementation.fromExtern(string);
  final offset = startIndex.toIntUnsigned();
  for (var i = 0; i < source.length; i++) {
    outArray.write(offset + i, source.codeUnitAtUnchecked(i));
  }
  return WasmVoid();
}

// -- Regular expressions ------------------------------------------------------

final class _RegExpHandle {
  final CompiledRegExp regExp;

  _RegExpHandle(this.regExp);
}

final class _MatchHandle {
  final _RegExpHandle regExp;
  final WasmStringImplementation input;
  final RegExpMatchData data;

  _MatchHandle(this.regExp, this.input, this.data);
}

@pragma('wasm:export')
WasmExternRef regexpCreateOrFailWithString(
  WasmExternRef? string,
  WasmI32 multiLine,
  WasmI32 caseSensitive,
  WasmI32 unicode,
  WasmI32 dotAll,
) {
  try {
    final compiled = CompiledRegExp(
      _dartString(string),
      multiLine: multiLine.toBool(),
      caseSensitive: caseSensitive.toBool(),
      unicode: unicode.toBool(),
      dotAll: dotAll.toBool(),
    );
    return _RegExpHandle(compiled).externalize();
  } on RegExpSyntaxError catch (e) {
    return _externString(e.message);
  }
}

@pragma('wasm:export')
WasmI32 regexpIsRegexp(WasmExternRef? ref) {
  return WasmI32.fromBool(ref!.internalize().toObject() is _RegExpHandle);
}

@pragma('wasm:export')
WasmExternRef regexpEscape(WasmExternRef? string) {
  return _externString(CompiledRegExp.escape(_dartString(string)));
}

_MatchHandle? _search(
  WasmExternRef? regexp,
  WasmExternRef? string,
  int start,
  bool asPrefix,
) {
  final handle = regexp!.internalize().toObject() as _RegExpHandle;
  final input = WasmStringImplementation.fromExtern(string);
  final data = handle.regExp.match(_WasmCodeUnits(input), start, asPrefix);
  return data == null ? null : _MatchHandle(handle, input, data);
}

@pragma('wasm:export')
WasmExternRef? regexpMatch(
  WasmExternRef? regexp,
  WasmExternRef? string,
  WasmI32 start,
  WasmI32 asPrefix,
) {
  final match = _search(
    regexp,
    string,
    start.toIntUnsigned(),
    asPrefix.toBool(),
  );
  return match?.externalize();
}

_MatchHandle _matchOf(WasmExternRef? ref) =>
    ref!.internalize().toObject() as _MatchHandle;

@pragma('wasm:export')
WasmI32 regexpMatchGetStart(WasmExternRef? match) =>
    WasmI32.fromInt(_matchOf(match).data.start);

@pragma('wasm:export')
WasmI32 regexpMatchGetEnd(WasmExternRef? match) =>
    WasmI32.fromInt(_matchOf(match).data.end);

@pragma('wasm:export')
WasmI32 regexpMatchGetGroupCount(WasmExternRef? match) =>
    WasmI32.fromInt(_matchOf(match).data.groupCount);

WasmExternRef? _group(_MatchHandle match, int index) {
  final start = match.data.starts[index];
  final end = match.data.ends[index];
  if (start < 0 || end < 0) return null;
  return match.input
      .substring(WasmI32.fromInt(start), WasmI32.fromInt(end))
      .externalize();
}

@pragma('wasm:export')
WasmExternRef? regexpMatchGetGroup(WasmExternRef? match, WasmI32 index) =>
    _group(_matchOf(match), index.toIntUnsigned());

@pragma('wasm:export')
WasmI32 regexpMatchGetNamedGroups(WasmExternRef? match) => WasmI32.fromInt(
  _matchOf(match).regExp.regExp.groupNames.length,
);

@pragma('wasm:export')
WasmExternRef regexpMatchGetGroupName(WasmExternRef? match, WasmI32 index) =>
    _externString(
      _matchOf(match).regExp.regExp.groupNames[index.toIntUnsigned()],
    );

@pragma('wasm:export')
WasmExternRef? regexpMatchGetGroupByName(
  WasmExternRef? match,
  WasmI32 nameIndex,
) {
  final handle = _matchOf(match);
  final groupIndex =
      handle.regExp.regExp.groupNameIndices[nameIndex.toIntUnsigned()];
  return _group(handle, groupIndex);
}

@pragma('wasm:export')
WasmExternRef? stringReplaceAllRegExp(
  WasmExternRef? string,
  WasmExternRef? needle,
  WasmExternRef? replacement,
) {
  final handle = needle!.internalize().toObject() as _RegExpHandle;
  final source = WasmStringImplementation.fromExtern(string);
  final inserted = WasmStringImplementation.fromExtern(replacement);
  final input = _WasmCodeUnits(source);
  final buffer = WasmStringBuffer();

  var copied = 0;
  var position = 0;
  while (position <= source.length) {
    final data = handle.regExp.match(input, position, false);
    if (data == null) break;
    _write(buffer, source, copied, data.start);
    buffer.writeString(inserted);
    copied = data.end;
    if (data.end == data.start) {
      // Zero-width match: step over one character, keeping surrogate pairs of
      // unicode patterns together.
      var next = data.end + 1;
      if (handle.regExp.unicode &&
          data.end + 1 < source.length &&
          _isHigh(source.codeUnitAtUnchecked(data.end)) &&
          _isLow(source.codeUnitAtUnchecked(data.end + 1))) {
        next++;
      }
      position = next;
    } else {
      position = data.end;
    }
  }
  _write(buffer, source, copied, source.length);
  return buffer.renderToString().externalize();
}

bool _isHigh(int c) => c >= 0xd800 && c <= 0xdbff;
bool _isLow(int c) => c >= 0xdc00 && c <= 0xdfff;

// -- Time zones ---------------------------------------------------------------

// Plugins run in UTC: WASI has no time zone database.

@pragma('wasm:export')
WasmExternRef timeZoneNameForClampedSeconds(WasmI64 secondsSinceEpoch) =>
    _externString('UTC');

@pragma('wasm:export')
WasmI32 timeZoneOffsetInSecondsForClampedSeconds(WasmI64 secondsSinceEpoch) =>
    const WasmI32(0);

// -- Environment --------------------------------------------------------------

@pragma('wasm:export')
WasmExternRef? baseUri() => null;

@pragma('wasm:export')
WasmI32 isWindows() => const WasmI32(0);

@pragma('wasm:export')
WasmVoid inspect(WasmAnyRef? object) => WasmVoid();

@pragma('wasm:export')
WasmI32 timelineStreamEnabled() => const WasmI32(0);

@pragma('wasm:export')
WasmI32 reportTaskEvent(
  WasmI32 taskId,
  WasmI32 flowId,
  WasmI32 type,
  WasmExternRef? name,
  WasmExternRef? argumentsAsJson,
) => const WasmI32(0);

// -- Weak references, expandos and finalizers ---------------------------------

// There is no garbage collector hook in a Wasm component, so these keep strong
// references: weak references never clear, expandos never drop entries and
// finalizers never run. They behave correctly, they just never free memory.

final class _StrongReference {
  final WasmAnyRef value;

  _StrongReference(this.value);
}

@pragma('wasm:export')
WasmExternRef weakRefCreate(WasmAnyRef originalValue) =>
    _StrongReference(originalValue).externalize();

@pragma('wasm:export')
WasmAnyRef? weakRefGet(WasmExternRef? weakReference) =>
    (weakReference!.internalize().toObject() as _StrongReference).value;

final class _ExpandoEntry {
  final Object target;
  WasmAnyRef? value;

  _ExpandoEntry(this.target, this.value);
}

final class _ExpandoStorage {
  final Map<int, List<_ExpandoEntry>> entries = {};
}

@pragma('wasm:export')
WasmExternRef expandoCreate() => _ExpandoStorage().externalize();

_ExpandoEntry? _findExpandoEntry(
  _ExpandoStorage storage,
  Object target,
  int hash,
) {
  final bucket = storage.entries[hash];
  if (bucket == null) return null;
  for (final entry in bucket) {
    if (identical(entry.target, target)) return entry;
  }
  return null;
}

@pragma('wasm:export')
WasmAnyRef? expandoGet(
  WasmExternRef? expando,
  WasmAnyRef target,
  WasmI64 targetIdentityHashCode,
) {
  final storage = expando!.internalize().toObject() as _ExpandoStorage;
  return _findExpandoEntry(
    storage,
    target.toObject(),
    targetIdentityHashCode.toInt(),
  )?.value;
}

@pragma('wasm:export')
WasmVoid expandoSet(
  WasmExternRef? expando,
  WasmAnyRef target,
  WasmI64 targetIdentityHashCode,
  WasmAnyRef? value,
) {
  final storage = expando!.internalize().toObject() as _ExpandoStorage;
  final hash = targetIdentityHashCode.toInt();
  final object = target.toObject();
  final existing = _findExpandoEntry(storage, object, hash);
  if (existing != null) {
    existing.value = value;
  } else if (value != null) {
    (storage.entries[hash] ??= []).add(_ExpandoEntry(object, value));
  }
  return WasmVoid();
}

@pragma('wasm:export')
WasmExternRef finalizerCreate(
  WasmFunction<WasmVoid Function(WasmAnyRef, WasmAnyRef?)> callback,
  WasmAnyRef firstParameter,
) => _StrongReference(firstParameter).externalize();

@pragma('wasm:export')
WasmVoid finalizerAttach(
  WasmExternRef? finalizer,
  WasmAnyRef object,
  WasmAnyRef? token,
  WasmAnyRef? detachToken,
) => WasmVoid();

@pragma('wasm:export')
WasmVoid finalizerDetach(WasmExternRef? finalizer, WasmAnyRef detachToken) =>
    WasmVoid();
