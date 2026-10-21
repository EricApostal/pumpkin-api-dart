// An assembled contraption must reach the client as one bundle: the entity *and* the payload that
// tells the client what the contraption is made of.
//
// A contraption is a plugin entity whose visually meaningful data is its spawn payload — the client
// rebuilds the structure from it (`lib/src/contraptions/contraptions_module.dart:86`: the entity is
// registered with `spawnDataChannel: neoforge:advanced_add_entity` when it has complex spawn data,
// and the host uses that channel for every flavour, NeoForge client or not:
// `crates/pumpkin-core/src/entity/plugin_entity.rs:430`). The host therefore sends the add-entity
// and that payload inside one bundle (`plugin_entity.rs:496`): as separate packets the client can
// tick between the entity being added and its data being applied, and lose the entity for good.
//
// The scenario assembles a real contraption from the console, which needs no player:
//
//  * a `create:creative_motor` is the rotation source (default speed 16);
//  * both it and the `create:mechanical_bearing` default to `facing=north`
//    (`lib/src/manifest/blocks.g.dart`), and a bearing's shaft leaves through the side *opposite* its
//    `facing` (`lib/src/kinetics/block_data.dart:125`) while its structure is the block in front of
//    it — so along z the layout is structure, bearing, motor;
//  * a bearing that starts turning assembles the block in front of it
//    (`lib/src/contraptions/bearing/bearing_block_entities.dart:126`: `onSpeedChanged` queues the
//    assembly, `tick` performs it).
//
// One stone block is the whole contraption — the bearing's search starts at the block in front of it
// (`bearing_contraptions.dart:30`) and captures it without glue — which keeps the trace free of
// other plugin entities, so the assertion names this spawn unambiguously.
//
// The rig is placed inside one chunk of the client that watches (its own spawn column, read from the
// console: a console `tp` does not move a client's tracked chunks, so a scenario has to run where
// the client already is).
//
// Run it with (see example/create/README.md):
//
// ```sh
// PUMPKIN_E2E=1 PUMPKIN_BIN=<build>/pumpkin PUMPKIN_TESTER_BIN=<build>/pumpkin-tester \
//   puro dart test test/e2e/contraption_spawn_bundle_test.dart
// ```

@Tags(['e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'package:test/test.dart';

import '../support/pumpkin_lab.dart';
import '../support/pumpkin_trace.dart';

void main() {
  group(
    'a contraption reaches the client with its payload',
    skip: PumpkinLab.skipReason(),
    () {
      test('a bearing driven by a creative motor assembles', () async {
        final lab = await PumpkinLab.boot();
        addTearDown(lab.shutdown);

        final watcher = await lab.connect('Watcher');
        final stand = await lab.playerPosition('Watcher');
        // The rig lies along z from the anchor, so it starts at the chunk's own corner: bearing and
        // motor stay in the column the client tracks.
        final anchor = TracePos(stand.x & ~15, stand.y - 3, (stand.z & ~15) + 4);
        final bearing = TracePos(anchor.x, anchor.y, anchor.z + 1);
        final motor = TracePos(anchor.x, anchor.y, anchor.z + 2);

        await lab.server.placeBlock(anchor, 'minecraft:stone');
        await lab.server.placeBlock(bearing, 'create:mechanical_bearing');
        await lab.server.placeBlock(motor, 'create:creative_motor');
        await lab.server.sync();
        // Assembly is tick-driven: the bearing queues it when its speed changes and performs it on
        // a later tick.
        await lab.server.settle(const Duration(seconds: 2));
        await lab.server.sync();

        final trace = watcher.readTrace();
        final serverTrace = lab.server.readTrace();

        // The rig really was what the scenario meant, so a failure below is about the plugin and not
        // about the blocks this test placed.
        for (final (name, pos) in [('bearing', bearing), ('motor', motor)]) {
          expect(
            trace.stateAt(pos),
            isNotNull,
            reason:
                'the client was never told the $name block at $pos, so this run never assembled '
                'anything:\n${trace.describe()}\n\nserver tail:\n${_tail(lab.server.logLines)}',
          );
        }

        final spawns = [
          for (final spawn in trace.spawns)
            if (spawn.pos == anchor) spawn,
        ];
        expect(
          spawns,
          isNotEmpty,
          reason:
              'no entity was spawned at the bearing anchor $anchor: the contraption never '
              'assembled, or the client was never told about it.\n'
              'client trace:\n${trace.describe()}\n\n'
              'server tail:\n${_tail(lab.server.logLines)}',
        );

        final carrying = [
          for (final spawn in spawns)
            if (spawn.carriedPayload) spawn,
        ];
        expect(
          carrying,
          isNotEmpty,
          reason:
              'the contraption reached the client without its spawn payload in the same bundle, so '
              'a real client draws the entity but no contraption:\n'
              '${spawns.first.describe()}\n\nclient trace:\n${trace.describe()}',
        );

        final spawn = carrying.first;
        expect(
          spawn.bundledPayloads.first.channel,
          'neoforge:advanced_add_entity',
          reason:
              'the payload that travelled with the entity is not the channel the entity type was '
              'registered with: ${spawn.describe()}',
        );
        // The server enqueued the same thing to a connection, i.e. this is not a client-side
        // artefact, and nothing was dropped on the way out.
        expect(serverTrace.drops, isEmpty, reason: serverTrace.describe());
        expect(
          [
            for (final serverSpawn in serverTrace.spawns)
              if (serverSpawn.pos == anchor) serverSpawn,
          ],
          isNotEmpty,
          reason:
              'the client saw the contraption but the server trace has no spawn at $anchor:\n'
              '${serverTrace.describe()}',
        );
      });
    },
  );
}

String _tail(List<String> lines, [int count = 30]) =>
    (lines.length > count ? lines.sublist(lines.length - count) : lines).join('\n');