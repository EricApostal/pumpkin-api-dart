// Host side of the display board (`display_board`): the CreateBlock with its kinetic behaviour,
// the use handler (placement assist, text, dye, glow ink), the column updates of the multi block and
// the `FlapDisplayAccess` service the display link target reads the boards through.
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart';
import '../../api/kinetics.dart';
import '../../api/placement.dart' as assist;
import '../../api/redstone.dart' show ClipboardApi, FlapControllerView, FlapDisplayAccess;
import '../../api/util.dart' hide pos;
import '../../core/blocks.dart';
import '../../kinetics/behavior_builder.dart';
import '../../kinetics/block_factory.dart';
import '../../kinetics/placement.dart';
import '../../kinetics/use_records.dart';
import '../../redstone/support/shapes.dart';
import '../../redstone/support/text.dart' show Txt;
import '../station/host_ops.dart';
import '../support/runtime.dart';
import 'flap_display_block.dart';
import 'flap_display_block_entity.dart';

const String displayBoardKey = FlapDisplayBlock.key;

/// `FlapDisplayBlock implements ICogWheel` with `getMinimumRequiredSpeedLevel() = MEDIUM`: the shaft
/// runs through the board along its facing axis.
final class FlapDisplayKineticDef extends KineticBlockDef {
  const FlapDisplayKineticDef();

  Dir _facing(KState s) => s.dirOf('facing') ?? Dir.north;

  @override
  KAxis rotationAxis(KState state) => _facing(state).axis;

  @override
  bool hasShaftTowards(KState state, Dir face) => face.axis == rotationAxis(state);

  @override
  SpeedLevel get minimumRequiredSpeedLevel => SpeedLevel.medium;

  @override
  bool get isSmallCog => true;
}

/// `index of [state]` in the layout of [block].
int? _stateIndexOf(CreateBlock block, BState state) {
  try {
    return block.layout.indexOf({...block.definition.defaultState, ...state.props});
  } catch (_) {
    return null;
  }
}

BState _bstate(KState s) => BState(s.block, s.props);

KState _kstate(BState s) => KState(s.key, s.props);

late final CreateBlock _block;
late final KineticBlockSpec _spec;

/// The CreateBlock of the display board (the first call builds it).
CreateBlock buildFlapDisplayBlock() {
  final block = manifestBlock(
    'display_board',
    blockEntityType: FlapDisplayBlockEntity.type,
    drops: lootTableOf('display_board'),
    placement: [PlacementRule.horizontalFacing('facing', opposite: true)],
    shapeRules: directionalShapeRules(
      'facing',
      [pixelBox(0, 0, 3, 16, 16, 13)],
      Direction.south,
      directions: Direction.horizontals,
    ),
    behavior: buildKineticBehavior(
      () => _block,
      specRef: () => _spec,
      use: _use,
      scheduledTick: _scheduledTick,
      updateShape: _updateShape,
      replaced: _replaced,
      afterPlaced: _afterPlaced,
    ),
  );
  _block = block;
  _spec = KineticBlockSpec(
    block,
    def: const FlapDisplayKineticDef(),
    placement: _placement,
  );
  return block;
}

/// `KineticBlockSpec` of the board (the placement correction).
KineticBlockSpec get flapDisplaySpec => _spec;

/// `getStateForPlacement`: the facing of the board it is placed against (unless sneaking), the
/// column flags and the water.
FutureOr<KState> _placement(PlacementContext ctx, KState placed, UseRecord? use, World world) {
  final level = HostBlockGetter(world);
  final pos = (ctx.pos.x, ctx.pos.y, ctx.pos.z);
  final clickedFace = Direction.byName(ctx.clickedFace.name)!;
  final state = FlapDisplayBlock.getStateForPlacement(
    level,
    pos,
    clickedFace,
    Direction.byName(ctx.horizontal.name)!,
    sneaking: ctx.sneaking,
    hasPlayer: ctx.hasPlayer,
    inWater: placed.flag('waterlogged'),
  );
  return _kstate(state);
}

