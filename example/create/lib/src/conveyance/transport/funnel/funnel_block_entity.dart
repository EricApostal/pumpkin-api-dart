// `FunnelBlockEntity` (server behaviour): the andesite/brass funnels and the belt funnels. A
// funnel either collects items (dropped items and belts in front of its open face, inserted into
// the inventory behind it) or extracts them (pulled out of that inventory and spat out in front).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/advancements.dart';
import '../../../api/blocks.dart';
import '../../../api/redstone.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../../core/block_entity.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../behaviours/filtering.dart';
import '../../behaviours/processing_bridge.dart';
import '../../behaviours/value_box.dart';
import '../../belt/belt_ports.dart';
import '../../belt/transported_item.dart';
import '../../items/inventory.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../transport_inventory.dart';
import '../transport_inventory_api.dart';
import '../transport_support.dart';
import 'funnel_logic.dart';

/// `FunnelBlockEntity.Mode`.
enum _FunnelMode {
  invalid,
  paused,
  collect,
  pushingToBelt,
  takingFromBelt,
  extract,
}

/// `FunnelBlockEntity`.
class FunnelBlockEntity extends CreateBlockEntity
    implements
        ItemInventoryProvider,
        DirectBeltInput,
        FunnelPort,
        BeltFunnelPort {
  late final FilteringBehaviour filtering;
  final VersionTracker invVersionTracker = VersionTracker();
  int extractionCooldown = 0;

  /// `registerAwardables(behaviours, AllAdvancements.FUNNEL)` (`Java FunnelBlockEntity.java:273`):
  /// the player that placed the funnel gets it on its first transfer (`onTransfer`).
  late final AdvancementBehaviour advancements;

  FunnelBlockEntity(super.worldId, super.pos) {
    advancements = addBehaviour(
      AdvancementBehaviour([AllAdvancements.funnel], () => rt.advancements),
    );
    filtering = addBehaviour(FilteringBehaviour(const FixedSlot(_filterSlot)))
      ..showCountWhen(supportsAmountOnFilter)
      ..onlyActiveWhen(supportsFiltering)
      ..withCallback((_) => invVersionTracker.reset());
  }

  static Vec3 _filterSlot(BState state) => voxel(8, 6, 15.5);

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  BState get state => rt.stateAt(worldId, this.pos.toPos());

  BState stateAt(Pos p) => rt.stateAt(worldId, p);

  /// `AbstractFunnelBlock.getFunnelFacing`.
  @override
  Direction get facing => funnelFacing(state) ?? Direction.north;

  // -- Mode ------------------------------------------------------------------------------------

  _FunnelMode _determineCurrentMode() {
    final blockState = state;
    if (!isFunnelState(blockState) && !isBeltFunnelState(blockState)) {
      return _FunnelMode.invalid;
    }
    if (blockState.flag('powered')) return _FunnelMode.paused;
    if (isBeltFunnelState(blockState)) {
      final shape = blockState['shape'];
      if (shape == 'pulling') return _FunnelMode.takingFromBelt;
      if (shape == 'pushing') return _FunnelMode.pushingToBelt;
      final belt = rt.beAt(worldId, this.pos.toPos().below);
      if (belt is BeltEnvironment) {
        return (belt as BeltEnvironment).movementFacing ==
                blockState.dir('facing')
            ? _FunnelMode.pushingToBelt
            : _FunnelMode.takingFromBelt;
      }
      return _FunnelMode.invalid;
    }
    return blockState.flag('extracting')
        ? _FunnelMode.extract
        : _FunnelMode.collect;
  }

  @override
  void tick() {
    super.tick();
    if (world == null) return;
    final mode = _determineCurrentMode();
    if (mode == _FunnelMode.paused) extractionCooldown = 0;
    if (mode == _FunnelMode.takingFromBelt) return;
    if (extractionCooldown > 0) {
      extractionCooldown--;
      return;
    }
    if (mode == _FunnelMode.pushingToBelt) {
      rt.fire('Belt funnel output', activateExtractingBeltFunnel);
    } else if (mode == _FunnelMode.extract) {
      rt.fire('Funnel extraction', activateExtractor);
    }
  }

  // -- Extraction ------------------------------------------------------------------------------

  Future<void> activateExtractor() async {
    final inv = _inventoryBehind();
    if (inv == null || invVersionTracker.stillWaiting(versionOf(inv))) return;
    if (_blockedByOverflow()) return;

    final amount = amountToExtract;
    final mode = modeToExtract;
    // `InvManipulationBehaviour.getFilterTest`: the funnel's filter is ANDed into every
    // extraction (`invManipulation.extract(mode, amount)`).
    final stack = await extractMatching(inv, filtering.test, mode, amount);
    if (stack.isEmpty) {
      invVersionTracker.awaitNewVersion(versionOf(inv));
      return;
    }

    flap(false);
    onTransfer(stack);

    final world = this.world;
    if (world == null) return;
    var output = this.pos.toPos().center;
    final vertical = facing.isVertical;
    final up = facing == Direction.up;
    final scale = vertical ? (up ? .15 : .5) : .25;
    output = (
      output.$1 + facing.stepX * scale,
      output.$2 + facing.stepY * scale,
      output.$3 + facing.stepZ * scale,
    );
    if (!vertical) output = (output.$1, output.$2 - .45, output.$3);
    final motion = up ? (0.0, 4 / 16.0, 0.0) : (0.0, 0.0, 0.0);
    await spawnItemEntity(world, output, stack, velocity: motion);
    startCooldown();
  }

  /// `getEntityOverflowScanningArea` check: an item already sits in front of the funnel.
  bool _blockedByOverflow() {
    final world = this.world;
    if (world == null) return false;
    final center = this.pos.toPos().center;
    final below = facing != Direction.up;
    final min = (
      center.$1 - .5,
      center.$2 - (below ? 1.5 : .5),
      center.$3 - .5,
    );
    final max = (center.$1 + .5, center.$2 + .5, center.$3 + .5);
    return itemEntitiesIn(world, min, max).isNotEmpty;
  }

  Future<void> activateExtractingBeltFunnel() async {
    final inv = _inventoryBehind();
    if (inv == null || invVersionTracker.stillWaiting(versionOf(inv))) return;

    final side = state.dir('facing') ?? Direction.north;
    final beltPos = this.pos.toPos().below;
    final belt = rt.beAt(worldId, beltPos);
    if (belt == null) return;
    if (!_canInsertAt(beltPos, side)) return;
    if (_isOccupiedAt(beltPos, side)) return;

    final amount = amountToExtract;
    final mode = modeToExtract;

    // Peek at what would be extracted, then check that the belt accepts it before taking it.
    final peek = await extractMatching(
      inv,
      filtering.test,
      mode,
      amount,
      simulate: true,
    );
    if (peek.isEmpty) {
      invVersionTracker.awaitNewVersion(versionOf(inv));
      return;
    }
    final remainder = await _insertAt(beltPos, peek, side, true);
    if (remainder.isNotEmpty) return;

    final stack = await extractMatching(inv, filtering.test, mode, amount);
    if (stack.isEmpty) return;
    flap(false);
    onTransfer(stack);
    await _insertAt(beltPos, stack, side, false);
    startCooldown();
  }

  int startCooldown() => extractionCooldown = rt.defaultExtractionTimer;

  // -- FunnelPort ------------------------------------------------------------------------------

  @override
  bool get hasInserting => _inventoryBehind() != null;

  @override
  bool filterRejects(ItemValue stack) => !filtering.test(stack);

  @override
  (int, int)? get inventoryVersion => versionOf(_inventoryBehind());

  @override
  int get amountToExtract => funnelExtractionAmount(
    supportsAmount: supportsAmountOnFilter(),
    filterActive: filtering.isActive,
    filterAmount: filtering.amount,
  );

  @override
  ExtractionCountMode get modeToExtract => funnelExtractionMode(
    supportsAmount: supportsAmountOnFilter(),
    filterActive: filtering.isActive,
    filterUpTo: filtering.upTo,
  );

  @override
  Future<ItemValue> insert(ItemValue stack, {required bool simulate}) async {
    final inv = _inventoryBehind();
    if (inv == null) return stack;
    return insertStacked(inv, stack, simulate: simulate);
  }

  /// `AbstractFunnelBlock.tryInsert`: the funnel's filter is checked, then the stack goes into
  /// the inventory behind the open face. Returns the remainder (the whole stack when refused).
  Future<ItemValue> tryInsert(
    ItemValue stack, {
    required bool simulate,
  }) async {
    if (!filtering.test(stack)) return stack;
    final inv = _inventoryBehind();
    if (inv == null) return stack;
    final insert = await insertStacked(inv, stack, simulate: simulate);
    if (!simulate && insert.count != stack.count) {
      onTransfer(stack);
      // `if (funnelBlockEntity.hasFlap())`: only a funnel with a horizontal facing has a flap.
      if (funnelFacing(state)?.isHorizontal ?? false) flap(true);
    }
    return insert;
  }

  /// `DirectBeltInputBehaviour.tryExportingToBeltFunnel` for this funnel: `null` when the block
  /// above a depot/ejector is not a pulling belt funnel (or has no block entity). A powered
  /// funnel takes nothing, so the stack comes back unchanged.
  Future<ItemValue?> tryExportingToBeltFunnel(
    ItemValue stack,
    Direction? side, {
    required bool simulate,
  }) async {
    final blockState = state;
    if (!beltFunnelTakesOutput(blockState, side)) return null;
    if (blockState.flag('powered')) return stack;
    final insert = await tryInsert(stack, simulate: simulate);
    if (insert.count != stack.count && !simulate) flap(true);
    return insert;
  }

  @override
  void flap(bool inward) {
    final world = this.world;
    if (world == null) return;
    // `FunnelBlockEntity.flap`: the server tells the clients tracking the funnel which way the
    // flap moved; the sound follows the animation there. Only a client sends nothing.
    rt.bus?.sendToTracking('create:funnel_flap', world, this.pos, {
      'pos': this.pos.toPos(),
      'inwards': inward,
    });
    rt.playCreateSound(
      world,
      this.pos.toPos(),
      'funnel_flap',
      volume: 1,
      pitch: 1,
    );
  }

  @override
  void onTransfer(ItemValue stack) {
    // `onTransfer(stack)` -> `award(AllAdvancements.FUNNEL)` (`Java FunnelBlockEntity.java:369`):
    // the player that placed the funnel gets it on its first transfer.
    unawaited(advancements.awardPlayer(AllAdvancements.funnel));
    // `SmartObserverBlock.onFunnelTransfer`: observers aimed at this funnel with a matching filter
    // fire.
    final world = this.world;
    if (world == null) return;
    final display = rt.ctx.services.find<RedstoneDisplayApi>();
    if (display == null) return;
    final pos = this.pos;
    rt.fire(
      'Funnel transfer notification',
      () => display.onFunnelTransfer(world, pos, stack.key),
    );
  }

  bool supportsAmountOnFilter() {
    final blockState = state;
    var beltFunnelSupportsAmount = false;
    if (isBeltFunnelState(blockState)) {
      beltFunnelSupportsAmount =
          blockState['shape'] == 'pushing' ||
          rt.beAt(worldId, this.pos.toPos().below) != null;
    }
    final extractor =
        isFunnelState(blockState) && blockState.flag('extracting');
    return beltFunnelSupportsAmount || extractor;
  }

  bool supportsFiltering() {
    final key = state.key;
    return key == 'create:brass_funnel' || key == 'create:brass_belt_funnel';
  }

  bool supportsDirectBeltInput(Direction side) {
    final blockState = state;
    if (!isFunnelState(blockState)) return false;
    if (blockState.flag('extracting')) return false;
    return funnelFacing(blockState) == Direction.up;
  }

  Future<ItemValue> _handleDirectInsertion(
    ItemValue inserted,
    Direction side,
    bool simulate,
  ) async {
    if (!filtering.test(inserted)) return inserted;
    if (_determineCurrentMode() == _FunnelMode.paused) return inserted;
    if (!simulate) onTransfer(inserted);
    final inv = _inventoryBehind();
    if (inv == null) return inserted;
    return insertStacked(inv, inserted, simulate: simulate);
  }

  // -- BeltFunnelPort --------------------------------------------------------------------------

  @override
  String get shape => state['shape'] ?? 'retracted';

  @override
  bool get powered => state.flag('powered');

  @override
  FunnelPort? get entity => this;

  // -- DirectBeltInput -------------------------------------------------------------------------

  @override
  bool get canSupportBeltFunnels => false;

  @override
  bool canInsertFromSide(Direction side) => supportsDirectBeltInput(side);

  @override
  bool isOccupied(Direction side) => false;

  @override
  FutureOr<ItemValue> handleInsertion(
    TransportedItemStack transported,
    Direction side, {
    bool simulate = false,
  }) => _handleDirectInsertion(transported.stack, side, simulate);

  // -- ItemInventoryProvider -------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) => null;

  // -- Inventory behind ------------------------------------------------------------------------

  ItemInventory? _inventoryBehind() {
    final blockState = state;
    final facing = funnelFacing(blockState);
    if (facing == null) return null;
    return ItemInventories.at(
      worldId,
      this.pos.toPos().relative(facing.opposite),
    );
  }

  /// The inventory this funnel inserts into and extracts from (the block behind its open face).
  ItemInventory? get itemInventoryBehind => _inventoryBehind();

  DirectBeltInput? _directInputAt(Pos p) {
    final be = rt.beAt(worldId, p);
    if (be is DirectBeltInput) return be as DirectBeltInput;
    final behaviour = be?.getBehaviour<pt.DirectBeltInputBehaviour>();
    return behaviour == null ? null : DirectInputAdapter(behaviour);
  }

  bool _canInsertAt(Pos p, Direction side) =>
      _directInputAt(p)?.canInsertFromSide(side) ?? false;

  bool _isOccupiedAt(Pos p, Direction side) =>
      _directInputAt(p)?.isOccupied(side) ?? false;

  Future<ItemValue> _insertAt(
    Pos p,
    ItemValue stack,
    Direction side,
    bool simulate,
  ) async {
    final input = _directInputAt(p);
    if (input == null) return stack;
    return input.handleInsertion(
      TransportedItemStack(stack),
      side,
      simulate: simulate,
    );
  }

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('TransferCooldown', extractionCooldown);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    extractionCooldown = tag.getInt('TransferCooldown') ?? 0;
  }
}
