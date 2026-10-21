// The trace parser and the relogin diff, on traces in the shape the host writes.
//
// These are part of the default suite: they are fast and need no server. They cover the parts the
// end-to-end tests stand on (the line shape, the NBT decode, the bundle delimiters, the diff), so a
// change in the trace format shows up here rather than as a confusing failure in a 3-minute server
// run.
//
// The fixtures under `test/support/fixtures/` are hand-written to match
// `crates/pumpkin-core/src/net/packet_trace.rs` field for field — they are *not* recorded runs. The
// live runs are the `test/e2e/` suite; this file only keeps the reading side honest.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:create/src/core/nbt.dart';
import 'package:test/test.dart';

import 'support/pumpkin_server.dart';
import 'support/pumpkin_trace.dart';

const TracePos lowerTank = TracePos(4, 70, 0);
const TracePos upperTank = TracePos(4, 71, 0);

PumpkinTrace fixture(String name) => PumpkinTrace.parse(
  File(
    joinPath(joinPath(HarnessPaths.packageRoot().path, 'test/support/fixtures'), name),
  ).readAsStringSync(),
  source: name,
);

/// One trace line, as the host writes it: `nbt` and `data` are hex.
String line(Map<String, Object?> fields) => jsonEncode(fields);

String hexOf(List<int> bytes) =>
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

