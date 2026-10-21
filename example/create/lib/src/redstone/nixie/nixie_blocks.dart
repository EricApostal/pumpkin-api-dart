// `NixieTubeBlock` (16 dye colours) and `NixieTubeBlockEntity`: a two digit display that
// shows the redstone strength around it or a custom text from a name tag, a clipboard or a
// display link. Rendering (the glow, the blinking of computer controlled tubes) is client
// side; ComputerCraft control is not ported.
import 'dart:async';
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/blocks.dart' show HostBlockGetter;
import '../../api/redstone.dart' show ClipboardApi;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../display/display_link_block.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/placement.dart';
import '../support/placer.dart';
import '../support/rs_runtime.dart';
import '../support/shapes.dart';
import '../support/text.dart';
import 'nixie_logic.dart';

/// `NixieTubeBlockEntity`.
final class NixieTubeBlockEntity extends CreateBlockEntity {
  static const String type = 'create:nixie_tube';

  int redstoneStrength = 0;

  /// `customText`: the raw JSON and its resolved form (the same here: selectors are not resolved).
  Object? _rawCustomText;
  Object? _parsedCustomText;
  int nixieIndex = 0;

  /// `computerSignal`: the display of a ComputerCraft controlled row (client update tag).
  ComputerSignal? computerSignal;

  NixieTubeBlockEntity(super.worldId, super.pos);

  /// `reactsToRedstone`.
  bool get reactsToRedstone => _parsedCustomText == null;

  bool get hasCustomText => _parsedCustomText != null;

  /// The JSON of the custom text, `null` without one.
  Object? get customTextJson => _parsedCustomText;

  /// `getFullText`: the custom text or the strength as text.
  Txt get fullText {
    final json = _parsedCustomText;
    if (json == null) return Txt.literal('$redstoneStrength');
    return Txt.literal(plainTextOfJson(json));
  }

  /// `getDisplayedStrings` (server side, for display links that copy tubes).
  (String, String) get displayedStrings => nixieDisplayedStrings();

  (String, String) nixieDisplayedStrings() {
    final json = _parsedCustomText;
    return displayedStrings0(json == null ? null : plainTextOfJson(json));
  }

  (String, String) displayedStrings0(String? text) =>
      displayedStringsOf(customText: text, nixieIndex: nixieIndex, redstoneStrength: redstoneStrength);

  /// `updateRedstoneStrength`.
  void updateRedstoneStrength(int signalStrength) {
    clearCustomText();
    redstoneStrength = signalStrength;
    _notifyGatherers();
    sendData();
  }

  /// `displayCustomText(tagElement, nixiePositionInRow)`: [tagElement] is the JSON text.
  void displayCustomText(String? tagElement, int nixiePositionInRow) {
    if (tagElement == null) return;
    final raw = tryParseJson(tagElement);
    if (_parsedCustomText != null && jsonEncode(_rawCustomText) == jsonEncode(raw)) return;
    _rawCustomText = raw;
    _parsedCustomText = raw;
    nixieIndex = nixiePositionInRow;
    _notifyGatherers();
    sendData();
  }

  /// `displayEmptyText`.
  void displayEmptyText(int nixiePositionInRow) => displayCustomText('""', nixiePositionInRow);

  /// `clearCustomText`.
  void clearCustomText() {
    nixieIndex = 0;
    _rawCustomText = null;
    _parsedCustomText = null;
  }

  void _notifyGatherers() {
    final w = world;
    if (w == null) return;
    unawaited(DisplayLinkBlock.notifyGatherers(Lvl(w), pos.toPos()));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    if (_parsedCustomText != null) {
      tag.putInt('CustomTextIndex', nixieIndex);
      tag.putString('RawCustomText', jsonEncode(_rawCustomText));
      tag.putString('CustomText', jsonEncode(_parsedCustomText));
    } else {
      tag.putInt('RedstoneStrength', redstoneStrength);
    }
    if (clientPacket && computerSignal != null) tag.putByteArray('ComputerSignal', computerSignal!.encode());
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    if (tag.containsKey('CustomText')) {
      final raw = tryParseJson(tag.getString('RawCustomText') ?? '');
      final parsed = tryParseJson(tag.getString('CustomText') ?? '');
      if (raw != null && parsed != null) {
        _rawCustomText = raw;
        _parsedCustomText = parsed;
        nixieIndex = tag.getInt('CustomTextIndex') ?? 0;
      } else {
        clearCustomText();
      }
    } else {
      clearCustomText();
    }
    if (_parsedCustomText == null) redstoneStrength = tag.getInt('RedstoneStrength') ?? 0;
    if (clientPacket) {
      final bytes = tag.getByteArray('ComputerSignal');
      computerSignal = bytes == null ? null : (ComputerSignal()..decode(bytes));
    }
  }
}

