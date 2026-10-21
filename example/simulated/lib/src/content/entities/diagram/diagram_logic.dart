// Building the diagram's data packet, and the per-player recording queue.
//
// `DiagramEntity.makeDiagramDataPacket` divides every recorded force by the
// physics time step (so the client sees a force, not an impulse), drops groups
// that recorded nothing, and *adds* gravity as a single force at the centre of
// mass — replacing any recorded gravity group.
//
// The queue is the part that decides who receives the next frame:
// `queueDiagramDataFor` adds a player to the sub-level's ticket (creating it
// once), and `postPhysicsTick` sends one frame to every player of every valid
// ticket, then drops the ticket and disables per-force tracking again.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.entities.diagram.DiagramEntity
//       …content.entities.diagram.DiagramRecordingTicket
import 'package:sable/sable.dart' show Vector3d;

import '../../../network/payloads/diagram_packets.dart';
import '../../../network/sim_wire.dart';

/// `ForceGroups.GRAVITY.getKey()`.
const String gravityForceGroup = 'sable:gravity';

/// `DiagramEntity.makeDiagramDataPacket`.
abstract final class DiagramForces {
  /// Builds the frame for one sub-level.
  ///
  /// [recordedForces] is the sub-level's queued force groups (id to the forces
  /// recorded this tick), [timeStep] is `1 / 20 / substepsPerTick`,
  /// [localGravity] is gravity transformed into the sub-level's local space and
  /// scaled by the mass, and [centerOfMass] is the point it acts on.
  static DiagramDataPacket build({
    required Map<String, List<PointForce>> recordedForces,
    required double timeStep,
    required double mass,
    required Vector3d centerOfMass,
    required Vector3d localGravity,
  }) {
    final sent = <String, List<PointForce>>{};
    recordedForces.forEach((groupId, forces) {
      if (forces.isEmpty) return;
      sent[groupId] = [
        for (final force in forces)
          PointForce(
            force.point,
            Vector3d(force.force.x / timeStep, force.force.y / timeStep, force.force.z / timeStep),
          ),
      ];
    });

    // `sentForces.put(GRAVITY, ...)`: gravity always replaces whatever the
    // sub-level recorded under that id.
    sent[gravityForceGroup] = [PointForce(centerOfMass, localGravity)];

    return DiagramDataPacket(sent, mass);
  }
}

/// One sub-level's pending diagram frame.
final class DiagramRecording {
  final String subLevel;

  /// The players that asked for a frame, in request order, without duplicates.
  final List<String> players = <String>[];

  DiagramRecording(this.subLevel);

  /// `ticket.isValid()`: a ticket with no players is dead.
  bool get isValid => players.isNotEmpty;

  /// Adds [player], ignoring a second request from the same one.
  void addPlayer(String player) {
    if (!players.contains(player)) players.add(player);
  }
}

/// `DiagramEntity.queuedDiagramRecordings`, per dimension.
final class DiagramRecordingQueue {
  final Map<String, Map<String, DiagramRecording>> _byDimension = <String, Map<String, DiagramRecording>>{};

  /// `queueDiagramDataFor(subLevel, player)`.
  void queue(String dimension, String subLevel, String player) {
    final recordings = _byDimension.putIfAbsent(dimension, () => <String, DiagramRecording>{});
    var recording = recordings[subLevel];
    if (recording != null && !recording.isValid) {
      recordings.remove(subLevel);
      recording = null;
    }
    recording ??= recordings[subLevel] = DiagramRecording(subLevel);
    recording.addPlayer(player);
  }

  /// `postPhysicsTick(level)`: the frames to send, and the sub-levels whose
  /// per-force tracking may be switched off again.
  ///
  /// Invalid tickets are dropped without a frame.
  List<({DiagramRecording recording, List<String> players})> drain(String dimension) {
    final recordings = _byDimension[dimension];
    if (recordings == null) return const [];
    final out = <({DiagramRecording recording, List<String> players})>[];
    for (final entry in recordings.entries.toList()) {
      recordings.remove(entry.key);
      final recording = entry.value;
      if (!recording.isValid) continue;
      out.add((recording: recording, players: List<String>.unmodifiable(recording.players)));
    }
    if (recordings.isEmpty) _byDimension.remove(dimension);
    return out;
  }

  /// The number of pending recordings in [dimension] (tests and diagnostics).
  int pending(String dimension) => _byDimension[dimension]?.length ?? 0;
}
