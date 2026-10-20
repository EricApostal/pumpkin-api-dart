// The smart observer (`content_observer`) and the threshold switch (`stockpile_switch`):
// blocks that look at the container, belt or pipe they face and give a redstone signal.
// Items and fluids in neighbouring containers are read through the host's item and fluid
// handlers; belts, pipes and chain conveyors through the [ObservableProbe]s other modules
// register.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/redstone.dart';
import '../../api/util.dart' hide pos;
import '../../core/block_entity.dart';
import '../../core/blocks.dart';
import '../display/display_core.dart' show ObservedFluid, ObservedItem, ObserverView;
import '../display/display_link_block.dart';
import '../support/level.dart';
import '../support/manifest_block.dart';
import '../support/placement.dart';
import '../support/placer.dart';
import '../support/rs_runtime.dart';
import 'filter_behaviour.dart';
import 'threshold_logic.dart';

const String observerKey = 'create:content_observer';
const String thresholdKey = 'create:stockpile_switch';

/// The probes other modules registered (`RedstoneObservables`).
final class ObservableRegistry implements RedstoneObservables {
  final List<ObservableProbe> probes = [];

  @override
  void register(ObservableProbe probe) => probes.add(probe);

  bool canObserve(String worldId, Pos pos) => probes.any((p) => p.canObserve(worldId, pos));
}

Direction _facing(Map<String, String> p) => Direction.byName(p['facing'] ?? 'north') ?? Direction.north;

/// `DirectedDirectionalBlock.getTargetDirection(state)`.
Direction targetDirectionOf(Map<String, String> p) => directedTargetDirection(p['target'] ?? 'wall', _facing(p));

BlockUseResult _pass(bool withItem) => withItem ? BlockUseResult.tryEmptyHand : BlockUseResult.pass;

