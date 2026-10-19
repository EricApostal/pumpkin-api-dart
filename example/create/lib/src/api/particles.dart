/// Option encoders for Create's particle types (the `StreamCodec` of each `ICustomParticleData`),
/// to pass as `options` of `World.spawnPluginParticleAt`. Pure.
///
/// ```dart
/// world.spawnPluginParticleAt('create:air_flow', pos, options: CreateParticleOptions.airFlow(x, y, z));
/// ```
library;

import 'package:pumpkin_api/pumpkin_api_core.dart';

abstract final class CreateParticleOptions {
  /// `AirFlowParticleData`: three ints (the fan position).
  static List<int> airFlow(int x, int y, int z) => PacketBuffer.encode((w) {
    w.writeInt(x);
    w.writeInt(y);
    w.writeInt(z);
  });

  /// `AirParticleData`: drag and speed floats.
  static List<int> air(double drag, double speed) => PacketBuffer.encode((w) {
    w.writeFloat(drag);
    w.writeFloat(speed);
  });

  /// `SteamJetParticleData`: one float.
  static List<int> steamJet(double speed) => PacketBuffer.encode((w) => w.writeFloat(speed));

  /// `RotationIndicatorParticleData`: color, speed, radius1, radius2, lifespan, axis ordinal (VarInt).
  static List<int> rotationIndicator({
    required int color,
    required double speed,
    required double radius1,
    required double radius2,
    required int lifeSpan,
    required int axisOrdinal,
  }) => PacketBuffer.encode((w) {
    w.writeInt(color);
    w.writeFloat(speed);
    w.writeFloat(radius1);
    w.writeFloat(radius2);
    w.writeInt(lifeSpan);
    w.writeVarInt(axisOrdinal);
  });

  /// `CubeParticleData`: r, g, b, scale floats, average age int, hot flag.
  static List<int> cube({
    required double r,
    required double g,
    required double b,
    required double scale,
    required int avgAge,
    required bool hot,
  }) => PacketBuffer.encode((w) {
    w.writeFloat(r);
    w.writeFloat(g);
    w.writeFloat(b);
    w.writeFloat(scale);
    w.writeInt(avgAge);
    w.writeBool(hot);
  });

  /// `FluidParticleData` (fluid_particle, basin_fluid, fluid_drip): a `FluidStack` in the
  /// network encoding, given as raw bytes (the fluid holder id, amount and component patch).
  static List<int> fluid(List<int> fluidStackBytes) => fluidStackBytes;

  /// Particle types without options (`wifi`, `soul`, `soul_base`, `soul_perimeter`,
  /// `soul_expanding_perimeter`).
  static const List<int> none = [];
}