/// `level.getFluidState(pos).getType() == Fluids.WATER`: a *source* of water (Java's `getType()` is
/// the state's own fluid, so flowing water does not count).
bool isWaterAt(World world, BlockPos pos) {
  final fluid = world.getFluidState(pos: pos);
  return fluid != null && fluid.fluid == 'minecraft:water' && fluid.isSource;
}

/// The text and strength of a tube, to survive a recolouring (a block replaced by another block).
final class _NixieSnapshot {
  final int strength;
  final Object? raw;
  final int index;

  _NixieSnapshot(NixieTubeBlockEntity be)
    : strength = be.redstoneStrength,
      raw = be._rawCustomText,
      index = be.nixieIndex;

  void restore(NixieTubeBlockEntity be) {
    be.redstoneStrength = strength;
    if (raw != null) {
      be._rawCustomText = raw;
      be._parsedCustomText = raw;
      be.nixieIndex = index;
    }
    be.sendData();
  }
}

/// The 16 `NixieTubeBlock`s.
final class NixieTubeBlocks {
  final Map<String, CreateBlock> blocks = {};

  List<CreateBlock> build() {
    final shapes = _shapeRules();
    for (final color in dyeColorNames) {
      final key = nixieBlockKey(color).substring('create:'.length);
      final isOrange = color == 'orange';
      late final CreateBlock block;
      block = buildManifestBlock(
        key,
        blockEntityType: NixieTubeBlockEntity.type,
        shapeRules: shapes,
        collisionShape: BlockShape.fullCube,
        // The non orange tubes have no item of their own and drop the orange one.
        drops: isOrange ? null : BlockDrops.lootTable('create:blocks/$key'),
        behavior: BlockBehavior(
          onPlaced: _onPlaced,
          // `neighborChanged`: one tick per position, not one per neighbour.
          onNeighborUpdate: (server, e) {
            final world = e.targetWorld;
            if (world.hasScheduledTick(pos: e.pos)) return;
            Lvl(world).scheduleTick(e.pos.toPos(), 1);
          },
          onScheduledTick: (server, e) async => _updateDisplayed(Lvl(e.targetWorld), e.pos, e.targetWorld, force: false),
          // `updateShape`: a waterlogged tube keeps its water ticking.
          onUpdateShape: (server, e) {
            final state = HostBlockGetter(e.targetWorld).stateAt((e.pos.x, e.pos.y, e.pos.z));
            if (isNixieKey(state.key) && state.flag('waterlogged')) {
              e.targetWorld.scheduleFluidTick(pos: e.pos, delay: 5);
            }
            return null;
          },
          onUse: _onUse,
          canConnectRedstone: (server, e) => e.direction != null,
          isPathfindable: (server, e) => false,
          onCloneItem: isOrange ? null : (server, e) async => ItemStacks.plain('create:nixie_tube'),
        ),
      );
      blocks[key] = block;
    }
    return blocks.values.toList();
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: NixieTubeBlockEntity.type,
    validBlocks: nixieBlockKeys,
    create: NixieTubeBlockEntity.new,
    // Only the client ticks a nixie tube (rendering).
    tickInterval: 0,
  );

  /// `NIXIE_TUBE` / `NIXIE_TUBE_CEILING` (tubes along the clockwise axis of the facing) and
  /// `NIXIE_TUBE_WALL`.
  List<ShapeRule> _shapeRules() {
    final floor = [pixelBox(9, 0, 5, 15, 12, 11), pixelBox(1, 0, 5, 7, 12, 11)];
    final ceiling = [pixelBox(9, 4, 5, 15, 16, 11), pixelBox(1, 4, 5, 7, 16, 11)];
    final wall = [pixelBox(5, 9, 0, 11, 15, 12), pixelBox(5, 1, 0, 11, 7, 12)];
    final rules = <ShapeRule>[];
    for (final facing in Direction.horizontals) {
      // get(facing.getClockWise().getAxis()): the Z axis shape as defined, the X axis one turned.
      final axis = facing.clockWise.axis;
      final turns = axis == Axis.z ? Direction.south : Direction.east;
      for (final (face, boxes) in [('floor', floor), ('ceiling', ceiling)]) {
        final rotated = rotateBoxes(boxes, Direction.south, turns);
        rules.add(
          ShapeRule(
            when: {'double_face': face, 'facing': facing.serializedName},
            collisionShape: BlockShape.boxes(rotated),
            selectionShape: BlockShape.boxes(rotated),
          ),
        );
      }
      final w = rotateBoxes(wall, Direction.south, facing);
      for (final face in ['wall', 'wall_reversed']) {
        rules.add(
          ShapeRule(
            when: {'double_face': face, 'facing': facing.serializedName},
            collisionShape: BlockShape.boxes(w),
            selectionShape: BlockShape.boxes(w),
          ),
        );
      }
    }
    return rules;
  }

