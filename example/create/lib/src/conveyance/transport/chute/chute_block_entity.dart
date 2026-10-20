// `ChuteBlockEntity` and `SmartChuteBlockEntity` (server behaviour): the chute's one held item,
// its motion from the fans above/below, inserting into and pulling from the neighbouring
// inventories, chutes and belts, and the smart chute's filter and redstone gate.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../api/blocks.dart';
import '../../../common/direction.dart';
import '../../../common/host_bridge.dart';
import '../../../common/pos.dart';
import '../../belt/transported_item.dart';
import '../../../common/vec_helper.dart';
import '../../../core/block_entity.dart';
import '../../../processing/transport/transport_behaviours.dart' as pt;
import '../../behaviours/belt_interfaces.dart';
import '../../behaviours/filtering.dart';
import '../../behaviours/value_box.dart';
import '../../belt/belt_ports.dart';
import '../../items/inventory.dart';
import '../../items/item_codec.dart';
import '../../items/item_data.dart';
import '../../runtime.dart';
import '../transport_inventory.dart';
import '../transport_inventory_api.dart';
import '../transport_support.dart';

/// `ChuteBlockEntity`: one item travelling down (or up) a line of chutes.
class ChuteBlockEntity extends CreateBlockEntity
    implements ItemInventoryProvider, DirectBeltInput {
  ItemValue item = ItemValue.empty;
  double itemPosition = 0;

  double pull = 0;
  double push = 0;
  double bottomPullDistance = 0;
  double beltBelowOffset = 0;
  TransportedItemStackHandler? _beltBelow;
  bool canPickUpItems = false;

  bool _updateAirFlow = true;
  int _airCurrentUpdateCooldown = 0;
  int _entitySearchCooldown = 0;

  final VersionTracker _tracker = VersionTracker();
  late final _ChuteInventory _inventory = _ChuteInventory(this);

  ChuteBlockEntity(super.worldId, super.pos) {
    // The processing behaviour is the machine-facing counterpart of the pure interface this
    // class implements; both share the same insertion gate.
    addBehaviour(
      pt.DirectBeltInputBehaviour()
        ..onlyInsertWhen((side) => canDirectlyInsertCached)
        ..setInsertionHandler(
          (inserted, side, simulate) =>
              pStackOf(_insertDirect(inserted.stack, simulate)),
        ),
    );
  }

  ConveyanceRuntime get rt => ConveyanceRuntime.i;

  BState get state => rt.stateAt(worldId, this.pos.toPos());

  BState stateAt(Pos p) => rt.stateAt(worldId, p);

  // -- Item handler ----------------------------------------------------------------------------

  @override
  ItemInventory? itemInventory(Direction? side) => _inventory;

  @override
  bool get canSupportBeltFunnels => false;

  @override
  bool canInsertFromSide(Direction side) => canDirectlyInsertCached;

  @override
  bool isOccupied(Direction side) => false;

  @override
  FutureOr<ItemValue> handleInsertion(
    TransportedItemStack transported,
    Direction side, {
    bool simulate = false,
  }) => _insertDirect(pStackOf(transported.stack), simulate);

  /// The direct belt insertion: the same gate as `canDirectlyInsert`, then the item handler.
  ItemValue _insertDirect(PStack stack, bool simulate) =>
      _inventory.insert(0, itemValueOf(stack), simulate: simulate);

  /// `canDirectlyInsertCached`: the cached answer for this tick.
  bool get canDirectlyInsertCached => canPickUpItems;

  /// `canDirectlyInsert`.
  bool canDirectlyInsert() {
    final blockState = state;
    final above = stateAt(this.pos.toPos().above);
    if (!isChuteState(blockState)) return false;
    if (chuteFacing(above) == Direction.down) return false;
    if (getItemMotion() > 0 && inputChutes.isEmpty) return false;
    return isOpenChute(blockState);
  }

  /// `canAcceptItem`.
  bool canAcceptItem(ItemValue stack) => item.isEmpty;

  /// `getExtractionAmount`.
  int get extractionAmount => 16;

  /// `getExtractionMode`.
  ExtractionCountMode get extractionMode => ExtractionCountMode.upTo;

  /// `canActivate`.
  bool canActivate() => true;

  // -- Lifecycle -------------------------------------------------------------------------------

  @override
  void initialize() {
    super.initialize();
    onAdded();
  }

  @override
  Future<void> tick() async {
    super.tick();
    if (world != null) canPickUpItems = canDirectlyInsert();

    final itemMotion = getItemMotion();
    await _tickAirStreams(itemMotion);

    if (item.isEmpty) {
      if (itemMotion < 0) await _handleInputFromAbove();
      if (itemMotion > 0) await _handleInputFromBelow();
      return;
    }

    var nextOffset = itemPosition + itemMotion;

    if (itemMotion < 0) {
      if (nextOffset < .5) {
        if (!await _handleDownwardOutput(true)) {
          nextOffset = .5;
        } else if (nextOffset < 0) {
          await _handleDownwardOutput(false);
          nextOffset = itemPosition;
        }
      }
    } else if (itemMotion > 0) {
      if (nextOffset > .5) {
        if (!await _handleUpwardOutput(true)) {
          nextOffset = .5;
        } else if (nextOffset > 1) {
          await _handleUpwardOutput(false);
          nextOffset = itemPosition;
        }
      }
    }

    itemPosition = nextOffset;
  }

  @override
  void onRemoved() {
    super.onRemoved();
    final world = this.world;
    if (world != null && item.isNotEmpty) {
      rt.fire(
        'Dropping the chute item',
        () => dropItemAt(world, this.pos.toPos(), item),
      );
    }
    final target = getTargetChute(state);
    final inputs = inputChutes;
    setItem(ItemValue.empty);
    target?.updatePull();
    target?.propagatePush();
    for (final input in inputs) {
      input.updatePush(inputs.length);
    }
  }

  /// `onAdded`.
  void onAdded() {
    updatePull();
    final target = getTargetChute(state);
    if (target != null) {
      target.propagatePush();
    } else {
      updatePush(1);
    }
  }

  /// `blockBelowChanged`.
  void blockBelowChanged() => _updateAirFlow = true;

  // -- Item movement ---------------------------------------------------------------------------

  /// `getItemMotion`: the motion of the held item in blocks per tick.
  double getItemMotion() {
    const fanSpeedModifier = 1 / 64.0;
    const maxItemSpeed = 20.0;
    const gravity = 4.0;
    final motion = (push + pull) * fanSpeedModifier;
    final clamped = motion.clamp(-maxItemSpeed, maxItemSpeed);
    return (clamped + (motion <= 0 ? -gravity : 0)) / 20;
  }

  /// `setItem(stack)`.
  void setItem(ItemValue stack) =>
      setItemAt(stack, getItemMotion() < 0 ? 1 : 0);

  /// `setItem(stack, insertionPos)`.
  void setItemAt(ItemValue stack, double insertionPos) {
    item = stack;
    itemPosition = insertionPos;
    _tracker.reset();
    if (world != null) {
      markDirty();
      sendData();
    }
  }

  // -- Input -----------------------------------------------------------------------------------

  Future<void> _handleInputFromAbove() =>
      _handleInput(_grabCapability(Direction.up), 1);

  Future<void> _handleInputFromBelow() =>
      _handleInput(_grabCapability(Direction.down), 0);

  Future<void> _handleInput(ItemInventory? inv, double startLocation) async {
    if (inv == null || !canActivate()) return;
    if (_tracker.stillWaiting(versionOf(inv))) return;
    final count = extractionAmount;
    final mode = extractionMode;
    final extracted = await extractMatching(inv, canAcceptItem, mode, count);
    if (extracted.isNotEmpty) {
      setItemAt(extracted, startLocation);
      return;
    }
    _tracker.awaitNewVersion(versionOf(inv));
  }

  /// `grabCapability(side)`: the inventory next to this chute seen from [side], unless it is
  /// another chute (chutes hand items over directly).
  ItemInventory? _grabCapability(Direction side) {
    final target = this.pos.toPos().relative(side);
    final be = rt.beAt(worldId, target);
    if (be is ChuteBlockEntity) {
      if (side != Direction.down ||
          be is! SmartChuteBlockEntity ||
          getItemMotion() > 0)
        return null;
    }
    return ItemInventories.at(worldId, target, side: side.opposite);
  }

  // -- Output ----------------------------------------------------------------------------------

  Future<bool> _handleDownwardOutput(bool simulate) async {
    final blockState = state;
    final targetChute = getTargetChute(blockState);
    final direction = chuteFacing(blockState);
    if (direction == null || !canActivate()) return false;

    final capBelow = _grabCapability(Direction.down);
    if (capBelow != null) {
      if (_tracker.stillWaiting(versionOf(capBelow))) return false;
      final remainder = await insertStacked(capBelow, item, simulate: simulate);
      final held = item;
      if (!simulate) setItemAt(remainder, itemPosition);
      if (remainder.count != held.count) return true;
      _tracker.awaitNewVersion(versionOf(capBelow));
      if (direction == Direction.down) return false;
    }

    if (targetChute != null) {
      final canInsert = targetChute.canAcceptItem(item);
      if (!simulate && canInsert) {
        targetChute.setItemAt(item, direction == Direction.down ? 1 : .51);
        setItem(ItemValue.empty);
      }
      return canInsert;
    }

    // Diagonal chutes cannot drop items.
    if (direction.isHorizontal) return false;

    final below = this.pos.toPos().below;
    if (funnelFacing(stateAt(below)) == Direction.down) return false;
    final world = this.world;
    if (world == null) return false;
    if (HostBlockGetter(world).isFaceSturdy(below, Direction.up)) return false;

    if (!simulate) {
      final drop = (
        this.pos.x + .5,
        this.pos.y + .5 - 12 / 16.0,
        this.pos.z + .5,
      );
      await spawnItemEntity(world, drop, item, velocity: (0, -.25, 0));
      setItem(ItemValue.empty);
    }
    return true;
  }

  Future<bool> _handleUpwardOutput(bool simulate) async {
    final world = this.world;
    if (world == null || !canActivate()) return false;
    final above = this.pos.toPos().above;
    final stateAbove = stateAt(above);

    if (isOpenChute(state)) {
      final capAbove = _grabCapability(Direction.up);
      if (capAbove != null) {
        if (_tracker.stillWaiting(versionOf(capAbove))) return false;
        final countBefore = item.count;
        final remainder = await insertStacked(
          capAbove,
          item,
          simulate: simulate,
        );
        if (!simulate) item = remainder;
        if (countBefore != remainder.count) return true;
        _tracker.awaitNewVersion(versionOf(capAbove));
        return false;
      }
    }

    ChuteBlockEntity? bestOutput;
    final inputs = inputChutes;
    for (final target in inputs) {
      if (!target.canAcceptItem(item)) continue;
      final itemMotion = target.getItemMotion();
      if (itemMotion < 0) continue;
      if (bestOutput == null || bestOutput.getItemMotion() < itemMotion)
        bestOutput = target;
    }

    if (bestOutput != null) {
      if (!simulate) {
        bestOutput.setItemAt(item, 0);
        setItem(ItemValue.empty);
      }
      return true;
    }

    if (funnelFacing(stateAbove) == Direction.up) return false;
    if (HostBlockGetter(world).isFaceSturdy(above, Direction.down))
      return false;
    if (inputs.isNotEmpty) return false;

    if (!simulate) {
      final drop = (
        this.pos.x + .5,
        this.pos.y + .5 + 8 / 16.0,
        this.pos.z + .5,
      );
      await spawnItemEntity(
        world,
        drop,
        item,
        velocity: (0, getItemMotion() * 2, 0),
      );
      setItem(ItemValue.empty);
    }
    return true;
  }

  // -- Neighbour chutes ------------------------------------------------------------------------

  /// `getTargetChute(state)`.
  ChuteBlockEntity? getTargetChute(BState blockState) {
    final targetDirection = chuteFacing(blockState);
    if (targetDirection == null) return null;
    var chutePos = this.pos.toPos().below;
    if (targetDirection.isHorizontal)
      chutePos = chutePos.relative(targetDirection.opposite);
    if (!isChuteState(stateAt(chutePos))) return null;
    return rt.typedAt<ChuteBlockEntity>(worldId, chutePos);
  }

  /// `getInputChutes`.
  List<ChuteBlockEntity> get inputChutes {
    final out = <ChuteBlockEntity>[];
    for (final d in Direction.values) {
      final chute = _inputChute(d);
      if (chute != null) out.add(chute);
    }
    return out;
  }

  ChuteBlockEntity? _inputChute(Direction direction) {
    if (direction == Direction.down) return null;
    direction = direction.opposite;
    var chutePos = this.pos.toPos().above;
    if (direction.isHorizontal) chutePos = chutePos.relative(direction);
    final chuteFacingHere = chuteFacing(stateAt(chutePos));
    if (chuteFacingHere != direction) return null;
    final be = rt.typedAt<ChuteBlockEntity>(worldId, chutePos);
    if (be != null && !be.removed) return be;
    return null;
  }

  // -- Air flow (pull / push) ------------------------------------------------------------------

  void updatePull() {
    final totalPull = calculatePull();
    if (pull == totalPull) return;
    pull = totalPull;
    _updateAirFlow = true;
    sendData();
    getTargetChute(state)?.updatePull();
  }

  void updatePush(int branchCount) {
    final totalPush = calculatePush(branchCount);
    if (push == totalPush) return;
    _updateAirFlow = true;
    push = totalPush;
    sendData();
    propagatePush();
  }

  void propagatePush() {
    final inputs = inputChutes;
    for (final input in inputs) {
      input.updatePush(inputs.length);
    }
  }

  double calculatePull() {
    final above = this.pos.toPos().above;
    final fanSpeed = _fanSpeed(above, Direction.down);
    if (fanSpeed != null) return fanSpeed;

    var totalPull = 0.0;
    for (final d in Direction.values) {
      final input = _inputChute(d);
      if (input == null) continue;
      totalPull += input.pull;
    }
    return totalPull;
  }

  double calculatePush(int branchCount) {
    final below = this.pos.toPos().below;
    final fanSpeed = _fanSpeed(below, Direction.up);
    if (fanSpeed != null) return fanSpeed;

    final target = getTargetChute(state);
    if (target == null) return 0;
    return target.push / branchCount;
  }

  /// `EncasedFanBlockEntity.getSpeed()` of an encased fan at [p] facing [facing], if there is one.
  double? _fanSpeed(Pos p, Direction facing) {
    final s = stateAt(p);
    if (s.key != 'create:encased_fan' || s.dir('facing') != facing) return null;
    final be = rt.beAt(worldId, p);
    if (be == null || be.removed) return null;
    return rt.kinetics?.speedAt(worldId, p.toBlockPos()) ?? 0;
  }

  Future<void> _tickAirStreams(double itemSpeed) async {
    if (_airCurrentUpdateCooldown-- <= 0) {
      _airCurrentUpdateCooldown = rt.fanBlockCheckRate;
      _updateAirFlow = true;
    }
    if (_updateAirFlow) _updateAirFlowNow(itemSpeed);
    if (_entitySearchCooldown-- <= 0 && item.isEmpty) {
      _entitySearchCooldown = 5;
      await _findEntities(itemSpeed);
    }
    _extractFromBelt(itemSpeed);
  }

  void _updateAirFlowNow(double itemSpeed) {
    _updateAirFlow = false;
    if (itemSpeed <= 0 || world == null) return;

    final speed = pull - push;
    double maxPullDistance;
    if (speed >= 128) {
      maxPullDistance = 3;
    } else if (speed >= 64) {
      maxPullDistance = 2;
    } else if (speed >= 32) {
      maxPullDistance = 1;
    } else {
      // `Mth.lerp(speed / 32, 0, 1)`: unclamped, so a negative (pushing) fan gives a negative
      // pull distance and pulls nothing.
      maxPullDistance = _lerp(speed / 32, 0, 1);
    }
    if (isChuteState(stateAt(this.pos.toPos().below))) maxPullDistance = 0;

    // `AirCurrent.getFlowLimit` needs the fan air-current machinery; the fan's own range is used
    // as the limit here.
    final flowLimit = maxPullDistance;

    _beltBelow = null;
    // `if (flowLimit > 0)`: a chute that does not pull does not look for a belt either.
    if (flowLimit > 0) {
      for (var i = 1; i <= flowLimit + 1; i++) {
        final be = rt.beAt(worldId, this.pos.toPos().belowBy(i));
        if (be is TransportedItemStackHandler) {
          _beltBelow = be as TransportedItemStackHandler;
          beltBelowOffset = i - 1.0;
          break;
        }
      }
    }
    bottomPullDistance = math.max(0, flowLimit);
    sendData();
  }

  /// `Mth.lerp(delta, start, end)`.
  static double _lerp(double delta, double start, double end) =>
      start + (end - start) * delta;

  Future<void> _findEntities(double itemSpeed) async {
    if (bottomPullDistance <= 0 && item.isNotEmpty) return;
    if (itemSpeed <= 0 || world == null || !canActivate()) return;

    final center = this.pos.toPos().center;
    // `new AABB(center.add(0, -bottomPullDistance - .5, 0), center.add(0, -.5, 0)).inflate(.45f)`:
    // the inflation widens the box by .45 on all three axes, the vertical one included.
    final min = (
      center.$1 - .45,
      center.$2 - bottomPullDistance - .5 - .45,
      center.$3 - .45,
    );
    final max = (center.$1 + .45, center.$2 - .5 + .45, center.$3 + .45);
    for (final entity in itemEntitiesIn(world!, min, max)) {
      final value = await ItemCodec.read(entity.getStack());
      if (!canAcceptItem(value)) continue;
      final position = entity.asEntity().getPosition();
      setItemAt(value, position.$2 - this.pos.y);
      entity.discard();
      break;
    }
  }

  void _extractFromBelt(double itemSpeed) {
    if (itemSpeed <= 0 || world == null) return;
    final belt = _beltBelow;
    if (item.isNotEmpty || belt == null) return;
    belt.handleCenteredProcessingOnAllItems(.5, (transported) {
      if (!canAcceptItem(transported.stack))
        return TransportedResult.doNothing();
      setItemAt(transported.stack, -beltBelowOffset);
      return TransportedResult.removeItem();
    });
  }

  // -- Persistence -----------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag
      ..putCompound('Item', ItemCodec.toTag(item, clientPacket: clientPacket))
      ..putFloat('ItemPosition', itemPosition)
      ..putFloat('Pull', pull)
      ..putFloat('Push', push)
      ..putFloat('BottomAirFlowDistance', bottomPullDistance);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    item = ItemCodec.fromAnyNbt(tag.getCompound('Item'));
    itemPosition = tag.getDouble('ItemPosition') ?? 0;
    pull = tag.getDouble('Pull') ?? 0;
    push = tag.getDouble('Push') ?? 0;
    bottomPullDistance = tag.getDouble('BottomAirFlowDistance') ?? 0;
  }
}