/// A readable name for an item key when the host gives no translation (`getHoverName`).
String prettyItemName(String key) {
  final path = key.substring(key.indexOf(':') + 1);
  return path.split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// Item stacks of a handler seen by the filter, with the item key and count.
Future<List<ObservedItem>> readHandlerItems(ItemHandler handler, FilterBehaviour? filter) async {
  final result = <ObservedItem>[];
  final slots = handler.slotCount();
  for (var slot = 0; slot < slots; slot++) {
    final stack = handler.getStack(slot: slot);
    if (stack == null) continue;
    final count = await stack.getCount();
    if (count <= 0) continue;
    final key = await stack.getRegistryKey();
    if (filter != null && !filter.testItem(key)) continue;
    final name = await stack.getCustomName();
    result.add(ObservedItem(key, name?.getText() ?? prettyItemName(key), count));
  }
  return result;
}

/// Fluids of a handler seen by the filter.
List<ObservedFluid> readHandlerFluids(FluidHandler handler, FilterBehaviour? filter) {
  final result = <ObservedFluid>[];
  for (var tank = 0; tank < handler.tankCount(); tank++) {
    final fluid = handler.getFluid(tank: tank);
    if (fluid == null || fluid.amount <= 0) continue;
    if (filter != null && !filter.testFluid(fluid.fluid)) continue;
    result.add(ObservedFluid(fluid.fluid, prettyItemName(fluid.fluid), fluid.amount));
  }
  return result;
}

// -- Smart observer ---------------------------------------------------------------------------------------

/// `SmartObserverBlockEntity`.
final class SmartObserverBlockEntity extends CreateBlockEntity {
  static const String type = 'create:content_observer';
  static const int defaultDelay = 6;

  late final FilterBehaviour filtering;
  int turnOffTicks = 0;
  bool _busy = false;

  /// `VersionedInventoryTrackerBehaviour.lastKnownVersion`: the inventory contents seen by
  /// the last `awaitNewVersion`.
  String? _inventoryVersion;

  /// `sustainSignal`: a change was seen and the observer keeps its pulse alive while the
  /// inventory does not change again.
  bool sustainSignal = false;

  SmartObserverBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 20;
    filtering = addBehaviour(FilterBehaviour());
  }

  Pos get _pos => pos.toPos();

  Direction? _targetDirection(Lvl lvl) {
    final props = lvl.info(_pos)?.properties;
    return props == null ? null : targetDirectionOf(props);
  }

  @override
  void tick() {
    super.tick();
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);

    if (turnOffTicks > 0) {
      turnOffTicks--;
      if (turnOffTicks == 0) lvl.scheduleTick(_pos, 1);
    }

    if (_busy) return;
    _busy = true;
    unawaited(
      _scan(lvl).whenComplete(() => _busy = false),
    );
  }

  /// The detection part of `tick()`.
  Future<void> _scan(Lvl lvl) async {
    final dir = _targetDirection(lvl);
    if (dir == null) return;
    final targetPos = _pos.relative(dir);
    final world = lvl.world;
    final targetKey = lvl.blockKey(targetPos);

    // Detect the block itself when a filter is set.
    if (!filtering.isEmpty && ItemRegistries.host.idOf(targetKey) != null) {
      if (filtering.testItem(targetKey)) {
        await activate(3);
        return;
      }
    }

    // Belts, pipes, chain conveyors (other modules).
    final probes = Rs.i.ctx.services.find<ObservableRegistry>()?.probes ?? const <ObservableProbe>[];
    for (final probe in probes) {
      final detected = probe.detect(worldId, targetPos, filtering);
      if (detected == null) continue;
      if (detected && turnOffTicks != 6) await activate();
      return;
    }
    for (final probe in probes) {
      final packages = probe.loopingPackageAddresses(worldId, targetPos, filtering);
      if (packages == null) continue;
      if (packages.isNotEmpty) await activate();
      return;
    }

    // Containers (`observedInventory`): one six tick pulse per inventory change.
    final handler = ItemHandlers.at(world, targetPos.toBlockPos());
    if (handler != null) {
      final version = await _inventoryVersionOf(handler);
      // `stillWaiting`: nothing changed since the last `awaitNewVersion`.
      final skipInv = version == _inventoryVersion;
      _inventoryVersion = version;
      if (skipInv && sustainSignal) turnOffTicks = defaultDelay;
      if (!skipInv) {
        sustainSignal = false;
        if (await _hasMatchingItem(handler)) {
          sustainSignal = true;
          await activate();
          return;
        }
      }
    }
    final tank = world.fluidHandlerAt(targetPos.toBlockPos());
    if (tank != null && readHandlerFluids(tank, filtering).isNotEmpty) {
      await activate();
    }
  }

  /// The contents of [handler] as one comparable value: the version the tracker watches.
  Future<String> _inventoryVersionOf(ItemHandler handler) async {
    final parts = <String>[];
    final slots = handler.slotCount();
    for (var slot = 0; slot < slots; slot++) {
      final stack = handler.getStack(slot: slot);
      if (stack == null) continue;
      final count = await stack.getCount();
      if (count <= 0) continue;
      parts.add('$slot:${await stack.getRegistryKey()}:$count');
    }
    return parts.join('|');
  }

  Future<bool> _hasMatchingItem(ItemHandler handler) async {
    final slots = handler.slotCount();
    for (var slot = 0; slot < slots; slot++) {
      final stack = handler.getStack(slot: slot);
      if (stack == null || await stack.getCount() <= 0) continue;
      if (filtering.isEmpty) return true;
      if (filtering.testItem(await stack.getRegistryKey())) return true;
    }
    return false;
  }

  /// `activate(ticks)`.
  Future<void> activate([int ticks = defaultDelay]) async {
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    turnOffTicks = ticks;
    final props = lvl.info(_pos)?.properties;
    if (props == null || props['powered'] == 'true') return;
    await lvl.setProps(_pos, {'powered': 'true'}, neighbors: true);
    await lvl.updateNeighbors(_pos);
  }

  /// What the observer sees (for the display sources).
  Future<ObserverView> view() async {
    final w = world;
    if (w == null) return const ObserverView();
    final lvl = Lvl(w);
    final dir = _targetDirection(lvl);
    if (dir == null) return const ObserverView();
    final targetPos = _pos.relative(dir);
    final handler = ItemHandlers.at(w, targetPos.toBlockPos());
    final tank = w.fluidHandlerAt(targetPos.toBlockPos());

    var items = const <ObservedItem>[];
    String? address;
    if (handler != null) {
      items = await readHandlerItems(handler, filtering);
      final slots = handler.slotCount();
      for (var slot = 0; slot < slots && address == null; slot++) {
        final stack = handler.getStack(slot: slot);
        if (stack == null || await stack.getCount() <= 0) continue;
        if (!filtering.testItem(await stack.getRegistryKey())) continue;
        address = _packageAddress(stack);
      }
    } else {
      final probes = Rs.i.ctx.services.find<ObservableRegistry>()?.probes ?? const <ObservableProbe>[];
      for (final p in probes) {
        final packages = p.loopingPackageAddresses(worldId, targetPos, filtering);
        if (packages != null) {
          if (packages.isNotEmpty) address = packages.first;
          break;
        }
      }
    }
    return ObserverView(
      items: items,
      fluids: tank == null ? const [] : readHandlerFluids(tank, filtering),
      packageAddress: address,
      hasInventory: handler != null,
      hasTank: tank != null,
    );
  }

  /// `PackageItem.getAddress` of a package stack (`create:package_address`, a string).
  static String? _packageAddress(ItemStack stack) {
    final bytes = stack.customComponent('create:package_address');
    if (bytes == null) return null;
    try {
      return PacketReader(bytes).readString();
    } on Object {
      return null;
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putInt('TurnOff', turnOffTicks);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    turnOffTicks = tag.getInt('TurnOff') ?? 0;
  }
}

