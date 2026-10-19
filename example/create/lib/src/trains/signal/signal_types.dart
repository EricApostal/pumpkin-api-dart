// The enums of the signal block and its block entity (pure): `SignalBlock.SignalType`,
// `SignalBlockEntity.SignalState` and `SignalBlockEntity.OverlayState`. The constants keep the Java
// names because `name()` is what the saved data and the client NBT carry.
// ignore_for_file: constant_identifier_names

/// `SignalBlock.SignalType`.
enum SignalType {
  ENTRY_SIGNAL,
  CROSS_SIGNAL;

  /// `getSerializedName()` (`Lang.asId(name())`): the block state value.
  String get serializedName => name.toLowerCase();

  /// The type with this block state value.
  static SignalType? bySerializedName(String? value) {
    for (final t in values) {
      if (t.serializedName == value) return t;
    }
    return null;
  }
}

/// `SignalBlockEntity.OverlayState`.
enum OverlayState { RENDER, SKIP, DUAL }

/// `SignalBlockEntity.SignalState`.
enum SignalState {
  RED,
  YELLOW,
  GREEN,
  INVALID;

  bool isRedLight(double renderTime) => this == RED || this == INVALID && renderTime % 40 < 3;

  bool isYellowLight(double renderTime) => this == YELLOW;

  bool isGreenLight(double renderTime) => this == GREEN;
}

/// `NBTHelper.readEnum` of the 26.x port: the constant with the saved name, else the first one.
E readEnumByName<E extends Enum>(String name, List<E> values) {
  for (final e in values) {
    if (e.name == name) return e;
  }
  return values.first;
}
