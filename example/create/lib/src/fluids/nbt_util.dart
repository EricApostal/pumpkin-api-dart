// Typed reads of `NbtValue` compounds (pure) and the NBT form of a fluid stack
// (`TransferUtil.saveFluid` / `parseFluid`).
import '../core/nbt.dart';
import 'fluid_stack.dart';
import 'potion_data.dart';

/// Reads a compound like `CompoundTag.getXxxOr`: absent or mistyped values are `null`.
extension NbtCompoundRead on Map<String, NbtValue> {
  bool has(String key) => containsKey(key);

  int? readInt(String key) {
    final v = this[key];
    if (v == null) return null;
    return switch (v.kind) {
      NbtKind.byte ||
      NbtKind.short ||
      NbtKind.int ||
      NbtKind.long => v.value as int,
      NbtKind.float || NbtKind.double => (v.value as double).toInt(),
      _ => null,
    };
  }

  double? readDouble(String key) {
    final v = this[key];
    if (v == null) return null;
    return switch (v.kind) {
      NbtKind.byte ||
      NbtKind.short ||
      NbtKind.int ||
      NbtKind.long => (v.value as int).toDouble(),
      NbtKind.float || NbtKind.double => v.value as double,
      _ => null,
    };
  }

  bool readBool(String key, {bool or = false}) {
    final v = readInt(key);
    return v == null ? or : v != 0;
  }

  String? readString(String key) {
    final v = this[key];
    return v != null && v.kind == NbtKind.string ? v.value as String : null;
  }

  Map<String, NbtValue>? readCompound(String key) {
    final v = this[key];
    return v != null && v.kind == NbtKind.compound ? v.asCompound : null;
  }

  List<NbtValue>? readList(String key) {
    final v = this[key];
    return v != null && v.kind == NbtKind.list
        ? v.value as List<NbtValue>
        : null;
  }

  List<int>? readIntArray(String key) {
    final v = this[key];
    return v != null && v.kind == NbtKind.intArray
        ? v.value as List<int>
        : null;
  }
}

/// A position as an int array (`BlockPos.CODEC`).
NbtValue posToNbt((int, int, int) p) => NbtValue.intArray([p.$1, p.$2, p.$3]);

(int, int, int)? posFromNbt(NbtValue? v) {
  if (v == null) return null;
  if (v.kind == NbtKind.intArray) {
    final a = v.value as List<int>;
    if (a.length >= 3) return (a[0], a[1], a[2]);
  }
  if (v.kind == NbtKind.compound) {
    final c = v.asCompound;
    return (c.readInt('X') ?? 0, c.readInt('Y') ?? 0, c.readInt('Z') ?? 0);
  }
  return null;
}

/// The NBT of a fluid stack: `{id, amount, components}`; empty for an empty stack.
abstract final class FluidNbt {
  static NbtValue write(FStack stack) {
    if (stack.isEmpty) return NbtValue.emptyCompound();
    final tag = <String, NbtValue>{
      'id': NbtValue.string(stack.fluid),
      'amount': NbtValue.int32(stack.amount),
    };
    final potion = PotionFluidData.decode(stack.data);
    if (potion != null)
      tag['components'] = NbtValue.compound(potion.toComponents());
    return NbtValue.compound(tag);
  }

  static FStack read(NbtValue? value) {
    if (value == null || value.kind != NbtKind.compound) return FStack.empty;
    final tag = value.asCompound;
    final id = tag.readString('id') ?? tag.readString('FluidName');
    final amount = tag.readInt('amount') ?? tag.readInt('Amount') ?? 0;
    if (id == null || id.isEmpty || id == 'minecraft:empty' || amount <= 0)
      return FStack.empty;
    List<int>? data;
    final components = tag.readCompound('components');
    if (components != null)
      data = PotionFluidData.fromComponents(components)?.encode();
    return FStack(id, amount, data);
  }
}

/// The NBT of a `CreateFluidTank` (`CreateFluidTank.writeToNBT` / `readFromNBT`): the fluid
/// stack under `Fluid`; an empty tank is an empty compound (the key is omitted).
NbtValue fluidTankNbt(FStack stack) => stack.isEmpty
    ? NbtValue.emptyCompound()
    : NbtValue.compound({'Fluid': FluidNbt.write(stack)});

FStack readFluidTankNbt(NbtValue? value) {
  final compound = value != null && value.kind == NbtKind.compound
      ? value.asCompound
      : null;
  return FluidNbt.read(compound?['Fluid']);
}

/// One `SmartFluidTankBehaviour.TankSegment`: `{TankContent, Level}` (`TankSegment.writeNBT`).
/// [level] defaults to the fill fraction, which is what the client animates towards; the port
/// does not keep the per-tank `LerpedFloat`, so the steady value is written.
NbtValue tankSegmentNbt(FStack stack, int capacity, {double? level}) {
  final fill = capacity <= 0
      ? 0.0
      : (stack.amount / capacity).clamp(0.0, 1.0).toDouble();
  final value = (level ?? fill).toDouble();
  return NbtValue.compound({
    'TankContent': fluidTankNbt(stack),
    'Level': NbtValue.compound({
      'Speed': NbtValue.float(0),
      'Target': NbtValue.float(value),
      'Value': NbtValue.float(value),
    }),
  });
}

FStack readTankSegmentNbt(NbtValue? value) {
  final compound = value != null && value.kind == NbtKind.compound
      ? value.asCompound
      : null;
  return readFluidTankNbt(compound?['TankContent']);
}

/// A `SmartFluidTankBehaviour` list: one `TankSegment` per tank under `InputTanks` / `OutputTanks`
/// or `Tanks`.
NbtValue tankSegmentListNbt(List<FStack> stacks, List<int> capacities) =>
    NbtValue.list([
      for (var i = 0; i < stacks.length; i++)
        tankSegmentNbt(stacks[i], i < capacities.length ? capacities[i] : 0),
    ]);