/// `ChuteItemHandler`: the chute seen as one slot.
final class _ChuteInventory implements ItemInventory {
  final ChuteBlockEntity be;

  _ChuteInventory(this.be);

  @override
  int get slots => 1;

  @override
  ItemValue getStack(int slot) => be.item;

  @override
  int slotLimit(int slot) => be.item.isEmpty ? 64 : be.item.maxStack;

  @override
  bool isItemValid(int slot, ItemValue stack) => true;

  @override
  ItemValue insert(int slot, ItemValue stack, {bool simulate = false}) {
    if (!be.canAcceptItem(stack)) return stack;
    final max = stack.maxStack;
    final remainder = stack.count > max
        ? stack.withCount(stack.count - max)
        : ItemValue.empty;
    if (!simulate) be.setItem(stack);
    return remainder;
  }

  @override
  ItemValue extract(int slot, int amount, {bool simulate = false}) {
    final remainder = be.item;
    final (split, rest) = remainder.split(amount);
    if (!simulate) be.setItem(rest);
    return split;
  }
}

/// `SmartChuteBlockEntity`: a chute with a filter and a redstone gate.
class SmartChuteBlockEntity extends ChuteBlockEntity {
  late final FilteringBehaviour filtering;

  SmartChuteBlockEntity(super.worldId, super.pos) {
    filtering = addBehaviour(FilteringBehaviour(const FixedSlot(_filterSlot)))
      ..showCountWhen(isExtracting)
      ..withCallback((_) => _tracker.reset());
  }

  static Vec3 _filterSlot(BState state) => voxel(8, 12, 8);

  @override
  bool canAcceptItem(ItemValue stack) =>
      super.canAcceptItem(stack) && canActivate() && filtering.test(stack);

  @override
  int get extractionAmount =>
      filtering.isCountVisible && !filtering.anyAmount ? filtering.amount : 64;

  @override
  ExtractionCountMode get extractionMode =>
      filtering.isCountVisible && !filtering.anyAmount && !filtering.upTo
      ? ExtractionCountMode.exactly
      : ExtractionCountMode.upTo;

  @override
  bool canActivate() {
    final s = state;
    return s.has('powered') && !s.flag('powered');
  }

  /// `isExtracting`.
  bool isExtracting() {
    final up = getItemMotion() < 0;
    final chutePos = this.pos.toPos().relative(
      up ? Direction.up : Direction.down,
    );
    final s = stateAt(chutePos);
    return !isChuteState(s) && !s.isAir;
  }
}