/// `SmartObserverBlock`.
final class SmartObserverBlock {
  static const String key = 'content_observer';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: SmartObserverBlockEntity.type,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onScheduledTick: (server, e) async {
          final lvl = Lvl(e.targetWorld);
          await lvl.setProps(e.pos.toPos(), {'powered': 'false'});
          await lvl.updateNeighbors(e.pos.toPos());
        },
        onWeakPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          if (p['powered'] != 'true') return 0;
          // `getSignal`: nothing towards the side opposite the observed block; 15 everywhere else.
          return e.face.toDirection() != targetDirectionOf(p).opposite ? 15 : 0;
        },
        canConnectRedstone: (server, e) {
          final side = e.direction?.toDirection();
          return side != _facing(block.stateOf(e.stateIndex)).opposite;
        },
        onUse: (server, e) async => _pass(e.withItem),
      ),
    );
    return block;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: SmartObserverBlockEntity.type,
    validBlocks: const [observerKey],
    create: SmartObserverBlockEntity.new,
    tickInterval: 1,
  );

  /// `getStateForPlacement`.
  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final ctx = placeContextOf(server, e);
    if (ctx == null) return;
    final lvl = Lvl(e.targetWorld);
    final registry = Rs.i.ctx.services.find<ObservableRegistry>();
    final worldId = Rs.i.worldId(e.targetWorld);
    final placeWorld = HostPlaceWorld(lvl, detectBlockEntity: (p) => registry?.canObserve(worldId, p) ?? false);
    final placed = directedPlacement(ctx, placeWorld.canDetect);
    final current = block.stateOf(e.stateIndex);
    if (placed['target'] != current['target'] || placed['facing'] != current['facing']) {
      await lvl.setProps(e.pos.toPos(), placed);
    }
  }

  /// `onFunnelTransfer(world, funnelPos, transferred)`.
  static Future<void> onFunnelTransfer(World world, BlockPos funnelPos, String itemKey) async {
    final lvl = Lvl(world);
    final fp = funnelPos.toPos();
    for (final d in Direction.values) {
      final detectorPos = fp.relative(d);
      final info = lvl.info(detectorPos);
      if (info == null || info.key != observerKey) continue;
      if (targetDirectionOf(info.properties) != d.opposite) continue;
      final be = Rs.i.be<SmartObserverBlockEntity>(world, BlockPos(x: detectorPos.x, y: detectorPos.y, z: detectorPos.z));
      if (be == null || !be.filtering.testItem(itemKey)) continue;
      await be.activate(4);
    }
  }
}

// -- Threshold switch ------------------------------------------------------------------------------------

/// `ThresholdSwitchBlockEntity.ThresholdType`: what the observed block provides.
enum ThresholdType { unsupported, item, fluid, custom }

/// `ThresholdSwitchBlockEntity`.
final class ThresholdSwitchBlockEntity extends CreateBlockEntity {
  static const String type = 'create:stockpile_switch';

  int onWhenAbove = 128;
  int offWhenBelow = 64;

  int currentMinLevel = 0;
  int currentLevel = -1;
  int currentMaxLevel = 0;
  bool inStacks = false;

