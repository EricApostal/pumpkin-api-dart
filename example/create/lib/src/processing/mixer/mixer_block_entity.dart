// `MechanicalMixerBlockEntity`: a basin operator that mixes (and compacts through the press)
// the basin two blocks below it, with the 40 tick head animation.
import 'dart:math';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../basin/basin_operating_block_entity.dart';
import '../recipe/recipe_type.dart';

/// `MechanicalMixerBlockEntity`.
final class MechanicalMixerBlockEntity extends BasinOperatingBlockEntity {
  static const String type = 'create:mechanical_mixer';

  int runningTicks = 0;

  /// `processingTicks`: ticks until the recipe is applied; -1 while not counting.
  int processingTicks = -1;

  bool running = false;

  MechanicalMixerBlockEntity(super.worldId, super.pos);

  /// `matchStaticFilters`: mixing recipes (shapeless crafting is not part of the recipe book).
  @override
  List<CreateRecipeType> get matchingRecipeTypes => const [
    CreateRecipeType.mixing,
  ];

  @override
  bool isRunning() => running;

  @override
  void tick() {
    super.tick();

    if (runningTicks >= 40) {
      running = false;
      runningTicks = 0;
      scheduleBasinCheck();
      return;
    }

    final speed = this.speed.abs();
    if (!running) return;

    if (speed == 0 || !isSpeedRequirementFulfilled) {
      if (runningTicks < 20) {
        runningTicks = 40 - runningTicks;
      } else if (runningTicks == 20) {
        runningTicks++;
      }
    }

    if (runningTicks == 20) {
      if (processingTicks < 0) {
        processingTicks = _nextProcessingTicks(speed);
      } else {
        processingTicks--;
        if (processingTicks == 0) {
          runningTicks++;
          processingTicks = -1;
          applyBasinRecipe();
          sendData();
        }
      }
    }

    if (runningTicks != 20) runningTicks++;
  }

  /// `max(Mth.log2((int) (512 / speed)) * ceil(recipeSpeed * 15) + 1, 1)`.
  int _nextProcessingTicks(double speed) {
    var recipeSpeed = 1.0;
    final duration = currentRecipe?.processingDuration ?? 0;
    if (duration != 0) recipeSpeed = duration / 100;

    final divisor = speed <= 0 ? 1 : speed;
    final log = _log2((512 / divisor).toInt());
    return max(log * (recipeSpeed * 15).ceil() + 1, 1);
  }

  /// `Mth.log2(int)`: the floor of the base 2 logarithm.
  static int _log2(int value) {
    if (value <= 0) return 0;
    var v = value;
    var result = 0;
    while (v > 1) {
      v >>= 1;
      result++;
    }
    return result;
  }

  @override
  void startProcessingBasin() {
    if (running && runningTicks <= 20) return;
    super.startProcessingBasin();
    running = true;
    runningTicks = 0;
  }

  @override
  bool continueWithPreviousRecipe() {
    runningTicks = 20;
    return true;
  }

  @override
  void onBasinRemoved() {
    if (!running) return;
    runningTicks = 40;
    running = false;
  }

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    tag.putBool('Running', running);
    tag.putInt('Ticks', runningTicks);
    super.write(tag, clientPacket: clientPacket);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    running = tag.getBool('Running') ?? false;
    runningTicks = tag.getInt('Ticks') ?? 0;
    super.read(tag, clientPacket: clientPacket);
  }
}
