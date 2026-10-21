// A semantic differential between what two *different* servers told a client.
//
// The question this answers is the one a user asks after "it works against the Java mod and not
// against the plugin": *where is the first difference in the play-phase packets the two clients
// received?* A byte diff of the two traces is worthless — the packet ids, registration order,
// entity ids, block-state ids and tick pacing all differ legitimately — so this compares
// **events**: `block_update(pos)`, `block_entity_data(pos, nbt)`, `add_entity(pos, type, bundle)`,
// `custom_payload(channel, data)`, `chunk(x, z)`. Same *kind* of event, same *place*, equivalent
// *content*.
//
// Three normalisations make two independent runs comparable, and each one is lossy in a way that
// is stated here rather than hidden:
//
//  * **Positions are relative to the scenario's anchor.** The two servers generate their own world
//    and spawn the client at their own height, so the same rig sits at different absolute
//    coordinates; every position is translated by the anchor the runner read from each server's own
//    console. The region compared is then a box in *rig* coordinates, which also keeps world noise
//    (terrain the two worldgen implementations disagree about) out of the comparison.
//  * **Ids are mapped through each server's own numbering.** A block state id, an entity id, an
//    entity type id or an id-shaped value inside a payload means nothing across servers; what does
//    mean something is the *equality pattern* — "the same state that was sent at p also appears at
//    q", "this entity is the first one spawned in this trace". So each of those is renamed to an
//    ordinal (`state#0`, `entity#1`) in order of first appearance per trace. Two runs agree when
//    their patterns agree. This deliberately cannot tell `minecraft:stone` from
//    `minecraft:air`: the traces do not carry the block palette, so the rig's *identity* is pinned
//    by the console instead (`data get block` on both servers, reported by the runner as ground
//    truth), and a real block-level difference shows up as a pattern difference instead.
//  * **Payloads are compared by content, decoded.** A `custom_payload` (the contraption's
//    `neoforge:advanced_add_entity` spawn data, above all) is decoded as NBT and flattened to
//    `path -> value`; the first differing path is the finding. A leaf whose *name* is id-shaped
//    (`EntityID`, `id`) is renamed through the same numbering as the entity ids in the stream, and
//    an integer array (a contraption's block list) compares by length and equality pattern — for
//    the same reason ids do. Both keep the raw numbers alongside the comparison, and the report
//    prints them (`as the servers sent it`), so nothing is hidden behind the normalisation. The
//    exception is a channel whose content *is* world state (`worldDependentPayloadChannels`): the
//    event is still compared — a server that never sent the channel is a difference — but its bytes
//    are not, because the two arms build their own world around their own client.
//
// What is *not* compared, and why: packets the client trace does not model (`other`, e.g.
// keep-alives and time updates) — they differ between a plugin server and the vanilla one by
// construction and say nothing about Create; tick numbers and absolute packet indices — timing, not
// content; and the order of packets belonging to different positions *within* one bundle, which the
// client does not observe (a bundle is delivered whole) — bundle membership is compared as part of
// the entity that was spawned in it, so "the payload did not travel with the entity" is still
// caught, which is exactly the defect that makes a contraption invisible.
//
// The order check therefore covers the rig's own story — *was the block state at p sent, then the
// block entity's payload, then the entity with its bundle* — and not the pacing of the whole
// stream.

import 'dart:convert';
import 'dart:typed_data';

import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/core/nbt.dart';

import '../pumpkin_trace.dart';

/// The region of a scenario that is compared, in anchor-relative block coordinates.
final class RigBox {
  const RigBox({
    required this.xMin,
    required this.xMax,
    required this.yMin,
    required this.yMax,
    required this.zMin,
    required this.zMax,
  });

  /// A box `radius` blocks around the anchor on every axis.
  const RigBox.around(int radius)
    : xMin = -radius,
      xMax = radius,
      yMin = -radius,
      yMax = radius,
      zMin = -radius,
      zMax = radius;

  final int xMin, xMax, yMin, yMax, zMin, zMax;

  bool contains(TracePos pos) =>
      pos.x >= xMin &&
      pos.x <= xMax &&
      pos.y >= yMin &&
      pos.y <= yMax &&
      pos.z >= zMin &&
      pos.z <= zMax;

  /// Whether the chunk column at the anchor-relative `(chunkX, chunkZ)` is compared.
  ///
  /// Only the anchor's own column is. A server tells a joining client about every chunk within its
  /// *view distance*, and that distance is a server setting, not something Create decides: the two
  /// arms are configured separately (`pumpkin.toml` against `server.properties`), so comparing the
  /// neighbours would report a configuration difference as if it were a mod difference. The
  /// anchor's own chunk is the one both servers must send — the rig is built in it — so it is the
  /// one whose presence says "this client tracks the rig".
  bool containsChunk(int chunkX, int chunkZ) => chunkX == 0 && chunkZ == 0;

  @override
  String toString() =>
      'x $xMin..$xMax, y $yMin..$yMax, z $zMin..$zMax (anchor-relative)';
}

/// Payload channels whose *content* is world state rather than the plugin's answer, so two servers
/// that generate their own worlds legitimately send different bytes.
///
/// `neoforge:auxiliary_light_data` is one payload per chunk, naming the chunk's coordinates and the
/// light its blocks emit on top of their state. The two arms build the rig where their own client
/// stands (different chunks) and each world is generated independently, so the bytes cannot be
/// equal even when the two servers behave identically. The *event* is still compared — a server
/// that never sent the channel is a difference, and that is the regression the contraption's
/// rendering bug was — but its content is not, and neither is the order of the chunks it names.
const Set<String> worldDependentPayloadChannels = {
  'neoforge:auxiliary_light_data',
};

/// The renamer that turns each server's own ids into comparable ordinals.
///
/// One instance belongs to one trace, because the whole point is that the numbering is the *server's*
/// and only its equality pattern travels across.
final class CanonicalIds {
  final Map<String, int> _next = {};
  final Map<String, String> _tokens = {};

