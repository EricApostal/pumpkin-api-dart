// What a client was told, read back from a packet trace.
//
// `PUMPKIN_PACKET_TRACE=<path>` makes the server write one JSON object per line for every packet
// it enqueues to a client (`crates/pumpkin-core/src/net/packet_trace.rs`), and the headless client
// of `tools/pumpkin-tester` writes the same line shape for every packet it *receives* (plus
// `"dir":"recv"`). The client's trace is the authoritative record of what arrived; the server's
// says what was sent, so "the server never sent it" and "it was sent but never arrived" stay
// distinguishable.
//
// The line shape, as the server writes it:
//
//   {"tick":12,"client":0,"kind":"block_update","pos":[4,70,0],"state":1234}
//   {"tick":12,"client":0,"kind":"section_block_update","pos":[4,70,0],"state":1234}
//   {"tick":12,"client":0,"kind":"block_entity_data","pos":[4,70,0],"type":42,"nbt":"0a00..."}
//   {"tick":12,"client":0,"kind":"add_entity","entity":7,"type":91,"pos":[4,70,0]}
//   {"tick":12,"client":0,"kind":"custom_payload","channel":"create:x","data":"0a00..."}
//   {"tick":12,"client":0,"kind":"chunk","chunk":[0,0]}
//   {"tick":12,"client":0,"kind":"unload_chunk","chunk":[0,0]}
//   {"tick":12,"client":0,"kind":"bundle_start"}   {"tick":12,"client":0,"kind":"bundle_end"}
//   {"tick":12,"client":0,"kind":"dropped","id":24}
//
// A packet that went out inside a bundle also carries `"bundle":true`; the delimiters are their
// own lines because a missing closing delimiter is exactly the defect worth catching, so the
// bundle a packet belongs to is read from the markers, never inferred from adjacency. `pos` is
// `[x,y,z]`, `chunk` is `[x,z]`, and `nbt`/`data` are hex. A client trace has no `client` field.
//
// The parser is deliberately tolerant about field spelling (a trace is a debugging aid, and
// `PUMPKIN_PACKET_TRACE` output is not a stable file format), but strict about *meaning*: a line
// whose kind it does not recognize is kept and reported rather than dropped silently.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:create/src/common/binary_nbt.dart';
import 'package:create/src/core/nbt.dart';

/// A block position (or a chunk column, for the two chunk kinds).
final class TracePos {
  const TracePos(this.x, this.y, this.z);

  final int x;
  final int y;
  final int z;

  @override
  bool operator ==(Object other) =>
      other is TracePos && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '$x, $y, $z';
}

/// The kinds a trace line can have.
enum TraceKind {
  bundleStart('bundle_start'),
  bundleEnd('bundle_end'),
  blockUpdate('block_update'),
  sectionBlockUpdate('section_block_update'),
  blockEntityData('block_entity_data'),

  /// A block entity a client's *chunk packet* carried inline (`CChunkData` carries the block
  /// entities of the column, so a client that just joined knows them without a separate packet).
  chunkBlockEntity('chunk_block_entity'),
  addEntity('add_entity'),
  customPayload('custom_payload'),
  chunk('chunk'),
  unloadChunk('unload_chunk'),
  dropped('dropped'),

  /// A packet a client received that the trace does not model (the client trace's catch-all).
  other('other'),
  unknown('unknown');

  const TraceKind(this.wire);

  /// The `kind` string the host writes.
  final String wire;

  static TraceKind of(String name) {
    for (final kind in values) {
      if (kind != unknown && kind.wire == name) return kind;
    }
    return unknown;
  }
}

/// One traced packet.
final class TracedPacket {
  TracedPacket({
    required this.rawKind,
    required this.line,
    required this.index,
    required this.fields,
    required this.tick,
    required this.client,
    required this.direction,
  }) : kind = TraceKind.of(rawKind);

  /// The `kind` exactly as the line spelled it: an unrecognized kind is reported, not dropped.
  final String rawKind;

  /// The 1-based line of the trace file this came from, so a failure can point at it.
  final int line;

  /// Where the packet sits in the trace, for "before/after" questions.
  final int index;

  /// The whole JSON object.
  final Map<String, Object?> fields;

  final TraceKind kind;
  final int? tick;

  /// The connection the server trace attributes the packet to; null in a client trace.
  final String? client;

