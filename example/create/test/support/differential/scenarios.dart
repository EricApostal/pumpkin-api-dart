// The rigs the parity suite and `tool/diff_servers.dart` share.
//
// A scenario is the whole of a parity test's *input*: the commands both arms are driven with, the
// box that is compared, and what the reference arm must show for the run to mean anything. Keeping
// them here, rather than in one test file each, is what makes "run the same rig on both servers"
// literal: `tool/diff_servers.dart --scenario fluid_tank` and
// `test/parity/fluid_tank_parity_test.dart` are the same rig, and a fix to a rig reaches both.
//
// A rig has to be built where the client already is: a server only tells a client about what it
// tracks, and the two servers put the world spawn at different heights, so every anchor is derived
// from the position each server reports for the client, and the comparison is anchored on it.

import '../pumpkin_trace.dart';
import 'game_server.dart';
import 'scenario.dart';
import 'trace_diff.dart';

/// The rig: a bearing driven by a creative motor, carrying one stone.
///
/// This is the shape of the user's replay, and it is built out of the console alone (no player has
/// to place anything):
///
///  * a `create:creative_motor` is the rotation source; it drives the block in front of it, so the
///    layout along z is structure, bearing, motor;
///  * a bearing assembles the block in front of it on a later tick than the one that starts it
///    turning, which is why the motor is placed last and the run then settles;
///  * the rig is built in the air directly above the client, because a server only tells a client
///    about what it tracks: a rig anywhere else produces no packets at all, and the two servers put
///    the world spawn at different heights, so the only position that means the same thing on both
///    is "where this server says the client is".
///
/// The one stone is deliberate: the bearing's search starts at the block in front of it and captures
/// that block without glue, so a plain stone floor (which the two worldgen implementations disagree
/// about) is never captured and the payload stays one block — a difference in the payload is then
/// about the plugin, not about the world.
Scenario contraptionScenario() => Scenario(
  name: 'contraption',
  description:
      'a mechanical bearing driven by a creative motor assembles one stone into a contraption',
  box: const RigBox(
    xMin: -1,
    xMax: 1,
    yMin: -2,
    yMax: 2,
    zMin: -2,
    zMax: 4,
  ),
  anchorOf: (player) => TracePos(player.x, player.y + 5, player.z),
  build: (anchor) {
    final bearing = TracePos(anchor.x, anchor.y, anchor.z + 1);
    final motor = TracePos(anchor.x, anchor.y, anchor.z + 2);
    return [
      // The contraption's content first, so the bearing has something to capture.
      ScenarioStep('setblock ${anchor.x} ${anchor.y} ${anchor.z} minecraft:stone'),
      ScenarioStep(
        'setblock ${bearing.x} ${bearing.y} ${bearing.z} '
        'create:mechanical_bearing[facing=north]',
      ),
      // Then the power: the bearing queues an assembly when its speed changes, and performs it on a
      // following tick.
      ScenarioStep(
        'setblock ${motor.x} ${motor.y} ${motor.z} '
        'create:creative_motor[facing=north]',
      ),
    ];
  },
  probes: (anchor) {
    final bearing = TracePos(anchor.x, anchor.y, anchor.z + 1);
    final motor = TracePos(anchor.x, anchor.y, anchor.z + 2);
    // A `setblock` in a far corner of the same column is the marker: the command runs only if the
    // block *is* the one the rig asked for, and the write is what lands in the console log (a
    // `say` would not). Each probe gets its own marker position, so "matched" cannot be another
    // probe's write.
    ScenarioProbe marker(TracePos at, String block, int index) => ScenarioProbe(
      'execute if block ${at.x} ${at.y} ${at.z} $block run '
      'setblock ${anchor.x} ${anchor.y + 30 + index} ${anchor.z} minecraft:redstone_block',
      expected: ConsoleSession.changedBlock,
    );
    return [
      marker(anchor, 'minecraft:stone', 0),
      marker(bearing, 'create:mechanical_bearing', 1),
      marker(motor, 'create:creative_motor', 2),
      // …and what each server says those block entities *are*, which is where a plugin's own
      // additions to a block entity's data show up next to the mod's.
      ScenarioProbe(
        'data get block ${bearing.x} ${bearing.y} ${bearing.z}',
        expected: RegExp('create:mechanical_bearing'),
      ),
      ScenarioProbe(
        'data get block ${motor.x} ${motor.y} ${motor.z}',
        expected: RegExp('create:creative_motor|create:motor'),
      ),
    ];
  },
  expected: ScenarioPrecondition.contraptionSpawned(),
);

/// The rig: two vertically stacked fluid tanks, which are one multiblock.
///
/// The lower tank becomes the controller (a `Height` of 2) and the upper one a part that points at
/// it (`Controller`), and both are rewritten so a client draws one tank. That merge is a block
/// entity's *client data*, so the whole of it is only visible from a client's side — a server-side
/// test can see the block entity and still miss that the client was never told.
///
/// Two blocks are placed in the air above the client for the same reason as the contraption rig,
/// and nothing else is touched, so a difference in the payload is about the tank and not about the
/// world underneath it.
Scenario fluidTankScenario() => Scenario(
  name: 'fluid_tank',
  description: 'two stacked fluid tanks merge into one controller and one part',
  box: const RigBox(
    xMin: -1,
    xMax: 1,
    yMin: -1,
    yMax: 2,
    zMin: -1,
    zMax: 1,
  ),
  anchorOf: (player) => TracePos(player.x, player.y + 4, player.z),
  build: (anchor) {
    final upper = TracePos(anchor.x, anchor.y + 1, anchor.z);
    return [
      ScenarioStep('setblock ${anchor.x} ${anchor.y} ${anchor.z} create:fluid_tank'),
      ScenarioStep('setblock ${upper.x} ${upper.y} ${upper.z} create:fluid_tank'),
    ];
  },
  probes: (anchor) {
    final upper = TracePos(anchor.x, anchor.y + 1, anchor.z);
    return [
      // The controller knows it is two tall; the part knows who controls it. Both are read from the
      // server that built them, so the report shows what each server believes the rig *is* next to
      // what each client was told.
      ScenarioProbe(
        'data get block ${anchor.x} ${anchor.y} ${anchor.z}',
        expected: RegExp('Height: 2'),
      ),
      ScenarioProbe(
        'data get block ${upper.x} ${upper.y} ${upper.z}',
        expected: RegExp('Controller'),
      ),
    ];
  },
  expected: const ScenarioPrecondition(
    'a block entity payload for the merged tank reached the client',
    _tankPayloadSeen,
  ),
);

/// The tank precondition: the client was told a block entity's data inside the rig.
bool _tankPayloadSeen(NormalisedTrace trace) => trace.events.any(
  (event) => event.kind == 'block_entity_data' && event.payloads.isNotEmpty,
);

/// No rig at all: the run is about the handshake, which happens before the world.
///
/// The scenario machinery still needs a position (the runner reads where the client is, so an arm
/// that never joined is a failure and not a silent zero), but nothing is built and nothing is
/// compared: the caller reads the two servers' declarations off the wire instead.
Scenario handshakeScenario() => Scenario(
  name: 'handshake',
  description: 'no rig: the NeoForge declaration each server negotiates',
  box: const RigBox.around(0),
  anchorOf: (player) => player,
  build: (_) => const [],
);

/// Every rig the tool and the parity tests know, by the name the CLI selects them by.
final Map<String, Scenario Function()> parityScenarios = {
  'handshake': handshakeScenario,
  'contraption': contraptionScenario,
  'fluid_tank': fluidTankScenario,
};
