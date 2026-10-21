// A scenario: the commands both arms are driven with, and the geometry the comparison is anchored
// on.
//
// A scenario is a *function of the anchor*, not a fixed list, because the rig has to be built where
// the client is: both servers only tell a client about the chunks it tracks, and the two worldgen
// implementations put the spawn at different heights, so the same rig sits at different absolute
// coordinates on the two arms. The anchor (read from each server's own console) is what makes the
// two runs the *same* run, and the box is what keeps the comparison to the rig instead of to the
// world.
//
// The commands are the vanilla ones, because that is the language both servers already speak: the
// plugin implements the same `setblock`/`fill`/`forceload` commands with the same replies, so one
// text drives both arms and a difference in the *result* is a difference in the game, not in the
// harness.

import '../pumpkin_trace.dart';
import 'game_server.dart';
import 'trace_diff.dart';

/// One console command of a scenario, and the reply that says it ran.
final class ScenarioStep {
  const ScenarioStep(this.command, {this.success, this.retryWhile});

  /// The command line, as typed into the server's console.
  final String command;

  /// The reply that means it landed. Defaults to a block write's reply, the common case.
  final Pattern? success;

  /// The reply that means "not yet" (an unloaded chunk), and is worth retrying.
  final Pattern? retryWhile;

  @override
  String toString() => command;
}

/// A rig: where to build it, what to build, and how to read it back.
final class Scenario {
  const Scenario({
    required this.name,
    required this.description,
    required this.box,
    required this.anchorOf,
    required this.build,
    this.probes = _noProbes,
    this.expected,
  });

  static List<ScenarioProbe> _noProbes(TracePos anchor) => const [];

  /// The name the CLI selects this scenario by.
  final String name;

  /// One paragraph: what the rig is and what it is for.
  final String description;

  /// The region compared, in anchor-relative coordinates.
  final RigBox box;

  /// Where the rig goes, given where the client's player is.
  final TracePos Function(TracePos player) anchorOf;

  /// The commands that build the rig.
  final List<ScenarioStep> Function(TracePos anchor) build;

  /// Commands run after the rig, whose reply is printed as ground truth.
  ///
  /// This is where a scenario pins what a trace cannot: a client-bound block *state id* means
  /// nothing across two servers, so the scenario asks each server what the block at a rig position
  /// actually *is* and the report shows both answers — the same question asked of both servers, so
  /// the two answers can be read side by side.
  final List<ScenarioProbe> Function(TracePos anchor) probes;

  /// What the reference arm must show for the run to mean anything (asserted, with a message,
  /// before any difference is reported): a scenario that did not assemble on the server that works
  /// has nothing to compare.
  final ScenarioPrecondition? expected;
}

/// One question a scenario asks a server, and the reply that means "yes".
///
/// A plain command's reply is a *sentence*, and two servers word their sentences differently — so a
/// probe counts as answered when the reply matches [expected], which is what makes the two answers
/// comparable instead of merely similar.
final class ScenarioProbe {
  const ScenarioProbe(this.command, {required this.expected});

  final String command;

  /// The reply that means the question was answered yes.
  final Pattern expected;

  /// Reads the reply: `matched`, `NOT matched`, or `no reply`.
  ///
  /// The reply itself is quoted (capped), because "did not match" is useless without what the
  /// server actually said.
  String read(List<String> reply) {
    if (reply.isEmpty) return 'no reply';
    final text = _quoted(reply.map(_cleanReply).join(' | '));
    return expected.allMatches(reply.join(' | ')).isEmpty
        ? 'NOT matched — $text'
        : 'matched — $text';
  }

  static String _quoted(String text, {int limit = 300}) =>
      text.length <= limit ? text : '${text.substring(0, limit)}… (${text.length} chars)';
}

/// A cheap sanity check on the reference arm's own trace.
final class ScenarioPrecondition {
  const ScenarioPrecondition(this.description, this.test);

  final String description;

  /// Whether [trace] (already normalised) shows what the scenario claims to produce.
  final bool Function(NormalisedTrace trace) test;

  /// The precondition a contraption scenario is expected to satisfy: an entity was spawned inside
  /// the rig, carrying its payload in the same bundle.
  static ScenarioPrecondition contraptionSpawned() => ScenarioPrecondition(
    'an entity was spawned inside the rig with its payload in the same bundle',
    (trace) => trace.events.any(
      (event) => event.kind == 'add_entity' && event.value.contains('bundle=['),
    ),
  );
}

/// Runs a scenario against one arm's console.
Future<void> runScenario(
  ConsoleSession console,
  Scenario scenario,
  TracePos anchor,
) async {
  for (final step in scenario.build(anchor)) {
    await console.until(
      step.command,
      step.success ?? ConsoleSession.changedBlock,
      retryWhile: step.retryWhile ?? ConsoleSession.positionNotLoaded,
    );
  }
  await console.sync();
}

/// The ground-truth answers a scenario's probes receive, in order.
Future<List<String>> runProbes(
  ConsoleSession console,
  Scenario scenario,
  TracePos anchor,
) async {
  final answers = <String>[];
  for (final probe in scenario.probes(anchor)) {
    final reply = await console.outputOf(probe.command);
    answers.add(
      '${probe.command} → ${probe.read(reply)}'
      '${reply.isEmpty ? '' : ' (${reply.map(_cleanReply).join(' | ')})'}',
    );
  }
  return answers;
}

/// The vanilla reply sentences carry the log's own prefix; the report only wants the sentence.
String _cleanReply(String line) {
  final marker = RegExp(r'System chat: |\]: ');
  var end = -1;
  for (final match in marker.allMatches(line)) {
    end = match.end;
  }
  return end < 0 ? line.trim() : line.substring(end).trim();
}