  /// `"recv"` in a client trace, null in a server trace.
  final String? direction;

  /// Whether the server marked the packet as sent inside a bundle (`"bundle":true`).
  bool get markedBundled => fields['bundle'] == true;

  TracePos? get pos => _pos(_first(const ['pos', 'position', 'location']));

  /// The block state the client was told (a registry state id).
  int? get state => _int(_first(const ['state', 'state_id', 'block_state']));

  /// The chunk column, for `chunk` and `unload_chunk`.
  TracePos? get chunk => _pos(_first(const ['chunk', 'chunk_pos'])) ?? pos;

  /// The entity the client was told about (`add_entity`).
  int? get entity => _int(_first(const ['entity', 'entity_id']));

  /// The entity or block-entity *type* registry id.
  int? get type =>
      _int(_first(const ['type', 'entity_type', 'block_entity_type']));

  /// The payload channel (`custom_payload`).
  String? get channel => _string(_first(const ['channel']));

  /// The packet id of a line that reports one (`dropped`, `other`).
  int? get packetId => _int(fields['id']);

  /// The raw payload bytes (`custom_payload`).
  Uint8List? get data =>
      _hex(_first(const ['data', 'data_hex', 'payload', 'payload_hex']));

  /// The raw block-entity NBT bytes (`block_entity_data`).
  Uint8List? get nbtBytes =>
      _hex(_first(const ['nbt', 'nbt_hex', 'nbt-hex']));

  Map<String, NbtValue>? get nbt {
    if (!_nbtRead) {
      _nbtRead = true;
      _nbt = _decodeNbt(nbtBytes);
    }
    return _nbt;
  }

  bool _nbtRead = false;
  Map<String, NbtValue>? _nbt;

  /// A short, greppable rendering of the packet for a failure message.
  String describe() {
    final parts = <String>[
      'line $line: $rawKind',
      if (tick != null) 'tick=${tick!}',
      if (client != null) 'client=$client',
      if (direction != null) 'dir=$direction',
      if (pos != null) 'pos=[${pos!}]',
      if (chunk != null && kind != TraceKind.blockEntityData && kind != TraceKind.blockUpdate && kind != TraceKind.sectionBlockUpdate && kind != TraceKind.addEntity)
        'chunk=[${chunk!.x}, ${chunk!.z}]',
      if (state != null) 'state=${state!}',
      if (entity != null) 'entity=${entity!}',
      if (type != null) 'type=${type!}',
      if (channel != null) 'channel=${channel!}',
      if (nbt != null) 'nbt=${nbt!.keys.join(',')}',
      if (data != null) 'data=${data!.length}B',
      if (markedBundled) 'bundle=true',
    ];
    return parts.join(' ');
  }

  Object? _first(List<String> keys) {
    for (final key in keys) {
      final value = fields[key];
      if (value != null) return value;
    }
    return null;
  }

  @override
  String toString() => describe();
}

/// An entity the client was told about, with the bundle it arrived in.
///
/// An entity whose data is a payload of its own (a contraption, whose client rebuilds it from the
/// spawn data) is spawned *inside a bundle* together with that payload: as separate packets the
/// client can tick between the entity being added and its data being applied, and lose the entity
/// for good. The bundle is read from the delimiters, not inferred from adjacency.
final class TracedSpawn {
  const TracedSpawn(this.spawn, this.bundle);

  final TracedPacket spawn;

  /// The bundle the spawn went out in, null when it was sent on its own.
  final PacketBundle? bundle;

  TracePos? get pos => spawn.pos;

  int? get entity => spawn.entity;

  int? get type => spawn.type;

  /// Every payload that travelled in the same bundle as the entity.
  List<TracedPacket> get bundledPayloads => bundle == null
      ? const []
      : [
          for (final packet in bundle!.ofKind(TraceKind.customPayload)) packet,
        ];

  bool get carriedPayload => bundledPayloads.isNotEmpty;

  String describe() =>
      '${spawn.describe()} | bundle: ${bundle == null ? 'none' : bundle!.packets.map((p) => p.rawKind).join(', ')}';
}

/// A group of packets that reached the client together, between two delimiters.
final class PacketBundle {
  const PacketBundle(this.packets);

  final List<TracedPacket> packets;

