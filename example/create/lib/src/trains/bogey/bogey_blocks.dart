// Host side of the standard bogey blocks (`small_bogey`, `large_bogey`): the CreateBlocks, the
// wrench interaction that cycles style and size (`AbstractBogeyBlock.useItemOn`) and the
// waterlogging update.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/wrenchable.dart';
import '../../api/util.dart' hide pos;
import '../../core/blocks.dart';
import '../station/host_ops.dart';
import '../support/runtime.dart';
import 'abstract_bogey_block.dart';
import 'abstract_bogey_block_entity.dart';
import 'bogey_sizes.dart';
import 'bogey_style.dart';
import 'standard_bogey_block.dart';

const String smallBogeyKey = 'create:small_bogey';
const String largeBogeyKey = 'create:large_bogey';

/// The block entity type shared by the bogeys (`AllBlockEntityTypes.BOGEY`).
const String bogeyBlockEntityType = StandardBogeyBlockEntity.type;

/// The railway casing, what a bogey drops and costs (`AllBlocks.RAILWAY_CASING`).
const String railwayCasingKey = 'create:railway_casing';

/// The CreateBlock of the bogey `create:[key]` (`small_bogey` / `large_bogey`).
CreateBlock buildBogeyBlock(String key) {
  late final CreateBlock block;
  block = manifestBlock(
    key,
    blockEntityType: bogeyBlockEntityType,
    drops: lootTableOf(key),
    behavior: BlockBehavior(
      // `updateShape`: `updateWater` keeps the fluid ticking.
      onUpdateShape: (server, e) {
        updateWater(e.targetWorld, e.pos.toPos(), BState(block.key, block.stateOf(e.stateIndex)));
        return null;
      },
      onUseWithItem: _useItemOn,
      // `getCloneItemStack`: the railway casing.
      onCloneItem: (server, e) => ItemStack.create(registryKey: railwayCasingKey, count: 1),
    ),
  );
  return block;
}

/// `AbstractBogeyBlock.useItemOn` on the server.
Future<BlockUseResult> _useItemOn(Server server, CustomBlockUseEventData e) async {
  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final level = HostBlockGetter(world);
  final state = level.stateAt(pos);
  final block = AbstractBogeyBlock.byKey(state.key);
  if (block == null) return BlockUseResult.tryEmptyHand;

  final player = e.player;
  final stackKey = await e.item.getRegistryKey();
  if (e.sneaking ||
      stackKey != 'create:wrench' ||
      player.isOnCooldown(group: stackKey) ||
      AllBogeyStyles.count <= 1) {
    return block.onInteractWithBogey(state, world, pos, player);
  }

  final be = Tr.i.be<AbstractBogeyBlockEntity>(world, e.pos);
  if (be == null) return BlockUseResult.fail;

  player.startCooldown(group: stackKey, durationTicks: 20);
  final currentStyle = be.getStyle();

  var size = block.getSize();

  final style = block.getNextStyle(currentStyle);
  if (style == currentStyle) return BlockUseResult.tryEmptyHand;

  final validSizes = style.validSizes();

  for (var i = 0; i < BogeySizes.all().length; i++) {
    if (validSizes.contains(size)) break;
    size = size.nextBySize();
  }

  be.setBogeyStyle(style);

  final defaultData = style.defaultData;
  final data = be.getBogeyData();
  data.merge(defaultData);
  be.setBogeyData(data);

  if (size == block.getSize()) {
    if (state.key != style.getBlockForSize(size).key) {
      final oldData = be.getBogeyData();
      await setBlockState(world, pos, block.copyProperties(state, block.getStateOfSize(style, state, size)));
      final bogeyBlockEntity = await _entityAt(world, e.pos);
      if (bogeyBlockEntity == null) return BlockUseResult.fail;
      bogeyBlockEntity.setBogeyData(oldData);
    }
    sendOverlay(player, '${plainTrainsText(trainsText('create.bogey.style.updated_style'))}: ${plainTrainsText(style.displayName)}');
  } else {
    final oldData = be.getBogeyData();
    await setBlockState(world, pos, block.getStateOfSize(style, state, size));
    final bogeyBlockEntity = await _entityAt(world, e.pos);
    if (bogeyBlockEntity == null) return BlockUseResult.fail;
    bogeyBlockEntity.setBogeyData(oldData);
    sendOverlay(
      player,
      '${plainTrainsText(trainsText('create.bogey.style.updated_style_and_size'))}: ${plainTrainsText(style.displayName)}',
    );
  }

  return BlockUseResult.consume;
}

/// The bogey block entity at [pos] after the block was replaced (created when the host did not do
/// it yet).
Future<AbstractBogeyBlockEntity?> _entityAt(World world, BlockPos pos) async {
  var be = Tr.i.be<AbstractBogeyBlockEntity>(world, pos);
  if (be == null || be.removed) {
    final created = Tr.i.store.createAt(world, pos, bogeyBlockEntityType);
    be = created is AbstractBogeyBlockEntity ? created : null;
  }
  return be;
}

/// `onInteractWithBogey`: the hook for custom interactions (`TRY_WITH_EMPTY_HAND` by default).
extension BogeyInteraction on AbstractBogeyBlock {
  BlockUseResult onInteractWithBogey(BState state, World world, Pos pos, Player player) => BlockUseResult.tryEmptyHand;
}

/// Wrench behaviour of the bogeys (`IWrenchable` with `getRotatedBlockState`).
Wrenchable bogeyWrenchable() => CallbackWrenchable(
  rotatedState: (c) {
    final state = BState(c.blockKey, c.properties);
    final block = AbstractBogeyBlock.byKey(state.key);
    if (block == null) return null;
    final rotated = block.getRotatedBlockState(state, c.face.toDirection());
    return stateIdOf(rotated);
  },
);

/// The Java blocks of this module.
List<StandardBogeyBlock> registerBogeyLogic() {
  AllBogeyStyles.init();
  return StandardBogeyBlock.registerStandardBlocks();
}