  bool redstoneState = false;
  bool inverted = false;
  bool poweredAfterDelay = false;

  late final FilterBehaviour filtering;
  bool _updating = false;

  ThresholdSwitchBlockEntity(super.worldId, super.pos) {
    lazyTickRate = 10;
    filtering = addBehaviour(
      FilterBehaviour(callback: (_) => updateCurrentLevel()),
    );
  }

  Pos get _pos => pos.toPos();

  /// `shouldBePowered`.
  bool get shouldBePowered => inverted != redstoneState;

  /// `isPowered`.
  bool get isPowered => poweredAfterDelay;

  /// `setInverted(inverted)`.
  void setInverted(bool value) {
    if (value == inverted) return;
    inverted = value;
    updatePowerAfterDelay();
  }

  /// `updatePowerAfterDelay`.
  void updatePowerAfterDelay() {
    poweredAfterDelay = shouldBePowered;
    final w = world;
    if (w != null) unawaited(Lvl(w).updateNeighbors(_pos));
    sendData();
  }

  /// `scheduleBlockTick`: a tick that is already due this tick is not scheduled again.
  void _scheduleBlockTick(Lvl lvl) {
    if (lvl.world.hasScheduledTick(pos: _pos.toBlockPos())) return;
    lvl.scheduleTick(_pos, 2);
  }

  @override
  void lazyTick() {
    super.lazyTick();
    updateCurrentLevel();
  }

  /// `updateCurrentLevel()`; runs in the background (item scans are asynchronous).
  void updateCurrentLevel() {
    if (_updating) return;
    _updating = true;
    unawaited(_update().whenComplete(() => _updating = false));
  }

  Future<void> _update() async {
    final w = world;
    if (w == null) return;
    final lvl = Lvl(w);
    final props = lvl.info(_pos)?.properties;
    if (props == null || lvl.blockKey(_pos) != thresholdKey) return;

    final prevLevel = currentLevel;
    final dir = targetDirectionOf(props);
    final target = _pos.relative(dir);
    final tbp = target.toBlockPos();

    final probes = Rs.i.ctx.services.find<ObservableRegistry>()?.probes ?? const <ObservableProbe>[];
    ThresholdObservation? observed;
    for (final p in probes) {
      observed = p.observation(worldId, target);
      if (observed != null) break;
    }

    final targetKey = lvl.blockKey(target);
    final supported = thresholdTargetSupported(targetKey);
    final handler = supported ? ItemHandlers.at(w, tbp) : null;
    final tank = supported ? w.fluidHandlerAt(tbp) : null;

    if (observed != null) {
      currentMinLevel = observed.min;
      currentLevel = observed.current;
      currentMaxLevel = observed.max;
    } else if (handler != null || tank != null) {
      currentMinLevel = 0;
      currentLevel = 0;
      currentMaxLevel = 0;

      if (handler != null) {
        final slots = handler.slotCount();
        for (var slot = 0; slot < slots; slot++) {
          final stack = handler.getStack(slot: slot);
          final slotLimit = handler.getSlotLimit(slot: slot);
          var space = math.min(64, slotLimit);
          var count = 0;
          if (stack != null) {
            count = await stack.getCount();
            if (count > 0) space = math.min(await stack.getMaxCount(), slotLimit);
          }
          if (space == 0) continue;
          currentMaxLevel += space;
          if (count > 0 && filtering.testItem(await stack!.getRegistryKey())) currentLevel += count;
        }
      }

      if (tank != null) {
        for (var slot = 0; slot < tank.tankCount(); slot++) {
          final stack = tank.getFluid(tank: slot);
          final space = tank.getTankCapacity(tank: slot);
          final count = stack?.amount ?? 0;
          if (space == 0) continue;
          currentMaxLevel += space;
          if (stack != null && filtering.testFluid(stack.fluid)) currentLevel += count;
        }
      }
    } else {
      // No compatible inventories found.
      currentMinLevel = -1;
      currentMaxLevel = -1;
      if (currentLevel == -1) return;

      await lvl.setProps(_pos, {'level': '0'}, neighbors: true);
      currentLevel = -1;
      redstoneState = false;
      sendData();
      _scheduleBlockTick(lvl);
      return;
    }

    currentLevel = thresholdClamp(currentLevel, currentMinLevel, currentMaxLevel);
    final changed = currentLevel != prevLevel;

    final next = thresholdRedstoneState(
      state: redstoneState,
      current: currentLevel,
      onWhenAbove: onWhenAbove,
      offWhenBelow: offWhenBelow,
    );
    redstoneState = next.state;
    final update = next.changed;

    final displayLevel = thresholdDisplayLevel(
      current: currentLevel,
      min: currentMinLevel,
      max: currentMaxLevel,
    );
    await lvl.setProps(_pos, {'level': '$displayLevel'}, neighbors: update);

    if (update) _scheduleBlockTick(lvl);

    if (changed || update) {
      await DisplayLinkBlock.notifyGatherers(lvl, _pos);
      sendData();
    }
  }

