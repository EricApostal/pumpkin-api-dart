// Host lookups for the copycat material rules: what an item would place as a block.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/blocks.dart';
import '../common/host_bridge.dart';
import 'copycat.dart';
import 'vanilla_blocks.dart';

final Map<String, MaterialCandidate?> _candidates = {};

/// The block an item of [itemKey] places, as a [MaterialCandidate]; `null` if the item is not
/// the block item of a block (approximated by the block with the same key).
MaterialCandidate? materialCandidateOfItem(String itemKey) {
  if (_candidates.containsKey(itemKey)) return _candidates[itemKey];
  final c = _compute(itemKey);
  _candidates[itemKey] = c;
  return c;
}

MaterialCandidate? _compute(String itemKey) {
  final block = BlockRegistry.of(itemKey);
  if (block == null) return null;
  final stateId = block.defaultStateId;
  final state = BlockRegistry.stateFromId(stateId);
  if (state == null) return null;
  final bs = HostBlockGetter.stateOfId(stateId);
  if (bs.isAir) return null;
  // `block instanceof EntityBlock`: vanilla states without a block entity carry u16::MAX.
  final isEntity = state.blockEntityType != 0xFFFF;
  final isStair = isStairsState(bs) || BlockStates.isTag(stateId, 'minecraft:stairs');
  // Shape test: a full block selection shape and a non-empty collision shape.
  var shapeOk = state.collisionShapes.isNotEmpty;
  if (shapeOk) {
    var minX = 2.0, minY = 2.0, minZ = 2.0, maxX = -1.0, maxY = -1.0, maxZ = -1.0;
    for (final b in state.outlineShapes) {
      if (b.min.$1 < minX) minX = b.min.$1;
      if (b.min.$2 < minY) minY = b.min.$2;
      if (b.min.$3 < minZ) minZ = b.min.$3;
      if (b.max.$1 > maxX) maxX = b.max.$1;
      if (b.max.$2 > maxY) maxY = b.max.$2;
      if (b.max.$3 > maxZ) maxZ = b.max.$3;
    }
    const e = 1e-6;
    shapeOk = state.outlineShapes.isNotEmpty &&
        minX.abs() < e && minY.abs() < e && minZ.abs() < e &&
        (maxX - 1).abs() < e && (maxY - 1).abs() < e && (maxZ - 1).abs() < e;
  }
  return MaterialCandidate(
    defaultState: bs,
    isEntityBlock: isEntity,
    isStair: isStair,
    allowTag: bs.key == 'minecraft:barrel',
    denyTag: BlockStates.isTag(stateId, 'minecraft:cauldrons') ||
        BlockStates.isTag(stateId, 'minecraft:saplings') ||
        BlockStates.isTag(stateId, 'minecraft:climbable'),
    shapeOk: shapeOk,
  );
}

/// The item that places [blockKey] (`new ItemStack(block)`): the block key itself.
String itemOfBlock(String blockKey) => blockKey;
