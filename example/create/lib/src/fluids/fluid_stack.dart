// The fluid stack of the fluids module (pure): Create's `FluidStack`, an immutable value. The
// host's `FluidStack` (fluid, amount, data) converts with `host_fluids.dart`.
import '../common/pos.dart' show Pos;

/// The keys of the fluids the module knows by name.
abstract final class FluidKeys {
  static const String water = 'minecraft:water';
  static const String lava = 'minecraft:lava';
  static const String milk = 'minecraft:milk';
  static const String potion = 'create:potion';
  static const String tea = 'create:tea';
  static const String honey = 'create:honey';
  static const String chocolate = 'create:chocolate';
  static const String flowingPotion = 'create:flowing_potion';
  static const String flowingTea = 'create:flowing_tea';
  static const String flowingHoney = 'create:flowing_honey';
  static const String flowingChocolate = 'create:flowing_chocolate';

  /// The flowing variant of a still fluid key (`FluidHelper.convertToFlowing`).
  static String flowing(String still) => switch (still) {
    water => 'minecraft:flowing_water',
    lava => 'minecraft:flowing_lava',
    _ => still.startsWith('create:') && !still.startsWith('create:flowing_')
        ? 'create:flowing_${still.substring(7)}'
        : still,
  };

  /// The still fluid of a fluid key (`FluidHelper.convertToStill`).
  static String still(String key) => switch (key) {
    'minecraft:flowing_water' => water,
    'minecraft:flowing_lava' => lava,
    _ => key.startsWith('create:flowing_') ? 'create:${key.substring(15)}' : key,
  };

  /// Whether the fluid is a flowing variant.
  static bool isFlowing(String key) => still(key) != key;
}

/// An amount of a fluid in millibuckets. [data] is the plugin data that travels with the fluid
/// (the potion type of a `create:potion`); two stacks of the same fluid with different data are
/// different fluids for tanks and pipes (`FluidStack.isSameFluidSameComponents`).
final class FStack {
  /// The fluid key (`minecraft:water`); empty for no fluid.
  final String fluid;
  final int amount;
  final List<int>? data;

  const FStack(this.fluid, this.amount, [this.data]);

  /// `FluidStack.EMPTY`.
  static const FStack empty = FStack('', 0);

  bool get isEmpty => fluid.isEmpty || amount <= 0;
  bool get isNotEmpty => !isEmpty;

  /// `copyWithAmount`: [empty] for an amount of 0 or less.
  FStack withAmount(int newAmount) => isEmpty || newAmount <= 0 ? empty : FStack(fluid, newAmount, data);

  /// `FluidStack.grow`.
  FStack grow(int by) => withAmount(amount + by);

  /// `FluidStack.shrink`.
  FStack shrink(int by) => withAmount(amount - by);

  /// `FluidStack.isSameFluidSameComponents`: both empty, or the same fluid with the same data.
  bool isSameFluid(FStack other) {
    if (isEmpty || other.isEmpty) return isEmpty && other.isEmpty;
    return fluid == other.fluid && dataEquals(data, other.data);
  }

  /// `Fluid.isSame` on the still fluids, ignoring data.
  bool isSameType(FStack other) => isNotEmpty && other.isNotEmpty && FluidKeys.still(fluid) == FluidKeys.still(other.fluid);

  static bool dataEquals(List<int>? a, List<int>? b) {
    if (a == null || a.isEmpty) return b == null || b.isEmpty;
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is FStack && (isEmpty && other.isEmpty || other.fluid == fluid && other.amount == amount && dataEquals(data, other.data));

  @override
  int get hashCode => isEmpty ? 0 : Object.hash(fluid, amount, Object.hashAll(data ?? const <int>[]));

  @override
  String toString() => isEmpty ? 'FStack.empty' : 'FStack($fluid x$amount${data == null ? '' : ' +data'})';
}

/// A position as a map key (`world:x,y,z`).
String posKey(Pos p) => '${p.$1},${p.$2},${p.$3}';