  Iterable<TracedPacket> ofKind(TraceKind kind) =>
      packets.where((packet) => packet.kind == kind);

  bool contains(TracedPacket packet) => packets.any((p) => identical(p, packet));

  @override
  String toString() => packets.map((p) => p.describe()).join('\n  ');
}

/// Every packet one trace file holds.
final class PumpkinTrace {
  PumpkinTrace._(this.source, this.packets);

  /// Where the trace came from (a path, or a fixture name).
  final String source;

  final List<TracedPacket> packets;

  /// Parses trace lines. Blank lines are skipped; anything else must be a JSON object.
  static PumpkinTrace parse(String contents, {String source = '<memory>'}) {
    final packets = <TracedPacket>[];
    final lines = const LineSplitter().convert(contents);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final Object? decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('$source:${i + 1}: not a JSON object: $line');
      }
      final kind = _kindOf(decoded);
      packets.add(
        TracedPacket(
          rawKind: kind,
          line: i + 1,
          index: packets.length,
          fields: decoded,
          tick: _int(decoded['tick']),
          client: _client(decoded['client']),
          direction: _string(decoded['dir'] ?? decoded['direction']),
        ),
      );
    }
    return PumpkinTrace._(source, packets);
  }

  static PumpkinTrace read(File file) =>
      parse(file.readAsStringSync(), source: file.path);

  /// Reads a trace a process is still writing.
  ///
  /// The writers append line by line, so a read can catch a line that is only half flushed. A
  /// *trailing* line that does not parse is therefore dropped; any other malformed line is still an
  /// error, so a trace that is broken (rather than mid-write) still fails loudly. Use [read] once
  /// the writer has stopped.
  static PumpkinTrace readWhileWriting(File file) {
    if (!file.existsSync()) return PumpkinTrace.empty(file.path);
    final text = file.readAsStringSync();
    try {
      return parse(text, source: file.path);
    } on FormatException {
      final lastBreak = text.lastIndexOf('\n');
      if (lastBreak <= 0) rethrow;
      return parse(text.substring(0, lastBreak + 1), source: file.path);
    }
  }

  /// A trace with no packets, for a run that produced none.
  static PumpkinTrace empty(String source) => PumpkinTrace._(source, const []);

  bool get isEmpty => packets.isEmpty;

  int get length => packets.length;

  Iterable<TracedPacket> ofKind(TraceKind kind) =>
      packets.where((packet) => packet.kind == kind);

  Iterable<TracedPacket> get blockUpdates => ofKind(TraceKind.blockUpdate);

  Iterable<TracedPacket> get sectionBlockUpdates =>
      ofKind(TraceKind.sectionBlockUpdate);

  Iterable<TracedPacket> get blockEntityData =>
      ofKind(TraceKind.blockEntityData);

  Iterable<TracedPacket> get addEntities => ofKind(TraceKind.addEntity);

  Iterable<TracedPacket> get customPayloads => ofKind(TraceKind.customPayload);

  Iterable<TracedPacket> get chunks => ofKind(TraceKind.chunk);

  /// Packets the server could not hand to the connection (full or gone queue).
  Iterable<TracedPacket> get drops => ofKind(TraceKind.dropped);

  /// Kinds this parser does not know, so a trace that moved on is visible rather than silent.
  Iterable<TracedPacket> get unrecognized =>
      packets.where((packet) => packet.kind == TraceKind.unknown);

  /// The connections the server traced.
  Iterable<String> get clients => {
    for (final packet in packets)
      if (packet.client != null) packet.client!,
  };

  /// Whether the trace is a client's own ("what arrived") rather than the server's.
  bool get isClientTrace =>
      packets.any((packet) => packet.direction == 'recv');

  /// The packets that belong to one connection.
  PumpkinTrace forClient(String client) => PumpkinTrace._(
    '$source (client $client)',
    [
      for (final packet in packets)
        if (packet.client == client) packet,
    ],
  );

  /// Every payload the client was told about a position, oldest first, whether the server pushed it
  /// (`block_entity_data`) or the client's chunk packet carried it inline (`chunk_block_entity`).
  ///
  /// A client ends up with the same block entity either way, so a test asking "does the client know
  /// this position" wants both; a test asking "did the server push it when it changed" wants
  /// [pushedPayloadAt].
  List<TracedPacket> blockEntitiesAt(TracePos pos) => [
    for (final packet in packets)
      if ((packet.kind == TraceKind.blockEntityData ||
              packet.kind == TraceKind.chunkBlockEntity) &&
          packet.pos == pos)
        packet,
  ];

  /// The last payload for a position: what the client's block entity ends up as.
  TracedPacket? blockEntityAt(TracePos pos) {
    TracedPacket? last;
    for (final packet in packets) {
      if ((packet.kind == TraceKind.blockEntityData ||
              packet.kind == TraceKind.chunkBlockEntity) &&
          packet.pos == pos) {
        last = packet;
      }
    }
    return last;
  }

  /// The payloads the server *pushed* (`block_entity_data`), not the ones a chunk carried.
  Iterable<TracedPacket> get pushedBlockEntityData =>
      ofKind(TraceKind.blockEntityData);

  /// The block entities the client's chunk packets carried inline.
  Iterable<TracedPacket> get chunkBlockEntities =>
      ofKind(TraceKind.chunkBlockEntity);

  /// The last payload the server pushed for a position, null when it never pushed one.
  TracedPacket? pushedPayloadAt(TracePos pos) {
    TracedPacket? last;
    for (final packet in pushedBlockEntityData) {
      if (packet.pos == pos) last = packet;
    }
    return last;
  }

  /// The last state the client was told for a position, from either block-update kind.
  int? stateAt(TracePos pos) {
    int? state;
    for (final packet in packets) {
      if (packet.kind != TraceKind.blockUpdate &&
          packet.kind != TraceKind.sectionBlockUpdate) {
        continue;
      }
      if (packet.pos == pos) state = packet.state;
    }
    return state;
  }

  /// Every state the client was told for a position, oldest first.
  ///
  /// A block the plugin rewrites after placing it (a tank part whose connecting flags change when
  /// it merges) is told more than once, and the client only ever renders the last one.
  List<int> statesFor(TracePos pos) => [
    for (final packet in packets)
      if ((packet.kind == TraceKind.blockUpdate ||
              packet.kind == TraceKind.sectionBlockUpdate) &&
          packet.pos == pos &&
          packet.state != null)
        packet.state!,
  ];

  /// Every entity the client was told about, with the bundle it arrived in.
  List<TracedSpawn> get spawns => [
    for (final packet in addEntities) TracedSpawn(packet, bundleOf(packet)),
  ];

  /// The spawns whose payload arrived with the entity, in the same bundle.
  List<TracedSpawn> get bundledSpawns =>
      [for (final spawn in spawns) if (spawn.carriedPayload) spawn];

  /// Every position a state was sent for, with the last state sent.
  Map<TracePos, int> get blockStates {
    final states = <TracePos, int>{};
    for (final packet in packets) {
      if (packet.kind != TraceKind.blockUpdate &&
          packet.kind != TraceKind.sectionBlockUpdate) {
        continue;
      }
      final pos = packet.pos;
      final state = packet.state;
      if (pos != null && state != null) states[pos] = state;
    }
    return states;
  }

  /// Whether the client was told a state for [pos] before the first block-entity payload for it,
  /// or in the same bundle as that payload.
  ///
  /// This is what a client needs and what its own code enforces:
  /// `ClientPacketListener.handleBlockEntityData` looks the block entity up by position *and* type
  /// and drops the payload when it has none — so a payload that arrives before the block update
  /// that creates the block entity is lost, and the client is left with an empty block entity
  /// until its chunk is sent again (a relogin). True when there is no payload for [pos], because
  /// then there is nothing to drop, and true for a payload the chunk packet carried (the chunk
  /// brings the state and the payload together).
  bool payloadFollowsState(TracePos pos) {
    TracedPacket? payload;
    for (final packet in packets) {
      if ((packet.kind == TraceKind.blockEntityData ||
              packet.kind == TraceKind.chunkBlockEntity) &&
          packet.pos == pos) {
        payload = packet;
        break;
      }
    }
    if (payload == null) return true;
    if (payload.kind == TraceKind.chunkBlockEntity) return true;
    for (final packet in packets) {
      if (packet.index >= payload.index) break;
      if ((packet.kind == TraceKind.blockUpdate ||
              packet.kind == TraceKind.sectionBlockUpdate) &&
          packet.pos == pos) {
        return true;
      }
    }
    final bundle = bundleOf(payload);
    if (bundle == null) return false;
    return bundle.packets.any(
      (packet) =>
          (packet.kind == TraceKind.blockUpdate ||
              packet.kind == TraceKind.sectionBlockUpdate) &&
          packet.pos == pos,
    );
  }

  /// The positions the client was sent a block-entity payload for, in order.
  List<TracePos> get payloadPositions => [
    for (final packet in blockEntityData)
      if (packet.pos != null) packet.pos!,
  ];

  /// The bundle a packet went out in, read from the delimiters around it.
  PacketBundle? bundleOf(TracedPacket packet) {
    for (final bundle in bundles) {
      if (bundle.contains(packet)) return bundle;
    }
    return null;
  }

  /// Every bundle in the trace, in order.
  List<PacketBundle> get bundles {
    final bundles = <PacketBundle>[];
    List<TracedPacket>? open;
    for (final packet in packets) {
      switch (packet.kind) {
        case TraceKind.bundleStart:
          open = <TracedPacket>[];
        case TraceKind.bundleEnd:
          if (open != null) bundles.add(PacketBundle(open));
          open = null;
        default:
          open?.add(packet);
      }
    }
    // An unterminated bundle is still worth reporting: it means the closing delimiter never went
    // out, which is a defect of its own.
    if (open != null && open.isNotEmpty) bundles.add(PacketBundle(open));
    return bundles;
  }

  /// The positions, states and entities one client was told about.
  ClientVisibility visibility({String? client}) =>
      ClientVisibility.of(this, client: client);

  String describe({int limit = 40}) {
    final lines = <String>[
      '$source: ${packets.length} traced packets',
      if (packets.length > limit) '  (first $limit)',
      for (final packet in packets.take(limit)) '  ${packet.describe()}',
    ];
    return lines.join('\n');
  }

  @override
  String toString() => describe();
}