  /// `format(value, stacks)` for the screen: the unit text, or the probe's own format.
  Txt format(int value, bool stacks) {
    final type = typeOfCurrentTarget;
    if (type == ThresholdType.custom) {
      final w = world;
      final props = w == null ? null : Lvl(w).info(_pos)?.properties;
      if (w != null && props != null) {
        final target = _pos.relative(targetDirectionOf(props));
        for (final probe in _probes) {
          final observation = probe.observation(worldId, target);
          if (observation != null) return observation.format(value);
        }
      }
    }
    final suffix = type == ThresholdType.item
        ? (stacks ? 'create.schedule.condition.threshold.stacks' : 'create.schedule.condition.threshold.items')
        : 'create.schedule.condition.threshold.buckets';
    return Txt.literal('$value ').append(Txt.translate(suffix));
  }

  /// `getTypeOfCurrentTarget`: item, fluid, custom (a probe observation) or unsupported.
  ThresholdType get typeOfCurrentTarget {
    final w = world;
    if (w == null) return ThresholdType.unsupported;
    final lvl = Lvl(w);
    final props = lvl.info(_pos)?.properties;
    if (props == null) return ThresholdType.unsupported;
    final target = _pos.relative(targetDirectionOf(props));
    final targetPos = target.toBlockPos();
    final supported = thresholdTargetSupported(lvl.blockKey(target));
    if (supported && ItemHandlers.at(w, targetPos) != null) return ThresholdType.item;
    if (supported && w.fluidHandlerAt(targetPos) != null) return ThresholdType.fluid;
    for (final probe in _probes) {
      if (probe.observation(worldId, target) != null) return ThresholdType.custom;
    }
    return ThresholdType.unsupported;
  }

  List<ObservableProbe> get _probes =>
      Rs.i.ctx.services.find<ObservableRegistry>()?.probes ?? const <ObservableProbe>[];

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putFloat('OnAboveAmount', onWhenAbove.toDouble());
    tag.putFloat('OffBelowAmount', offWhenBelow.toDouble());
    tag.putBool('Inverted', inverted);
    tag.putInt('CurrentAmount', currentLevel);
    tag.putInt('CurrentMinAmount', currentMinLevel);
    tag.putInt('CurrentMaxAmount', currentMaxLevel);
    tag.putBool('InStacks', inStacks);
    tag.putBool('Powered', redstoneState);
    tag.putBool('PoweredAfterDelay', poweredAfterDelay);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    onWhenAbove = (tag.getDouble('OnAboveAmount') ?? 0).toInt();
    offWhenBelow = (tag.getDouble('OffBelowAmount') ?? 0).toInt();
    currentLevel = tag.getInt('CurrentAmount') ?? 0;
    currentMinLevel = tag.getInt('CurrentMinAmount') ?? 0;
    currentMaxLevel = tag.getInt('CurrentMaxAmount') ?? 0;
    inStacks = tag.getBool('InStacks') ?? false;
    redstoneState = tag.getBool('Powered') ?? false;
    inverted = tag.getBool('Inverted') ?? false;
    poweredAfterDelay = tag.getBool('PoweredAfterDelay') ?? false;
    super.read(tag, clientPacket: clientPacket);
  }
}

/// `ThresholdSwitchBlock`.
final class ThresholdSwitchBlock {
  static const String key = 'stockpile_switch';

  late final CreateBlock block;