  /// The token for [key] in the [namespace], minted on first sight (`state#0`, `entity#1`, ...).
  String token(String namespace, Object key) {
    final id = '$namespace/$key';
    final existing = _tokens[id];
    if (existing != null) return existing;
    final ordinal = _next[namespace] ?? 0;
    _next[namespace] = ordinal + 1;
    final token = '$namespace#$ordinal';
    _tokens[id] = token;
    return token;
  }

  /// How many distinct values of [namespace] this trace has seen (for the report).
  int count(String namespace) => _next[namespace] ?? 0;
}

/// One normalised event, comparable across two traces.
final class TraceEvent {
  TraceEvent({
    required this.kind,
    required this.key,
    required this.value,
    required this.order,
    required this.line,
    required this.raw,
    this.payloads = const [],
    this.payloadLabels = const [],
  });

  /// The trace schema's own kind (`block_update`, `custom_payload`, ...).
  final String kind;

  /// What the event is *about*: a position, an entity ordinal, a channel.
  final String key;

  /// The comparable content: a state ordinal, a bundle listing, a payload digest.
  final String value;

  /// Where this sits in the trace's own event order, so "first" is well defined.
  final int order;

  /// The trace line this came from, for the report.
  final int line;

  /// The line itself, so a failure can be read without opening the trace.
  final String raw;

  /// The decoded payloads this event carried, in the order they were sent: a `custom_payload`'s
  /// own data, a block entity's NBT, or the payloads that travelled inside an entity's bundle.
  ///
  /// These are what the content check compares — [value] is only their summary, because two
  /// payloads of the same length and shape can differ in a leaf, and comparing summaries would miss
  /// exactly the difference this whole tool exists for.
  final List<PayloadDigest> payloads;

  /// The channel of each payload in [payloads], for a report that names what differed.
  final List<String> payloadLabels;

  @override
  String toString() => '$kind($key) = $value';
}

/// A payload reduced to something two servers can be compared on.
///
/// NBT flattens to `path -> rendered value` leaves, so a divergence can name the *path* that
/// differs instead of printing two blobs. A payload that is not NBT is compared as raw bytes, and
/// one that is empty is a value of its own (an empty payload is a real difference from a missing
/// one).
final class PayloadDigest {
  PayloadDigest._(
    this.form,
    this.length,
    this.compares,
    this.display,
    this.raw,
    this.rawHash,
  );

  /// `nbt`, `raw`, `empty` or `world`.
  final String form;
  final int length;

  /// A payload whose content is not compared because it is world state
  /// ([worldDependentPayloadChannels]).
  ///
  /// The event itself is still compared, so a server that never sent the channel is a difference;
  /// only the bytes (and the chunk they name) are left out, because the two arms generate their
  /// own world around their own client.
  const PayloadDigest.worldDependent()
    : form = 'world',
      length = 0,
      compares = const {},
      display = const {},
      raw = null,
      rawHash = null;

  /// Path -> comparable value, for `nbt`. This is what two servers are compared on.
  final Map<String, String> compares;

  /// Path -> the same value as a human should read it (an id array shows its numbers here, while
  /// [compares] holds the *pattern*, because the numbers themselves are per-server).
  final Map<String, String> display;

  /// The raw bytes, hex, capped, for the report's context.
  final String? raw;

  /// A cheap fingerprint of the whole payload, for the report.
  final String? rawHash;

  /// Decodes [bytes] with the same NBT reader the client uses, falling back to raw bytes.
  /// [ids] renames id-shaped values through the *trace's* numbering, so an entity id or a block
  /// state id inside the payload compares as a reference rather than as a number, and [origin] is
  /// the anchor the rig was built at, which is what makes a value that *is* the rig's position
  /// comparable across two worlds.
  factory PayloadDigest.of(
    Uint8List? bytes,
    CanonicalIds ids, {
    required TracePos origin,
  }) {
    if (bytes == null || bytes.isEmpty) {
      return PayloadDigest._('empty', 0, const {}, const {}, null, null);
    }
    final hash = _fnv1a(bytes);
    final hex = _hex(bytes, limit: 512);
    // Plain NBT first: a block entity's payload *is* the NBT, and nothing is guessed for it.
    var decoded = _decodeNbt(bytes);
    var frame = 0;
    Frame? framed;
    if (decoded == null) {
      // Then the framed form. The NeoForge entity payload this differential exists for
      // (`neoforge:advanced_add_entity`, the contraption's spawn data) is a `FriendlyByteBuf`: the
      // entity id as a VarInt, the NBT's length as a VarInt, then the NBT. The length therefore has
      // to match the bytes that follow *exactly*, which is what makes the rule a check rather than
      // a guess — a payload that is not framed this way falls through to raw bytes below.
      framed = _readFramed(bytes);
      if (framed != null) {
        decoded = _decodeNbt(framed.nbt);
        if (decoded != null) frame = framed.entityId;
      }
    }
    // The plain binary form (a root tag with a name), as a `.nbt` file uses.
    decoded ??= _readFileNbt(bytes);
    if (decoded == null) {
      return PayloadDigest._('raw', bytes.length, const {}, const {}, hex, hash);
    }
    final compares = <String, String>{};
    final display = <String, String>{};
    if (frame != 0 || framed != null) {
      // The reference to the entity, renamed through the trace's own numbering — the same numbering
      // the `add_entity` for it uses, so "the payload is about the entity that was spawned" is a
      // comparison and not a coincidence of two servers agreeing on an id.
      compares['@entity'] = ids.token('entity', frame);
      display['@entity'] = '$frame (framed payload)';
    }
    _flatten(decoded, '', compares, display, CanonicalIds(), origin);
    return PayloadDigest._('nbt', bytes.length, compares, display, hex, hash);
  }

