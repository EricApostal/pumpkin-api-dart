// `FunnelBlockEntity` (server behaviour): the andesite/brass funnels and the belt funnels. A
// funnel either collects items (dropped items and belts in front of its open face, inserted into
// the inventory behind it) or extracts them (pulled out of that inventory and spat out in front).
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

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

  FunnelBlockEntity(super.worldId, super.pos) {
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
    final stack = await extractMatching(inv, (_) => true, mode, amount);
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
      (_) => true,
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

    final stack = await extractMatching(inv, (_) => true, mode, amount);
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
  int get amountToExtract {
    if (!supportsAmountOnFilter()) return 64;
    final amount = filtering.amount;
    if (!filtering.isActive) return 1;
    return amount;
  }

  @override
  ExtractionCountMode get modeToExtract {
    if (!supportsAmountOnFilter() || !filtering.isActive)
      return ExtractionCountMode.upTo;
    return filtering.upTo
        ? ExtractionCountMode.upTo
        : ExtractionCountMode.exactly;
  }

  @override
  Future<ItemValue> insert(ItemValue stack, {required bool simulate}) async {
    final inv = _inventoryBehind();
    if (inv == null) return stack;
    return insertStacked(inv, stack, simulate: simulate);
  }

  @override
  void flap(bool inward) {
    final world = this.world;
    if (world != null)
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
    // `SmartObserverBlock.onFunnelTransfer`: observers aimed at this funnel with a matching filter
    // fire. The funnel advancement is placer bound and has no behaviour to award it from here.
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
