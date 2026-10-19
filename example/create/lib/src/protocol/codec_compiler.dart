// The codec compiler (pure): turns the manifest's payload descriptors
// (`NetPayload` / `NetType`) into readers and writers over `PacketReader` /
// `PacketWriter` (FriendlyByteBuf compatible). Nothing here is payload specific
// except two documented exceptions (`_gates`, the `SignalBoundary` hook).
//
// Value mapping (what a decoded field is, and what `encode` accepts):
//
//   varint, varlong, int, long, short, byte  int (signed)
//   bool                                     bool
//   float, double                            double (a float is rounded to 32 bits)
//   string                                   String (UTF-8, `maxLength` enforced)
//   resourceLocation                         String `namespace:path` (validated on read)
//   uuid                                     String, canonical lower-case 8-4-4-4-12
//   blockPos, vec3i                          (int x, int y, int z) record
//   vec3                                     (double, double, double) record
//   direction                                int, the 3D data value (0 down, 1 up, 2 north, 3 south, 4 west, 5 east)
//   enumeration                              int ordinal (the manifest does not list the constants;
//                                            handlers must range-check ordinals against their Java enum)
//   blockState                               int, id in the block state registry
//   itemStack / itemStackOptional            ItemStackData (empty only for the optional kind)
//   fluidStack / fluidStackOptional          FluidStackData
//   nbtCompound                              NbtValue (kind compound)
//   nbtTag                                   NbtValue (non-null; `ByteBufCodecs.TAG` rejects TAG_End).
//                                            When the manifest names a compound-only codec in `className`
//                                            (`legacyNbtWithRegistries`, `codec-as-nbt`) a compound is required.
//   component                                NbtValue (a text component is an NBT tag on the wire);
//                                            `encode` also accepts a plain String
//   bytes                                    Uint8List
//   list                                     List<Object?>
//   map                                      Map<Object?, Object?> in wire order. Keys of kind custom/list are
//                                            Map/List instances (identity equality): iterate `entries`
//   optional                                 the element value, or null
//   either                                   EitherValue
//   custom                                   Map<String, Object?> by field name
//   dispatch                                 PayloadVariant(variantName, value)
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../core/byte_buf.dart';
import '../core/nbt.dart';
import '../manifest/network.g.dart';
import '../manifest/types_network.dart';
import 'item_stack.dart';
import 'wire_values.dart';

/// The enclosing struct while a field is read or written (siblings decoded so far).
typedef WireScope = Map<String, Object?>;

/// Reads and writes one wire type.
abstract class WireCodec {
  const WireCodec();

  /// A lower bound of the bytes one value takes (0 when it can be empty); used to
  /// reject absurd list counts before allocating.
  int get minSize;

  Object? read(PacketReader r, WireScope scope);

  void write(PacketWriter w, Object? value, WireScope scope);
}

final class _Fn extends WireCodec {
  @override
  final int minSize;
  final Object? Function(PacketReader r, WireScope scope) _read;
  final void Function(PacketWriter w, Object? v, WireScope scope) _write;

  const _Fn(this.minSize, this._read, this._write);

  @override
  Object? read(PacketReader r, WireScope scope) => _read(r, scope);

  @override
  void write(PacketWriter w, Object? value, WireScope scope) => _write(w, value, scope);
}

/// Thrown by the compiler when a descriptor cannot be compiled.
final class SchemaException implements Exception {
  final String message;

  const SchemaException(this.message);

  @override
  String toString() => 'SchemaException: $message';
}

// ---------------------------------------------------------------- value coercion

PacketException _typeError(String expected, Object? v) =>
    PacketException('expected $expected but got ${v == null ? 'null' : v.runtimeType}');

int _int(Object? v) => v is int ? v : throw _typeError('int', v);
bool _bool(Object? v) => v is bool ? v : throw _typeError('bool', v);
double _double(Object? v) => v is num ? v.toDouble() : throw _typeError('double', v);
String _string(Object? v) => v is String ? v : throw _typeError('String', v);

(int, int, int) _ints3(Object? v) {
  if (v is (int, int, int)) return v;
  if (v is List && v.length == 3 && v.every((e) => e is int)) return (v[0] as int, v[1] as int, v[2] as int);
  throw _typeError('(int, int, int)', v);
}