  /// The first leaf that differs from [other], or null when the payloads are equivalent.
  PayloadDifference? firstDifference(PayloadDigest other) {
    if (form != other.form) {
      return PayloadDifference(
        path: 'the payload',
        reference: form,
        candidate: other.form,
        referenceDisplay: form,
        candidateDisplay: other.form,
      );
    }
    if (form == 'raw') {
      if (rawHash == other.rawHash) return null;
      return PayloadDifference(
        path: 'the bytes',
        reference: '$rawHash ($length B)',
        candidate: '${other.rawHash} (${other.length} B)',
        referenceDisplay: raw ?? '',
        candidateDisplay: other.raw ?? '',
      );
    }
    if (form == 'empty' || form == 'world') return null;
    for (final key in compares.keys) {
      if (other.compares.containsKey(key)) continue;
      return PayloadDifference(
        path: key,
        reference: compares[key]!,
        candidate: 'absent',
        referenceDisplay: display[key]!,
        candidateDisplay: 'absent',
      );
    }
    for (final key in other.compares.keys) {
      if (compares.containsKey(key)) continue;
      return PayloadDifference(
        path: key,
        reference: 'absent',
        candidate: other.compares[key]!,
        referenceDisplay: 'absent',
        candidateDisplay: other.display[key]!,
      );
    }
    for (final entry in compares.entries) {
      final theirs = other.compares[entry.key];
      if (entry.value == theirs) continue;
      return PayloadDifference(
        path: entry.key,
        reference: entry.value,
        candidate: theirs!,
        referenceDisplay: display[entry.key]!,
        candidateDisplay: other.display[entry.key]!,
      );
    }
    return null;
  }

  /// Whether this payload carries anything at all (an empty payload is `empty`, not `nbt`).
  bool get isEmptyPayload => form == 'empty';

  String get summary => switch (form) {
    'empty' => 'empty payload',
    'world' => 'world-dependent content (not compared)',
    'raw' => 'raw $length B ($rawHash)',
    _ => 'nbt $length B, ${compares.length} leaves',
  };

  /// The leaves, for a failure message: the paths that were compared and what they held.
  String describeLeaves({int limit = 8}) {
    if (compares.isEmpty) return summary;
    final entries = display.entries.take(limit);
    final more = display.length > limit
        ? ' … ${display.length - limit} more'
        : '';
    return '$summary: ${entries.map((e) => '${e.key}=${e.value}').join(', ')}$more';
  }

  bool _identicalTo(PayloadDigest other) => firstDifference(other) == null;

  @override
  String toString() => '$summary${raw == null ? '' : ' $raw'}';

  @override
  bool operator ==(Object other) =>
      other is PayloadDigest && _identicalTo(other);

  @override
  int get hashCode => rawHash?.hashCode ?? compares.hashCode;
}

/// One leaf of two payloads that do not match.
final class PayloadDifference {
  const PayloadDifference({
    required this.path,
    required this.reference,
    required this.candidate,
    required this.referenceDisplay,
    required this.candidateDisplay,
  });

  /// The NBT path (`Contents.Blocks.BlockList`), or `the bytes` for a payload that is not NBT.
  final String path;

  /// What the comparison saw, in comparable form (a pattern, for an array of ids).
  final String reference;
  final String candidate;

  /// The same values as a human reads them (an array of ids shows its numbers here).
  final String referenceDisplay;
  final String candidateDisplay;

  /// The one-line description: what differed, in comparable terms.
  String get describe => '$path: $reference vs $candidate';

  /// What the two servers actually said, when that is more than the pattern.
  String get describeDisplay =>
      referenceDisplay == reference && candidateDisplay == candidate
      ? describe
      : '$path: $referenceDisplay vs $candidateDisplay';
}

/// A payload with a `FriendlyByteBuf` frame: the entity it is about, and the NBT inside.
final class Frame {
  const Frame(this.entityId, this.nbt);

  final int entityId;
  final Uint8List nbt;
}

NbtValue? _decodeNbt(Uint8List bytes) {
  try {
    final value = NetworkNbt.decode(bytes);
    if (value != null && value.kind == NbtKind.compound) return value;
  } on Object {
    return null;
  }
  return null;
}

NbtValue? _readFileNbt(Uint8List bytes) {
  try {
    final root = BinaryNbt.read(bytes)?.root;
    if (root != null && root.kind == NbtKind.compound) return root;
  } on Object {
    return null;
  }
  return null;
}

/// Reads `VarInt entity id, VarInt length, length bytes of NBT`, or null when that is not exactly
/// what the bytes are.
Frame? _readFramed(Uint8List bytes) {
  final id = _readVarInt(bytes, 0);
  if (id == null || id.value < 0) return null;
  final length = _readVarInt(bytes, id.length);
  if (length == null) return null;
  final start = id.length + length.length;
  if (length.value <= 0 || start + length.value != bytes.length) return null;
  return Frame(id.value, Uint8List.sublistView(bytes, start));
}

({int value, int length})? _readVarInt(Uint8List bytes, int at) {
  var value = 0;
  for (var i = 0; i < 5; i++) {
    if (at + i >= bytes.length) return null;
    final byte = bytes[at + i];
    value |= (byte & 0x7F) << (7 * i);
    if ((byte & 0x80) == 0) return (value: value, length: i + 1);
  }
  return null;
}

/// The value a payload leaf is compared as.
///
/// A number is a number, unless it is an id — in which case the *trace's* numbering renames it, so
/// two servers that number their states differently still compare equal.
String _renderLeaf(NbtValue value) => switch (value.kind) {
  NbtKind.byte ||
  NbtKind.short ||
  NbtKind.int ||
  NbtKind.long => '${value.value as int}',
  NbtKind.float || NbtKind.double => '${value.value as double}',
  NbtKind.string => jsonEncode(value.value as String),
  NbtKind.byteArray ||
  NbtKind.intArray ||
  NbtKind.longArray => _renderArray(value.value as List<int>),
  NbtKind.list => '[${(value.value as List<NbtValue>).length} items]',
  NbtKind.compound => '{${(value.value as Map<String, NbtValue>).length} keys}',
  NbtKind.end => 'end',
};

