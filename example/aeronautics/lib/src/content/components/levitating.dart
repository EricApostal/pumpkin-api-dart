// The `aeronautics:levitating` data component: an item that cancels most of its
// own fall.
//
// Java: `content/components/Levitating`.
//
// ```java
// record Levitating(Float dragFraction, Optional<ParticleOptions> particle)
// ```
//
// The codec has defaults (`drag_fraction` 0.93, no particle), so a stack written
// with only one field reads back the same way it would in Java. The only
// `ParticleOptions` the mod puts in it is `LevititeSparkleParticleData`, whose
// codec is one colour int (`content/particle/LevititeSparkleParticleData.java`).
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart' show ComponentCodec;

/// `LevititeSparkleParticleData`: the colour a levitite sparkle is drawn in.
final class LevititeSparkleParticle {
  /// `AeroParticleTypes.LEVITITE_SPARKLE` (`aeronautics:levitite_sparkle`).
  static const String type = 'aeronautics:levitite_sparkle';

  /// `LEVITITE_GREEN`.
  static const int green = 9424022;

  /// `LEVITITE_PINK`.
  static const int pink = 15521489;

  /// The rgb colour.
  final int color;

  const LevititeSparkleParticle(this.color);

  Map<String, Object?> toJson() => {'type': type, 'color': color};

  static LevititeSparkleParticle? fromJson(Map<String, Object?> json) =>
      json['type'] == type ? LevititeSparkleParticle((json['color'] as num?)?.toInt() ?? green) : null;

  @override
  bool operator ==(Object other) => other is LevititeSparkleParticle && other.color == color;

  @override
  int get hashCode => color;

  @override
  String toString() => 'LevititeSparkleParticle($color)';
}

/// `Levitating`: how much of the fall is cancelled, and the particle trail.
final class Levitating {
  /// `drag_fraction`: the fraction of the fall velocity that is kept.
  final double dragFraction;

  /// The particle trail, or `null` for none.
  final LevititeSparkleParticle? particle;

  const Levitating(this.dragFraction, [this.particle]);

  /// `Levitating.DEFAULT`.
  static const Levitating defaultLevitating = Levitating(0.93);

  /// `Levitating.END_STONE`.
  static const Levitating endStone = Levitating(0.85);

  /// `Levitating.LEVITITE`: the green sparkle.
  static const Levitating levitite = Levitating(0.93, LevititeSparkleParticle(LevititeSparkleParticle.green));

  /// `Levitating.PEARLESCENT_LEVITITE`: the pink sparkle.
  static const Levitating pearlescentLevitite =
      Levitating(0.93, LevititeSparkleParticle(LevititeSparkleParticle.pink));

  /// The codec's default `drag_fraction`.
  static const double defaultDragFraction = 0.93;

  /// `Levitating.CODEC`.
  Map<String, Object?> toJson() => {
    'drag_fraction': dragFraction,
    if (particle != null) 'particle': particle!.toJson(),
  };

  /// Reads the codec's defaults for the fields the json leaves out.
  static Levitating fromJson(Map<String, Object?> json) {
    final particle = json['particle'];
    return Levitating(
      (json['drag_fraction'] as num?)?.toDouble() ?? defaultDragFraction,
      particle is Map ? LevititeSparkleParticle.fromJson(particle.cast<String, Object?>()) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Levitating && other.dragFraction == dragFraction && other.particle == particle;

  @override
  int get hashCode => Object.hash(dragFraction, particle);

  @override
  String toString() => 'Levitating($dragFraction, $particle)';
}

/// The component's network shape.
///
/// Java registers the type with `persistent(Levitating.CODEC)` only, so the
/// network codec is the derived `ByteBufCodecs.fromCodecWithRegistries`: one
/// network NBT tag.
const ComponentCodec levitatingComponentCodec = ComponentCodec.nbt;
