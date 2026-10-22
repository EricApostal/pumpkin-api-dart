// The block entity of the portable engine: a single-slot fuel burner that is a
// kinetic generator.
//
// Java: `PortableEngineBlockEntity extends GeneratingKineticBlockEntity`, with
// `PortableEngineInventory` (one slot, 64 items) and a scroll box for the
// rotation direction. The burn state machine is in `portable_engine_logic.dart`;
// this file is the host glue: kinetics, the slot, the block state, the
// comparator and NBT.
//
// What is not here, because the port has no counterpart:
//   * the client half (`PortableEngineRenderer`, the hatch animation, the
//     particle bursts and the ambient sounds, all run by the client tick);
//   * `SimStats.PORTABLE_ENGINES_FED` and the two advancements
//     (`steamless_engine`, `that_should_do_for_now`): the port awards no
//     advancements for engine use;
//   * the crafting remainder of a burnt item (a lava bucket leaves no bucket):
//     the plugin API has no `ItemStack.getCraftingRemainder`, so a fuel item is
//     only ever shrunk;
//   * the light level of a lit engine (Java: 6): a plugin block's `luminance` is
//     one number for all of its states.
//
// The slot is the block entity's own (`SmartInventory`, the port's
// `PortableEngineInventory`), not a host plugin inventory: the host can give a
// block entity a fixed inventory it owns (`PluginInventories`), but that slot is
// only reachable with the asynchronous `ItemHandler` calls, and the burn step
// runs in the synchronous block entity tick. A hopper therefore cannot feed the
// engine; feeding it by hand is the interaction `PortableEngineBlock.useItemOn`
// ports (the same host gap `fluids/drain.dart` documents).
//
// Host: this file uses `pumpkin_api`; create's internals are implementation
// imports, as in the other block entities of this package.
//
// Java: dev.simulated_team.simulated.content.blocks.portable_engine.PortableEngineBlockEntity
// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:math' as math;

import 'package:create/src/api/blocks.dart' show HostBlockGetter;
import 'package:create/src/kinetics/behaviours.dart' show ScrollValueBehaviour;
import 'package:create/src/kinetics/geometry.dart' show Dir;
import 'package:create/src/kinetics/kinetic_block_entity.dart'
    show GeneratingKineticBlockEntity, KineticOps;
import 'package:create/src/kinetics/runtime.dart' show KineticsRuntime;
import 'package:create/src/kinetics/settings.dart' show convertToDirection;
import 'package:create/src/processing/common/stack.dart' show PStack;
import 'package:create/src/processing/common/storage.dart' show SmartInventory;
import 'package:create/src/processing/host/stack_host.dart' show HostStacks, StackNbt;
import 'package:pumpkin_api/pumpkin_api.dart';

import '../../../service/sim_services.dart';
import 'portable_engine_logic.dart';

/// `PortableEngineBlockEntity`.
final class PortableEngineBlockEntity extends GeneratingKineticBlockEntity {
  /// The block entity type key (`SimBlockEntityTypes.PORTABLE_ENGINE`).
  static const String type = 'simulated:portable_engine';

  /// `PortableEngineInventory`: one slot of 64.
  static const int slotLimit = 64;

  PortableEngineBlockEntity(super.worldId, super.pos) {
    movementDirection = addBehaviour(
      ScrollValueBehaviour()..between(0, movementModeCount - 1),
    );
    inventory = SmartInventory(
      1,
      stackSize: slotLimit,
      onChanged: (slot) => markDirty(),
    )..validator = (slot, stack) => canInsert(stack.key);
  }

  /// `movementDirection`: `ScrollOptionBehaviour<MovementMode>`. Java cycles
  /// through `IControlContraption.MovementMode.values()`; only `> 0` matters to
  /// the engine, which reverses its rotation.
  late final ScrollValueBehaviour movementDirection;

  /// `PortableEngineInventory.inventory`: one slot that takes fuel only.
  late final SmartInventory inventory;

  /// `burnTime`, `superHeated`, `eatingCake`.
  final PortableEngineBurn burn = PortableEngineBurn();

  final math.Random _random = math.Random();

  /// `level.getGameTime() % 60` of Java; the plugin API has no game time, so the
  /// engine counts its own ticks (same period, its own phase).
  int _ticks = 0;

  /// `HORIZONTAL_FACING` of the block.
  Dir get facing => blockState.dirOf('facing') ?? Dir.north;

  /// `convertToDirection(1, HORIZONTAL_FACING)`.
  int get directionSign => convertToDirection(1, facing).toInt();

  @override
  double get generatedSpeed =>
      burn.generatedSpeed(movementDirection.value, directionSign);

  /// `PortableEngineInventory.canInsertItem`: only fuel goes in.
  bool canInsert(String itemKey) => SimServices.instance.host.burnTime(itemKey) > 0;

  /// The stack in the slot.
  PStack get slot => inventory.stackIn(0);

  /// `getAnalogOutputSignal`: the fuel left, 15 when it is infinite.
  int get analogOutput {
    final stack = slot;
    final next = stack.isEmpty ? 0 : SimServices.instance.host.burnTime(stack.key);
    if (burn.isTotalFuelInfinite(next)) return 15;
    return analogPower(burn.totalBurnTime(stack.count, next));
  }

  /// `getTotalBurnTime()`, for the goggles tooltip of the block's client half.
  int get totalBurnTime {
    final stack = slot;
    return burn.totalBurnTime(
      stack.count,
      stack.isEmpty ? 0 : SimServices.instance.host.burnTime(stack.key),
    );
  }

  /// Inserts [stack] like `PortableEngineInventory.insertGeneral`. Returns what
  /// did not fit.
  PStack insert(PStack stack) => inventory.insert(0, stack);

