// The display link: block, block entity, the configuration payload and the click to link
// item flow. It reads a source block next to it and writes the text to a target block
// somewhere else (signs, lecterns, nixie tubes, display boards).
import 'dart:async';
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/panel_support.dart';
import '../../api/payloads.dart' show NbtValue;
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../../core/module.dart';
import '../observer/observer_blocks.dart' show configAllowed;
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/rs_runtime.dart';
import '../support/shapes.dart';
import 'config_tag.dart';
import 'display_core.dart';
import 'display_env.dart';
import 'display_sources.dart';

const String displayLinkKey = 'create:display_link';

Direction _facing(Map<String, String> p) => Direction.byName(p['facing'] ?? 'up') ?? Direction.up;

/// `DisplayLinkBlockEntity`.
final class DisplayLinkBlockEntity extends CreateBlockEntity implements GatheredDataLink {
  static const String type = 'create:display_link';

  Pos targetOffset = posZero;
  DisplaySource? activeSource;
  ConfigTag _sourceConfig = ConfigTag();
  DisplayTarget? activeTarget;
  int targetLine = 0;
  int refreshTicks = 0;
  bool _sendPulse = false;
  bool _updating = false;

  late final PanelSupportBehaviour factoryPanelSupport;

  DisplayLinkBlockEntity(super.worldId, super.pos) {
    factoryPanelSupport = addBehaviour(
      PanelSupportBehaviour.of(Rs.i.ctx, isOutput: () => false, outputPower: () => false, onNotify: _notifyPanelChange),
    );
  }

  void _notifyPanelChange() => unawaited(updateGatheredData());

  Pos get _pos => pos.toPos();

  @override
  ConfigTag get sourceConfig => _sourceConfig;

  set sourceConfig(ConfigTag value) => _sourceConfig = value;

  /// `getDirection()`: the direction from the link to the source block.
  Direction get direction {
    final w = world;
    final props = w == null ? null : Lvl(w).info(_pos)?.properties;
    return (props == null ? Direction.up : _facing(props)).opposite;
  }

  /// `getSourcePosition()`.
  Pos get sourcePosition {
    for (final panel in factoryPanelSupport.linkedPanels) {
      return panel.pos;
    }
    return _pos.relative(direction);
  }

  /// `getTargetPosition()`.
  Pos get targetPosition => _pos + targetOffset;

  /// `target(targetPosition)`.
  void target(Pos targetPos) => targetOffset = targetPos - _pos;

  @override
  bool get isPowered {
    final w = world;
    final props = w == null ? null : Lvl(w).info(_pos)?.properties;
    // getOptionalValue(POWERED).orElse(true)
    return props == null ? true : props['powered'] == 'true';
  }

  @override
  int get gameTime => world?.getWorldAge() ?? 0;

  @override
  void tick() {
    super.tick();
    final source = activeSource;
    if (source == null) return;
    refreshTicks++;
    if (refreshTicks < source.passiveRefreshTicks || !source.shouldPassiveReset) return;
    tickSource();
  }

  /// `tickSource()`.
  void tickSource() {
    refreshTicks = 0;
    if (isPowered) return;
    unawaited(updateGatheredData());
  }

  /// `onNoLongerPowered()`.
  void onNoLongerPowered() {
    final source = activeSource;
    if (source == null) return;
    refreshTicks = 0;
    final ctx = _context();
    if (ctx != null) source.onSignalReset(ctx);
    unawaited(updateGatheredData());
  }

  DisplayLinkContext? _context() {
    final w = world;
    if (w == null) return null;
    return DisplayLinkContext(
      env: HostDisplayEnv(Lvl(w), Rs.i),
      linkPos: _pos,
      sourcePos: sourcePosition,
      targetPos: targetPosition,
      sourceConfig: _sourceConfig,
      direction: direction,
      activeTarget: activeTarget,
      linkedPanels: [for (final p in factoryPanelSupport.linkedPanels) (p.pos, p.slot.serializedName)],
    );
  }

