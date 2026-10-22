// `SpoutBlockEntity` (host side): fills the item on the belt or depot two blocks
// below with the fluid in its 1000 mB tank, using the filling recipes and the
// generic item filling of `FillingBySpout`.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/behaviour/spouting/spouting.dart';
import '../common/direction.dart';
import '../common/nbt_convert.dart';
import '../common/pos.dart';
import '../core/block_entity.dart';
import '../processing/common/stack.dart';
import '../processing/transport/transport_behaviours.dart';
import 'fluid_host.dart';
import 'fluid_runtime.dart';
import 'fluid_storage.dart';
import 'generic_item_fluid.dart';
import 'nbt_util.dart';

/// `SpoutBlockEntity`.
class SpoutBlockEntity extends CreateBlockEntity
    implements FluidCapable, SidedFluidCapable {
  /// `FILLING_TIME`.
  static const int fillingTime = 20;

  late final SmartFluidTank tank;
  late final BeltProcessingBehaviour beltProcessing;

  /// `processingTicks`; -1 when idle.
  int processingTicks = -1;

  /// `sendSplash`: the client plays the splash effect on the next sync.
  bool sendSplash = false;

  /// `customProcess`: the block below the spout that is being filled, `null` for the
  /// item path.
  BlockSpoutingBehaviour? customProcess;
  Pos? customPos;

  /// `createdSweetRoll`, `createdHoneyApple`, `createdChocolateBerries`: the foods the
  /// spout filled, for `AllAdvancements.FOODS`.
  bool createdSweetRoll = false;
  bool createdHoneyApple = false;
  bool createdChocolateBerries = false;

  SpoutBlockEntity(super.worldId, super.pos) {
    tank = SmartFluidTank(1000, (_) => sendData());
    beltProcessing = addBehaviour(BeltProcessingBehaviour())
      ..whenItemEnters(_onItemReceived)
      ..whileItemHeld(_whenItemHeld);
  }

  /// `FillingBySpout` over the module's item rules and recipes.
  FillingBySpout get spout => FillingBySpout(
    GenericItemFilling(FluidsRuntime.instance.rules),
    FluidsRuntime.instance.recipes,
  );

  @override
  FluidStorage? get fluidHandler => tank;

  /// `SpoutBlockEntity.registerCapabilities`: no handler from below.
  @override
  FluidStorage? fluidHandlerAt(Direction? side) =>
      side == Direction.down ? null : tank;

  static FluidItemSpec _item(PStack stack) => stack.isEmpty
      ? FluidItemSpec.empty
      : FluidItemSpec(stack.key, stack.count, stack.comps);

  static PStack _stack(FluidItemSpec item) =>
      item.isEmpty ? PStack.empty : PStack(item.key, item.count, comps: item.comps);

  /// `onItemReceived`.
  ProcessingResult _onItemReceived(
    TransportedItemStack transported,
    TransportedItemStackHandler handler,
  ) {
    if (!spout.canItemBeFilled(_item(transported.stack)))
      return ProcessingResult.pass;
    if (tank.isEmpty) return ProcessingResult.hold;
    if (spout.getRequiredAmountForItem(_item(transported.stack), tank.fluid) ==
        -1)
      return ProcessingResult.pass;
    return ProcessingResult.hold;
  }

  /// `whenItemHeld`.
  ProcessingResult _whenItemHeld(
    TransportedItemStack transported,
    TransportedItemStackHandler handler,
  ) {
    if (processingTicks != -1 && processingTicks != 5) {
      return ProcessingResult.hold;
    }
    final item = _item(transported.stack);
    if (!spout.canItemBeFilled(item)) return ProcessingResult.pass;
    if (tank.isEmpty) return ProcessingResult.hold;
    final fluid = tank.fluid;
    final required = spout.getRequiredAmountForItem(item, fluid);
    if (required == -1) return ProcessingResult.pass;
    if (required > fluid.amount) return ProcessingResult.hold;

    if (processingTicks == -1) {
      processingTicks = fillingTime;
      sendData();
      _playSound(
        'create:spout',
        volume: 0.75,
        pitch: 0.9 + 0.2 * (FluidsRuntime.instance.random.nextDouble()),
      );
      return ProcessingResult.hold;
    }

    // Process finished.
    final (result, leftStack, leftFluid) = spout.fillItem(
      required,
      item,
      fluid,
    );
    if (result.isNotEmpty) {
      final output = TransportedItemStack(_stack(result));
      final held = leftStack.isEmpty
          ? null
          : TransportedItemStack(_stack(leftStack));
      transported.stack = _stack(leftStack);
      handler.handleProcessingOnItem(
        transported,
        held == null
            ? TransportedResult.convertToAll([output])
            : TransportedResult.convertToAndLeaveHeld([output], held),
      );
      _trackFood(result.key);
    }
    // `SpoutBlockEntity.whenItemHeld` awards SPOUT after every finished process.
    _award('spout');

    tank.setFluid(leftFluid);
    sendSplash = true;
    sendData();
    return ProcessingResult.hold;
  }

  /// `AllAdvancements.FOODS`: the three food items of the spout.
  void _trackFood(String itemKey) {
    if (itemKey == 'create:chocolate_berries') {
      createdChocolateBerries = true;
    } else if (itemKey == 'create:honeyed_apple') {
      createdHoneyApple = true;
    } else if (itemKey == 'create:sweet_roll') {
      createdSweetRoll = true;
    }
    if (createdChocolateBerries && createdHoneyApple && createdSweetRoll) {
      _award('foods');
    }
  }

  void _award(String advancement) =>
      FluidsRuntime.instance.award(worldId, posOf, advancement);

  Pos get posOf => (this.pos.x, this.pos.y, this.pos.z);

  @override
  void tick() {
    super.tick();
    final level = FluidsRuntime.instance.levelOf(worldId);
    if (level == null) return;
    final current = tank.fluid;
    final below = posOf.belowBy(2);

    // `BlockSpoutingBehaviour`: while idle, a block below the spout may accept fluid.
    if (processingTicks == -1 && current.isNotEmpty) {
      final state = level.stateAt(below);
      final behaviour = BlockSpoutingBehaviour.get(state.key);
      if (behaviour != null &&
          behaviour.fillBlock(level, below, this, current, simulate: true) >
              0) {
        processingTicks = fillingTime;
        customProcess = behaviour;
        customPos = below;
        sendData();
      }
    }

    if (processingTicks >= 0) {
      processingTicks--;
      if (processingTicks == 5 && customProcess != null) {
        final behaviour = customProcess!;
        final target = customPos ?? below;
        customProcess = null;
        customPos = null;
        final filled = behaviour.fillBlock(
          level,
          target,
          this,
          current,
          simulate: false,
        );
        if (filled > 0) {
          tank.setFluid(current.shrink(filled));
          sendSplash = true;
          sendData();
        }
      }
    }
  }

  void _playSound(String sound, {double volume = 1, double pitch = 1}) {
    final w = world;
    if (w == null) return;
    try {
      w.playCustomSound(
        soundName: sound,
        category: SoundCategory.blocks,
        pos: (this.pos.x + .5, this.pos.y + .5, this.pos.z + .5),
        volume: volume,
        pitch: pitch,
      );
    } on HostException {
      // The sound is not registered; the filling still happened.
    }
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    processingTicks = tag.getInt('ProcessingTicks') ?? -1;
    customProcess = null;
    customPos = null;
    createdChocolateBerries = tag.getBool('ChocolateBerries') ?? false;
    createdHoneyApple = tag.getBool('HoneyApple') ?? false;
    createdSweetRoll = tag.getBool('SweetRoll') ?? false;
    final fluid = tag.getCompound('Tank');
    if (fluid != null) tank.rawSet(readFluidTankNbt(valueOfCompound(fluid)));
    // `SmartFluidTankBehaviour.write`: a single tank under `Tanks`.
    final tanks = tag.getList('Tanks');
    if (tanks != null && tanks.isNotEmpty) {
      final first = tanks.first;
      if (first is NbtCompound) {
        tank.rawSet(readTankSegmentNbt(valueOfCompound(first)));
      }
    }
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('ProcessingTicks', processingTicks);
    // `SmartFluidTankBehaviour.write`: a single tank under `Tanks`.
    tag.putList('Tanks', [
      compoundOf(tankSegmentNbt(tank.fluid, tank.tankCapacity(0))),
    ]);
    if (sendSplash && clientPacket) {
      tag.putBool('Splash', true);
      sendSplash = false;
    }
    if (createdChocolateBerries) tag.putBool('ChocolateBerries', true);
    if (createdHoneyApple) tag.putBool('HoneyApple', true);
    if (createdSweetRoll) tag.putBool('SweetRoll', true);
  }
}