/// Everything one client was told: the state it can render from.
final class ClientVisibility {
  ClientVisibility._(
    this.label,
    this.blockEntities,
    this.blockStates,
    this.entities,
    this.chunks,
  );

  final String label;

  /// The last block-entity payload per position, whether it was pushed or carried by a chunk.
  final Map<TracePos, TracedPacket> blockEntities;

  /// The last block state per position. Only states the server *sent* are here: a state a chunk
  /// packet carried inline is not decoded, so a relogin legitimately has fewer entries than the
  /// client that watched the change happen.
  final Map<TracePos, int> blockStates;

  /// The entities the client was told about, by entity id, with the position they spawned at.
  final Map<int, TracePos?> entities;

  /// The chunk columns the client was given.
  final Set<TracePos> chunks;

  /// What one client of a trace (or a whole client trace) was told.
  factory ClientVisibility.of(PumpkinTrace trace, {String? client}) {
    final scoped = client == null ? trace : trace.forClient(client);
    final blockEntities = <TracePos, TracedPacket>{};
    for (final packet in scoped.packets) {
      if (packet.kind != TraceKind.blockEntityData &&
          packet.kind != TraceKind.chunkBlockEntity) {
        continue;
      }
      final pos = packet.pos;
      if (pos != null) blockEntities[pos] = packet;
    }
    return ClientVisibility._(
      client == null ? scoped.source : 'client $client',
      blockEntities,
      scoped.blockStates,
      {
        for (final packet in scoped.addEntities)
          if (packet.entity != null) packet.entity!: packet.pos,
      },
      {
        for (final packet in scoped.chunks)
          if (packet.chunk != null) packet.chunk!,
      },
    );
  }