void main() {
  group('trace lines', () {
    test('read the server shape: tick, connection, position, state', () {
      final trace = fixture('relogin_ok.trace.jsonl');

      expect(trace.clients, unorderedEquals(['1', '2']));
      expect(trace.isClientTrace, isFalse);
      expect(trace.unrecognized, isEmpty);
      expect(trace.drops, isEmpty);

      final early = trace.forClient('1');
      expect(early.length, 7, reason: early.describe());
      expect(early.chunks.single.chunk, const TracePos(0, 0, 0));
      expect(early.blockEntityAt(lowerTank)?.type, 17);
      expect(early.blockEntityAt(lowerTank)?.kind, TraceKind.blockEntityData);
      expect(early.blockStates, {
        lowerTank: 38181,
        upperTank: 38182,
      });
      expect(early.statesFor(lowerTank), [38180, 38181]);

      // A relogin learns the block entities of every chunk it is sent, inside the chunk packet.
      // Those lines are what makes the two clients comparable.
      final late = trace.forClient('2');
      expect(late.chunkBlockEntities.length, 2);
      expect(late.pushedPayloadAt(lowerTank), isNull);
      expect(late.blockEntityAt(upperTank)?.kind, TraceKind.chunkBlockEntity);
      expect(late.blockEntityAt(upperTank)?.chunk, const TracePos(0, 0, 0));
    });

    test('read the client shape: dir, named client, and `other` for the rest', () {
      final trace = fixture('spawn_bundle.trace.jsonl');

      expect(trace.isClientTrace, isTrue);
      expect(trace.clients, ['Watcher']);
      expect(trace.chunks.single.chunk, const TracePos(0, 0, 0));
      // Every packet the client could not name is still a line, so nothing it received is missing.
      expect(trace.ofKind(TraceKind.other).single.packetId, 80);
      expect(trace.unrecognized, isEmpty);
    });

    test('keep a kind they do not know instead of dropping it', () {
      final trace = PumpkinTrace.parse(
        line({'tick': 4, 'client': 0, 'kind': 'something_new', 'x': 1}),
      );
      expect(trace.unrecognized.single.rawKind, 'something_new');
      expect(trace.unrecognized.single.tick, 4);
    });

    test('report a packet the connection never took', () {
      final trace = PumpkinTrace.parse(
        line({'tick': 5, 'client': 3, 'kind': 'dropped', 'id': 24}),
      );
      expect(trace.drops.single.packetId, 24);
      expect(trace.drops.single.client, '3');
    });

    test('decode a block-entity payload the way the client reads it', () {
      // The plugin's own encoder writes the payload the host traces, so this is the round trip a
      // real `block_entity_data` line has to survive. This is the fluid tank's client shape:
      // `Size`/`Height` on the controller, `Controller` on a part
      // (`lib/src/fluids/fluid_tank.dart:494`).
      final payload = NetworkNbt.encode(
        NbtValue.compound({
          'Size': const NbtValue.int32(1),
          'Height': const NbtValue.int32(2),
          'Controller': const NbtValue.intArray([4, 70, 0]),
        }),
      );
      final trace = PumpkinTrace.parse(
        line({
          'tick': 22,
          'client': 1,
          'kind': 'block_entity_data',
          'pos': [4, 70, 0],
          'type': 17,
          'nbt': hexOf(payload),
        }),
      );

      final nbt = trace.blockEntityAt(lowerTank)!.nbt!;
      expect(nbt['Size']!.value, 1);
      expect(nbt['Height']!.value, 2);
      expect(nbt['Controller']!.value, [4, 70, 0]);
    });
  });

  group('bundles', () {
    test('come from the delimiters, and carry the entity with its payload', () {
      final trace = fixture('spawn_bundle.trace.jsonl');

      expect(trace.bundles.length, 1);
      final spawn = trace.bundledSpawns.single;
      expect(spawn.entity, 42);
      expect(spawn.pos, const TracePos(0, 70, 0));
      expect(spawn.bundledPayloads.single.channel, 'neoforge:advanced_add_entity');
      // The block update outside the delimiters is not part of the bundle.
      expect(
        trace.bundleOf(trace.ofKind(TraceKind.blockUpdate).single),
        isNull,
      );
    });

    test('report a bundle whose closing delimiter never arrived', () {
      final trace = PumpkinTrace.parse(
        [
          line({'dir': 'recv', 'kind': 'bundle_start'}),
          line({
            'dir': 'recv',
            'kind': 'add_entity',
            'entity': 1,
            'type': 2,
            'pos': [0, 0, 0],
            'bundle': true,
          }),
        ].join('\n'),
      );

      // An unterminated bundle is a defect of its own, so the packets are still reported.
      expect(trace.bundles.single.ofKind(TraceKind.addEntity).length, 1);
      expect(trace.bundledSpawns, isEmpty);
    });
  });

  group('the relogin diff', () {
    test('is empty in the defect direction when the present client was told the payloads', () {
      final trace = fixture('relogin_ok.trace.jsonl');
      final diff = VisibilityDiff.between(
        ClientVisibility.of(trace, client: '1'),
        ClientVisibility.of(trace, client: '2'),
      );

      // The client that was there was *pushed* both payloads; the relogin learned them from its
      // chunk. Neither learned less than the other.
      expect(diff.blockEntitiesOnlyInLate, isEmpty, reason: diff.describe());
      expect(diff.blockStatesOnlyInLate, isEmpty, reason: diff.describe());
      expect(diff.lateIsNoWiser, isTrue, reason: diff.describe());
      expect(diff.blockEntitiesOnlyInEarly, isEmpty, reason: diff.describe());
      expect(diff.earlyIsNoWiser, isTrue, reason: diff.describe());
      // Not `isEmpty`: the relogin's states ride inside its chunk packet, which the trace does not
      // decode, so the present client's state lines have no counterpart to compare with.
      expect(diff.blockStatesOnlyInEarly, {lowerTank, upperTank});
    });

    test('names the payload only the relogin had', () {
      final trace = fixture('relogin_missing.trace.jsonl');
      final diff = VisibilityDiff.between(
        ClientVisibility.of(trace, client: '1'),
        ClientVisibility.of(trace, client: '2'),
      );

      // The upper tank's payload never reached the client that was there, and the relogin got it
      // from its chunk: exactly "it only appears after a relogin".
      expect(diff.lateIsNoWiser, isFalse);
      expect(diff.blockEntitiesOnlyInLate, {upperTank});
      expect(diff.blockEntitiesOnlyInEarly, isEmpty);
      expect(diff.describe(), contains('block entity at 4, 71, 0'));
    });

    test('names a state only the later client was told', () {
      final trace = PumpkinTrace.parse(
        [
          line({'tick': 1, 'client': 1, 'kind': 'chunk', 'chunk': [0, 0]}),
          line({'tick': 2, 'client': 1, 'kind': 'block_update', 'pos': [4, 70, 0], 'state': 10}),
          line({'tick': 3, 'client': 2, 'kind': 'chunk', 'chunk': [0, 0]}),
          line({'tick': 4, 'client': 2, 'kind': 'block_update', 'pos': [4, 71, 0], 'state': 11}),
        ].join('\n'),
      );
      final diff = VisibilityDiff.between(
        ClientVisibility.of(trace, client: '1'),
        ClientVisibility.of(trace, client: '2'),
      );

      expect(diff.blockStatesOnlyInLate, {upperTank});
      expect(diff.blockStatesOnlyInEarly, {lowerTank});
      expect(diff.lateIsNoWiser, isFalse);
    });
  });

  group('payload ordering', () {
    test('a pushed payload needs the state that creates it first', () {
      final after = PumpkinTrace.parse(
        [
          line({'tick': 1, 'client': 1, 'kind': 'block_update', 'pos': [1, 2, 3], 'state': 7}),
          line({
            'tick': 1,
            'client': 1,
            'kind': 'block_entity_data',
            'pos': [1, 2, 3],
            'type': 17,
            'nbt': '0a00',
          }),
        ].join('\n'),
      );
      expect(after.payloadFollowsState(const TracePos(1, 2, 3)), isTrue);

      // The client drops a payload for a block entity it has no block for, and the block entity it
      // creates from the block update stays empty until its chunk is sent again.
      final before = PumpkinTrace.parse(
        [
          line({
            'tick': 1,
            'client': 1,
            'kind': 'block_entity_data',
            'pos': [1, 2, 3],
            'type': 17,
            'nbt': '0a00',
          }),
          line({'tick': 1, 'client': 1, 'kind': 'block_update', 'pos': [1, 2, 3], 'state': 7}),
        ].join('\n'),
      );
      expect(before.payloadFollowsState(const TracePos(1, 2, 3)), isFalse);

      // ... unless both are in one bundle, which the client applies at once.
      final bundled = PumpkinTrace.parse(
        [
          line({'dir': 'recv', 'kind': 'bundle_start'}),
          line({
            'dir': 'recv',
            'kind': 'block_entity_data',
            'pos': [1, 2, 3],
            'type': 17,
            'nbt': '0a00',
            'bundle': true,
          }),
          line({
            'dir': 'recv',
            'kind': 'block_update',
            'pos': [1, 2, 3],
            'state': 7,
            'bundle': true,
          }),
          line({'dir': 'recv', 'kind': 'bundle_end'}),
        ].join('\n'),
      );
      expect(bundled.payloadFollowsState(const TracePos(1, 2, 3)), isTrue);

      // A payload the chunk carried needs no separate state: the chunk brings both.
      final chunked = PumpkinTrace.parse(
        [
          line({'dir': 'recv', 'kind': 'chunk', 'chunk': [0, 0]}),
          line({
            'dir': 'recv',
            'kind': 'chunk_block_entity',
            'chunk': [0, 0],
            'pos': [1, 2, 3],
            'type': 17,
            'nbt': '0a00',
          }),
        ].join('\n'),
      );
      expect(chunked.payloadFollowsState(const TracePos(1, 2, 3)), isTrue);
    });
  });

  group('reading a trace a process is still writing', () {
    late Directory directory;
    late File file;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('trace-read-');
      file = File(joinPath(directory.path, 'live.jsonl'));
    });
    tearDown(() => directory.deleteSync(recursive: true));

    test('drops only a half-flushed trailing line', () {
      file.writeAsStringSync(
        [
          line({'tick': 1, 'client': 0, 'kind': 'chunk', 'chunk': [0, 0]}),
          '',
          '{"tick":2,"client":0,"kind":"block_upd',
        ].join('\n'),
      );

      expect(PumpkinTrace.readWhileWriting(file).length, 1);
      expect(() => PumpkinTrace.read(file), throwsA(isA<FormatException>()));
    });

    test('still refuses a broken line that is not the last one', () {
      file.writeAsStringSync(
        [
          line({'tick': 1, 'client': 0, 'kind': 'chunk', 'chunk': [0, 0]}),
          'not json at all',
          line({'tick': 3, 'client': 0, 'kind': 'chunk', 'chunk': [1, 0]}),
        ].join('\n'),
      );

      expect(() => PumpkinTrace.readWhileWriting(file), throwsA(isA<FormatException>()));
    });

    test('reads a file that does not exist yet as empty', () {
      expect(PumpkinTrace.readWhileWriting(File(joinPath(directory.path, 'none.jsonl'))).isEmpty, isTrue);
    });
  });

  group('hex payloads', () {
    test('reject an odd number of digits when the bytes are read', () {
      final trace = PumpkinTrace.parse(
        line({
          'dir': 'recv',
          'kind': 'custom_payload',
          'channel': 'create:x',
          'data': 'abc',
        }),
      );
      // Parsing is lazy about payload bytes: a trace with a payload a test does not look at is
      // still readable, and one it does look at fails loudly rather than silently decoding half.
      expect(trace.length, 1);
      expect(
        () => trace.customPayloads.single.data,
        throwsA(isA<FormatException>()),
      );
    });

    test('keep empty payloads distinct from missing ones', () {
      final trace = PumpkinTrace.parse(
        [
          line({
            'dir': 'recv',
            'kind': 'custom_payload',
            'channel': 'create:empty',
            'data': '',
          }),
          line({'dir': 'recv', 'kind': 'custom_payload', 'channel': 'create:none'}),
        ].join('\n'),
      );
      final packets = trace.customPayloads.toList();
      expect(packets[0].data, Uint8List(0));
      expect(packets[1].data, isNull);
    });
  });
}