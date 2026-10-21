// The differential's own tests: it must find a real difference, and it must not invent one.
//
// Both halves matter equally. A comparator that reports a difference between two equivalent traces
// (the two servers number their states and entities differently, pace their ticks differently, and
// spawn the same contraption at different absolute coordinates) would send someone hunting a plugin
// defect that is not there — so most of these tests are "this *should* agree", built with exactly
// those legitimate differences in them. The rest are one-defect-at-a-time traces, each asserting
// that the report names the *first* difference and where it is.
//
// The traces here are hand-written lines in the schema `pumpkin_trace.dart` reads, because that is
// what both the client and the proxy write; the payloads are real network NBT, encoded with the
// plugin's own codec, so the NBT comparison is exercised on the bytes a server would send.

import 'dart:convert';
import 'dart:io';

import 'package:create/src/core/nbt.dart';
import 'package:test/test.dart';

import 'support/differential/trace_diff.dart';
import 'support/pumpkin_trace.dart';

/// The anchor both hand-written traces are built around; the rig is relative to it, so the two
/// servers may sit in different worlds.
const TracePos origin = TracePos(100, 70, 200);

/// The spawn payload of a contrived contraption: a paletted block list, an anchor, and an entity
/// id — the three shapes that differ legitimately between two servers.
String payloadHex({
  int entityId = 42,
  int? anchorX,
  int contents = 1,
  List<int> blockList = const [7, 7, 9],
}) {
  final nbt = NbtValue.compound({
    'EntityID': NbtValue.int32(entityId),
    'Anchor': NbtValue.intArray([anchorX ?? origin.x, origin.y, origin.z]),
    'Contents': NbtValue.compound({'Value': NbtValue.int32(contents)}),
    'BlockList': NbtValue.longArray(blockList),
  });
  final bytes = NetworkNbt.encode(nbt);
  return [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
}

/// One JSONL line, as both the client and the proxy write them.
String line(Map<String, Object?> fields) =>
    jsonEncode({'dir': 'recv', 'client': 'Watcher', ...fields});

/// A client trace of the contraption rig, with the knobs a *difference* needs.
///
/// [bundle] false puts the payload outside the entity's bundle (the defect that makes a contraption
/// invisible), [spawn] false removes the entity altogether, and the ids and states are parameters
/// so that two calls can differ the way two servers do without being different in any way that
/// matters.
String contraptionTrace({
  required List<int> states,
  int entity = 42,
  int type = 161,
  bool bundle = true,
  bool spawn = true,
  String? payload,
  List<(List<int> pos, int state)> extraUpdates = const [],
  List<Map<String, Object?>> noise = const [],
}) {
  final lines = <String>[
    line({'kind': 'chunk', 'chunk': [origin.x >> 4, origin.z >> 4]}),
  ];
  for (final extra in extraUpdates) {
    lines.add(line({
      'kind': 'block_update',
      'pos': extra.$1,
      'state': extra.$2,
    }));
  }
  lines.addAll(noise.map(line));
  final rig = [
    [origin.x, origin.y, origin.z],
    [origin.x, origin.y, origin.z + 1],
    [origin.x, origin.y, origin.z + 2],
  ];
  for (var i = 0; i < states.length && i < rig.length; i++) {
    lines.add(line({'kind': 'block_update', 'pos': rig[i], 'state': states[i]}));
  }
  if (spawn) {
    if (bundle) lines.add(line({'kind': 'bundle_start'}));
    lines.add(line({
      'kind': 'add_entity',
      'entity': entity,
      'type': type,
      'pos': [origin.x, origin.y, origin.z],
      if (bundle) 'bundle': true,
    }));
    lines.add(line({
      'kind': 'custom_payload',
      'channel': 'neoforge:advanced_add_entity',
      'data': payload ?? payloadHex(),
      if (bundle) 'bundle': true,
    }));
    if (bundle) lines.add(line({'kind': 'bundle_end'}));
  } else if (payload != null) {
    lines.add(line({
      'kind': 'custom_payload',
      'channel': 'neoforge:advanced_add_entity',
      'data': payload,
    }));
  }
  return '${lines.join('\n')}\n';
}

/// A block entity payload that churns the way a running machine's does: the angle and the network
/// counter change every push, the structure does not.
String spinningPayload({
  required double angle,
  required int networkId,
  bool pluginClientData = false,
}) {
  final nbt = NbtValue.compound({
    'id': NbtValue.string('create:mechanical_bearing'),
    'Angle': NbtValue.float(angle),
    'Running': NbtValue.byte(1),
    'Network': NbtValue.compound({
      'Id': NbtValue.long(networkId),
      'Speed': NbtValue.float(-16),
    }),
    if (pluginClientData)
      'PluginClientData': NbtValue.compound({'Angle': NbtValue.float(angle)}),
  });
  final bytes = NetworkNbt.encode(nbt);
  return [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
}

NormalisedTrace normalise(String trace, {String label = 'trace'}) =>
    NormalisedTrace.of(
      PumpkinTrace.parse(trace, source: label),
      label: label,
      origin: origin,
    );

void main() {
  group('two servers that said the same thing', () {
    test('agree even though their ids, states and payload ids differ', () {
      // The reference: state ids 37762.., entity 42, payload ids and anchor as the Java server
      // numbers them, sent one tick apart.
      final reference = normalise(
        contraptionTrace(
          states: const [37762, 37764, 37208],
          entity: 42,
          type: 1500,
          payload: payloadHex(entityId: 42),
        ),
        label: 'java',
      );
      // The candidate: a different state numbering, a different entity id and type, a different
      // absolute anchor *inside* the payload, and more ticks in between.
      final candidate = normalise(
        contraptionTrace(
          states: const [9001, 9002, 9003],
          entity: 7,
          type: 55,
          payload: payloadHex(entityId: 7, anchorX: origin.x + 1),
        ),
        label: 'pumpkin',
      );

      final differential = Differential.compare(reference, candidate);
      expect(
        differential.agrees,
        isTrue,
        reason: differential.report(all: true),
      );
      expect(reference.timeline, isNotEmpty);
    });

    test('agree when the payload is not even NBT, as long as the bytes match', () {
      final bytes = '0a0003016102';
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3], payload: bytes)),
        normalise(contraptionTrace(states: const [9, 8, 7], payload: bytes)),
      );
      expect(differential.agrees, isTrue, reason: differential.report());
    });

    test('agree when one server sent the same states in another order', () {
      // Two block updates at two positions are independent packets: the order inside a tick is not
      // something a client observes, and neither server is wrong.
      final reordered = contraptionTrace(states: const [3, 2, 1]);
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(reordered),
      );
      expect(differential.agrees, isTrue, reason: differential.report());
    });

    test('the fixture of a real spawn compares equal to itself', () {
      final fixture = File(
        'test/support/fixtures/spawn_bundle.trace.jsonl',
      ).readAsStringSync();
      final differential = Differential.compare(
        NormalisedTrace.of(
          PumpkinTrace.parse(fixture),
          label: 'a',
          origin: const TracePos(0, 70, 0),
        ),
        NormalisedTrace.of(
          PumpkinTrace.parse(fixture),
          label: 'b',
          origin: const TracePos(0, 70, 0),
        ),
      );
      expect(differential.agrees, isTrue, reason: differential.report(all: true));
      // …and the fixture is a rig the comparator actually compared, not one it skipped.
      expect(
        differential.reference.events.map((e) => e.kind),
        contains('add_entity'),
      );
    });
  });

  group('what a running machine churns', () {
    // A machine pushes its block entity's state every tick, and those pushes carry a turn angle and
    // a session counter: comparing them would drown the one difference that matters, so the first
    // push is compared for content and every push for shape.
    String pushes(int count, {bool pluginClientData = false}) {
      final lines = <String>[];
      for (var i = 0; i < count; i++) {
        lines.add(line({
          'kind': 'block_entity_data',
          'pos': [origin.x, origin.y, origin.z + 1],
          'type': 42,
          'nbt': spinningPayload(
            angle: i * 4.7,
            networkId: 8267 + i,
            pluginClientData: pluginClientData,
          ),
        }));
      }
      return '${contraptionTrace(states: const [1, 2, 3])}'
          '${lines.join('\n')}\n';
    }

    test('a payload pushed every tick is not a difference, however many pushes', () {
      final differential = Differential.compare(
        normalise(pushes(20), label: 'java'),
        normalise(pushes(2), label: 'pumpkin'),
      );
      expect(differential.agrees, isTrue, reason: differential.report(all: true));
      expect(differential.reference.blockEntityPushes.values.first, 20);
    });

    test('…but a key the other server never sends is', () {
      final differential = Differential.compare(
        normalise(pushes(2)),
        normalise(pushes(2, pluginClientData: true)),
      );
      expect(differential.agrees, isFalse);
      // The first push is compared key by key, so the extra key is named there — and the shape
      // event says the same thing about *every* push, which is what catches a key that only ever
      // appears in a later one.
      expect(differential.first!.subject, contains('block_entity_data'));
      expect(
        differential.first!.candidate,
        contains('PluginClientData'),
        reason: differential.report(all: true),
      );
      expect(
        differential.divergences.any(
          (d) => d.subject.contains('block_entity_data_paths'),
        ),
        isTrue,
        reason: differential.report(all: true),
      );
    });

    test('a state the server re-sends unchanged is not a difference', () {
      // The same state the rig already sent for that position (the bearing), six more times.
      final repeated = [
        for (var i = 0; i < 6; i++)
          line({
            'kind': 'block_update',
            'pos': [origin.x, origin.y, origin.z + 1],
            'state': 2,
          }),
      ].join('\n');
      final withRepeats =
          '${contraptionTrace(states: const [1, 2, 3])}$repeated\n';
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(withRepeats),
      );
      // The *state* is what the client sees: a server that re-sends the same one has not told it
      // anything new, so this is not a difference — the count is reported instead.
      expect(
        differential.divergences.where((d) => d.subject.contains('block_update')),
        isEmpty,
        reason: differential.report(all: true),
      );
      expect(
        differential.candidate.ignored.keys.join(' '),
        contains('repeat of the same state'),
      );
    });
  });

  group('a real difference', () {
    test('a payload that did not travel in the entity´s bundle is the first finding', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(contraptionTrace(states: const [4, 5, 6], bundle: false)),
      );
      expect(differential.agrees, isFalse);
      final first = differential.first!;
      // The finding is about the entity, because that is what the payload travelled with — and the
      // report shows both the payload count and the bundle listing that explain it.
      expect(first.subject, contains('add_entity'));
      expect(first.reference, contains('payloads: 1'));
      expect(first.reference, contains('bundle=[neoforge:advanced_add_entity]'));
      expect(first.candidate, contains('bundle=[]'));
      expect(differential.report(), contains('FIRST SEMANTIC DIFFERENCE'));
    });

    test('a payload leaf that differs is named by its path', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(
          contraptionTrace(states: const [1, 2, 3], payload: payloadHex(contents: 2)),
        ),
      );
      expect(differential.agrees, isFalse);
      final first = differential.first!;
      expect(first.subject, contains('add_entity'));
      expect(first.reference, contains('Contents.Value: 1 vs 2'));
    });

    test('a block list of a different shape is a difference', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(
          contraptionTrace(
            states: const [1, 2, 3],
            payload: payloadHex(blockList: const [7, 7]),
          ),
        ),
      );
      expect(differential.agrees, isFalse);
      expect(differential.first!.reference, contains('BlockList'));
    });

    test('an entity that was never spawned is a shape difference', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(contraptionTrace(states: const [1, 2, 3], spawn: false)),
      );
      expect(differential.agrees, isFalse);
      expect(differential.first!.check, 'shape');
      expect(differential.first!.subject, contains('add_entity'));
    });

    test('an extra block update at a rig position is reported with its position', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(
          contraptionTrace(
            states: const [1, 2, 3],
            // The same position, told a *different* state afterwards: the client is told the block
            // changed, and the other server never said so.
            extraUpdates: [
              ([origin.x, origin.y, origin.z], 99),
            ],
          ),
        ),
      );
      expect(differential.agrees, isFalse);
      final first = differential.first!;
      expect(first.subject, contains('block_update'));
    });

    test('the order the kinds appear in is checked', () {
      // The entity spawned before the state that creates it: a client that ticks between them has
      // an entity with no block under it.
      final broken = [
        line({'kind': 'chunk', 'chunk': [origin.x >> 4, origin.z >> 4]}),
        line({'kind': 'bundle_start'}),
        line({
          'kind': 'add_entity',
          'entity': 1,
          'type': 2,
          'pos': [origin.x, origin.y, origin.z],
          'bundle': true,
        }),
        line({
          'kind': 'custom_payload',
          'channel': 'neoforge:advanced_add_entity',
          'data': payloadHex(),
          'bundle': true,
        }),
        line({'kind': 'bundle_end'}),
        line({
          'kind': 'block_update',
          'pos': [origin.x, origin.y, origin.z],
          'state': 1,
        }),
      ].join('\n');
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise('$broken\n'),
      );
      expect(differential.agrees, isFalse);
      expect(
        differential.divergences.any((d) => d.check == 'order'),
        isTrue,
        reason: differential.report(all: true),
      );
    });

    test('what is outside the rig is not compared', () {
      // Noise elsewhere in the world (another player's contraption, a mob) is not this scenario's
      // business: the same trace with and without it must compare equal.
      final noise = [
        {'kind': 'add_entity', 'entity': 99, 'type': 3, 'pos': [0, 0, 0]},
        {'kind': 'block_update', 'pos': [400, 64, -400], 'state': 12},
      ];
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(contraptionTrace(states: const [1, 2, 3], noise: noise)),
      );
      expect(differential.agrees, isTrue, reason: differential.report(all: true));
      expect(
        differential.candidate.ignored.values.fold<int>(0, (a, b) => a + b),
        greaterThanOrEqualTo(2),
      );
    });

    test('a drop on one side only is a difference', () {
      final dropped = '${contraptionTrace(states: const [1, 2, 3])}'
          '${line({'kind': 'dropped', 'id': 24})}\n';
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3])),
        normalise(dropped),
      );
      expect(differential.agrees, isFalse);
      expect(differential.divergences.first.subject, contains('dropped'));
    });
  });

  group('the report', () {
    test('says what was compared when the two servers agree', () {
      final report = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3]), label: 'java'),
        normalise(contraptionTrace(states: const [1, 2, 3]), label: 'pumpkin'),
      ).report();
      expect(report, contains('no semantic difference'));
      expect(report, contains('java:'));
      expect(report, contains('pumpkin:'));
    });

    test('lists the rest of the differences only when asked', () {
      final differential = Differential.compare(
        normalise(contraptionTrace(states: const [1, 2, 3], spawn: false)),
        normalise(
          contraptionTrace(
            states: const [1, 2, 3],
            spawn: false,
            payload: payloadHex(entityId: 7),
            extraUpdates: [
              ([origin.x, origin.y, origin.z], 99),
            ],
          ),
        ),
      );
      expect(differential.divergences.length, greaterThanOrEqualTo(2));
      expect(differential.agrees, isFalse);
      final count = differential.divergences.length;
      expect(differential.report(), contains('and ${count - 1} more'));
      expect(differential.report(), isNot(contains('all $count differences')));
      expect(differential.report(all: true), contains('all $count differences'));
    });
  });
}