(double, double, double) _doubles3(Object? v) {
  if (v is (double, double, double)) return v;
  if (v is (num, num, num)) return (v.$1.toDouble(), v.$2.toDouble(), v.$3.toDouble());
  if (v is List && v.length == 3 && v.every((e) => e is num)) {
    return ((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble());
  }
  throw _typeError('(double, double, double)', v);
}

final RegExp _idPattern = RegExp(r'^(?:[a-z0-9_.-]+:)?[a-z0-9_./-]+$');

String _checkId(String s) {
  if (!_idPattern.hasMatch(s)) throw PacketException('Invalid resource location `$s`');
  return s;
}

/// The default bound of lists/maps/byte arrays that do not declare one.
const int defaultCollectionLimit = 1 << 20;

/// Class names the manifest gives to `nbtTag` fields whose Java codec is compound-only:
/// `CreateStreamCodecs.ofLegacyNbtWithRegistries` and the `codec-as-nbt` mounted storage
/// codecs both go through `FriendlyByteBuf.readNbt()` / `writeNbt(CompoundTag)`.
const Set<String> _compoundOnlyTags = {'legacyNbtWithRegistries', 'codec-as-nbt'};

// ---------------------------------------------------------------- compiler

/// Special cases that the manifest describes in prose: fields from a given field on
/// are absent when a flag field is true.
const Map<String, ({String flag, String from})> _gates = {
  // TrackGraphSyncPacket: nothing follows `fullWipe` when the packet deletes the graph.
  'create:sync_rail_graph': (flag: 'packetDeletesGraph', from: 'dimensionPalette'),
};

/// Compiles [type] into a codec. [path] names the field in error messages.
WireCodec compileType(NetType type, [String path = '']) {
  switch (type.kind) {
    case NetKind.varint:
    case NetKind.blockState:
      return _Fn(1, (r, _) => r.readVarInt(), (w, v, _) => w.writeVarInt(_int(v)));
    case NetKind.varlong:
      return _Fn(1, (r, _) => r.readVarLong(), (w, v, _) => w.writeVarLong(_int(v)));
    case NetKind.int:
      return _Fn(4, (r, _) => r.readInt(), (w, v, _) => w.writeInt(_int(v)));
    case NetKind.long:
      return _Fn(8, (r, _) => r.readLong(), (w, v, _) => w.writeLong(_int(v)));
    case NetKind.short:
      return _Fn(2, (r, _) => r.readShort(), (w, v, _) => w.writeShort(_int(v)));
    case NetKind.byte:
      return _Fn(1, (r, _) => r.readByte(), (w, v, _) => w.writeByte(_int(v)));
    case NetKind.bool:
      return _Fn(1, (r, _) => r.readBool(), (w, v, _) => w.writeBool(_bool(v)));
    case NetKind.float:
      return _Fn(4, (r, _) => r.readFloat(), (w, v, _) => w.writeFloat(_double(v)));
    case NetKind.double:
      return _Fn(8, (r, _) => r.readDouble(), (w, v, _) => w.writeDouble(_double(v)));
    case NetKind.string:
      final max = type.maxLength ?? defaultMaxStringLength;
      return _Fn(1, (r, _) => r.readString(maxLength: max), (w, v, _) => w.writeString(_string(v), maxLength: max));
    case NetKind.resourceLocation:
      return _Fn(
        1,
        (r, _) => _checkId(r.readString()),
        (w, v, _) => w.writeString(_checkId(_string(v))),
      );
    case NetKind.blockPos:
      return _Fn(8, (r, _) => r.readBlockPos(), (w, v, _) => w.writeBlockPos(_ints3(v)));
    case NetKind.uuid:
      return _Fn(16, (r, _) => r.readUuid(), (w, v, _) => w.writeUuid(_string(v)));
    case NetKind.itemStack:
      return _Fn(
        1,
        (r, _) => ItemStackData.read(r, allowEmpty: false),
        (w, v, _) => _stack(v).write(w, allowEmpty: false),
      );
    case NetKind.itemStackOptional:
      return _Fn(1, (r, _) => ItemStackData.read(r), (w, v, _) => _stack(v).write(w));
    case NetKind.fluidStack:
      return _Fn(
        1,
        (r, _) => FluidStackData.read(r, allowEmpty: false),
        (w, v, _) => _fluid(v).write(w, allowEmpty: false),
      );
    case NetKind.fluidStackOptional:
      return _Fn(1, (r, _) => FluidStackData.read(r), (w, v, _) => _fluid(v).write(w));
    case NetKind.nbtCompound:
      return _Fn(
        1,
        (r, _) {
          final tag = r.readNbt();
          if (tag == null || tag.kind != NbtKind.compound) throw const PacketException('expected a compound tag');
          return tag;
        },
        (w, v, _) {
          if (v == null) {
            w.writeNbt(NbtValue.emptyCompound());
          } else if (v is NbtValue && v.kind == NbtKind.compound) {
            w.writeNbt(v);
          } else {
            throw _typeError('NbtValue compound', v);
          }
        },
      );
    case NetKind.nbtTag:
      // ByteBufCodecs.TAG rejects TAG_End in both directions. The manifest also uses this kind
      // for compound-only codecs, named in `className` (`ofLegacyNbtWithRegistries` and the
      // `codec-as-nbt` mounted storage codecs both call FriendlyByteBuf.readNbt()).
      final compoundOnly = _compoundOnlyTags.contains(type.className);
      return _Fn(
        1,
        (r, _) {
          final tag = r.readNbt();
          if (tag == null) throw const PacketException('expected a tag but got TAG_End');
          if (compoundOnly && tag.kind != NbtKind.compound) throw const PacketException('expected a compound tag');
          return tag;
        },
        (w, v, _) {
          if (v is! NbtValue) throw _typeError('NbtValue', v);
          if (compoundOnly && v.kind != NbtKind.compound) throw const PacketException('expected a compound tag');
          w.writeNbt(v);
        },
      );
    case NetKind.component:
      return _Fn(
        1,
        (r, _) => r.readNbt() ?? (throw const PacketException('empty text component')),
        (w, v, _) => switch (v) {
          final String s => w.writeNbt(NbtValue.string(s)),
          final NbtValue n => w.writeNbt(n),
          _ => throw _typeError('NbtValue or String', v),
        },
      );
    case NetKind.bytes:
      final max = type.maxLength;
      return _Fn(
        1,
        (r, _) => r.readByteArray(maxLength: max),
        (w, v, _) => v is List<int> ? w.writeByteArray(v, maxLength: max) : throw _typeError('Uint8List', v),
      );
    case NetKind.list:
      return _compileList(type, path);
    case NetKind.map:
      return _compileMap(type, path);
    case NetKind.optional:
      final element = compileType(_need(type.element, 'optional element', path), '$path?');
      return _Fn(
        1,
        (r, scope) => r.readBool() ? element.read(r, scope) : null,
        (w, v, scope) {
          if (v == null) {
            w.writeBool(false);
          } else {
            w.writeBool(true);
            element.write(w, v, scope);
          }
        },
      );
    case NetKind.either:
      final left = compileType(_need(type.key, 'either left', path), '$path<');
      final right = compileType(_need(type.value, 'either right', path), '$path>');
      return _Fn(
        1,
        (r, scope) => r.readBool() ? EitherValue.left(left.read(r, scope)) : EitherValue.right(right.read(r, scope)),
        (w, v, scope) {
          if (v is! EitherValue) throw _typeError('EitherValue', v);
          w.writeBool(v.isLeft);
          (v.isLeft ? left : right).write(w, v.value, scope);
        },
      );
    case NetKind.enumeration:
      return _Fn(1, (r, _) {
        final o = r.readVarInt();
        if (o < 0) throw PacketException('negative enum ordinal $o');
        return o;
      }, (w, v, _) {
        final o = _int(v);
        if (o < 0) throw PacketException('negative enum ordinal $o');
        w.writeVarInt(o);
      });
    case NetKind.vec3:
      return _Fn(24, (r, _) => r.readVec3(), (w, v, _) => w.writeVec3(_doubles3(v)));
    case NetKind.vec3i:
      return _Fn(12, (r, _) => (r.readInt(), r.readInt(), r.readInt()), (w, v, _) {
        final (x, y, z) = _ints3(v);
        w
          ..writeInt(x)
          ..writeInt(y)
          ..writeInt(z);
      });
    case NetKind.direction:
      return _Fn(1, (r, _) {
        final d = r.readVarInt();
        if (d < 0 || d > 5) throw PacketException('invalid direction $d');
        return d;
      }, (w, v, _) {
        final d = _int(v);
        if (d < 0 || d > 5) throw PacketException('invalid direction $d');
        w.writeVarInt(d);
      });
    case NetKind.custom:
      return _compileCustom(type, path);
    case NetKind.dispatch:
      return _compileDispatch(type, path);
  }
}

ItemStackData _stack(Object? v) => v is ItemStackData ? v : throw _typeError('ItemStackData', v);
FluidStackData _fluid(Object? v) => v is FluidStackData ? v : throw _typeError('FluidStackData', v);

T _need<T>(T? v, String what, String path) => v ?? (throw SchemaException('$path: missing $what'));

WireCodec _compileList(NetType type, String path) {
  final element = compileType(_need(type.element, 'list element', path), '$path[]');
  final max = type.maxLength ?? defaultCollectionLimit;
  final intPrefix = (type.className ?? '').contains('int count prefix');
  return _Fn(
    intPrefix ? 4 : 1,
    (r, scope) {
      final n = intPrefix ? r.readInt() : r.readVarInt();
      _checkCount(n, max, element.minSize, r);
      return <Object?>[for (var i = 0; i < n; i++) element.read(r, scope)];
    },
    (w, v, scope) {
      if (v is! Iterable) throw _typeError('List', v);
      final list = v is List ? v : v.toList();
      if (list.length > max) throw PacketException('list of ${list.length} is longer than $max');
      intPrefix ? w.writeInt(list.length) : w.writeVarInt(list.length);
      for (final e in list) {
        element.write(w, e, scope);
      }
    },
  );
}

void _checkCount(int n, int max, int elementMinSize, PacketReader r) {
  if (n < 0) throw PacketException('negative count $n');
  if (n > max) throw PacketException('count $n is larger than the maximum $max');
  if (elementMinSize > 0 && n * elementMinSize > r.remaining) {
    throw PacketException('count $n does not fit the ${r.remaining} remaining byte(s)');
  }
}

WireCodec _compileMap(NetType type, String path) {
  final key = compileType(_need(type.key, 'map key', path), '$path{k}');
  final value = compileType(_need(type.value, 'map value', path), '$path{v}');
  final max = type.maxLength ?? defaultCollectionLimit;
  return _Fn(
    1,
    (r, scope) {
      final n = r.readVarInt();
      _checkCount(n, max, key.minSize + value.minSize, r);
      final map = <Object?, Object?>{};
      for (var i = 0; i < n; i++) {
        final k = key.read(r, scope);
        map[k] = value.read(r, scope);
      }
      return map;
    },
    (w, v, scope) {
      final Iterable<MapEntry<Object?, Object?>> entries = switch (v) {
        final Map<Object?, Object?> m => m.entries,
        final Iterable<MapEntry<Object?, Object?>> it => it,
        _ => throw _typeError('Map', v),
      };
      final list = entries.toList();
      if (list.length > max) throw PacketException('map of ${list.length} is larger than $max');
      w.writeVarInt(list.length);
      for (final e in list) {
        key.write(w, e.key, scope);
        value.write(w, e.value, scope);
      }
    },
  );
}

WireCodec _compileCustom(NetType type, String path) {
  final name = type.className ?? '';
  if (name.startsWith('SignalBoundary only')) return _signalGroups;
  final fields = type.fields ?? (throw SchemaException('$path: custom type `$name` has no expansion'));
  return _Struct(fields, path);
}

/// `TrackEdgePoint` subclass data: only `create:signal` points append two optional group ids.
const WireCodec _signalGroups = _Fn(
  0,
  _readSignalGroups,
  _writeSignalGroups,
);

Object? _readSignalGroups(PacketReader r, WireScope scope) {
  if (scope['type'] != 'create:signal') return null;
  return <String?>[for (var i = 0; i < 2; i++) r.readBool() ? r.readUuid() : null];
}

void _writeSignalGroups(PacketWriter w, Object? v, WireScope scope) {
  if (scope['type'] != 'create:signal') return;
  if (v is! List || v.length != 2) throw _typeError('List of 2 uuid strings', v);
  for (final g in v) {
    if (g == null) {
      w.writeBool(false);
    } else {
      w.writeBool(true);
      w.writeUuid(_string(g));
    }
  }
}

WireCodec _compileDispatch(NetType type, String path) {
  final variants = type.fields ?? (throw SchemaException('$path: dispatch without variants'));
  final codecs = [for (final v in variants) compileType(v.type, '$path/${v.name}')];
  return _Fn(
    1,
    (r, scope) {
      final i = r.readVarInt();
      if (i < 0 || i >= variants.length) throw PacketException('unknown variant $i (of ${variants.length})');
      return PayloadVariant(variants[i].name, codecs[i].read(r, scope));
    },
    (w, v, scope) {
      if (v is! PayloadVariant) throw _typeError('PayloadVariant', v);
      final i = variants.indexWhere((f) => f.name == v.variant);
      if (i < 0) throw PacketException('unknown variant `${v.variant}`');
      w.writeVarInt(i);
      codecs[i].write(w, v.value, scope);
    },
  );
}

/// An ordered struct of named fields; the value is a `Map<String, Object?>`.
final class _Struct extends WireCodec {
  final List<NetField> fields;
  final List<WireCodec> codecs;
  final List<bool> optional;
  final ({String flag, String from})? gate;
  late final int _gateIndex;
  @override
  late final int minSize;

  _Struct(this.fields, String path, {this.gate})
    : codecs = [for (final f in fields) compileType(f.type, '$path.${f.name}')],
      optional = [for (final f in fields) f.type.kind == NetKind.optional] {
    final g = gate;
    _gateIndex = g == null ? fields.length : fields.indexWhere((f) => f.name == g.from);
    if (_gateIndex < 0) throw SchemaException('$path: gate field `${g!.from}` not found');
    minSize = [for (var i = 0; i < _gateIndex; i++) codecs[i].minSize].fold(0, (a, b) => a + b);
  }

  bool _gated(WireScope scope) => gate != null && scope[gate!.flag] == true;

  @override
  Object? read(PacketReader r, WireScope parent) {
    final map = <String, Object?>{};
    for (var i = 0; i < fields.length; i++) {
      if (i >= _gateIndex && _gated(map)) break;
      try {
        map[fields[i].name] = codecs[i].read(r, map);
      } on PacketException catch (e) {
        throw PacketException('`${fields[i].name}`: ${e.message}');
      }
    }
    return map;
  }

  @override
  void write(PacketWriter w, Object? value, WireScope parent) {
    final map = switch (value) {
      final Map<String, Object?> m => m,
      null when fields.isEmpty => const <String, Object?>{},
      _ => throw _typeError('Map<String, Object?>', value),
    };
    for (var i = 0; i < fields.length; i++) {
      if (i >= _gateIndex && _gated(map)) break;
      final f = fields[i];
      if (!map.containsKey(f.name) && !optional[i] && f.type.kind != NetKind.custom) {
        throw PacketException('missing field `${f.name}`');
      }
      try {
        codecs[i].write(w, map[f.name], map);
      } on PacketException catch (e) {
        throw PacketException('`${f.name}`: ${e.message}');
      }
    }
  }
}

// ---------------------------------------------------------------- payload schemas

/// The compiled codec of one payload.
final class PayloadSchema {
  final NetPayload payload;
  final WireCodec _root;

  PayloadSchema(this.payload)
    : _root = _Struct(payload.fields, payload.id, gate: _gates[payload.id]);

  String get id => payload.id;
  NetDirection get direction => payload.direction;

  /// Decodes a whole payload body. Trailing bytes are an error.
  Map<String, Object?> decode(List<int> bytes) {
    final r = PacketReader(bytes);
    final value = _root.read(r, const {}) as Map<String, Object?>;
    r.expectEnd();
    return value;
  }

  /// Encodes [fields] (keys are the manifest field names).
  Uint8List encode(Map<String, Object?> fields) =>
      PacketBuffer.encode((w) => _root.write(w, fields, const {}));

  /// Reads the payload fields from [r] (does not require the end).
  Map<String, Object?> read(PacketReader r) => _root.read(r, const {}) as Map<String, Object?>;

  void write(PacketWriter w, Map<String, Object?> fields) => _root.write(w, fields, const {});
}

/// All 119 payloads of the manifest, compiled once, by id.
final class PayloadSchemas {
  PayloadSchemas._(this.byId);

  final Map<String, PayloadSchema> byId;

  /// Compiles [payloads]; throws [SchemaException] if one cannot be compiled.
  factory PayloadSchemas.compile(Iterable<NetPayload> payloads) {
    final map = <String, PayloadSchema>{};
    for (final p in payloads) {
      if (map.containsKey(p.id)) throw SchemaException('duplicate payload ${p.id}');
      map[p.id] = PayloadSchema(p);
    }
    return PayloadSchemas._(Map.unmodifiable(map));
  }

  static PayloadSchemas? _manifest;

  /// The schemas of `networkPayloads` (cached).
  static PayloadSchemas get manifest => _manifest ??= PayloadSchemas.compile(networkPayloads);

  PayloadSchema operator [](String id) => byId[id] ?? (throw ArgumentError.value(id, 'id', 'is not a Create payload'));

  Iterable<PayloadSchema> get all => byId.values;
}