  CreateBlock build() {
    block = buildManifestBlock(
      key,
      blockEntityType: ThresholdSwitchBlockEntity.type,
      behavior: BlockBehavior(
        onPlaced: _onPlaced,
        onScheduledTick: (server, e) async =>
            Rs.i.be<ThresholdSwitchBlockEntity>(e.targetWorld, e.pos)?.updatePowerAfterDelay(),
        onWeakPower: (server, e) {
          final p = block.stateOf(e.stateIndex);
          // `getSignal`: nothing towards the side opposite the observed block.
          if (e.face.toDirection() == targetDirectionOf(p).opposite) return 0;
          return Rs.i.be<ThresholdSwitchBlockEntity>(e.targetWorld, e.pos)?.isPowered == true ? 15 : 0;
        },
        canConnectRedstone: (server, e) {
          final side = e.direction?.toDirection();
          return side != null && side.opposite != targetDirectionOf(block.stateOf(e.stateIndex));
        },
        onUse: _onUse,
      ),
    );
    return block;
  }

  BlockEntityTypeSpec entitySpec() => BlockEntityTypeSpec(
    key: ThresholdSwitchBlockEntity.type,
    validBlocks: const [thresholdKey],
    create: ThresholdSwitchBlockEntity.new,
    tickInterval: 1,
  );

  Future<void> _onPlaced(Server server, CustomBlockPlacedEventData e) async {
    final lvl = Lvl(e.targetWorld);
    final ctx = placeContextOf(server, e);
    if (ctx != null) {
      final placeWorld = HostPlaceWorld(
        lvl,
        // Only containers count for the threshold switch.
        detectBlockEntity: (_) => false,
      );
      final placed = directedPlacement(ctx, placeWorld.canDetect);
      final current = block.stateOf(e.stateIndex);
      if (placed['target'] != current['target'] || placed['facing'] != current['facing']) {
        await lvl.setProps(e.pos.toPos(), placed);
      }
    }
    // onPlace: updateObservedInventory
    Rs.i.be<ThresholdSwitchBlockEntity>(e.targetWorld, e.pos)?.updateCurrentLevel();
  }

  /// `useItemOn`: the screen opens on the client; a wrench falls through.
  Future<BlockUseResult> _onUse(Server server, CustomBlockUseEventData e) async {
    if (e.withItem && await e.item.getRegistryKey() == 'create:wrench') return BlockUseResult.tryEmptyHand;
    return BlockUseResult.success;
  }

  /// The serverbound `create:configure_stockswitch` (`ConfigureThresholdSwitchPacket`).
  static void installPacket(RsRuntime rs) {
    final bus = rs.bus;
    if (bus == null) return;
    bus.onServerbound('create:configure_stockswitch', (player, f) {
      final pos = f['pos'] as (int, int, int);
      final world = player.getWorld();
      if (!configAllowed(player, world, pos)) return;
      final be = rs.be<ThresholdSwitchBlockEntity>(world, BlockPos(x: pos.$1, y: pos.$2, z: pos.$3));
      if (be == null) return;
      be.offWhenBelow = f['offBelow'] as int;
      be.onWhenAbove = f['onAbove'] as int;
      be.setInverted(f['invert'] == true);
      be.inStacks = f['inStacks'] == true;
      be.sendData();
    });
  }
}

/// The checks of `BlockEntityConfigurationPacket.handle`: no spectators or adventure players, the
/// position loaded and within 20 blocks of the player.
bool configAllowed(Player player, World world, (int, int, int) pos) {
  final mode = player.getGamemode();
  if (mode == GameMode.spectator || mode == GameMode.adventure) return false;
  if (!world.isLoaded(pos: BlockPos(x: pos.$1, y: pos.$2, z: pos.$3))) return false;
  // `player.isWithinBlockInteractionRange(pos, 20)`: the squared distance from the eye to
  // the block's box against `blockInteractionRange + 20`.
  final entity = player.asEntity();
  final (ex, ey, ez) = entity.getEyePosition();
  double gap(double v, double lo, double hi) => v < lo ? lo - v : (v > hi ? v - hi : 0);
  final dx = gap(ex, pos.$1.toDouble(), pos.$1 + 1);
  final dy = gap(ey, pos.$2.toDouble(), pos.$2 + 1);
  final dz = gap(ez, pos.$3.toDouble(), pos.$3 + 1);
  final reach = entity.asLiving()?.getAttributeValue(attr: Attribute.blockInteractionRange) ?? 4.5;
  final range = reach + 20;
  return dx * dx + dy * dy + dz * dz < range * range;
}