  String get summary =>
      '$label: ${blockEntities.length} block entities, ${blockStates.length} block states, '
      '${entities.length} entities, ${chunks.length} chunks';
}

/// What one client was told that another was not.
///
/// This is the shape of "it only shows up after a relogin": `blockEntitiesOnlyInLate`,
/// `blockStatesOnlyInLate` and `entitiesOnlyInLate` are state the later client heard about that the
/// earlier one never did — the server pushed nothing when it changed, and the relogin's chunk and
/// payloads are the first time that client hears about it. Anything listed there is a defect: a
/// client that was *there* must not learn less than one that just joined.
///
/// The other direction (`*OnlyInEarly`) is mostly not a defect for block *states*: a relogin learns
/// a block's state inside its chunk packet, and the trace reports that chunk as a `chunk` line
/// without decoding the sections, so the relogin legitimately has no separate state line for a
/// block that was placed before it joined. Block *entities* are decoded on both paths
/// (`chunk_block_entity`), so those compare in both directions for real.
///
/// Both sides are read from client traces (what arrived) or from one connection of a server trace,
/// so a difference is always about what a client was told, never about server-side state.
///
/// [between] takes a `focus`: the positions the test is about. Without one the comparison covers the
/// whole world, and a live server disagrees with itself in ways that are nobody's defect — an
/// ambient mob that spawned between the two sessions is an `add_entity` the later client saw and the
/// earlier one did not. A focus keeps the comparison to the scenario's region (and to the entities
/// and chunks in it), so a difference left over is about the plugin.
final class VisibilityDiff {
  VisibilityDiff._({
    required this.blockEntitiesOnlyInLate,
    required this.blockStatesOnlyInLate,
    required this.entitiesOnlyInLate,
    required this.blockEntitiesOnlyInEarly,
    required this.blockStatesOnlyInEarly,
    required this.entitiesOnlyInEarly,
    required this.early,
    required this.late,
    required this.focus,
  });

