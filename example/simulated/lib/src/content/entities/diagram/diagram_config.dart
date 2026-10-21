// A diagram's settings, as the open/save payloads carry them.
//
// The stream codec is the interesting part; the Java order is
//
//   Identifier list (enabled force groups)   VarInt count, then strings
//   bool  displayCenterOfMass
//   bool  mergeForces
//   double yaw
//   double pitch
//   NoteConfigs:
//     BoundingBox3d noteScope                VarInt 6, then six doubles
//     double noteYaw
//     double notePitch
//     bool   active
//
// `SimCodecUtil.BOUNDING_BOX_3D_STREAM_CODEC` is
// `ByteBufCodecs.DOUBLE.apply(ByteBufCodecs.list(6))`, hence the count prefix.
//
// Pure: no host imports.
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
//
// Java: dev.simulated_team.simulated.content.entities.diagram.DiagramConfig
import 'package:pumpkin_api/pumpkin_api_core.dart';
import 'package:sable/sable.dart' show BoundingBox3d;

import '../../../network/sim_wire.dart';

/// `DiagramConfig.NoteConfigs`: a sticky note attached to the diagram.
final class NoteConfigs {
  /// The box the note points at, in the sub-level's local space.
  final BoundingBox3d noteScope;

  double noteYaw;
  double notePitch;
  bool active;

  NoteConfigs(this.noteScope, this.noteYaw, this.notePitch, this.active);

  /// `NoteConfigs.NOTE_CONFIG_STREAM_CODEC`.
  void write(PacketWriter w) {
    SimWire.writeBoundingBox3d(w, noteScope);
    w
      ..writeDouble(noteYaw)
      ..writeDouble(notePitch)
      ..writeBool(active);
  }

  /// The reader of [write].
  static NoteConfigs read(PacketReader r) =>
      NoteConfigs(SimWire.readBoundingBox3d(r), r.readDouble(), r.readDouble(), r.readBool());

  @override
  bool operator ==(Object other) =>
      other is NoteConfigs &&
      other.noteScope == noteScope &&
      other.noteYaw == noteYaw &&
      other.notePitch == notePitch &&
      other.active == active;

  @override
  int get hashCode => Object.hash(noteScope, noteYaw, notePitch, active);
}

/// `DiagramConfig`: which force groups the diagram draws, and how.
final class DiagramConfig {
  /// The force-group ids the player enabled (`simulated`/`sable` resource
  /// locations, e.g. `sable:gravity`).
  final List<String> enabledForceGroups;

  bool displayCenterOfMass;
  bool mergeForces;
  double yaw;
  double pitch;
  NoteConfigs noteConfig;

  DiagramConfig(
    this.enabledForceGroups,
    this.displayCenterOfMass,
    this.mergeForces,
    this.yaw,
    this.pitch,
    this.noteConfig,
  );

  /// `DiagramConfig.makeDefault(entity)`: the groups whose `defaultDisplayed()`
  /// is true, no centre of mass, no merge, and a note turned with the entity.
  ///
  /// [defaultDisplayedForceGroups] is the id list the force-group registry marks
  /// as displayed by default, in registry order.
  factory DiagramConfig.makeDefault({
    required Iterable<String> defaultDisplayedForceGroups,
    required double entityYRot,
    required double entityXRot,
  }) => DiagramConfig(
    List<String>.unmodifiable(defaultDisplayedForceGroups),
    false,
    false,
    -entityYRot,
    entityXRot,
    NoteConfigs(BoundingBox3d(), -entityYRot, entityXRot, false),
  );

  /// `DiagramConfig.STREAM_CODEC`.
  void write(PacketWriter w) {
    w.writeList(enabledForceGroups, (w, id) => w.writeString(id));
    w
      ..writeBool(displayCenterOfMass)
      ..writeBool(mergeForces)
      ..writeDouble(yaw)
      ..writeDouble(pitch);
    noteConfig.write(w);
  }

  /// The reader of [write].
  static DiagramConfig read(PacketReader r) {
    final groups = r.readList((r) => r.readString());
    final centerOfMass = r.readBool();
    final merge = r.readBool();
    final yaw = r.readDouble();
    final pitch = r.readDouble();
    return DiagramConfig(groups, centerOfMass, merge, yaw, pitch, NoteConfigs.read(r));
  }

  @override
  bool operator ==(Object other) =>
      other is DiagramConfig &&
      other.enabledForceGroups.length == enabledForceGroups.length &&
      _sameIds(other.enabledForceGroups, enabledForceGroups) &&
      other.displayCenterOfMass == displayCenterOfMass &&
      other.mergeForces == mergeForces &&
      other.yaw == yaw &&
      other.pitch == pitch &&
      other.noteConfig == noteConfig;

  static bool _sameIds(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(enabledForceGroups), displayCenterOfMass, mergeForces, yaw, pitch, noteConfig);
}
