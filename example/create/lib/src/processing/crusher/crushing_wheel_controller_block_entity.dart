// `CrushingWheelControllerBlockEntity`: the invisible block between two crushing wheels. It
// pulls in dropped items, crushes them with a `create:crushing` (or `create:milling`) recipe,
// pushes entities along and damages them with `create:crush`, then ejects the results.
//
// The inventory is a [ProcessingInventory] (32 slots, input in slot 0, results in 1..n). The
// entity being crushed is kept by id and uuid only: host handles are only valid inside the
// callback that produced them.
import 'dart:async';
import 'dart:math' as math;

import 'package:pumpkin_api/pumpkin_api.dart';

import '../../api/kinetics.dart';
import '../../common/nbt_convert.dart';
import '../../core/block_entity.dart';
import '../../core/nbt.dart';
import '../common/capabilities.dart';
import '../common/stack.dart';
import '../common/storage.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe_book.dart';
import '../transport/transport_behaviours.dart';
import 'crushing_keys.dart';
import 'crushing_logic.dart';
import 'crushing_wheel_block_entity.dart';
import 'processing_inventory.dart';

/// The custom data key the ejected items carry so the same controller does not take them back
/// (`CrushingWheelControllerBlockEntity.checkEntityForProcessing`).
const String _bypassNamespace = 'create';
const String _bypassKey = 'bypass_crushing_wheel';