  /// Positions the later client had a block entity for and the earlier one did not.
  final Set<TracePos> blockEntitiesOnlyInLate;

  /// Positions the later client was sent a *state* for that the earlier client was not told.
  final Set<TracePos> blockStatesOnlyInLate;

  final Set<int> entitiesOnlyInLate;

  /// Positions the earlier client had a block entity for and the later one did not.
  final Set<TracePos> blockEntitiesOnlyInEarly;

  /// Positions whose states the earlier client was told and the later one was not. Expected after a
  /// relogin for anything placed while the earlier client watched (see the class comment).
  final Set<TracePos> blockStatesOnlyInEarly;

  final Set<int> entitiesOnlyInEarly;
  final ClientVisibility early;
  final ClientVisibility late;

  /// The positions the comparison was limited to, null for the whole world.
  final Set<TracePos>? focus;

  static VisibilityDiff between(
    ClientVisibility early,
    ClientVisibility late, {
    Set<TracePos>? focus,
  }) {
    bool inFocus(TracePos pos) => focus == null || focus.contains(pos);
    bool entityInFocus(TracePos? pos) =>
        focus == null || (pos != null && focus.contains(pos));
    return VisibilityDiff._(
      blockEntitiesOnlyInLate: {
        for (final pos in late.blockEntities.keys)
          if (inFocus(pos) && !early.blockEntities.containsKey(pos)) pos,
      },
      blockStatesOnlyInLate: {
        for (final entry in late.blockStates.entries)
          if (inFocus(entry.key) && early.blockStates[entry.key] != entry.value)
            entry.key,
      },
      entitiesOnlyInLate: {
        for (final entry in late.entities.entries)
          if (entityInFocus(entry.value) && !early.entities.containsKey(entry.key))
            entry.key,
      },
      blockEntitiesOnlyInEarly: {
        for (final pos in early.blockEntities.keys)
          if (inFocus(pos) && !late.blockEntities.containsKey(pos)) pos,
      },
      blockStatesOnlyInEarly: {
        for (final entry in early.blockStates.entries)
          if (inFocus(entry.key) && late.blockStates[entry.key] != entry.value)
            entry.key,
      },
      entitiesOnlyInEarly: {
        for (final entry in early.entities.entries)
          if (entityInFocus(entry.value) && !late.entities.containsKey(entry.key))
            entry.key,
      },
      early: early,
      late: late,
      focus: focus,
    );
  }

  /// Nothing the later client was told that the earlier one was not. The defect direction: the
  /// client that was present when the state changed must not learn *less* than the relogin.
  bool get lateIsNoWiser =>
      blockEntitiesOnlyInLate.isEmpty &&
      blockStatesOnlyInLate.isEmpty &&
      entitiesOnlyInLate.isEmpty;

  /// Nothing the earlier client had that the later one did not, over what the trace decodes on both
  /// paths: block entities and entities.
  bool get earlyIsNoWiser =>
      blockEntitiesOnlyInEarly.isEmpty && entitiesOnlyInEarly.isEmpty;

  bool get isEmpty => lateIsNoWiser && earlyIsNoWiser;

