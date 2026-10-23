// `dev.ryanhcode.sable.physics.floating_block.FloatingBlockMaterial`: how a
// block behaves in a lifting gas / air current.
//
// The Java record is encoded on the wire with
// `ByteBufCodecs.fromCodec(CODEC)`, i.e. as a nameless network-NBT compound:
//
// ```json
// { "lift_strength": 1.0,                       // required, double
//   "prevent_self_lift": 1,                     // byte, omitted when false
//   "scale_with_pressure": 1,                   // byte, omitted when false
//   "scale_friction_with_gravity": 1,           // byte, omitted when false
//   "transition_speed": 0.0, ... }              // double, omitted when 0.0
// ```
//
// `optionalFieldOf` omits a field when it equals the default, so the encoder
// here does the same: the client decodes either form.
//
// Pure: no host imports.
// create's barrel re-exports the host bridge (wasm); the NBT model is pure.
// ignore_for_file: implementation_imports
import 'package:create/src/core/nbt.dart' show NbtValue;
import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../network/network_nbt.dart';

/// A floating block material.
final class FloatingBlockMaterial {
  /// Whether a block with this material does not lift itself.
  final bool preventSelfLift;

  /// Whether the lift scales with the local air pressure.
  final bool scaleWithPressure;

  /// Whether friction scales with gravity (`scale_friction_with_gravity`).
  final bool scaleWithGravity;

  /// The lift strength, in `kpg` of lift per block.
  final double liftStrength;

  /// How fast the block transitions between slow and fast friction.
  final double transitionSpeed;

  final double slowVerticalFriction;
  final double fastVerticalFriction;
  final double slowHorizontalFriction;
  final double fastHorizontalFriction;

  const FloatingBlockMaterial({
    required this.liftStrength,
    this.preventSelfLift = false,
    this.scaleWithPressure = false,
    this.scaleWithGravity = false,
    this.transitionSpeed = 0.0,
    this.slowVerticalFriction = 0.0,
    this.fastVerticalFriction = 0.0,
    this.slowHorizontalFriction = 0.0,
    this.fastHorizontalFriction = 0.0,
  });

  /// `FloatingBlockMaterial.CODEC`, as NBT.
  Map<String, NbtValue> toNbt() {
    final map = <String, NbtValue>{
      'lift_strength': NbtFields.doubleValue(liftStrength),
    };
    if (preventSelfLift) map['prevent_self_lift'] = NbtFields.boolean(true);
    if (scaleWithPressure) map['scale_with_pressure'] = NbtFields.boolean(true);
    if (scaleWithGravity) map['scale_friction_with_gravity'] = NbtFields.boolean(true);
    if (transitionSpeed != 0.0) map['transition_speed'] = NbtFields.doubleValue(transitionSpeed);
    if (slowVerticalFriction != 0.0) {
      map['slow_vertical_friction'] = NbtFields.doubleValue(slowVerticalFriction);
    }
    if (fastVerticalFriction != 0.0) {
      map['fast_vertical_friction'] = NbtFields.doubleValue(fastVerticalFriction);
    }
    if (slowHorizontalFriction != 0.0) {
      map['slow_horizontal_friction'] = NbtFields.doubleValue(slowHorizontalFriction);
    }
    if (fastHorizontalFriction != 0.0) {
      map['fast_horizontal_friction'] = NbtFields.doubleValue(fastHorizontalFriction);
    }
    return map;
  }

  /// `FloatingBlockMaterial.CODEC`, as NBT.
  factory FloatingBlockMaterial.fromNbt(Map<String, NbtValue> map) => FloatingBlockMaterial(
    preventSelfLift: NbtFields.boolOr(map, 'prevent_self_lift', false),
    scaleWithPressure: NbtFields.boolOr(map, 'scale_with_pressure', false),
    scaleWithGravity: NbtFields.boolOr(map, 'scale_friction_with_gravity', false),
    liftStrength: NbtFields.requireDouble(map, 'lift_strength'),
    transitionSpeed: NbtFields.doubleOr(map, 'transition_speed', 0.0),
    slowVerticalFriction: NbtFields.doubleOr(map, 'slow_vertical_friction', 0.0),
    fastVerticalFriction: NbtFields.doubleOr(map, 'fast_vertical_friction', 0.0),
    slowHorizontalFriction: NbtFields.doubleOr(map, 'slow_horizontal_friction', 0.0),
    fastHorizontalFriction: NbtFields.doubleOr(map, 'fast_horizontal_friction', 0.0),
  );