class CrushingWheelControllerBlockEntity extends CreateBlockEntity
    implements ItemStorageProvider {
  static const String type = crushingWheelControllerKey;

  late final ProcessingInventory inventory;
  late final DirectBeltInputBehaviour directBeltInput;

  /// `processingEntity`: the entity being crushed, as an id (resolved every tick).
  int? entityId;

  /// `entityUUID`: survives a reload, the id is looked up again (`searchForEntity`).
  Uuid? entityUuid;
  bool searchForEntity = false;

  /// `crushingspeed`: `|wheel speed| / 50`, set by [updateSpeed].
  double crushingspeed = 0;

  /// The tick body awaits host calls; do not start a second one while it runs.
  bool _ticking = false;

  CrushingWheelControllerBlockEntity(super.worldId, super.pos) {
    inventory = ProcessingInventory(onInserted: itemInserted);
    inventory.validator = (slot, stack) =>
        slot == 0 && inventory.isEmpty && !hasEntity;
    inventory.onChanged = (_) => markDirty();
    addBehaviour(
      directBeltInput = DirectBeltInputBehaviour()
        ..onlyInsertWhen(supportsDirectBeltInput)
        ..defaultInsertion = (inserted, side, simulate) =>
            ItemStorages.insertStacked(
              inventory,
              inserted.stack,
              simulate: simulate,
            ),
    );
  }

  // -- State ---------------------------------------------------------------------------------

  KState get blockState {
    final w = world;
    if (w == null) return KState.air;
    return KineticsRuntime.instance.level(worldId).stateAt(toKPos(pos));
  }

  bool get hasEntity => entityId != null;

  /// Whether [id] is the entity this controller is crushing (`processingEntity == entity`).
  bool isProcessingEntity(int id) => entityId == id;

  bool get isOccupied => hasEntity || !inventory.isEmpty;

  /// `supportsDirectBeltInput(side)`: belts may hand items to the output side only.
  bool supportsDirectBeltInput(String side) {
    final facing = blockState.dirOf('facing') ?? Dir.north;
    return facing == Dir.down || facing.name == side;
  }

  @override
  ItemStorage? itemStorage(String? side) => inventory;

  // -- Recipe --------------------------------------------------------------------------------

  /// `findRecipe`: `create:crushing` first, then `create:milling` (Java does the same for the
  /// crushing wheels).
  RecipeMatch? findRecipe(PStack stack) =>
      crushingRecipeFor(ProcessingRuntime.instance.recipes, stack);

  /// `itemInserted`: the timer of the item that just entered slot 0.
  void itemInserted(PStack stack) {
    final match = findRecipe(stack);
    inventory.remainingTime = (match?.recipe.processingDuration ?? 100)
        .toDouble();
    inventory.appliedRecipe = false;
  }

  /// `applyRecipe`: roll every item of the stack into the result slots.
  void applyRecipe() {
    final input = inventory.stackIn(0);
    final match = findRecipe(input);
    final list = <PStack>[];
    if (match != null) {
      final rolls = input.count;
      inventory.clear();
      final random = ProcessingRuntime.instance.random;
      for (var roll = 0; roll < rolls; roll++) {
        for (final stack in match.rollResults(random)) {
          _addToList(list, stack);
        }
      }
      for (
        var slot = 0;
        slot < list.length && slot + 1 < inventory.slots;
        slot++
      ) {
        inventory.setStack(slot + 1, list[slot]);
      }
    } else {
      inventory.clear();
    }
  }

  /// `ItemHelper.addToList`: merge into a matching entry, add a new one when it is full.
  static void _addToList(List<PStack> list, PStack stack) {
    if (stack.isEmpty) return;
    var rest = stack;
    for (var i = 0; i < list.length; i++) {
      final existing = list[i];
      if (!existing.sameItemSameComponents(rest)) continue;
      final limit = rest.maxStack;
      if (existing.count >= limit) continue;
      final moved = math.min(limit - existing.count, rest.count);
      list[i] = existing.grow(moved);
      rest = rest.shrink(moved);
      if (rest.isEmpty) return;
    }
    list.add(rest);
  }

  // -- Entity intake -------------------------------------------------------------------------

  /// `checkEntityForProcessing`: called from the block's `entityInside` hook.
  Future<void> checkEntityForProcessing(
    Server server,
    World world,
    int entityId,
    Uuid entityUuid,
  ) async {
    if (crushingspeed == 0) return;
    final entity = world.getEntityById(id: entityId);
    if (entity == null) return;
    if (_isBypassed(entity)) return;
    if (isOccupied) return;
    if (entity.type == EntityType.player) {
      final player = server.getPlayerByUuid(id: entityUuid);
      if (player != null && player.getGamemode() == GameMode.creative) return;
    }
    startCrushing(entityId, entityUuid, world);
  }

  /// `startCrushing`.
  void startCrushing(int id, Uuid uuid, World world) {
    entityId = id;
    entityUuid = uuid;
    searchForEntity = false;
    _invalidateShape(world);
  }

  /// `clear()`: nothing is being processed any more.
  void clear([World? world]) {
    entityId = null;
    entityUuid = null;
    searchForEntity = false;
    if (world != null) _invalidateShape(world);
  }

  /// Whether [entity] carries this controller's `BypassCrushingWheel` marker.
  bool bypasses(Entity entity) => _isBypassed(entity);

  bool _isBypassed(Entity entity) {
    final tree = entity.getCustomData(
      namespace: _bypassNamespace,
      key: _bypassKey,
    );
    if (tree == null) return false;
    final value = treeToValue(tree);
    if (value.kind != NbtKind.intArray) return false;
    final arr = value.value as List<int>;
    return arr.length >= 3 &&
        arr[0] == pos.x &&
        arr[1] == pos.y &&
        arr[2] == pos.z;
  }

  void _markBypassed(Entity entity) => entity.setCustomData(
    namespace: _bypassNamespace,
    key: _bypassKey,
    value: valueToTree(NbtValue.intArray([pos.x, pos.y, pos.z])),
  );

  /// `updateSpeed(state)`: picks the speed of an adjacent wheel (`CrushingWheelControllerBlock`).
  void updateSpeed(KState state) {
    if (!state.flag('valid')) {
      if (crushingspeed != 0) {
        crushingspeed = 0;
        sendData();
      }
      return;
    }
    final level = KineticsRuntime.instance.level(worldId);
    final kpos = toKPos(pos);
    for (final d in Dir.values) {
      final neighbour = level.stateAt(kpos.relative(d));
      if (neighbour.block != crushingWheelKey) continue;
      if (neighbour.axisOf('axis') == d.axis) continue;
      final wheel = store.typed<CrushingWheelBlockEntity>(
        worldId,
        toBlockPos(kpos.relative(d)),
      );
      if (wheel == null) continue;
      crushingspeed = (wheel.speed / 50).abs();
      sendData();
      break;
    }
  }

  // -- Ticking -------------------------------------------------------------------------------

  @override
  void tick() {
    super.tick();
    if (_ticking) return;
    _ticking = true;
    unawaited(
      _tick()
          .catchError((Object e, StackTrace s) {
            ProcessingRuntime.instance.log.error(
              'The crushing wheel controller at ${pos.x}, ${pos.y}, ${pos.z} failed',
              error: e,
              stackTrace: s,
            );
          })
          .whenComplete(() {
            _ticking = false;
          }),
    );
  }

  Future<void> _tick() async {
    final w = world;
    if (w == null) return;

    if (searchForEntity) {
      searchForEntity = false;
      final uuid = entityUuid;
      if (uuid != null) {
        final box = Cuboid.corners(
          (pos.x, pos.y, pos.z),
          (pos.x, pos.y, pos.z),
        );
        for (final snapshot in w.entitiesIn(box)) {
          if (snapshot.uuid.equals(uuid)) {
            entityId = snapshot.id;
            break;
          }
        }
      }
      if (entityId == null) {
        clear(w);
        return;
      }
    }

    if (!isOccupied) return;
    if (crushingspeed == 0) return;

    final facing = blockState.dirOf('facing') ?? Dir.north;
    final speed = crushingspeed * 4;
    final center = (pos.x + .5, pos.y + .5, pos.z + .5);
    final outSpeed = ejectionMotion(facing);
    final outPos = ejectionPosition(center, facing);

    if (!hasEntity) {
      final input = inventory.stackIn(0);
      inventory.remainingTime -= itemProcessingSpeed(
        speed,
        input.count,
        inventory.appliedRecipe,
      );

      if (inventory.remainingTime < 20 && !inventory.appliedRecipe) {
        applyRecipe();
        inventory.appliedRecipe = true;
        markDirty();
        sendData();
        return;
      }
      if (inventory.remainingTime > 0) return;
      inventory.remainingTime = 0;
      await _output(w, facing, outPos, outSpeed);
      return;
    }

    await _tickEntity(w, facing, center, outPos);
  }

  /// The item path: hand the results to a belt below, or eject them as item entities.
  Future<void> _output(
    World w,
    Dir facing,
    (double, double, double) outPos,
    (double, double, double) outSpeed,
  ) async {
    if (facing != Dir.up) {
      final next = toKPos(pos)
          .below()
          .relative(facing, facing.axis == KAxis.y ? 0 : 1);
      final behaviour = store
          .at(worldId, toBlockPos(next))
          ?.getBehaviour<DirectBeltInputBehaviour>();
      if (behaviour != null) {
        if (!behaviour.canInsertFromSide(facing.name)) return;
        var changed = false;
        for (var slot = 0; slot < inventory.slots; slot++) {
          final stack = inventory.stackIn(slot);
          if (stack.isEmpty) continue;
          final remainder = behaviour.handleInsertionOfStack(
            stack,
            facing.name,
            false,
          );
          if (remainder == stack) continue;
          inventory.setStack(slot, remainder);
          changed = true;
        }
        if (changed) {
          markDirty();
          sendData();
        }
        return;
      }
    }

    for (var slot = 0; slot < inventory.slots; slot++) {
      final stack = inventory.stackIn(slot);
      if (stack.isEmpty) continue;
      final host = await HostStacks.write(stack);
      if (host == null) continue;
      final item = await w.dropItem(outPos, host, velocity: outSpeed);
      if (item != null) _markBypassed(item.asEntity());
    }
    inventory.clear();
    markDirty();
    sendData();
    _invalidateShape(w);
  }

  /// The entity path: keep the entity in place, crush it, or take a dropped item in.
  Future<void> _tickEntity(
    World w,
    Dir facing,
    (double, double, double) center,
    (double, double, double) outPos,
  ) async {
    final id = entityId;
    final entity = id == null ? null : w.getEntityById(id: id);
    if (entity == null || !_isAlive(entity) || !_intersectsBlock(entity)) {
      clear(w);
      return;
    }

    final entityPos = entity.getPosition();
    entity.setVelocity(
      velocity: entityPushVelocity(
        facing: facing,
        crushingspeed: crushingspeed,
        center: center,
        entityPos: entityPos,
        sneaking: entity.isSneaking(),
      ),
    );

    final item = entity.asItem();
    if (item == null) {
      final entityOutPos = entityEjectionPosition(outPos, facing);
      final damage =
          (ProcessingRuntime
                      .instance
                      .configs
                      ?.server
                      .kinetics
                      .crushingDamage
                      .value ??
                  4)
              .toDouble();
      final living = entity.asLiving();
      if (living == null) return;
      // Move the entity before the lethal blow, so its drops appear at the output.
      if (living.getHealth() - damage <= 0) {
        entity.setPositionRotationDelta(
          pos: entityOutPos,
          yaw: entity.getYaw(),
          pitch: entity.getPitch(),
          velocity: entity.getVelocity(),
        );
      }
      await living.damageByKey(amount: damage, damageTypeKey: 'create:crush');
      if (living.isDead()) {
        entity.setPositionRotationDelta(
          pos: entityOutPos,
          yaw: entity.getYaw(),
          pitch: entity.getPitch(),
          velocity: entity.getVelocity(),
        );
      }
      return;
    }

    item.setPickupDelay(ticks: 20);
    final coord = facing.axis.chooseD(entityPos.$1, entityPos.$2, entityPos.$3);
    final centerCoord = facing.axis.chooseD(center.$1, center.$2, center.$3);
    if (intakesItem(facing, coord, centerCoord)) await _intake(w, item);
  }

  /// `intakeItem`: move the dropped item into the working slot and discard the entity.
  Future<void> _intake(World w, ItemEntity item) async {
    final stack = await HostStacks.read(item.getStack());
    inventory.clear();
    inventory.setStack(0, stack);
    itemInserted(stack);
    item.discard();
    markDirty();
    sendData();
    _invalidateShape(w);
  }

  bool _isAlive(Entity entity) {
    final living = entity.asLiving();
    return living == null || !living.isDead();
  }

  /// `processingEntity.getBoundingBox().intersects(new AABB(worldPosition).inflate(.5f))`.
  bool _intersectsBlock(Entity entity) {
    final box = entity.getBoundingBox();
    const inflate = .5;
    final minX = pos.x - inflate,
        minY = pos.y - inflate,
        minZ = pos.z - inflate;
    final maxX = pos.x + 1 + inflate,
        maxY = pos.y + 1 + inflate,
        maxZ = pos.z + 1 + inflate;
    return box.min.$1 < maxX &&
        box.max.$1 > minX &&
        box.min.$2 < maxY &&
        box.max.$2 > minY &&
        box.min.$3 < maxZ &&
        box.max.$3 > minZ;
  }

  /// The collision shape is empty while an entity is being crushed (it would push it out).
  void _invalidateShape(World world) => world.invalidateShape(pos);

  // -- Persistence ---------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);

    final uuid = entityUuid;
    if (hasEntity && uuid != null) {
      tag.putIntArray('Entity', [
        (uuid.high >> 32) & 0xFFFFFFFF,
        uuid.high & 0xFFFFFFFF,
        (uuid.low >> 32) & 0xFFFFFFFF,
        uuid.low & 0xFFFFFFFF,
      ]);
    }

    final inventoryTag = StackNbt.writeList(inventory.contents)
      ..putFloat('ProcessingTime', inventory.remainingTime)
      ..putFloat('RecipeTime', inventory.recipeDuration)
      ..putBool('AppliedRecipe', inventory.appliedRecipe);
    tag.putCompound('Inventory', inventoryTag);
    tag.putFloat('Speed', crushingspeed);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);

    final entity = tag.getIntArray('Entity');
    if (entity != null && entity.length >= 4 && !isOccupied) {
      entityUuid = Uuid(
        high: (entity[0] << 32) | (entity[1] & 0xFFFFFFFF),
        low: (entity[2] << 32) | (entity[3] & 0xFFFFFFFF),
      );
      searchForEntity = true;
    }
    crushingspeed = tag.getDouble('Speed') ?? 0;

    final inventoryTag = tag.getCompound('Inventory');
    inventory.load(StackNbt.readList(inventoryTag, ProcessingInventory.size));
    inventory.remainingTime = inventoryTag?.getDouble('ProcessingTime') ?? 0;
    inventory.recipeDuration = inventoryTag?.getDouble('RecipeTime') ?? 0;
    inventory.appliedRecipe = inventoryTag?.getBool('AppliedRecipe') ?? false;
    if (inventory.isEmpty) inventory.appliedRecipe = false;
  }

  /// `CrushingWheelControllerBlock`'s removal cleanup: the contents are dropped when the
  /// controller goes away (Java's 26.3 fork has this as an open TODO).
  @override
  void onRemoved() {
    super.onRemoved();
    final w = world;
    if (w == null) return;
    unawaited(
      () async {
        for (final stack in inventory.contents) {
          if (stack.isEmpty) continue;
          final host = await HostStacks.write(stack);
          if (host != null) {
            await w.dropItem((pos.x + .5, pos.y + .5, pos.z + .5), host);
          }
        }
        inventory.clear();
      }().catchError((Object e, StackTrace s) {
        ProcessingRuntime.instance.log.error(
          'Dropping the contents of the crushing wheel controller failed',
          error: e,
          stackTrace: s,
        );
      }),
    );
  }
}