/// `onPlace`: schedules the first tick that updates the column and the controller status.
Future<void> _afterPlaced(HookCtx c, CustomBlockPlacedEventData e) async {
  final old = e.oldStateId;
  if (old != null && BlockStates.blockKey(old) == displayBoardKey) return;
  c.world.scheduleBlockTick(pos: c.pos, delayTicks: 1, priority: TickPriority.normal);
}

/// `tick`.
Future<void> _scheduledTick(HookCtx c) async {
  final level = HostBlockGetter(c.world);
  final pos = c.pos.toPos();
  final state = _bstate(c.state);
  final next = FlapDisplayBlock.tickState(level, pos, state);
  if (next != null) await _switchTo(c, c.pos, next);
  c.beOf<FlapDisplayBlockEntity>()?.updateControllerStatus();
}

/// `KineticBlockEntity.switchToBlockState(level, pos, state)`.
Future<void> _switchTo(HookCtx c, BlockPos pos, BState state) =>
    KineticOps.switchToBlockState(c.rt, c.worldId, pos, _kstate(state));

/// `updateShape` -> `updatedShapeInner`.
int? _updateShape(HookCtx c, CustomBlockUpdateShapeEventData e) {
  final state = _bstate(c.state);
  if (state.flag('waterlogged')) updateWater(c.world, c.pos.toPos(), state);
  final neighbor = HostBlockGetter.stateOfId(e.neighborStateId);
  final next = FlapDisplayBlock.updatedShapeInner(state, e.direction.toDirection(), neighbor);
  if (next == state) return null;
  return _stateIndexOf(_block, next);
}

/// `affectNeighborsAfterRemoval`: the boards that were connected to the removed one update their column.
Future<void> _replaced(HookCtx c, CustomBlockStateReplacedEventData e) async {
  if (e.moved) return;
  final level = HostBlockGetter(c.world);
  final removed = _bstate(c.state);
  final updates = FlapDisplayBlock.neighboursAfterRemoval(level, c.pos.toPos(), removed);
  for (final entry in updates.entries) {
    await _switchTo(c, entry.key.toBlockPos(), entry.value);
  }
}