/// The *comparable* form of a leaf: the rendered value, with a number's NBT type.
///
/// A number's width is part of what the client receives (`create:fluid_tank`'s client data writes
/// `Boiler.Supply` as a `float` in the mod and as a `double` in the plugin), and two numbers of
/// different widths render the same, so without the type the comparison would call them equal and
/// only the payload's byte length would differ — which is a difference, but an unnamed one. The
/// type is written after the value rather than instead of it, so the report still reads
/// (`0.0 (float) vs 0.0 (double)`).
String _renderComparable(NbtValue value, String rendered) => switch (value.kind) {
  NbtKind.byte => '$rendered (byte)',
  NbtKind.short => '$rendered (short)',
  NbtKind.int => '$rendered (int)',
  NbtKind.long => '$rendered (long)',
  NbtKind.float => '$rendered (float)',
  NbtKind.double => '$rendered (double)',
  _ => rendered,
};

/// Arrays are compared by length and equality pattern, and *printed* as their content.
///
/// A contraption's block list is an array of block state ids; those ids are per-server, so the
/// pattern is what can be compared — `arr#0 arr#0 arr#1` versus `arr#0 arr#0 arr#0` is a real
/// difference (two blocks of one kind versus three of the same kind), while `37764` versus `9001`
/// is not. The numbers themselves go to the display map, so the report still shows what each server
/// said.
String _renderArray(List<int> values) {
  if (values.isEmpty) return '[]';
  // The ordinals are local to *this* array: an id array's meaning is its equality pattern
  // (`arr#0 arr#1 arr#0` is "two of one and one of another"), and a trace-wide namespace would make
  // the same array compare differently depending on what else the payload contained.
  final ordinals = <int, String>{};
  final pattern = <String>[];
  for (var i = 0; i < values.length && i < 256; i++) {
    final token = ordinals.putIfAbsent(
      values[i],
      () => 'arr#${ordinals.length}',
    );
    pattern.add(token);
  }
  final more = values.length > 256 ? ', … ${values.length - 256} more' : '';
  return '[@${values.length}: ${pattern.join(' ')}$more]';
}

/// The raw numbers of an array, for a human.
String _displayArray(List<int> values) {
  if (values.isEmpty) return '[]';
  final shown = values.take(64).map((value) => '$value').join(' ');
  final more = values.length > 64 ? ' … ${values.length - 64} more' : '';
  return '[@${values.length}: $shown$more]';
}

void _flatten(
  NbtValue value,
  String path,
  Map<String, String> compares,
  Map<String, String> display,
  CanonicalIds ids,
  TracePos origin,
) {
  final leaf = path.contains('.')
      ? path.substring(path.lastIndexOf('.') + 1)
      : path;
  switch (value.kind) {
    case NbtKind.compound:
      final compound = value.value as Map<String, NbtValue>;
      if (compound.isEmpty) {
        compares['$path()'] = '{}';
        display['$path()'] = '{}';
        return;
      }
      for (final key in compound.keys.toList()..sort()) {
        _flatten(
          compound[key]!,
          path.isEmpty ? key : '$path.$key',
          compares,
          display,
          ids,
          origin,
        );
      }
    case NbtKind.list:
      final list = value.value as List<NbtValue>;
      compares['$path<<list>>'] = '${list.length} items';
      display['$path<<list>>'] = '${list.length} items';
      for (var i = 0; i < list.length && i < 256; i++) {
        _flatten(list[i], '$path[$i]', compares, display, ids, origin);
      }
    case NbtKind.end:
      compares[path] = 'end';
      display[path] = 'end';
    case NbtKind.byteArray || NbtKind.intArray || NbtKind.longArray:
      final array = value.value as List<int>;
      final rigRelative = rigRelativeArray(array, origin);
      compares[path] = rigRelative ?? _renderArray(array);
      display[path] = _displayArray(array);
    default:
      final rendered = _renderComparable(value, _renderLeaf(value));
      display[path] = rendered;
      if (_isInteger(value.kind) && _isIdKey(leaf)) {
        // A leaf whose *name* is an id names something the server numbered itself (`EntityID`,
        // `ContraptionID`, `id`): the reference is what matters, not the number, so it is renamed
        // through this trace's numbering and two servers' different entity ids compare equal.
        compares[path] = ids.token('id', value.value as int);
      } else {
        compares[path] = _rigRelativeScalar(leaf, value, origin) ?? rendered;
      }
  }
}

/// An array that is the rig's own position, rendered relative to the anchor.
///
/// An absolute position is the one value in a contraption's payload that *cannot* match across two
/// servers: the two worlds put the rig in different places, and the mod sends the contraption's
/// anchor as plain coordinates. [origin] is each server's own anchor, so a value that is the anchor
/// (or an offset from it along one axis) says the same thing on both sides once it is written
/// relative to it.
///
/// The gate is "at least two of the three components are exactly the anchor's": an array that
/// merely contains a 0 somewhere is not a position, and a *relative* position (a contraption's
/// `Blocks.BlockList[i].Pos`, which is small and 0-based) is compared as itself, because a
/// coincidence of one component is not enough to translate it. A miss here can only leave a
/// legitimate difference reported, never hide a real one.
String? rigRelativeArray(List<int> values, TracePos origin) {
  if (values.length != 3) return null;
  final axis = [origin.x, origin.y, origin.z];
  var matches = 0;
  for (var i = 0; i < 3; i++) {
    if (values[i] == axis[i]) matches++;
  }
  if (matches < 2) return null;
  final rendered = [
    for (var i = 0; i < 3; i++) values[i] == axis[i] ? '0' : '${values[i]}',
  ];
  return '[@3 rel anchor: ${rendered.join(' ')}]';
}

/// A scalar named `x`, `y` or `z` that is exactly the anchor's component, rendered as `0`.
///
/// The same reasoning as [rigRelativeArray], for the payloads that spell a position out as three
/// scalars (a block entity's own coordinates) instead of as an array.
String? _rigRelativeScalar(String leaf, NbtValue value, TracePos origin) {
  if (!_isInteger(value.kind)) return null;
  final number = value.value as int;
  final axis = switch (leaf) {
    'x' || 'X' => origin.x,
    'y' || 'Y' => origin.y,
    'z' || 'Z' => origin.z,
    _ => null,
  };
  if (axis == null || number != axis) return null;
  return '0 (rel anchor)';
}

