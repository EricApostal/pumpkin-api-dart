// The envelope blocks: the airtight skin of a balloon, in sixteen dye colours,
// plus the encased shaft that lets a shaft pass through the skin.
//
// Java: `content/blocks/hot_air/envelope/{EnvelopeBlock,EnvelopeEncasedShaftBlock}`.
//
// Registration order is Java's (`index/AeroBlocks.java:73-160`): `white_envelope`
// is built on its own and the dyed list returns it for white, so the order is
// white, the fifteen other colours, then all sixteen encased shafts.
//
// A dye on an envelope recolours the clicked block, its neighbours, or the whole
// connected envelope; the flood fill is in `content/envelope_dye.dart`.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/create.dart';
import 'package:create/src/api/block_state.dart' show BState;
import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/common/host_bridge.dart' show PosToHost;
import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/kinetics/geometry.dart' show KState;
import 'package:create/src/kinetics/kinetic_block_entity.dart';
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../envelope_dye.dart';

/// The sixteen dye colours, in the vanilla order.
const List<String> envelopeColors = [
  'white',
  'orange',
  'magenta',
  'light_blue',
  'yellow',
  'lime',
  'pink',
  'gray',
  'light_gray',
  'cyan',
  'purple',
  'blue',
  'brown',
  'green',
  'red',
  'black',
];

/// `aeronautics:<colour>_envelope`.
String envelopeKey(String color) => 'aeronautics:${color}_envelope';

/// `aeronautics:<colour>_envelope_encased_shaft`.
String encasedEnvelopeKey(String color) => 'aeronautics:${color}_envelope_encased_shaft';

/// The envelope keys the dye writes.
const EnvelopeKeys envelopeKeys = EnvelopeKeys(
  envelope: envelopeKey,
  encased: encasedEnvelopeKey,
);

/// The colour of an envelope block, or `null` when [key] is not one.
String? envelopeColorOf(String key) {
  const prefix = 'aeronautics:';
  if (!key.startsWith(prefix)) return null;
  final path = key.substring(prefix.length);
  if (!path.endsWith('_envelope')) return null;
  final color = path.substring(0, path.length - '_envelope'.length);
  return envelopeColors.contains(color) ? color : null;
}

/// The colour of an encased envelope shaft, or `null`.
String? encasedColorOf(String key) {
  const prefix = 'aeronautics:';
  const suffix = '_envelope_encased_shaft';
  if (!key.startsWith(prefix) || !key.endsWith(suffix)) return null;
  final color = key.substring(prefix.length, key.length - suffix.length);
  return envelopeColors.contains(color) ? color : null;
}

/// The dye colour of an item key (`minecraft:red_dye`), or `null`.
String? dyeColorOf(String itemKey) {
  if (!itemKey.endsWith('_dye')) return null;
  final path = itemKey.substring(itemKey.indexOf(':') + 1);
  final color = path.substring(0, path.length - '_dye'.length);
  return envelopeColors.contains(color) ? color : null;
}

/// `EnvelopeBlock` and `EnvelopeEncasedShaftBlock` as one definition builder, in
/// the Java registration order.
///
/// Both are `SpecialBlockItemRequirement` in Java (the item is the white
/// envelope), and the encased shaft is a `KineticBlockEntity`.
List<CreateBlock> buildEnvelopeBlocks() => [
  // `WHITE_ENVELOPE_BLOCK`, then the dyed list's other fifteen colours.
  for (final color in envelopeColors) _envelopeBlock(color),
  // `ENVELOPE_ENCASED_SHAFTS`, all sixteen.
  for (final color in envelopeColors) _encasedEnvelopeBlock(color),
];

CreateBlock _envelopeBlock(String color) => CreateBlock(
  key: envelopeKey(color),
  // `EnvelopeBlock extends CasingBlock`: no state of its own.
  hardness: 1,
  blastResistance: 1,
  soundType: 'wool',
  canOcclude: true,
  mapColor: _mapColor(color),
  tags: const ['aeronautics:airtight'],
  behavior: envelopeBehavior,
);

CreateBlock _encasedEnvelopeBlock(String color) => CreateBlock(
  key: encasedEnvelopeKey(color),
  properties: [CreateProps.axis],
  // `RotatedPillarKineticBlock`'s default axis is `y`.
  defaultState: const {'axis': 'y'},
  hardness: 1,
  blastResistance: 1,
  soundType: 'scaffolding',
  canOcclude: false,
  mapColor: _mapColor(color),
  tags: const ['aeronautics:airtight', 'create:shafts'],
  blockEntityType: 'aeronautics:envelope_encased_shaft',
  behavior: envelopeBehavior,
);

/// `DyeColor`'s map colour per dye, as the host's palette index. The host takes
/// an int; the values are vanilla's `MapColor` ids, in `DyeColor` order.
int _mapColor(String color) => const {
  'white': 8,
  'orange': 15,
  'magenta': 16,
  'light_blue': 14,
  'yellow': 12,
  'lime': 10,
  'pink': 17,
  'gray': 22,
  'light_gray': 23,
  'cyan': 13,
  'purple': 19,
  'blue': 18,
  'brown': 21,
  'green': 11,
  'red': 20,
  'black': 24,
}[color] ?? 8;

/// `EnvelopeBlock.useItemOn` / `EnvelopeEncasedShaftBlock.useItemOn`: a dye
/// recolours the envelope.
final BlockBehavior envelopeBehavior = BlockBehavior(
  onUseWithItem: (server, e) async {
    final key = await e.item.getRegistryKey();
    final color = dyeColorOf(key);
    if (color == null) return BlockUseResult.tryEmptyHand;

    final world = e.targetWorld;
    final dyeWorld = _HostEnvelopeWorld(world);
    EnvelopeDye.apply(dyeWorld, (e.pos.x, e.pos.y, e.pos.z), color, envelopeKeys);
    return BlockUseResult.success;
  },
);

/// `EnvelopeEncasedShaftBlock`: a plain kinetic block entity.
final class EncasedShaftBlockEntity extends KineticBlockEntity {
  EncasedShaftBlockEntity(super.worldId, super.pos);
}

/// The envelope dye model over a host world.
final class _HostEnvelopeWorld implements EnvelopeDyeWorld {
  final World world;

  _HostEnvelopeWorld(this.world);

  @override
  BState stateAt(Pos pos) => HostBlockGetter.stateOfId(world.getBlockStateId(pos: pos.toBlockPos()));

  @override
  void setStateAt(Pos pos, BState state) {
    final id = KineticsRuntime.instance.states.idOf(KState(state.key, state.props));
    if (id == null) return;
    unawaited(world.setBlockState(pos: pos.toBlockPos(), state: id, updateFlags: BlockUpdateFlags.normal));
  }

  @override
  String? envelopeColor(BState state) => envelopeColorOf(state.key);

  @override
  String? encasedColor(BState state) => encasedColorOf(state.key);

  @override
  String? encasedAxis(BState state) => state['axis'];
}
