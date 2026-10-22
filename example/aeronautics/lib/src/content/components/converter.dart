// The `aeronautics:converter` data component: a dropped item that turns into
// another item after a delay.
//
// Java: `content/components/Converter`.
//
// ```java
// record Converter(ItemStack item, int ticks, Optional<Identifier> sound,
//                  Optional<Identifier> particle)
// ```
//
// The music disc is the only user: a dropped `music_disc_cloud_skipper` carries
// `Converter.cloudSkipper()` (60 ticks, the transform sound, white smoke), and
// the item entity tick rewrites the stack once the counter reaches zero.
//
// Pure: no host imports.
import 'package:pumpkin_api/pumpkin_api_core.dart' show ComponentCodec;

/// `Converter`: the item to become, and how long is left.
final class Converter {
  /// The item key the stack becomes, `null` for an empty stack.
  final String? item;

  /// Ticks left; the conversion happens when it reaches 0.
  final int ticks;

  /// The sound played on conversion (`aeronautics:item.cloud_skipper_transform`).
  final String? sound;

  /// The particle burst on conversion (`minecraft:white_smoke`).
  final String? particle;

  const Converter(this.item, this.ticks, {this.sound, this.particle});

  /// `Converter.cloudSkipper()`: the music disc turns into itself after three
  /// seconds.
  ///
  /// The sound is `AeroSoundEvents.CLOUD_SKIPPER_TRANSFORM.id()`
  /// (`Converter.java:31-33`), which `SoundEventRegistry.create` builds from the
  /// raw name `"item.cloud_skipper_transform"`
  /// (`index/AeroSoundEvents.java:86`) — `aeronautics:item.cloud_skipper_transform`,
  /// not the bare `aeronautics:cloud_skipper_transform` this used to play.
  static const Converter cloudSkipper = Converter(
    'aeronautics:music_disc_cloud_skipper',
    60,
    sound: 'aeronautics:item.cloud_skipper_transform',
    particle: 'minecraft:white_smoke',
  );

  /// `new Converter(converter, ticks)`: the same conversion with another counter.
  Converter withTicks(int ticks) => Converter(item, ticks, sound: sound, particle: particle);

  /// The json the persistent codec writes.
  Map<String, Object?> toJson() => {
    if (item != null) 'item': {'id': item, 'count': 1},
    'ticks': ticks,
    if (sound != null) 'sound': sound,
    if (particle != null) 'particle': particle,
  };

  /// `Converter.CODEC`: `item` and `ticks` are required, the other two optional.
  static Converter fromJson(Map<String, Object?> json) {
    final item = json['item'];
    return Converter(
      item is Map ? item['id'] as String? : item as String?,
      (json['ticks'] as num?)?.toInt() ?? 0,
      sound: json['sound'] as String?,
      particle: json['particle'] as String?,
    );
  }

  /// What one tick of an item entity carrying this component does.
  ///
  /// Returns `null` while the counter still runs (the caller writes
  /// [next] back), and the conversion once it reaches zero.
  ConverterTick tick() {
    if (item == null || item!.isEmpty) return const ConverterTick.nothing();
    if (ticks > 0) return ConverterTick.counting(withTicks(ticks - 1));
    return ConverterTick.convert(this);
  }

  @override
  String toString() => 'Converter($item, $ticks)';
}

/// The outcome of [Converter.tick].
final class ConverterTick {
  /// The component to store, or `null` when the stack keeps its component.
  final Converter? next;

  /// The conversion to run, or `null` when the counter is still running.
  final Converter? converted;

  const ConverterTick.counting(Converter this.next) : converted = null;
  const ConverterTick.convert(Converter this.converted) : next = null;
  const ConverterTick.nothing()
    : next = null,
      converted = null;

  /// Whether the counter advanced.
  bool get isCounting => next != null;

  /// Whether the stack converts this tick.
  bool get isConverting => converted != null;
}

/// The component's network shape: `persistent(Converter.CODEC)` only, so the
/// derived network codec is one network NBT tag.
const ComponentCodec converterComponentCodec = ComponentCodec.nbt;