/// Whether an NBT key names an id rather than a value.
///
/// The rule is deliberately syntactic — `id`, `ID`, `SomethingId`, `something_id` — and it is
/// *reported*: a payload difference that only exists because one of these was normalised shows both
/// numbers in the report (`as the servers sent it`), so nothing is hidden behind the rule.
bool _isInteger(NbtKind kind) =>
    kind == NbtKind.byte ||
    kind == NbtKind.short ||
    kind == NbtKind.int ||
    kind == NbtKind.long;

bool _isIdKey(String key) {
  if (key == 'id' || key == 'ID' || key == 'Id') return true;
  // `State` is a contraption's pointer into its own palette: the *palette* carries the block's
  // name (`minecraft:stone`), which is what is compared, so the id behind it only has to agree on
  // being the same id.
  if (key == 'State' || key == 'state') return true;
  return key.endsWith('Id') || key.endsWith('ID') || key.endsWith('_id');
}
 
/// Everything one trace said, in comparable form.
final class NormalisedTrace {
  NormalisedTrace({
    required this.label,
    required this.origin,
    required this.box,
    required this.events,
    required this.timeline,
    required this.sourceLines,
    required this.kinds,
    required this.ignored,
    required this.drops,
    this.blockEntityPushes = const {},
  });

  /// What this trace is (`java`, `pumpkin`).
  final String label;

  /// The anchor every position was translated by.
  final TracePos origin;

  final RigBox box;

  /// Every event inside the box, in trace order.
  final List<TraceEvent> events;

  /// The labels of the rig-relevant events, in order: the sequence two servers must agree on.
  ///
  /// Only the position- and entity-keyed kinds are here (`block_update`, `block_entity_data`,
  /// `chunk_block_entity`, `add_entity`), because only they have an order the client can act on.
  /// Payloads and chunk columns say "something was sent" rather than "in this order", so they are
  /// compared as sets — a payload that arrived *inside an entity's bundle* is compared on the
  /// entity instead, which is where its sequence actually matters.
  final List<String> timeline;

  /// How many lines the source trace had (so "compared 3 of 400" is visible).
  final int sourceLines;

  /// A histogram of the kinds compared, for the report.
  final Map<String, int> kinds;

  /// Lines the comparison skipped, and why (never silently dropped).
  final Map<String, int> ignored;

  /// The packets the connection could not be handed.
  final int drops;

  /// How many times each block entity's payload was pushed (position -> count). Not compared: a
  /// machine that is running pushes its state every tick, and how many ticks elapsed is timing.
  final Map<String, int> blockEntityPushes;

  bool get isEmpty => events.isEmpty;

  String get summary {
    final pushes = blockEntityPushes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = pushes.take(3).map((e) => '${e.key}×${e.value}').join(', ');
    return '$label: ${events.length} comparable events from $sourceLines lines '
        '(${kinds.entries.map((e) => '${e.key}=${e.value}').join(', ')})'
        '${ignored.isEmpty ? '' : '; skipped ${ignored.entries.map((e) => '${e.key}=${e.value}').join(', ')}'}'
        '${pushes.isEmpty ? '' : '; block entity pushes not compared: $shown'
            '${pushes.length > 3 ? ', …' : ''}'}';
  }

  static NormalisedTrace of(
    PumpkinTrace trace, {
    required String label,
    required TracePos origin,
    RigBox box = const RigBox.around(8),
    String? client,
  }) {
    final scoped = client == null ? trace : trace.forClient(client);
    final normaliser = _Normaliser(label: label, origin: origin, box: box);
    return normaliser.run(scoped);
  }

  /// The same trace with the events [remove] matches taken out — the *negative control* of a parity
  /// test.
  ///
  /// A parity test that only ever runs against two working servers has never been shown to fail, so
  /// `test/parity/negative_control_test.dart` takes a real run and deletes one event from one arm:
  /// "the server never pushed this block entity's payload" is the regression class this suite
  /// exists for, and the comparison has to report it. The timeline keeps its order minus the
  /// removed events, so the result is a trace a server could plausibly have produced.
  NormalisedTrace without(bool Function(TraceEvent event) remove) {
    final kept = [
      for (final event in events)
        if (!remove(event)) event,
    ];
    final keptLabels = {for (final event in kept) '${event.kind}(#${event.key})'};
    return NormalisedTrace(
      label: '$label (one event removed)',
      origin: origin,
      box: box,
      events: kept,
      timeline: [
        for (final label in timeline)
          if (keptLabels.contains(label)) label,
      ],
      sourceLines: sourceLines,
      kinds: {
        for (final event in kept)
          event.kind: (kinds[event.kind] ?? 0),
      },
      ignored: ignored,
      drops: drops,
      blockEntityPushes: blockEntityPushes,
    );
  }
}

class _Normaliser {
  _Normaliser({required this.label, required this.origin, required this.box});

  final String label;
  final TracePos origin;
  final RigBox box;
  final CanonicalIds ids = CanonicalIds();

  TracePos? _relative(TracePos? pos) {
    if (pos == null) return null;
    final rel = TracePos(pos.x - origin.x, pos.y - origin.y, pos.z - origin.z);
    return box.contains(rel) ? rel : null;
  }