  /// `updateGatheredData()`.
  @override
  Future<void> updateGatheredData() async {
    if (_updating) return;
    _updating = true;
    try {
      await _update();
    } finally {
      _updating = false;
    }
  }

  Future<void> _update() async {
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final sourcePos = sourcePosition;
    final targetPos = targetPosition;

    if (!lvl.isLoaded(targetPos) || !lvl.isLoaded(sourcePos)) return;

    final registry = Rs.i.displays;
    final target = registry.targetAt(lvl.blockKey(targetPos));
    final sources = registry.sourcesAt(lvl.blockKey(sourcePos));
    var notify = false;

    if (activeTarget != target) {
      activeTarget = target;
      notify = true;
    }

    if (activeSource != null && !sources.contains(activeSource)) {
      activeSource = null;
      _sourceConfig = ConfigTag();
      notify = true;
    }

    if (notify) sendData();
    final source = activeSource;
    final tgt = activeTarget;
    if (source == null || tgt == null) return;

    final ctx = _context();
    if (ctx == null) return;
    await source.transferData(ctx, tgt, targetLine);
    _sendPulse = true;
    sendData();
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putIntArray('TargetOffset', [targetOffset.x, targetOffset.y, targetOffset.z]);
    tag.putInt('TargetLine', targetLine);

    final source = activeSource;
    if (source != null) {
      final data = configToNbt(_sourceConfig.copy());
      data.putString('Id', source.id);
      tag.putCompound('Source', data);
    }
    if (clientPacket && activeTarget != null) tag.putString('TargetType', activeTarget!.id);
    if (clientPacket && _sendPulse) {
      _sendPulse = false;
      NbtHelper.putMarker(tag, 'Pulse');
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    targetOffset = NbtHelper.readBlockPos(tag, 'TargetOffset');
    targetLine = tag.getInt('TargetLine') ?? 0;

    final src = tag.getCompound('Source');
    if (src == null) return;
    final id = src.getString('Id');
    activeSource = Rs.i.displays.source(id);
    _sourceConfig = ConfigTag();
    if (activeSource != null) _sourceConfig = configFromNbt(src);
    // The target type is resolved again by the first update.
  }

  @override
  void onLoad() {
    super.onLoad();
    final w = world;
    if (w != null) activeTarget = Rs.i.displays.targetAt(Lvl(w).blockKey(targetPosition));
  }
}

/// `DisplayLinkBlock`.
final class DisplayLinkBlock {
  static const String key = 'display_link';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: DisplayLinkBlockEntity.type,
      placement: const [PlacementRule.clickedFace('facing')],
      shapeRules: directionalShapeRules('facing', [pixelBox(1, 0, 1, 15, 6, 15), pixelBox(3, 5, 3, 13, 9, 13)], Direction.up),
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onNeighborUpdate: _onNeighborUpdate,
        // useWithoutItem: the client opens the screen; the server only consumes the click.
        onUseWithoutItem: (server, e) => e.sneaking ? BlockUseResult.pass : BlockUseResult.success,
        isPathfindable: (server, e) => false,
      ),
    );
    return block;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: DisplayLinkBlockEntity.type,
    validBlocks: const [displayLinkKey],
    create: DisplayLinkBlockEntity.new,
    tickInterval: 1,
  );

  /// `shouldBePowered(state, level, pos)`.
  static Future<bool> shouldBePowered(Lvl lvl, Pos pos, Direction facing) async {
    for (final d in Direction.values) {
      if (d.opposite == facing) continue;
      if (await lvl.signalFrom(pos, d) == 0) continue;
      return true;
    }
    return false;
  }

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = block.stateOf(e.stateIndex);
    // getStateForPlacement: POWERED follows the neighbours.
    final powered = await shouldBePowered(lvl, pos, _facing(props));
    if (powered != (props['powered'] == 'true')) await lvl.setProps(pos, {'powered': '$powered'});
  }

  Future<void> _onNeighborUpdate(Server server, CustomBlockNeighborUpdateEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final pos = e.pos.toPos();
    final props = lvl.info(pos)?.properties ?? block.stateOf(e.stateIndex);
    final facing = _facing(props);

    final attachedPos = pos.relative(facing.opposite);
    if (e.sourcePos.toPos() == attachedPos) {
      await _sendToGatherersOfSource(lvl, attachedPos, redstonePowerOnly: true);
    }

    final powered = await shouldBePowered(lvl, pos, facing);
    final previouslyPowered = props['powered'] == 'true';
    if (previouslyPowered != powered) {
      await lvl.setProps(pos, {'powered': '${!previouslyPowered}'});
      if (!powered) Rs.i.be<DisplayLinkBlockEntity>(e.targetWorld, e.pos)?.onNoLongerPowered();
    }
  }

  // -- Gatherers (`forEachAttachedGatherer`) -------------------------------------------------

  static Future<void> _sendToGatherersOfSource(Lvl lvl, Pos pos, {bool redstonePowerOnly = false}) async {
    for (final be in attachedGatherers(lvl, pos)) {
      if (redstonePowerOnly && be.activeSource?.id != 'create:redstone_power') continue;
      be.tickSource();
    }
  }

  /// The display links next to [pos] that read the block at [pos] (and have a source).
  static List<DisplayLinkBlockEntity> attachedGatherers(Lvl lvl, Pos pos) {
    final result = <DisplayLinkBlockEntity>[];
    for (final d in Direction.values) {
      final offsetPos = pos.relative(d);
      final info = lvl.info(offsetPos);
      if (info == null || info.key != displayLinkKey) continue;
      final be = Rs.i.store.typed<DisplayLinkBlockEntity>(lvl.id, BlockPos(x: offsetPos.x, y: offsetPos.y, z: offsetPos.z));
      if (be == null || be.activeSource == null) continue;
      if (be.direction != d.opposite) continue;
      result.add(be);
    }
    return result;
  }

  /// `DisplayLinkBlock.notifyGatherers`.
  static Future<void> notifyGatherers(Lvl lvl, Pos pos) async {
    for (final be in attachedGatherers(lvl, pos)) {
      be.tickSource();
    }
  }

  /// `sendToGatherers(..., AccumulatedItemCountDisplaySource.class)`: items passed a tunnel.
  static Future<void> itemReceived(Lvl lvl, Pos pos, int amount) async {
    for (final be in attachedGatherers(lvl, pos)) {
      final source = be.activeSource;
      if (source is AccumulatedItemCountDisplaySource) await source.itemReceived(be, amount);
    }
  }

  // -- The configuration payload -----------------------------------------------------------------

  /// `DisplayLinkConfigurationPacket` (`create:configure_data_gatherer`).
  static void installPacket(RsRuntime rs) {
    final bus = rs.bus;
    if (bus == null) return;
    bus.onServerbound('create:configure_data_gatherer', (player, f) async {
      final pos = f['pos'] as (int, int, int);
      final world = player.getWorld();
      if (!configAllowed(player, world, pos)) return;
      final be = rs.be<DisplayLinkBlockEntity>(world, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
      if (be == null) return;
      final configData = ConfigTag.fromNbt(f['configData'] as NbtValue?);

      be.targetLine = f['targetLine'] as int;
      if (!configData.contains('Id')) {
        be.sendData();
        return;
      }
      final source = rs.displays.source(configData.getStringOr('Id', ''));
      if (source == null) {
        be.sendData();
        return;
      }
      if (be.activeSource == null || be.activeSource != source) {
        be.activeSource = source;
        be.sourceConfig = configData.copy();
      } else {
        be.sourceConfig.merge(configData);
      }
      await be.updateGatheredData();
      be.sendData();
    });
  }
}

