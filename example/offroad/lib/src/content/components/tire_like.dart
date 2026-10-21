// `TireLike`: the data of a wheel, carried by the `offroad:tire` component and
// read by the wheel mount, the borehead bearing and the contraption actors.
//
// The presets are the ones `TireLike` defines in Java, with their numbers.
//
// Pure: no host imports.
//
// Java: `content/components/TireLike.java`, `content/items/tire/TireItem.java`
// ignore_for_file: implementation_imports
import 'package:create/src/common/common.dart' show Vec3, vec3Zero;
import 'package:create/src/core/nbt.dart' show NbtKind, NbtValue;
import 'package:pumpkin_api/pumpkin_api_core.dart' show ComponentCodec;

import '../../index/offroad_ids.dart';

/// `TireLike(float radius, Vec3 rotation, Vec3 offset, Optional<Identifier> model, float minimumFriction)`
/// (`TireLike.java:14`).
final class TireLike {
  /// `radius`: the wheel's radius in blocks.
  final double radius;

  /// `rotation`: how the wheel model is turned, in degrees.
  final Vec3 rotation;

  /// `offset`: where the wheel sits relative to the mount, in blocks.
  final Vec3 offset;

  /// `model`: the partial model of the wheel, `null` for a bare tire.
  final String? model;

  /// `minimumFriction`: the friction the wheel never drops below.
  final double minimumFriction;

  const TireLike({
    required this.radius,
    this.rotation = const (90.0, 0.0, 0.0),
    this.offset = const (0.0, 0.0, 0.0),
    this.model,
    this.minimumFriction = 0,
  });

  /// `TireLike.CODEC` (`TireLike.java:15-22`): the field names, and the defaults
  /// of the optional ones (`radius` 1, `rotation` (90, 0, 0), `offset` zero,
  /// `model` absent, `minimumFriction` 0).
  static TireLike fromMap(Map<String, Object?> map) => TireLike(
    radius: (map['radius'] as num?)?.toDouble() ?? 1,
    rotation: _vec(map['rotation']) ?? const (90.0, 0.0, 0.0),
    offset: _vec(map['offset']) ?? const (0.0, 0.0, 0.0),
    model: map['model'] as String?,
    minimumFriction: (map['minimumFriction'] as num?)?.toDouble() ?? 0,
  );

  static Vec3? _vec(Object? value) {
    if (value is! List || value.length != 3) return null;
    final x = value[0], y = value[1], z = value[2];
    if (x is! num || y is! num || z is! num) return null;
    return (x.toDouble(), y.toDouble(), z.toDouble());
  }

  /// The JSON form of the codec, with the Java field names.
  Map<String, Object?> toMap() => {
    'radius': radius,
    'rotation': [rotation.$1, rotation.$2, rotation.$3],
    'offset': [offset.$1, offset.$2, offset.$3],
    if (model != null) 'model': model,
    'minimumFriction': minimumFriction,
  };

  /// The value as the network NBT tag `TireLike.CODEC` produces.
  ///
  /// `DataComponentType.Builder.persistent(Codec)` derives its stream codec with
  /// `ByteBufCodecs.fromCodec`, which writes the value as one unnamed network
  /// NBT tag (`OffroadDataComponents.java:14-15`).
  NbtValue toNbtValue() => NbtValue.compound({
    'radius': NbtValue.float(radius),
    'rotation': NbtValue.list([for (final v in [rotation.$1, rotation.$2, rotation.$3]) NbtValue.float(v)]),
    'offset': NbtValue.list([for (final v in [offset.$1, offset.$2, offset.$3]) NbtValue.float(v)]),
    if (model != null) 'model': NbtValue.string(model!),
    'minimumFriction': NbtValue.float(minimumFriction),
  });

  /// The value of an `offroad:tire` network NBT tag (`toNbtValue`).
  static TireLike fromNbtValue(NbtValue value) {
    final map = value.asCompound;
    Vec3? vec(String key) {
      final list = map[key];
      if (list == null || list.kind != NbtKind.list) return null;
      final parts = (list.value as List).cast<NbtValue>();
      if (parts.length != 3) return null;
      double f(NbtValue v) => (v.value as num).toDouble();
      return (f(parts[0]), f(parts[1]), f(parts[2]));
    }

    final model = map['model'];
    return TireLike(
      radius: (map['radius']?.value as num?)?.toDouble() ?? 1,
      rotation: vec('rotation') ?? const (90.0, 0.0, 0.0),
      offset: vec('offset') ?? const (0.0, 0.0, 0.0),
      model: model == null ? null : model.value as String,
      minimumFriction: (map['minimumFriction']?.value as num?)?.toDouble() ?? 0,
    );
  }

