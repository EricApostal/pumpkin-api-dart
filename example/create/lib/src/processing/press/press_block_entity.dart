// `MechanicalPressBlockEntity`: the press is a basin operator (compacting recipes) and also
// processes single items on belts, depots and on the ground through [PressingBehaviour].
import 'dart:async';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../basin/basin_operating_block_entity.dart';
import '../common/stack.dart';
import '../deployer/deployer_items.dart' show craftingRemainderOf;
import '../recipe/crafting_recipes.dart';
import '../host/stack_host.dart';
import '../processing_runtime.dart';
import '../recipe/recipe_applier.dart';
import '../recipe/recipe_book.dart';
import '../recipe/recipe_type.dart';
import '../transport/transported_stack.dart';
import '../../api/advancements.dart';
import 'press_behaviour.dart';

/// `MechanicalPressBlockEntity`.
final class MechanicalPressBlockEntity extends BasinOperatingBlockEntity
    implements PressingBehaviourSpecifics {
  static const String type = 'create:mechanical_press';

  late final PressingBehaviour pressingBehaviour;

  /// `registerAwardables(behaviours, PRESS, COMPACTING, TRACK_CRAFTING)`
  /// (`MechanicalPressBlockEntity.java:64-65`): the press awards its owner.
  late final AdvancementBehaviour advancements;

  /// `tracksCreated`: tracks pressed, for the track crafting advancement.
  int tracksCreated = 0;

  MechanicalPressBlockEntity(super.worldId, super.pos) {
    pressingBehaviour = addBehaviour(PressingBehaviour(this));
    advancements = addBehaviour(
      AdvancementBehaviour(
        [
          AllAdvancements.press,
          AllAdvancements.compacting,
          AllAdvancements.trackCrafting,
        ],
        () => _rt.advancements,
      ),
    );
  }

  ProcessingRuntime get _rt => ProcessingRuntime.instance;

  /// `matchStaticFilters`: compacting recipes.
  @override
  List<CreateRecipeType> get matchingRecipeTypes => const [
    CreateRecipeType.compacting,
  ];

  /// `matchStaticFilters` for vanilla crafting recipes: `canCompress` — a 2x2 or 3x3 square of
  /// one ingredient, when `recipes.allowShapedSquareInPress` is set (`canCompress` checks that
  /// flag itself). Mechanical crafting recipes are `create:*` recipes and never come from here.
  @override
  List<CraftingRecipeEntry> get matchingCraftingRecipes {
    if (!(_rt.configs?.server.recipes.allowShapedSquareInPress.value ?? false)) {
      return const [];
    }
    return [
      for (final entry
          in CraftingRecipeCache.current?.compressibleSquares ??
              const <CraftingRecipeEntry>[])
        if (!ignoredInAutomation(entry.id)) entry,
    ];
  }

  @override
  bool isRunning() => pressingBehaviour.running;

  /// `getRecipe(item)`: a sequenced assembly pressing step first, then a plain pressing recipe.
  RecipeMatch? _recipe(PStack item) =>
      _rt.recipes.findForInput(CreateRecipeType.pressing, item);

  /// `RecipeApplier.applyRecipeOn(level, stack, recipe, true)` honouring a sequenced assembly.
  List<PStack> _applyRecipe(PStack input, RecipeMatch match) {
    final random = _rt.random;
    final sequenced = match.sequenced;
    return applyRecipeOn(
      input,
      match.recipe,
      random,
      returnProcessingRemainder: true,
      craftingRemainder: craftingRemainderOf,
      rollFirst: sequenced == null ? null : sequenced.forcedResult(random),
    );
  }

  // -- PressingBehaviourSpecifics --------------------------------------------------------

  @override
  double get kineticSpeed => speed;

  @override
  bool get canProcessInBulk =>
      _rt.configs?.server.recipes.bulkPressing.value ?? false;

  @override
  int get particleAmount => 15;

  /// `getProcessedRecipeTrigger` (`MechanicalPressBlockEntity.java:246`).
  @override
  String? get processedRecipeAward => AllAdvancements.compacting;

  /// `tryProcessInBasin`: applying the basin recipe is what the cycle's mid point does.
  @override
  bool tryProcessInBasin({required bool simulate}) {
    applyBasinRecipe();
    return true;
  }

  /// A completed compacting cycle awards the trigger to the owner: `COMPACTING` is the press's
  /// `getProcessedRecipeTrigger`, which `BasinOperatingBlockEntity.java:120` awards.
  @override
  void onBasinCycleCompleted(String award) {
    unawaited(advancements.awardPlayer(award));
  }

  /// `tryProcessOnBelt`.
  @override
  bool tryProcessOnBelt(
    TransportedItemStack input,
    List<PStack>? outputList, {
    required bool simulate,
  }) {
    final match = _recipe(input.stack);
    if (match == null) return false;
    if (simulate) return true;

    final outputs = _applyRecipe(
      canProcessInBulk ? input.stack : input.stack.withCount(1),
      match,
    );
    for (final created in outputs) {
      if (created.isEmpty) continue;
      onItemPressed(created);
      break;
    }
    outputList?.addAll(outputs);
    return true;
  }

  /// `tryProcessInWorld(itemEntity, simulate)`: the check before the press starts its cycle.
  @override
  bool tryProcessInWorld(EntitySnapshot item, {required bool simulate}) {
    final entity = world?.getEntityById(id: item.id);
    if (entity == null || !entity.isOnGround()) return false;
    final summary = item.item;
    if (summary == null) return false;
    if (_recipe(PStack(summary.registryKey, summary.count)) != null)
      return true;
    // The components of a dropped item (a sequenced assembly's progress) are only readable in
    // `applyInWorld`; a transitional item may still match there.
    return _rt.recipes.sequencedAssemblies.any(
      (assembly) => assembly.transitionalItem.item == summary.registryKey,
    );
  }

  /// `tryProcessInWorld(itemEntity, false)`: replace the dropped item's stack with the result.
  @override
  Future<void> applyInWorld(EntitySnapshot item) async {
    final w = world;
    if (w == null) return;
    final entity = w.getEntityById(id: item.id);
    final itemEntity = entity?.asItem();
    if (entity == null || itemEntity == null || !entity.isOnGround()) return;

    final stack = await HostStacks.read(itemEntity.getStack());
    final match = _recipe(stack);
    if (match == null) return;

    PStack? created;
    if (canProcessInBulk || stack.count == 1) {
      final outputs = _applyRecipe(stack, match);
      if (outputs.isEmpty) {
        itemEntity.discard();
      } else {
        created = outputs.removeAt(0);
        await _setEntityStack(itemEntity, created);
        for (final extra in outputs) {
          await _spawn(w, entity.getPosition(), extra, entity.getVelocity());
        }
      }
    } else {
      for (final result in _applyRecipe(stack.withCount(1), match)) {
        created ??= result;
        await _spawn(w, entity.getPosition(), result, _randomOffset(.05));
      }
      final left = stack.shrink(1);
      if (left.isEmpty) {
        itemEntity.discard();
      } else {
        await _setEntityStack(itemEntity, left);
      }
    }

    if (created != null) onItemPressed(created);
  }

  Future<void> _setEntityStack(ItemEntity entity, PStack stack) async {
    final host = await HostStacks.write(stack);
    if (host == null) {
      entity.discard();
      return;
    }
    await entity.setStack(stack: host);
  }

  Future<void> _spawn(
    World w,
    (double, double, double) pos,
    PStack stack,
    (double, double, double) velocity,
  ) async {
    final host = await HostStacks.write(stack);
    if (host == null) return;
    await w.dropItem(pos, host, velocity: velocity);
  }

  (double, double, double) _randomOffset(double scale) {
    final random = _rt.random;
    double one() => (random.nextDouble() * 2 - 1) * scale;
    return (one(), one(), one());
  }

  /// `onItemPressed` (`MechanicalPressBlockEntity.java:68-76`).
  void onItemPressed(PStack result) {
    // Every pressed item awards `PRESS` once (Java awards it unconditionally, before the track
    // check); the owner-only duplicate suppression is `AdvancementBehaviour`'s own bookkeeping.
    unawaited(advancements.awardPlayer(AllAdvancements.press));
    if (_rt.tags.blockHasTag(result.key, 'create:tracks'))
      tracksCreated += result.count;
    if (tracksCreated >= 1000) {
      unawaited(advancements.awardPlayer(AllAdvancements.trackCrafting));
      tracksCreated = 0;
    }
  }

  // -- Basin -------------------------------------------------------------------------------

  @override
  void startProcessingBasin() {
    if (pressingBehaviour.running &&
        pressingBehaviour.runningTicks <= PressingBehaviour.cycle ~/ 2)
      return;
    super.startProcessingBasin();
    pressingBehaviour.start(PressingMode.basin);
  }

  @override
  void onBasinRemoved() {
    pressingBehaviour.running = false;
    pressingBehaviour.runningTicks = 0;
    sendData();
  }

  @override
  void onPressingCompleted() {
    if (pressingBehaviour.onBasin &&
        matchBasinRecipe(currentRecipe) &&
        (getBasin()?.canContinueProcessing ?? false)) {
      startProcessingBasin();
    } else {
      scheduleBasinCheck();
    }
  }

  // -- NBT ---------------------------------------------------------------------------------

  @override
  void write(NbtCompound tag, {required bool clientPacket}) {
    super.write(tag, clientPacket: clientPacket);
    tag.putInt('TracksCreated', tracksCreated);
  }

  @override
  void read(NbtCompound tag, {required bool clientPacket}) {
    super.read(tag, clientPacket: clientPacket);
    tracksCreated = tag.getInt('TracksCreated') ?? 0;
  }
}