  String describe() {
    final scope = focus == null
        ? ''
        : ' (limited to ${focus!.length} position(s): '
              '${focus!.take(4).map((pos) => '[$pos]').join(' ')}'
              '${focus!.length > 4 ? ' …' : ''})';
    if (isEmpty) {
      return '${early.summary}\n${late.summary}\n'
          'the two clients were told the same state$scope';
    }
    final lines = <String>[early.summary, late.summary, 'differences$scope:'];
    void section(String title, List<String> entries) {
      if (entries.isEmpty) return;
      lines..add(title)..addAll(entries);
    }

    section('  only the later client was told about (a client that was there learned less):', [
      for (final pos in blockEntitiesOnlyInLate)
        '    block entity at $pos (${late.blockEntities[pos]!.describe()})',
      for (final pos in blockStatesOnlyInLate)
        '    block state $pos = ${late.blockStates[pos]}'
            ' (the earlier client had ${early.blockStates[pos] ?? 'nothing'})',
      for (final entity in entitiesOnlyInLate)
        '    entity $entity at ${late.entities[entity] ?? 'an unknown position'}',
    ]);
    section('  only the earlier client had:', [
      for (final pos in blockEntitiesOnlyInEarly)
        '    block entity at $pos (${early.blockEntities[pos]!.describe()})',
      for (final pos in blockStatesOnlyInEarly)
        '    block state $pos = ${early.blockStates[pos]}'
            ' (the later client has ${late.blockStates[pos] ?? 'nothing'}; a state the chunk'
            ' packet carried is not decoded, so this alone is not a defect)',
      for (final entity in entitiesOnlyInEarly)
        '    entity $entity at ${early.entities[entity] ?? 'an unknown position'}',
    ]);
    return lines.join('\n');
  }

  @override
  String toString() => describe();
}

// ---------------------------------------------------------------------------- line fields

String _kindOf(Map<String, Object?> line) {
  final kind = _string(line['kind']);
  if (kind != null) return kind;
  // `type` is a field of `add_entity`/`block_entity_data`, so it is only a kind when it names one.
  final type = _string(line['type']);
  if (type != null && TraceKind.of(type) != TraceKind.unknown) return type;
  return 'unknown';
}

String? _client(Object? value) {
  if (value is String) return value;
  if (value is num) return value.toInt().toString();
  return null;
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

TracePos? _pos(Object? value) {
  if (value is List) {
    final ints = [for (final item in value) _int(item)];
    if (ints.length >= 3 && ints[0] != null && ints[1] != null && ints[2] != null) {
      return TracePos(ints[0]!, ints[1]!, ints[2]!);
    }
    if (ints.length == 2 && ints[0] != null && ints[1] != null) {
      return TracePos(ints[0]!, 0, ints[1]!);
    }
    return null;
  }
  if (value is Map) {
    final x = _int(value['x']);
    final y = _int(value['y']);
    final z = _int(value['z']);
    if (x != null && y != null && z != null) return TracePos(x, y, z);
    if (x != null && z != null) return TracePos(x, 0, z);
  }
  return null;
}

Uint8List? _hex(Object? value) {
  if (value is! String) return null;
  var text = value.trim();
  if (text.startsWith('0x')) text = text.substring(2);
  text = text.replaceAll(RegExp(r'[\s:]'), '');
  if (text.isEmpty) return Uint8List(0);
  if (text.length.isOdd) {
    throw FormatException('odd-length hex payload: $value');
  }
  final bytes = Uint8List(text.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byte = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) throw FormatException('not hex: $value');
    bytes[i] = byte;
  }
  return bytes;
}

/// Decodes a block-entity payload the way the client does: network NBT, with the plain binary
/// form (a root tag with a name, as `.nbt` files use) accepted as a fallback.
Map<String, NbtValue>? _decodeNbt(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  NbtValue? decoded;
  try {
    decoded = NetworkNbt.decode(bytes);
  } on Object {
    decoded = null;
  }
  if (decoded != null && decoded.kind == NbtKind.compound) {
    return decoded.asCompound;
  }
  // The plain binary form (a root tag with a name, as `.nbt` files use).
  try {
    final root = BinaryNbt.read(bytes)?.root;
    if (root != null && root.kind == NbtKind.compound) return root.asCompound;
  } on Object {
    return null;
  }
  return null;
}