/// `useItemOn`.
Future<BlockUseResult> _use(HookCtx c, CustomBlockUseEventData e) async {
  if (e.sneaking) return BlockUseResult.tryEmptyHand;

  final world = e.targetWorld;
  final pos = e.pos.toPos();
  final level = HostBlockGetter(world);
  final state = _bstate(c.state);
  final player = e.player;
  final stackKey = await e.item.getRegistryKey();
  final emptyStack = stackKey == 'minecraft:air' || await e.item.getCount() <= 0;

  // the placement helper (`PlacementHelper`): another board next to this one
  if (!emptyStack && stackKey == displayBoardKey) {
    final hit = (pos.x + e.cursor.$1, pos.y + e.cursor.$2, pos.z + e.cursor.$3);
    final directions = assist.orderedByDistanceExceptAxis(
      pos,
      hit,
      state.dir(FlapDisplayBlock.facingProperty)!.axis,
      (dir) => level.canBeReplaced(pos.relative(dir)),
    );
    if (directions.isEmpty) return BlockUseResult.pass;
    final target = pos.relative(directions.first);
    // PlacementOffset.placeInWorld
    if (!level.canBeReplaced(target)) return BlockUseResult.pass;
    var placed = FlapDisplayBlock.defaultBlockState().setValue(
      FlapDisplayBlock.facingProperty,
      state[FlapDisplayBlock.facingProperty]!,
    );
    placed = FlapDisplayBlock.updateColumn(level, target, placed, true);
    placed = placed.setFlag('waterlogged', level.isWater(target));
    await setBlockState(world, target, placed);
    if (!isCreative(player)) await shrinkHeld(player, e.hand);
    world.playCustomSound(
      soundName: 'minecraft:block.metal.place',
      category: SoundCategory.blocks,
      pos: target.center,
      volume: 1,
      pitch: 0.8,
    );
    return BlockUseResult.success;
  }

  var flapBE = c.beOf<FlapDisplayBlockEntity>();
  if (flapBE == null) return BlockUseResult.tryEmptyHand;
  flapBE = flapBE.getController();
  if (flapBE == null) return BlockUseResult.tryEmptyHand;

  final opposite = e.face.toDirection().opposite;
  final yCoord = (pos.y + e.cursor.$2) + opposite.stepY * .125;

  final lineIndex = flapBE.getLineIndexAt(yCoord);

  if (emptyStack) {
    if (!flapBE.isSpeedRequirementFulfilled) return BlockUseResult.tryEmptyHand;
    flapBE.applyTextManually(lineIndex, null);
    return BlockUseResult.success;
  }

  if (stackKey == 'minecraft:glow_ink_sac') {
    world.playCustomSound(
      soundName: 'minecraft:item.ink_sac.use',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    flapBE.setGlowing(lineIndex);
    return BlockUseResult.success;
  }

  final customName = await e.item.getCustomName();
  final isClipboard = stackKey == 'create:clipboard';
  final display = (stackKey == 'minecraft:name_tag' && customName != null) || isClipboard;
  final dye = _dyeOf(stackKey);

  if (!display && dye == null) return BlockUseResult.tryEmptyHand;
  if (dye == null && !flapBE.isSpeedRequirementFulfilled) return BlockUseResult.tryEmptyHand;

  if (display) {
    if (isClipboard) {
      var line = lineIndex;
      for (final entry in await _clipboardEntries(e.item)) {
        for (final string in entry.split('\n')) {
          flapBE.applyTextManually(line++, Txt.literal(string));
        }
      }
      return BlockUseResult.success;
    }

    flapBE.applyTextManually(lineIndex, Txt.literal(customName!.getText()));
  }
  if (dye != null) {
    world.playCustomSound(
      soundName: 'minecraft:item.dye.use',
      category: SoundCategory.blocks,
      pos: pos.center,
      volume: 1,
      pitch: 1,
    );
    flapBE.setColour(lineIndex, dye);
  }

  return BlockUseResult.success;
}

/// `DyeColor.getColor(stack)`: the dye of a dye item.
String? _dyeOf(String itemKey) {
  if (!itemKey.startsWith('minecraft:') || !itemKey.endsWith('_dye')) return null;
  final color = itemKey.substring('minecraft:'.length, itemKey.length - '_dye'.length);
  return dyeColors.contains(color) ? color : null;
}

/// `ClipboardEntry.getLastViewedEntries(stack)`: the texts of the entries of the page last viewed.
Future<List<String>> _clipboardEntries(ItemStack clipboard) async {
  final provider = Tr.i.service<FlapClipboardEntries>();
  if (provider != null) return provider.lastViewedEntryTexts(clipboard);
  final first = await Tr.i.service<ClipboardApi>()?.firstEntryText(clipboard);
  return first == null ? const [] : [first];
}

/// Optional service of the equipment module: the texts of all entries of the page of a clipboard
/// that was viewed last (`ClipboardEntry.getLastViewedEntries`). Without it only the first entry
/// (`ClipboardApi`) is used.
abstract interface class FlapClipboardEntries {
  Future<List<String>> lastViewedEntryTexts(ItemStack clipboard);
}

/// The `FlapDisplayAccess` the display link's board target reads.
final class FlapDisplayAccessImpl implements FlapDisplayAccess {
  @override
  FlapControllerView? controllerAt(String worldId, Pos pos) {
    final be = Tr.i.store.typed<FlapDisplayBlockEntity>(worldId, pos.toBlockPos());
    if (be == null) return null;
    final controller = be.getController();
    return controller == null ? null : FlapControllerAdapter(controller);
  }
}