  NormalisedTrace run(PumpkinTrace trace) {
    final events = <TraceEvent>[];
    final timeline = <String>[];
    final kinds = <String, int>{};
    final ignored = <String, int>{};
    var drops = 0;
    // A payload that travelled inside the same bundle as an entity is folded into that entity's
    // value (`bundle=[...]`), so it is not also a timeline event of its own: the client sees the
    // bundle, not the packets.
    final bundled = <TracedPacket>{};
    for (final spawn in trace.spawns) {
      bundled.addAll(spawn.bundledPayloads);
    }

    for (final packet in trace.packets) {
      final kind = packet.rawKind;
      switch (packet.kind) {
        case TraceKind.addEntity:
          final rel = _relative(packet.pos);
          if (rel == null) {
            _skip(ignored, kind);
            continue;
          }
          TracedSpawn? spawn;
          for (final candidate in trace.spawns) {
            if (identical(candidate.spawn, packet)) {
              spawn = candidate;
              break;
            }
          }
          final bundled = spawn?.bundledPayloads ?? const <TracedPacket>[];
          final channels = [for (final packet in bundled) packet.channel ?? '?'];
          final bundledDigests = [
            for (final packet in bundled) PayloadDigest.of(packet.data, ids, origin: origin),
          ];
          final entity = packet.entity == null
              ? '?'
              : ids.token('entity', packet.entity!);
          final type = packet.type == null ? '?' : ids.token('type', packet.type!);
          events.add(
            TraceEvent(
              kind: kind,
              key: '#$rel',
              value: '$entity type $type bundle=[${channels.join(', ')}]',
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
              payloads: bundledDigests,
              payloadLabels: channels,
            ),
          );
          timeline.add('$kind(#$rel)');
          _count(kinds, kind);
        case TraceKind.customPayload:
          if (bundled.contains(packet)) {
            _skip(ignored, '$kind (bundled with an entity)');
            continue;
          }
          final channel = packet.channel ?? '?';
          final digest = worldDependentPayloadChannels.contains(channel)
              ? const PayloadDigest.worldDependent()
              : PayloadDigest.of(packet.data, ids, origin: origin);
          final last = _lastPayload[channel];
          if (last != null && last.firstDifference(digest) == null) {
            // The same bytes on the same channel again is not new information: a server that
            // repeats itself must not read as a difference from one that does not.
            _skip(ignored, '$kind (repeat of the same bytes)');
            continue;
          }
          _lastPayload[channel] = digest;
          events.add(
            TraceEvent(
              kind: kind,
              key: channel,
              value: digest.summary,
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
              payloads: [digest],
              payloadLabels: [channel],
            ),
          );
          _count(kinds, kind);
        case TraceKind.chunkBlockEntity:
          final rel = _relative(packet.pos);
          if (rel == null) {
            _skip(ignored, kind);
            continue;
          }
          final carried = PayloadDigest.of(packet.nbtBytes, ids, origin: origin);
          events.add(
            TraceEvent(
              kind: kind,
              key: '#$rel',
              value: carried.summary,
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
              payloads: [carried],
            ),
          );
          timeline.add('$kind(#$rel)');
          _count(kinds, kind);
        case TraceKind.blockEntityData:
          final rel = _relative(packet.pos);
          if (rel == null) {
            _skip(ignored, kind);
            continue;
          }
          final digest = PayloadDigest.of(packet.nbtBytes, ids, origin: origin);
          final key = '#$rel';
          final pushes = _blockEntities[key];
          if (pushes != null) {
            // A block entity's payload is re-pushed whenever its state changes, and a *running*
            // machine's state changes every tick (an angle, a session counter, a transient flag):
            // the later pushes carry timing-dependent values, and how many of them there are
            // depends on how long the client stayed connected. Only the *first* push can be
            // compared between two runs — and it is, below, leaf by leaf. The rest are counted so
            // the report can say they were seen and not compared.
            _blockEntities[key] = pushes + 1;
            _skip(ignored, '$kind (later pushes of the same block entity)');
            continue;
          }
          _blockEntities[key] = 1;
          events.add(
            TraceEvent(
              kind: TraceKind.blockEntityData.wire,
              key: key,
              value: digest.summary,
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
              payloads: [digest],
            ),
          );
          timeline.add('${TraceKind.blockEntityData.wire}(#$rel)');
          _count(kinds, TraceKind.blockEntityData.wire);
        case TraceKind.blockUpdate:
        case TraceKind.sectionBlockUpdate:
          final rel = _relative(packet.pos);
          if (rel == null) {
            _skip(ignored, kind);
            continue;
          }
          // The state id is the server's; the *history* of states per position is not — so a state
          // the server re-sends unchanged (a block whose state did not change, re-announced) is
          // counted, not compared, and what is compared is the sequence of states the client was
          // actually told (`state#0 → state#1`), however many times each was repeated.
          //
          // The names are minted *per position*, not per trace: a block state id means nothing
          // across servers, so `state#0` has to mean "the first state this position was ever told",
          // and a trace-wide numbering would make two servers disagree whenever their packets
          // happened to arrive in a different order (a placement update that landed after a spawn
          // instead of before it would renumber every state after it).
          final key = '#$rel';
          final token = packet.state == null
              ? '?'
              : _stateToken(key, packet.state!);
          if (_lastState[key] == token) {
            _skip(ignored, '${TraceKind.blockUpdate.wire} (repeat of the same state)');
            continue;
          }
          _lastState[key] = token;
          events.add(
            TraceEvent(
              kind: TraceKind.blockUpdate.wire,
              key: key,
              value: token,
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
            ),
          );
          timeline.add('${TraceKind.blockUpdate.wire}(#$rel)');
          _count(kinds, TraceKind.blockUpdate.wire);
        case TraceKind.chunk:
        case TraceKind.unloadChunk:
          final chunk = packet.chunk;
          if (chunk == null) {
            _skip(ignored, kind);
            continue;
          }
          final relX = (chunk.x - (origin.x >> 4)).toInt();
          final relZ = (chunk.z - (origin.z >> 4)).toInt();
          if (!box.containsChunk(relX, relZ)) {
            _skip(ignored, '$kind (outside the rig)');
            continue;
          }
          events.add(
            TraceEvent(
              kind: kind,
              key: 'chunk#$relX,$relZ',
              value: '',
              order: events.length,
              line: packet.line,
              raw: packet.describe(),
            ),
          );
          _count(kinds, kind);
        case TraceKind.dropped:
          drops++;
          _count(kinds, kind);
        case TraceKind.bundleStart:
        case TraceKind.bundleEnd:
          // Bundle *boundaries* are not compared: which packets a server batches together is a
          // pacing choice, and membership is carried by the entity's own `bundle=[...]` value.
          _skip(ignored, kind);
        case TraceKind.other:
        case TraceKind.unknown:
          _skip(ignored, kind);
      }
    }

    if (drops > 0) {
      events.add(
        TraceEvent(
          kind: TraceKind.dropped.wire,
          key: '#drops',
          value: '$drops',
          order: events.length,
          line: 0,
          raw: '$drops packet(s) were never handed to the connection',
        ),
      );
    }
    return NormalisedTrace(
      label: label,
      origin: origin,
      box: box,
      events: events,
      timeline: timeline,
      sourceLines: trace.length,
      kinds: kinds,
      ignored: ignored,
      drops: drops,
      blockEntityPushes: _blockEntities,
    );
  }