  // -- The presets (`TireLike.java:46-56`) -------------------------------------

  /// `SMALL_TIRE`: 12/16 (`TireLike.java:46`).
  static const TireLike smallTire = TireLike(radius: 12 / 16);

  /// `TIRE`: 15.5/16 (`TireLike.java:47`).
  static const TireLike tire = TireLike(radius: 15.5 / 16);

  /// `LARGE_TIRE`: 1 + 4/16 (`TireLike.java:48`).
  static const TireLike largeTire = TireLike(radius: 1 + 4 / 16);

  /// `MONSTROUS_TIRE`: 2 (`TireLike.java:49`).
  static const TireLike monstrousTire = TireLike(radius: 2);

  /// `CRUSHING_WHEEL`: 1 (`TireLike.java:50`).
  static const TireLike crushingWheel = TireLike(radius: 1);

  /// `WATER_WHEEL`: 1 (`TireLike.java:51`).
  static const TireLike waterWheel = TireLike(radius: 1);

  /// `FLYWHEEL`: 1 + 6/16 (`TireLike.java:52`).
  static const TireLike flywheel = TireLike(radius: 1 + 6 / 16);

  /// `LARGE_WATER_WHEEL`: 2 + 7/16 (`TireLike.java:53`).
  static const TireLike largeWaterWheel = TireLike(radius: 2 + 7 / 16);

  /// `ROCKCUTTING_WHEEL`: radius 0.8, the wheel model of the rock cutter
  /// (`TireLike.java:54`).
  static const TireLike rockCuttingWheel = TireLike(
    radius: 0.8,
    rotation: (90.0, 0.0, 0.0),
    offset: vec3Zero,
    model: 'offroad:block/rockcutting_wheel/wheel',
  );

  /// `MECHANICAL_ROLLER`: radius 0.7, the roller's wheel model, half a block
  /// below its block (`TireLike.java:55`).
  static const TireLike mechanicalRoller = TireLike(
    radius: 0.7,
    rotation: (0.0, 0.0, 0.0),
    offset: (0.0, -0.5, 0.0),
    model: 'create:block/mechanical_roller/wheel',
  );

  /// The presets of the four tire items, by item key (`OffroadItems.java:20,30,
  /// 40,56`).
  static const Map<String, TireLike> tireItemPresets = {
    OffroadIds.smallTire: smallTire,
    OffroadIds.tire: tire,
    OffroadIds.largeTire: largeTire,
    OffroadIds.monstrousTire: monstrousTire,
  };

  /// The preset of the item [key], `null` when it is not a tire item.
  static TireLike? forItem(String key) => tireItemPresets[key];

  @override
  bool operator ==(Object other) =>
      other is TireLike &&
      other.radius == radius &&
      other.rotation == rotation &&
      other.offset == offset &&
      other.model == model &&
      other.minimumFriction == minimumFriction;

  @override
  int get hashCode => Object.hash(radius, rotation, offset, model, minimumFriction);

  @override
  String toString() => 'TireLike(radius: $radius, model: $model)';
}

/// `TireItem` (`content/items/tire/TireItem.java`).
///
/// The Java item only overrides `useOn` to tell the *client* that a tire cannot
/// be placed (`TireItem.java:18-26`); the server does what `Item` does, so the
/// port is the key of that message and no server behaviour.
abstract final class TireItem {
  /// The translation key of the placement error (`TireItem.java:22`).
  static const String placementErrorKey = 'item.offroad.tire.placement_error';
}

/// The component's network shape.
///
/// `OffroadDataComponents.java:14-15` registers the type with
/// `persistent(TireLike.CODEC)` only, so the network codec is the derived
/// `ByteBufCodecs.fromCodec`: one network NBT tag, the same shape
/// `TireLike.toNbtValue` writes.
const ComponentCodec tireComponentCodec = ComponentCodec.nbt;