  /// `FloatingBlockMaterial.CODEC` applied to one `floating_materials/*.json`
  /// entry: Java loads the registry with `SimpleJsonResourceReloadListener`,
  /// i.e. the codec reads plain JSON. The keys are the codec's field names and
  /// `lift_strength` is required (`Codec.DOUBLE.fieldOf`), so a file without it
  /// is an error, exactly as it is in Java.
  factory FloatingBlockMaterial.fromJson(Map<Object?, Object?> json) {
    final lift = json['lift_strength'];
    if (lift is! num) {
      throw FormatException('floating material has no numeric lift_strength: $json');
    }
    double doubleOr(String key) {
      final value = json[key];
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      throw FormatException('floating material field "$key" is not a number: $value');
    }

    return FloatingBlockMaterial(
      preventSelfLift: json['prevent_self_lift'] == true,
      scaleWithPressure: json['scale_with_pressure'] == true,
      scaleWithGravity: json['scale_friction_with_gravity'] == true,
      liftStrength: lift.toDouble(),
      transitionSpeed: doubleOr('transition_speed'),
      slowVerticalFriction: doubleOr('slow_vertical_friction'),
      fastVerticalFriction: doubleOr('fast_vertical_friction'),
      slowHorizontalFriction: doubleOr('slow_horizontal_friction'),
      fastHorizontalFriction: doubleOr('fast_horizontal_friction'),
    );
  }

  /// The payload-body encoding: the NBT root compound.
  void write(PacketWriter buf) => NetworkNbtMap.write(buf, toNbt());

  /// The payload-body decoding.
  static FloatingBlockMaterial read(PacketReader buf) => FloatingBlockMaterial.fromNbt(NetworkNbtMap.read(buf));

  FloatingBlockMaterial copyWith({
    bool? preventSelfLift,
    bool? scaleWithPressure,
    bool? scaleWithGravity,
    double? liftStrength,
    double? transitionSpeed,
    double? slowVerticalFriction,
    double? fastVerticalFriction,
    double? slowHorizontalFriction,
    double? fastHorizontalFriction,
  }) => FloatingBlockMaterial(
    preventSelfLift: preventSelfLift ?? this.preventSelfLift,
    scaleWithPressure: scaleWithPressure ?? this.scaleWithPressure,
    scaleWithGravity: scaleWithGravity ?? this.scaleWithGravity,
    liftStrength: liftStrength ?? this.liftStrength,
    transitionSpeed: transitionSpeed ?? this.transitionSpeed,
    slowVerticalFriction: slowVerticalFriction ?? this.slowVerticalFriction,
    fastVerticalFriction: fastVerticalFriction ?? this.fastVerticalFriction,
    slowHorizontalFriction: slowHorizontalFriction ?? this.slowHorizontalFriction,
    fastHorizontalFriction: fastHorizontalFriction ?? this.fastHorizontalFriction,
  );

  @override
  bool operator ==(Object other) =>
      other is FloatingBlockMaterial &&
      other.preventSelfLift == preventSelfLift &&
      other.scaleWithPressure == scaleWithPressure &&
      other.scaleWithGravity == scaleWithGravity &&
      other.liftStrength == liftStrength &&
      other.transitionSpeed == transitionSpeed &&
      other.slowVerticalFriction == slowVerticalFriction &&
      other.fastVerticalFriction == fastVerticalFriction &&
      other.slowHorizontalFriction == slowHorizontalFriction &&
      other.fastHorizontalFriction == fastHorizontalFriction;

  @override
  int get hashCode => Object.hash(
    preventSelfLift,
    scaleWithPressure,
    scaleWithGravity,
    liftStrength,
    transitionSpeed,
    slowVerticalFriction,
    fastVerticalFriction,
    slowHorizontalFriction,
    fastHorizontalFriction,
  );

  @override
  String toString() =>
      'FloatingBlockMaterial[lift=$liftStrength, pressure=$scaleWithPressure, '
      'gravity=$scaleWithGravity, selfLift=$preventSelfLift]';
}

/// `FloatingBlockMaterialDataHandler`: the materials by id, filled from the
/// datapack on the server and from `floating_material` payloads on the client.
final class FloatingBlockMaterialDataHandler {
  /// The materials by id (`sable:air`, ...).
  static final Map<String, FloatingBlockMaterial> allMaterials = {};

  /// `addMaterial(id, material)`.
  static void addMaterial(String id, FloatingBlockMaterial material) => allMaterials[id] = material;

  /// Clears the table (datapack reload).
  static void clear() => allMaterials.clear();

  /// The material [id], or `null`.
  static FloatingBlockMaterial? material(String id) => allMaterials[id];
}