  final Map<String, String> _lastState = {};
  final Map<String, Map<int, String>> _stateNames = {};
  final Map<String, int> _blockEntities = {};

  /// The name for a state id at one position: `state#0` is the first state that *this position* was
  /// told, whatever the server's own numbering is.
  String _stateToken(String key, int state) {
    final names = _stateNames.putIfAbsent(key, () => <int, String>{});
    return names.putIfAbsent(state, () => 'state#${names.length}');
  }
  final Map<String, PayloadDigest> _lastPayload = {};

  static void _count(Map<String, int> map, String key) =>
      map[key] = (map[key] ?? 0) + 1;

  static void _skip(Map<String, int> map, String key) =>
      map[key] = (map[key] ?? 0) + 1;
}

/// The first place two traces stop agreeing.
final class Divergence {
  const Divergence({
    required this.check,
    required this.subject,
    required this.reference,
    required this.candidate,
    required this.timeline,
    required this.contextReference,
    required this.contextCandidate,
  });

  /// `shape` (an event kind or key one server has and the other does not), `content` (the same
  /// event with different content) or `order` (the same events in a different sequence).
  final String check;

  /// What it is about (`block_update(#0, 0, 1)`).
  final String subject;

  final String reference;
  final String candidate;

  /// Where in the reference's timeline this happened, so "the first" is not the order of the checks.
  final int timeline;

  final List<String> contextReference;
  final List<String> contextCandidate;

  String describe() => switch (check) {
    'shape' => 'the $subject is different: reference has $reference, candidate has $candidate',
    'content' => 'the $subject carries different content: $reference vs $candidate',
    _ => 'the events are in a different order at $subject: $reference vs $candidate',
  };
}

/// The comparison of two normalised traces.
final class Differential {
  Differential._(this.reference, this.candidate, this.divergences);

  final NormalisedTrace reference;
  final NormalisedTrace candidate;

  /// Every divergence found, earliest in the reference's timeline first.
  final List<Divergence> divergences;

  bool get agrees => divergences.isEmpty;

  Divergence? get first => divergences.isEmpty ? null : divergences.first;

  /// Compares [reference] (the server that works) with [candidate] (the one under test).
  static Differential compare(
    NormalisedTrace reference,
    NormalisedTrace candidate, {
    int context = 4,
  }) {
    final found = <Divergence>[];

    // 1. Shape: the same kinds must be about the same things.
    final referenceByKind = _byKind(reference.events);
    final candidateByKind = _byKind(candidate.events);
    final allKinds = {...referenceByKind.keys, ...candidateByKind.keys}.toList()..sort();
    for (final kind in allKinds) {
      final mine = referenceByKind[kind] ?? const <String, List<TraceEvent>>{};
      final theirs = candidateByKind[kind] ?? const <String, List<TraceEvent>>{};
      final missing = mine.keys.where((key) => !theirs.containsKey(key)).toList();
      final extra = theirs.keys.where((key) => !mine.containsKey(key)).toList();
      if (missing.isEmpty && extra.isEmpty) continue;
      String render(Iterable<String> keys, Map<String, List<TraceEvent>> from) =>
          keys.isEmpty
          ? 'nothing'
          : '${keys.length} (${keys.take(3).join(', ')}${keys.length > 3 ? ', …' : ''})';
      found.add(
        Divergence(
          check: 'shape',
          subject: '$kind events',
          reference: render(missing, mine),
          candidate: render(extra, theirs),
          timeline: _orderOf(_firstOrNull(missing, mine) ?? _firstOrNull(extra, theirs)),
          contextReference: _context(
            reference.timeline,
            _orderOf(_firstOrNull(missing, mine)),
            context,
          ),
          contextCandidate: _context(
            candidate.timeline,
            _orderOf(_firstOrNull(extra, theirs)),
            context,
          ),
        ),
      );
    }

    // 2. Content: for every event both have, the values must match.
    for (final kind in allKinds) {
      final mine = referenceByKind[kind] ?? const <String, List<TraceEvent>>{};
      final theirs = candidateByKind[kind] ?? const <String, List<TraceEvent>>{};
      for (final key in mine.keys) {
        final other = theirs[key];
        if (other == null) continue;
        final mineList = mine[key]!;
        final most = mineList.length > other.length ? mineList.length : other.length;
        for (var i = 0; i < most; i++) {
          if (i >= mineList.length || i >= other.length) {
            found.add(
              Divergence(
                check: 'content',
                subject: '$kind($key) #${i + 1} (one server sent $most, the other fewer)',
                reference: i < mineList.length
                    ? 'value: ${mineList[i].value} | ${mineList[i].payloads.map((p) => p.describeLeaves()).join(' + ')}'
                    : 'absent',
                candidate: i < other.length
                    ? 'value: ${other[i].value} | ${other[i].payloads.map((p) => p.describeLeaves()).join(' + ')}'
                    : 'absent',
                timeline: _timelineOf(i < mineList.length ? mineList[i] : other.first),
                contextReference: _context(reference.timeline, mineList.first.order, context),
                contextCandidate: _context(candidate.timeline, other.first.order, context),
              ),
            );
            break;
          }
          final a = mineList[i];
          final b = other[i];
          final difference = _contentDifference(a, b);
          if (difference == null) continue;
          found.add(
            Divergence(
              check: 'content',
              subject: '$kind($key) #${i + 1}',
              reference:
                  '$difference\n            reference: ${a.raw}\n'
                  '              value: ${a.value}\n'
                  '              decoded: ${_decode(a)}',
              candidate:
                  'candidate: ${b.raw}\n'
                  '              value: ${b.value}\n'
                  '              decoded: ${_decode(b)}',
              timeline: _timelineOf(a),
              contextReference: _context(reference.timeline, a.order, context),
              contextCandidate: _context(candidate.timeline, b.order, context),
            ),
          );
        }
      }
    }

    // 3. Order: the kinds must enter the stream in the same order.
    //
    // Not the *events*, position by position: two block updates at two positions are two
    // independent packets whose order inside one tick a client cannot observe, and a server that
    // sends them the other way round is not defective. What the client *can* observe, and what the
    // contraption case is entirely about, is that the kinds come in the same order — the state at
    // the anchor, the payload, then the entity that carries it.
    final referenceKinds = _firstOccurrenceOrder(reference.timeline);
    final candidateKinds = _firstOccurrenceOrder(candidate.timeline);
    for (var i = 0; i < referenceKinds.length && i < candidateKinds.length; i++) {
      if (referenceKinds[i] == candidateKinds[i]) continue;
      found.add(
        Divergence(
          check: 'order',
          subject: 'the order the rig events appear in',
          reference: referenceKinds.join(' → '),
          candidate: candidateKinds.join(' → '),
          timeline: i,
          contextReference: _context(reference.timeline, i, context),
          contextCandidate: _context(candidate.timeline, i, context),
        ),
      );
      break;
    }

    found.sort((a, b) => a.timeline.compareTo(b.timeline));
    return Differential._(reference, candidate, found);
  }

