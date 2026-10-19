// Typed reads / writes of the module's custom data components on a host [ItemStack].
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../core/nbt.dart';
import '../data/equipment_components.dart';
import '../model/dir.dart';
import '../symmetry/mirror.dart';
import '../zapper/shaper_model.dart';

abstract final class StackData {
  // -- primitives ----------------------------------------------------------------

  static List<int>? raw(ItemStack s, String key) {
    try {
      return s.customComponent(key);
    } on Object {
      return null;
    }
  }

  static bool has(ItemStack s, String key) => raw(s, key) != null;

  static int? getVarInt(ItemStack s, String key) {
    final b = raw(s, key);
    return b == null ? null : EquipmentWire.readVarInt(b);
  }

  static bool? getFlag(ItemStack s, String key) {
    final b = raw(s, key);
    return b == null ? null : EquipmentWire.readFlag(b);
  }

  static void setVarInt(ItemStack s, String key, int v) => s.setCustomComponent(key, EquipmentWire.varInt(v));
  static void setFlag(ItemStack s, String key, bool v) => s.setCustomComponent(key, EquipmentWire.flag(v));
  static void remove(ItemStack s, String key) {
    try {
      s.removeCustomComponent(key);
    } on Object {
      // nothing to remove
    }
  }

  // -- symmetry wand ---------------------------------------------------------------

  /// `SymmetryWandItem.checkComponents`: a fresh wand gets an empty mirror, disabled.
  static void checkWand(ItemStack s) {
    if (!has(s, EquipmentComponents.symmetryWand)) {
      s.setCustomComponent(EquipmentComponents.symmetryWand, EquipmentWire.mirror(EmptyMirror((0, 0, 0))));
      setFlag(s, EquipmentComponents.symmetryWandEnable, false);
    }
  }

  static SymmetryMirror wandMirror(ItemStack s) {
    checkWand(s);
    return EquipmentWire.readMirror(raw(s, EquipmentComponents.symmetryWand)!);
  }

  static void setWandMirror(ItemStack s, SymmetryMirror m) =>
      s.setCustomComponent(EquipmentComponents.symmetryWand, EquipmentWire.mirror(m));

  /// `isEnabled`: enabled and not simulating a placement.
  static bool wandEnabled(ItemStack s) {
    checkWand(s);
    return (getFlag(s, EquipmentComponents.symmetryWandEnable) ?? false) &&
        !(getFlag(s, EquipmentComponents.symmetryWandSimulate) ?? false);
  }

  // -- zapper / worldshaper ------------------------------------------------------------

  static T _enum<T>(ItemStack s, String key, List<T> values, T fallback) {
    final i = getVarInt(s, key);
    return i != null && i >= 0 && i < values.length ? values[i] : fallback;
  }

  static PlacementPatterns pattern(ItemStack s) =>
      _enum(s, EquipmentComponents.placementPattern, PlacementPatterns.values, PlacementPatterns.solid);
  static TerrainBrushes brush(ItemStack s) =>
      _enum(s, EquipmentComponents.shaperBrush, TerrainBrushes.values, TerrainBrushes.cuboid);
  static PlacementOptions placement(ItemStack s) =>
      _enum(s, EquipmentComponents.shaperPlacementOptions, PlacementOptions.values, PlacementOptions.merged);
  static TerrainTools tool(ItemStack s) =>
      _enum(s, EquipmentComponents.shaperTool, TerrainTools.values, TerrainTools.fill);

  static P3? brushParams(ItemStack s) {
    final b = raw(s, EquipmentComponents.shaperBrushParams);
    return b == null ? null : EquipmentWire.readBlockPos(b);
  }

  static int? blockUsed(ItemStack s) => getVarInt(s, EquipmentComponents.shaperBlockUsed);

  static NbtValue? blockData(ItemStack s) {
    final b = raw(s, EquipmentComponents.shaperBlockData);
    return b == null ? null : EquipmentWire.readNbt(b);
  }

  static void configureWorldshaper(
    ItemStack s, {
    required PlacementPatterns pattern,
    required TerrainBrushes brush,
    required int px,
    required int py,
    required int pz,
    required TerrainTools tool,
    required PlacementOptions placement,
  }) {
    setVarInt(s, EquipmentComponents.placementPattern, pattern.index);
    setVarInt(s, EquipmentComponents.shaperBrush, brush.index);
    s.setCustomComponent(EquipmentComponents.shaperBrushParams, EquipmentWire.blockPos((px, py, pz)));
    setVarInt(s, EquipmentComponents.shaperTool, tool.index);
    setVarInt(s, EquipmentComponents.shaperPlacementOptions, placement.index);
  }

  // -- backtank -----------------------------------------------------------------------

  static int backtankAir(ItemStack s) => getVarInt(s, EquipmentComponents.backtankAir) ?? 0;
}