  CreateBlock? _blockFor(String key) => blocks[key.substring('create:'.length)];

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final block = _blockFor(e.block) ?? blocks.values.first;
    var props = block.stateOf(e.stateIndex);

    // getStateForPlacement
    final ctx = placeContextOf(server, e);
    if (ctx != null) {
      final placed = nixiePlacement(ctx);
      // `NixieTubeBlock.getStateForPlacement`: the tube keeps the water it is placed into.
      placed['waterlogged'] = '${isWaterAt(e.targetWorld, e.pos)}';
      if (placed['double_face'] != props['double_face'] ||
          placed['facing'] != props['facing'] ||
          placed['waterlogged'] != props['waterlogged']) {
        await lvl.setProps(pos, placed);
        props = {...props, ...placed};
      }
    }

    // onPlace: not for a recolouring, a move or a replacement of another tube.
    if (e.moved) return;
    final old = e.oldStateId;
    if (old != null && isNixieKey(BlockStates.blockKey(old))) return;
    await _updateDisplayed(lvl, e.pos, e.targetWorld, force: false);
  }

  /// `updateDisplayedRedstoneValue`.
  Future<void> _updateDisplayed(Lvl lvl, BlockPos bp, World world, {required bool force}) async {
    final pos = bp.toPos();
    final be = Rs.i.be<NixieTubeBlockEntity>(world, bp);
    final info = lvl.info(pos);
    if (be == null || info == null) return;
    if (be.reactsToRedstone || force) {
      final facing = Direction.byName(info.properties['facing'] ?? 'north') ?? Direction.north;
      be.updateRedstoneStrength(await lvl.linkStylePower(pos, facing));
    }
  }

  /// `useItemOn`.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    BlockUseResult pass() => e.withItem ? BlockUseResult.tryEmptyHand : BlockUseResult.pass;
    if (e.sneaking) return pass();
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final be = Rs.i.be<NixieTubeBlockEntity>(e.targetWorld, e.pos);
    if (be == null) return pass();

    if (!e.withItem) {
      if (be.reactsToRedstone) return pass();
      be.clearCustomText();
      await _updateDisplayed(lvl, e.pos, e.targetWorld, force: false);
      return BlockUseResult.success;
    }

    final itemKey = await e.item.getRegistryKey();
    String? tagUsed;
    var display = false;
    if (itemKey == 'minecraft:name_tag') {
      final name = await e.item.getCustomName();
      if (name != null) {
        display = true;
        tagUsed = name.toJson();
      }
    } else if (itemKey == 'create:clipboard') {
      final text = await clipboardFirstEntryText(e.item);
      display = true;
      tagUsed = jsonEncode(text ?? '');
    }
    final dye = dyeColorOfItem(itemKey);
    if (!display && dye == null) return pass();
    tagUsed ??= '""';

    final info = lvl.info(pos);
    if (info == null) return pass();
    final props = info.properties;
    for (final (currentPos, rowPosition) in walkNixies(pos, (p) => lvl.info(p))) {
      final bp = BlockPos(x: currentPos.x, y: currentPos.y, z: currentPos.z);
      final tube = Rs.i.be<NixieTubeBlockEntity>(e.targetWorld, bp);
      if (display) tube?.displayCustomText(tagUsed, rowPosition);
      if (dye != null) {
        final snapshot = tube == null ? null : _NixieSnapshot(tube);
        final state = BlockStates.withProperties(nixieBlockKey(dye), {
          'facing': props['facing'] ?? 'north',
          'waterlogged': props['waterlogged'] ?? 'false',
          'double_face': props['double_face'] ?? 'floor',
        });
        if (state != null) {
          await lvl.setState(currentPos, state, neighbors: true);
          final next = Rs.i.be<NixieTubeBlockEntity>(e.targetWorld, bp);
          if (next != null && snapshot != null) snapshot.restore(next);
        }
      }
    }
    return BlockUseResult.success;
  }
}

/// `ClipboardEntry.getLastViewedEntries(stack).getFirst().text` as plain text, `null` when the
/// clipboard has no entry. The clipboard format lives in the equipment module.
Future<String?> clipboardFirstEntryText(ItemStack stack) async =>
    Rs.i.ctx.services.find<ClipboardApi>()?.firstEntryText(stack);

/// Redirect so the entity can use the pure function with a short name.
(String, String) displayedStringsOf({String? customText, required int nixieIndex, required int redstoneStrength}) =>
    displayedStrings(customText: customText, nixieIndex: nixieIndex, redstoneStrength: redstoneStrength);
