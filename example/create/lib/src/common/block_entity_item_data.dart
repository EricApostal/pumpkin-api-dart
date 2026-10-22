// The item data of a block whose block entity survives break -> place (pure: no host bindings,
// so the shaping is testable on the VM; the interceptors and the block hooks are in
// `block_entity_item_data_host.dart`).
//
// The layout is Java's:
//  * a block entity's saved NBT travels on the item in the vanilla `minecraft:block_entity_data`
//    component (`BlockItem.setBlockEntityData`; that is also what vanilla's pick-block writes with
//    `saveCustomOnly`), at the top level of the component's compound - the tank's case;
//  * the mod's own components travel as themselves (`SchematicannonBlockEntity
//    .collectImplicitComponents` sets `create:schematicannon_options`).
//
// The way *in* differs per block:
//  * `FluidTankItem.place` strips the multiblock keys (`Luminosity`, `Size`, `Height`,
//    `Controller`, `LastKnownPos`) and clamps `TankContent` to one block's capacity, so a tank
//    broken as part of a multiblock comes back as a single tank. The stripped keys are the ones a
//    fresh block entity writes itself: vanilla's placement merges the item's NBT *over* the block
//    entity's own saved NBT (`TypedEntityData.loadInto`), so dropping them makes the fresh
//    geometry win, and clamping keeps the fluid inside that geometry.
//  * `SchematicannonBlockEntity.applyImplicitComponents` takes the options component, or
//    `SchematicannonOptions(2, true, false)` when the item has none.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api_core.dart';

import '../core/nbt.dart';
import '../fluids/nbt_util.dart';
import '../schematics/schematic_stack.dart' as cannon_stack;

/// `DataComponents.BLOCK_ENTITY_DATA`: the saved NBT of a block entity on its item.
const String blockEntityDataComponent = 'minecraft:block_entity_data';

/// `AllDataComponents.SCHEMATICANNON_OPTIONS`.
const String cannonOptionsComponent = 'create:schematicannon_options';

/// The cannon options an item without [`cannonOptionsComponent`] places
/// (`SchematicannonBlockEntity.applyImplicitComponents`'s default).
const ({int replaceMode, bool skipMissing, bool replaceBlockEntities}) defaultCannonOptions = (
  replaceMode: 2,
  skipMissing: true,
  replaceBlockEntities: false,
);

/// The shaping of the item data both blocks share.
abstract final class BlockEntityItemData {
  /// `FluidTankItem.place`: the saved keys the item must not carry back into a fresh tank, so
  /// the fresh block entity's own geometry (which vanilla merges the item's NBT over) wins.
  static const List<String> tankStrippedKeys = [
    'Luminosity',
    'Size',
    'Height',
    'Controller',
    'LastKnownPos',
  ];

  /// `FluidTankItem.place`: [itemData] with [tankStrippedKeys] removed and the `TankContent`
  /// fluid clamped to one block's capacity
  /// (`Math.min(FluidTankBlockEntity.getCapacityMultiplier(), fluid.getAmount())`).
  ///
  /// Java reads `TankContent` as a `FluidStack` and writes it back; here the nested
  /// `CreateFluidTank` layout (`{Fluid: {id, amount}}`) is read and written in the port's own
  /// terms, which is the same stack.
  static Map<String, NbtValue> sanitiseTankItemData(
    Map<String, NbtValue> itemData, {
    required int capacityMultiplier,
  }) {
    final out = <String, NbtValue>{
      for (final e in itemData.entries)
        if (!tankStrippedKeys.contains(e.key)) e.key: e.value,
    };
    final content = out['TankContent'];
    if (content != null && content.kind == NbtKind.compound) {
      final fluid = readFluidTankNbt(content);
      if (fluid.amount > capacityMultiplier) {
        out['TankContent'] = fluidTankNbt(fluid.withAmount(capacityMultiplier));
      }
    }
    return out;
  }

  /// `CompoundTag.merge`: [over] wins per key, and two compounds at the same key merge into
  /// each other (Java's recursive merge).
  ///
  /// This is what a placement does: the fresh block entity's own saved NBT, then the item's
  /// data over it (`TypedEntityData.loadInto`) - the fresh `Size` / `Height` of a single tank
  /// survive because [sanitiseTankItemData] removed them from the item's copy.
  static Map<String, NbtValue> merge(
    Map<String, NbtValue> base,
    Map<String, NbtValue> over,
  ) {
    final out = Map<String, NbtValue>.of(base);
    for (final e in over.entries) {
      final existing = out[e.key];
      if (existing != null &&
          existing.kind == NbtKind.compound &&
          e.value.kind == NbtKind.compound) {
        out[e.key] = NbtValue.compound(
          merge(existing.asCompound, e.value.asCompound),
        );
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// The value of the [blockEntityDataComponent] component: the block entity type (the host
  /// writes the id `0`, `BlockEntityDataImpl::serialize`) and the network NBT of the saved
  /// data. The host does not resolve the type, and the client only reads the compound.
  static Uint8List encodeBlockEntityData(Map<String, NbtValue> nbt) =>
      PacketBuffer.encode((w) {
        w.writeVarInt(0);
        NetworkNbt.write(w, NbtValue.compound(nbt));
      });

  /// The saved NBT of a [blockEntityDataComponent] value, `null` when it is unreadable.
  static Map<String, NbtValue>? decodeBlockEntityData(List<int> bytes) {
    try {
      final root = PacketBuffer.decode(bytes, (r) {
        r.readVarInt(); // the block entity type id, ignored
        return NetworkNbt.read(r);
      });
      return root == null ? null : Map<String, NbtValue>.of(root.asCompound);
    } on Object {
      return null;
    }
  }

  /// The value of the [cannonOptionsComponent] component
  /// (`SchematicannonOptions.STREAM_CODEC`: an int and two bools).
  static Uint8List encodeCannonOptions(
    int replaceMode,
    bool skipMissing,
    bool replaceBlockEntities,
  ) => cannon_stack.encodeCannonOptions(
    replaceMode,
    skipMissing,
    replaceBlockEntities,
  );

  /// The cannon options of an item, or [defaultCannonOptions] when it has no component
  /// (`applyImplicitComponents`'s `getOrDefault`).
  static ({int replaceMode, bool skipMissing, bool replaceBlockEntities}) cannonOptions(
    List<int>? bytes,
  ) => bytes == null
      ? defaultCannonOptions
      : cannon_stack.decodeCannonOptions(bytes);
}