  /// Whether [stack] would fit at all (`canInsertItem`).
  bool canInsertStack(PStack stack) => stack.isNotEmpty && canInsert(stack.key);

  /// Takes up to [amount] out of the slot (`extractSlot`).
  PStack extract(int amount) => inventory.extract(0, amount);

  // -- Tick -----------------------------------------------------------------------

  @override
  void tick() {
    super.tick();
    if (removed) return;
    final w = world;
    if (w == null) return;
    _ticks++;

    // `if (getGeneratedSpeed() != 0 && getSpeed() == 0) updateGeneratedRotation();`
    if (generatedSpeed != 0 && speed == 0) updateGeneratedRotation();

    // -- Fuel --
    final stack = slot;
    final nextTicks = stack.isEmpty ? 0 : SimServices.instance.host.burnTime(stack.key);
    final nextSuperheated =
        stack.isNotEmpty && SimServices.instance.host.superheatedBurnTime(stack.key) > 0;

    final neighbours = burn.tick(
      nextFuelTicks: nextTicks,
      slotCount: stack.count,
      nextSuperHeated: nextSuperheated,
      consumeOne: () => inventory.setStack(0, stack.shrink(1)),
    );
    if (neighbours) {
      // `level.updateNeighborsAt(pos, block)`: the comparators around the engine.
      unawaited(w.setBlockState(
        pos: pos,
        state: w.getBlockStateId(pos: pos),
        updateFlags: {BlockFlagsFlag.notifyNeighbors},
      ));
    }

    // -- Rotation direction --
    final fixed = burn.directionFix(
      movementDirection: movementDirection.value,
      speed: speed,
      directionSign: directionSign,
    );
    if (fixed != null) {
      movementDirection.value = fixed;
      updateGeneratedRotation();
    }

    // -- `lit` --
    final litState = blockState.flag('lit');
    final isLit = burn.isLit;
    if (litState && !isLit) {
      _setLit(false);
      updateGeneratedRotation();
    }
    if (!litState && isLit) {
      _setLit(true);
      w.playCustomSound(
        soundName: 'simulated:block.portable_engine.activate',
        category: SoundCategory.blocks,
        pos: (pos.x + .5, pos.y + .5, pos.z + .5),
        volume: .125 + _random.nextDouble() * .125,
        pitch: .75 - _random.nextDouble() * .25,
      );
      updateGeneratedRotation();
    }
    // Java's `previousSuperHeated` local is always false, so the condition is
    // `superHeated && lit`; kept as the Java behaves.
    if (burn.superHeated && litState && isLit) updateGeneratedRotation();

    if (_ticks % 60 == 0) _tickCake(w);
    if (burn.eatingCake) {
      burn.eatingCake = false;
      sendData();
    }
  }

  /// `tick`'s cake: every 60 ticks, an engine facing a cake eats a bite and
  /// gains five seconds of burn time.
  void _tickCake(World w) {
    final front = BlockPos(
      x: pos.x + facing.opposite.dx,
      y: pos.y + facing.opposite.dy,
      z: pos.z + facing.opposite.dz,
    );
    final frontState = HostBlockGetter.stateOfId(w.getBlockStateId(pos: front));
    if (frontState.key != 'minecraft:cake') return;
    burn.eatingCake = true;
    sendData();
    final bites = int.tryParse(frontState.props['bites'] ?? '') ?? 0;
    if (bites < 6) {
      final id = BlockRegistry.resolveState('minecraft:cake', {'bites': '${bites + 1}'});
      if (id != null) {
        unawaited(w.setBlockState(pos: front, state: id, updateFlags: BlockUpdateFlags.normal));
      }
    } else {
      unawaited(w.setBlockState(
        pos: front,
        state: BlockRegistry.resolveState('minecraft:air')!,
        updateFlags: BlockUpdateFlags.normal,
      ));
    }
    burn.burnTime += 20 * 5;
    w.sound(
      Sound.entityGenericEat,
      (pos.x + .5, pos.y + .5, pos.z + .5),
      category: SoundCategory.blocks,
      volume: 1,
      pitch: 1,
    );
  }

  /// The fuel in the slot as a host stack, for the block's use hook.
  PStack get slotStack => slot;

  /// Writes [stack] into the slot (the player fed the engine).
  void setSlot(PStack stack) => inventory.setStack(0, stack);

  /// The engine's own stack writing, for the use hook's merge branch.
  static Future<ItemStack?> hostStack(PStack stack) => HostStacks.write(stack);

  /// Writes `lit` on the block, keeping the kinetics attached
  /// (`KineticBlockEntity.switchToBlockState`).
  void _setLit(bool lit) {
    final current = blockState;
    if (current.flag('lit') == lit) return;
    unawaited(KineticOps.switchToBlockState(
      KineticsRuntime.instance,
      worldId,
      pos,
      current.setFlag('lit', lit),
    ));
  }

  // -- NBT ------------------------------------------------------------------------

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    burn.read(
      burnTime: tag.getInt('BurnTime') ?? 0,
      superHeated: tag.getBool('SuperHeated') ?? false,
      eatingCake: tag.getBool('EatingCake') ?? false,
    );
    final inv = tag.getCompound('Inventory');
    if (inv != null) inventory.load(StackNbt.readList(inv, 1));
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('BurnTime', burn.burnTime);
    tag.putBool('SuperHeated', burn.superHeated);
    tag.putBool('EatingCake', burn.eatingCake);
    // Java's `GeneratedSpeed` is its cached field; the port recomputes it.
    tag.putDouble('GeneratedSpeed', generatedSpeed);
    tag.putCompound('Inventory', StackNbt.writeList(inventory.contents));
  }
}