  /// What two events of the same kind at the same key differ in, or null when they do not.
  ///
  /// Payload content first, because that is where a contraption's meaning lives; the summary string
  /// only decides the events that carry no payload (a state id, a bundle listing, an entity type).
  static String? _contentDifference(TraceEvent a, TraceEvent b) {
    if (a.payloads.length != b.payloads.length) {
      return 'payloads: ${a.payloads.length} vs ${b.payloads.length}';
    }
    for (var i = 0; i < a.payloads.length; i++) {
      final difference = a.payloads[i].firstDifference(b.payloads[i]);
      if (difference == null) continue;
      final label = i < a.payloadLabels.length ? '${a.payloadLabels[i]}: ' : '';
      final shown = difference.describeDisplay;
      return shown == difference.describe
          ? '$label${difference.describe}'
          : '$label${difference.describe} (as the servers sent it — ${difference.referenceDisplay} vs ${difference.candidateDisplay})';
    }
    return a.value == b.value ? null : 'value: ${a.value} vs ${b.value}';
  }

  /// The payloads of an event, rendered for a failure message (form, size and the bytes).
  static String _decode(TraceEvent event) {
    if (event.payloads.isEmpty) return event.value;
    return event.payloads.map((payload) => payload.toString()).join(' + ');
  }

  static Map<String, Map<String, List<TraceEvent>>> _byKind(List<TraceEvent> events) {
    final byKind = <String, Map<String, List<TraceEvent>>>{};
    for (final event in events) {
      (byKind[event.kind] ??= {}).putIfAbsent(event.key, () => []).add(event);
    }
    return byKind;
  }

  /// The kinds of [timeline], in the order they first appear (`block_update, add_entity, ...`).
  static List<String> _firstOccurrenceOrder(List<String> timeline) {
    final kinds = <String>[];
    for (final entry in timeline) {
      final kind = entry.substring(0, entry.indexOf('('));
      if (!kinds.contains(kind)) kinds.add(kind);
    }
    return kinds;
  }

  static int _timelineOf(TraceEvent? event) => event?.order ?? 0;

  static int _orderOf(List<TraceEvent>? events) => events?.firstOrNull?.order ?? 0;

  static List<String> _context(List<String> timeline, int at, int radius) {
    final from = at - radius < 0 ? 0 : at - radius;
    final to = at + radius + 1 > timeline.length ? timeline.length : at + radius + 1;
    return [
      for (var i = from; i < to; i++) '${i == at ? '>' : ' '} #${i + 1} ${timeline[i]}',
    ];
  }

  /// The report: the first divergence in full, then what the rest look like.
  String report({bool all = false}) {
    final lines = <String>[reference.summary, candidate.summary];
    if (agrees) {
      lines
        ..add('')
        ..add(
          'no semantic difference: the two servers sent the same rig events with the same content '
          '(${reference.timeline.length} events compared over ${reference.box}).',
        );
      return lines.join('\n');
    }
    final headline = first!;
    lines
      ..add('')
      ..add('FIRST SEMANTIC DIFFERENCE (${headline.check}, at event #${headline.timeline + 1})')
      ..add('  ${headline.describe()}')
      ..add('  ${reference.label} around it:')
      ..addAll(headline.contextReference.map((line) => '    $line'))
      ..add('  ${candidate.label} around it:')
      ..addAll(headline.contextCandidate.map((line) => '    $line'));
    final rest = divergences.skip(1).toList();
    if (rest.isEmpty) {
      lines.add('no further differences.');
    } else if (all) {
      lines.add('all ${divergences.length} differences:');
      for (final divergence in divergences) {
        lines.add('  [${divergence.check}] ${divergence.describe()}');
      }
    } else {
      lines.add(
        'and ${rest.length} more (${_histogram(rest)}); rerun with --all for the list.',
      );
    }
    return lines.join('\n');
  }

  static String _histogram(List<Divergence> divergences) {
    final counts = <String, int>{};
    for (final divergence in divergences) {
      counts[divergence.check] = (counts[divergence.check] ?? 0) + 1;
    }
    return counts.entries.map((e) => '${e.value} ${e.key}').join(', ');
  }
}

/// The first of [keys] the map has events for (`package:collection` is not a dependency here).
List<TraceEvent>? _firstOrNull(
  List<String> keys,
  Map<String, List<TraceEvent>> byKey,
) {
  for (final key in keys) {
    final events = byKey[key];
    if (events != null) return events;
  }
  return null;
}

String _hex(Uint8List bytes, {int limit = 64}) {
  final end = bytes.length < limit ? bytes.length : limit;
  final buffer = StringBuffer();
  for (var i = 0; i < end; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  if (bytes.length > limit) buffer.write('… (${bytes.length} B)');
  return buffer.toString();
}

/// A 64-bit FNV-1a fingerprint, so a long raw payload still gets a one-token comparison.
String _fnv1a(Uint8List bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}