// -- Click to link ---------------------------------------------------------------------------------------

/// The click to link flow of `DisplayLinkBlockItem` / `ClickToLinkBlockItem`.
abstract final class ClickToLink {
  static const String component = 'create:click_to_link_data';
  static const String item = 'create:display_link';

  static Uint8List encodeData(Pos pos, String dimension) =>
      PacketBuffer.encode((w) {
        w.writeBlockPos((pos.x, pos.y, pos.z));
        w.writeString(dimension);
      });

  static (Pos, String)? decodeData(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return PacketBuffer.decode(bytes, (r) {
        final p = r.readBlockPos();
        return ((p.$1, p.$2, p.$3), r.readString());
      });
    } on Object {
      return null;
    }
  }

  static void install(CreateContext ctx, RsRuntime rs) {
    ctx.host.intercept(Events.playerUseBlock, (server, e) async {
      if (e.cancelled) return e;
      final stack = e.item;
      if (await stack.getCount() <= 0 || await stack.getRegistryKey() != item) return e;
      final player = e.player;
      final world = player.getWorld();
      final lvl = Lvl(world);
      final pos = e.blockPos.toPos();
      // linkableItemAlwaysPlacesWhenUsed: the display link itself still opens its screen.
      if (lvl.blockKey(pos) == displayLinkKey) return e;

      final held = player.getItemInHand(hand: e.hand);
      if (held == null) return e;
      final data = decodeData(held.customComponent(component));
      final maxDistance = rs.displayLinkRange;

      if (e.sneaking && data != null) {
        held.removeCustomComponent(component);
        await player.setItemInHand(hand: e.hand, stack: held);
        _message(player, 'Cleared position selection');
        return e.cancel();
      }

      final dimension = world.getId();
      if (data == null) {
        held.setCustomComponent(component, encodeData(pos, dimension));
        await player.setItemInHand(hand: e.hand, stack: held);
        _message(player, 'Targeted position selected');
        return e.cancel();
      }

      final (selectedPos, selectedDim) = data;
      final face = e.face.toDirection();
      final placedPos = pos.relative(face, lvl.canBeReplaced(pos) ? 0 : 1);
      if (!selectedPos.closerThan(placedPos, maxDistance.toDouble()) || selectedDim != dimension) {
        _message(player, '§cTargeted position is too far from here');
        return e.cancel();
      }
      if (!lvl.canBeReplaced(placedPos)) return e.cancel();

      final facing = face;
      final state = BlockStates.withProperties(displayLinkKey, {
        'facing': facing.serializedName,
        'powered': '${await DisplayLinkBlock.shouldBePowered(lvl, placedPos, facing)}',
      });
      if (state == null) return e.cancel();
      await lvl.setState(placedPos, state, neighbors: true);
      final bp = BlockPos(x: placedPos.x, y: placedPos.y, z: placedPos.z);
      final be = rs.store.typed<DisplayLinkBlockEntity>(lvl.id, bp);
      if (be != null) {
        be.target(selectedPos);
        be.sendData();
        unawaited(be.updateGatheredData());
      }

      if (player.getGamemode() != GameMode.creative) {
        final count = await held.getCount();
        if (count <= 1) {
          await player.setItemInHand(hand: e.hand, stack: null);
        } else {
          await held.setCount(count: count - 1);
          held.removeCustomComponent(component);
          await player.setItemInHand(hand: e.hand, stack: held);
        }
      } else {
        held.removeCustomComponent(component);
        await player.setItemInHand(hand: e.hand, stack: held);
      }
      _message(player, '§aSuccessfully bound to targeted position');
      return e.cancel();
    });
  }

  static void _message(Player player, String legacyText) =>
      player.sendSystemMessage(text: TextComponent.fromLegacyString(input: legacyText), overlay: true);
}
