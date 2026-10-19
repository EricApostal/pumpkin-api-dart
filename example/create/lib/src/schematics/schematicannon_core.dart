// The logic of the schematicannon (pure): `SchematicannonBlockEntity` without the host. The
// block entity wrapper (`cannon_block_entity.dart`) feeds it a [CannonEnv].
import '../api/block_state.dart';
import '../common/binary_nbt.dart';
import '../common/pos.dart';
import '../core/nbt.dart';
import 'item_requirement.dart';
import 'launched_item.dart';
import 'material_checklist.dart';
import 'schematic_printer.dart';
import 'schematic_stack.dart';
import 'schematic_world.dart';

/// `SchematicannonBlockEntity.State`.
enum CannonState { stopped, paused, running }

/// `ConfigureSchematicannonPacket.Option`.
enum CannonOption { dontReplace, replaceSolid, replaceAny, replaceEmpty, skipMissing, skipBlockEntities, play, pause, stop }

/// Slot numbers of the cannon inventory.
abstract final class CannonSlot {
  static const int blueprint = 0;
  static const int blueprintOutput = 1;
  static const int bookInput = 2;
  static const int checklistOutput = 3;
  static const int gunpowder = 4;
  static const int count = 5;
}

/// What the loading of a blueprint returned.
enum BlueprintStatus { ok, invalid, notPlaced, errored, expired }

/// A loaded blueprint.
final class BlueprintLoad {
  final BlueprintStatus status;
  final SchematicWorld? world;

  const BlueprintLoad(this.status, [this.world]);
}

/// The world and the inventories as the cannon sees them.
abstract interface class CannonEnv {
  PrinterTargetView get view;

  Pos get cannonPos;

  SchematicRequirements get requirements;

  /// `BlockMovementChecks.isBrittle`.
  bool isBrittle(BState state);

  /// `config().schematicannonDelay`.
  int get cannonDelay;

  /// `config().schematicannonShotsPerGunpowder`.
  int get shotsPerGunpowder;

  /// Loads the schematic of the blueprint stack in slot 0.
  BlueprintLoad loadBlueprint(SlotStack blueprint);

  /// A creative crate touches the cannon: no fuel and no items are needed.
  bool get hasCreativeCrate;

  Future<void> findInventories();

  /// `grabItemsFromAttachedInventories`.
  Future<bool> grabItems(StackRequirement required, {required bool simulate});

  /// One gunpowder from an attached inventory (`refillFuelIfPossible`); true if one was taken.
  Future<bool> takeExternalGunpowder();

  /// All stacks in the attached inventories (for the checklist).
  Future<List<SlotStack>> attachedStacks();

  void playFiringSound();

  void playFinishSound();

  /// `level.scheduleTick(pos, Fluids.WATER, ...)` for water next to a finished schematic.
  void scheduleWaterTick(Pos pos);

  /// A launched item landed: place it in the world.
  Future<void> place(LaunchedItem item);

  /// `BlockHelper.prepareBlockEntityData`: the block entity data to place with a block.
  List<int>? prepareBlockEntityData(BState state, List<int>? nbt);

  /// The written book / clipboard for the checklist.
  Future<SlotStack> createChecklistStack(MaterialChecklist checklist, {required bool clipboard});

  /// Whether [stack] is a clipboard item (slot 2 accepts clipboards and books).
  bool isClipboard(SlotStack stack);

  /// The cannon's item/stack answers (item keys).
  bool isBlueprintItem(SlotStack stack);
}

/// `SchematicannonBlockEntity`.
final class SchematicannonCore {
  static const int neighbourChecking = 100;
  static const int maxAnchorDistance = 256;

  final List<SlotStack> inventory = List.filled(CannonSlot.count, SlotStack.empty);

  bool sendUpdate = false;
  bool dontUpdateChecklist = false;
  int neighbourCheckCooldown = 0;

  final SchematicPrinter printer = SchematicPrinter();
  SlotStack? missingItem;
  bool positionNotLoaded = false;
  int printerCooldown = 0;
  int skipsLeft = 0;
  bool blockSkipped = false;
  Pos? previousTarget;
  final List<LaunchedItem> flyingBlocks = [];
  final MaterialChecklist checklist = MaterialChecklist();

  int remainingFuel = 0;
  double bookPrintingProgress = 0;
  double schematicProgress = 0;
  String statusMsg = 'idle';
  CannonState state = CannonState.stopped;
  int blocksPlaced = 0;
  int blocksToPlace = 0;

  // Settings
  int replaceMode = 2;
  bool skipMissing = false;
  bool replaceBlockEntities = false;
  double defaultYaw = 0;

  /// `isItemValid` of `SchematicannonInventory`.
  bool isItemValid(CannonEnv env, int slot, SlotStack stack) {
    switch (slot) {
      case CannonSlot.blueprint:
        return env.isBlueprintItem(stack);
      case CannonSlot.blueprintOutput:
      case CannonSlot.checklistOutput:
        return false;
      case CannonSlot.bookInput:
        return env.isClipboard(stack) || stack.item == 'minecraft:book' || stack.item == 'minecraft:written_book';
      case CannonSlot.gunpowder:
        return stack.item == 'minecraft:gunpowder';
    }
    return true;
  }

  /// `getShotsPerGunpowder`.
  int shotsPerGunpowder(CannonEnv env) => env.hasCreativeCrate ? 0 : env.shotsPerGunpowder;

  // ---- tick -------------------------------------------------------------------------------

  /// `tick()` on the server.
  Future<void> tick(CannonEnv env) async {
    if (state != CannonState.stopped && neighbourCheckCooldown-- <= 0) {
      neighbourCheckCooldown = neighbourChecking;
      await env.findInventories();
    }
    previousTarget = printer.currentTarget;
    await tickFlyingBlocks(env);
    await tickPaperPrinter(env);
    await refillFuelIfPossible(env);
    skipsLeft = 1000;
    blockSkipped = true;
    while (blockSkipped && skipsLeft-- > 0) {
      await tickPrinter(env);
    }
    schematicProgress = 0;
    if (blocksToPlace > 0) schematicProgress = blocksPlaced / blocksToPlace;
  }

  Future<void> tickFlyingBlocks(CannonEnv env) async {
    final landed = <LaunchedItem>[];
    for (final b in flyingBlocks) {
      if (b.update()) {
        await env.place(b);
        landed.add(b);
      }
    }
    if (landed.isNotEmpty) flyingBlocks.removeWhere(landed.contains);
  }

  Future<void> tickPrinter(CannonEnv env) async {
    final blueprint = inventory[CannonSlot.blueprint];
    blockSkipped = false;

    if (blueprint.isEmpty && statusMsg != 'idle' && inventory[CannonSlot.blueprintOutput].isEmpty) {
      state = CannonState.stopped;
      statusMsg = 'idle';
      sendUpdate = true;
      return;
    }

    // Skip if not active
    if (state == CannonState.stopped) {
      if (printer.isLoaded) resetPrinter();
      return;
    }

    if (state == CannonState.paused && !positionNotLoaded && missingItem == null && remainingFuel > 0) return;

    // Initialize printer
    if (!printer.isLoaded) {
      await initializePrinter(env, blueprint);
      return;
    }

    // Cooldown from last shot
    if (printerCooldown > 0) {
      printerCooldown--;
      return;
    }

    // Check fuel
    if (remainingFuel <= 0 && !env.hasCreativeCrate) {
      await refillFuelIfPossible(env);
      if (remainingFuel <= 0) {
        state = CannonState.paused;
        statusMsg = 'noGunpowder';
        sendUpdate = true;
        return;
      }
    }

    if (env.hasCreativeCrate) {
      remainingFuel = 0;
      if (missingItem != null) {
        missingItem = null;
        state = CannonState.running;
      }
    }

    // Update target
    if (missingItem == null && !positionNotLoaded) {
      if (!printer.advanceCurrentPos()) {
        await finishedPrinting(env);
        return;
      }
      sendUpdate = true;
    }

    // Check block
    if (!env.view.isLoaded(printer.currentTarget!)) {
      positionNotLoaded = true;
      statusMsg = 'targetNotLoaded';
      state = CannonState.paused;
      return;
    } else if (positionNotLoaded) {
      positionNotLoaded = false;
      state = CannonState.running;
    }

    // Get item requirement
    final requirement = printer.getCurrentRequirement();
    if (requirement.isInvalid || !printer.shouldPlaceCurrent(env.view, (p, s, be, r, ro, n) => shouldPlace(env, p, s, be, r, ro, n))) {
      sendUpdate = statusMsg != 'searching';
      statusMsg = 'searching';
      blockSkipped = true;
      return;
    }

    // Find item
    final requiredItems = requirement.requiredItems;
    if (!requirement.isEmpty) {
      for (final required in requiredItems) {
        if (!await env.grabItems(required, simulate: true)) {
          if (skipMissing) {
            statusMsg = 'skipping';
            blockSkipped = true;
            if (missingItem != null) {
              missingItem = null;
              state = CannonState.running;
            }
            return;
          }
          missingItem = SlotStack(required.item, required.count);
          state = CannonState.paused;
          statusMsg = 'missingBlock';
          return;
        }
      }
      for (final required in requiredItems) {
        await env.grabItems(required, simulate: false);
      }
    }

    // Success
    state = CannonState.running;
    final icon = requirement.isEmpty || requiredItems.isEmpty
        ? SlotStack.empty
        : SlotStack(requiredItems.first.item, requiredItems.first.count);
    printer.handleCurrentTarget((target, blockState, nbt) {
      statusMsg = blockState.key != 'minecraft:air' ? 'placing' : 'clearing';
      launchBlockOrBelt(env, target, icon, blockState, nbt);
    }, (target, entity) {
      statusMsg = 'placing';
      launchEntity(env, target, icon, entity);
    });

    printerCooldown = env.cannonDelay;
    remainingFuel -= 1;
    sendUpdate = true;
    missingItem = null;
  }

  Future<void> initializePrinter(CannonEnv env, SlotStack blueprint) async {
    final load = env.loadBlueprint(blueprint);
    switch (load.status) {
      case BlueprintStatus.invalid:
        state = CannonState.stopped;
        statusMsg = 'schematicInvalid';
        sendUpdate = true;
        return;
      case BlueprintStatus.notPlaced:
        state = CannonState.stopped;
        statusMsg = 'schematicNotPlaced';
        sendUpdate = true;
        return;
      case BlueprintStatus.errored:
        state = CannonState.stopped;
        statusMsg = 'schematicErrored';
        inventory[CannonSlot.blueprint] = SlotStack.empty;
        inventory[CannonSlot.blueprintOutput] = const SlotStack('create:empty_schematic', 1);
        printer.resetSchematic();
        sendUpdate = true;
        return;
      case BlueprintStatus.expired:
        state = CannonState.stopped;
        statusMsg = 'schematicExpired';
        inventory[CannonSlot.blueprint] = SlotStack.empty;
        inventory[CannonSlot.blueprintOutput] = const SlotStack('create:empty_schematic', 1);
        printer.resetSchematic();
        sendUpdate = true;
        return;
      case BlueprintStatus.ok:
        break;
    }
    printer.requirements = env.requirements;
    printer.isBrittle = env.isBrittle;
    printer.load(load.world!);
    if (printer.isWorldEmpty) {
      state = CannonState.stopped;
      statusMsg = 'schematicExpired';
      inventory[CannonSlot.blueprint] = SlotStack.empty;
      inventory[CannonSlot.blueprintOutput] = const SlotStack('create:empty_schematic', 1);
      printer.resetSchematic();
      sendUpdate = true;
      return;
    }
    if (printer.anchor!.distSqr(env.cannonPos) >= maxAnchorDistance * maxAnchorDistance) {
      state = CannonState.stopped;
      statusMsg = 'targetOutsideRange';
      printer.resetSchematic();
      sendUpdate = true;
      return;
    }
    state = CannonState.paused;
    statusMsg = 'ready';
    await updateChecklist(env);
    sendUpdate = true;
    blocksToPlace += blocksPlaced;
  }

  Future<void> finishedPrinting(CannonEnv env) async {
    if (replaceMode == CannonOption.replaceEmpty.index) {
      for (final p in printer.waterPositionsToTick(env.view)) {
        env.scheduleWaterTick(p);
      }
    }
    inventory[CannonSlot.blueprint] = SlotStack.empty;
    inventory[CannonSlot.blueprintOutput] =
        SlotStack('create:empty_schematic', inventory[CannonSlot.blueprintOutput].count + 1);
    state = CannonState.stopped;
    statusMsg = 'finished';
    resetPrinter();
    env.playFinishSound();
    sendUpdate = true;
  }

  void resetPrinter() {
    printer.resetSchematic();
    missingItem = null;
    sendUpdate = true;
    schematicProgress = 0;
    blocksPlaced = 0;
    blocksToPlace = 0;
  }

  // ---- placement rules ------------------------------------------------------------------

  bool shouldPlace(CannonEnv env, Pos pos, BState st, List<int>? be, BState toReplace, BState? toReplaceOther, bool isNormalCube) {
    if (pos.distSqr(env.cannonPos) < 4) return false; // pos.closerThan(getBlockPos(), 2f)
    bool hasBe(BState s) => env.requirements.blockEntityTypeOf(s.key) != null;
    if (!replaceBlockEntities && (hasBe(toReplace) || (toReplaceOther != null && hasBe(toReplaceOther)))) return false;
    if (shouldIgnoreBlockState(env, st, be)) return false;
    final placingAir = st.isAir;
    if (replaceMode == 3) return true;
    if (replaceMode == 2 && !placingAir) return true;
    if (replaceMode == 1 &&
        (isNormalCube ||
            (!env.view.isRedstoneConductor(toReplace) &&
                (toReplaceOther == null || !env.view.isRedstoneConductor(toReplaceOther)))) &&
        !placingAir) {
      return true;
    }
    if (replaceMode == 0 &&
        !env.view.isRedstoneConductor(toReplace) &&
        (toReplaceOther == null || !env.view.isRedstoneConductor(toReplaceOther)) &&
        !placingAir) {
      return true;
    }
    return false;
  }

  bool shouldIgnoreBlockState(CannonEnv env, BState st, List<int>? be) {
    // Block doesn't have a mapping (water, lava, etc)
    if (st.key == 'minecraft:structure_void') return true;
    final requirement = env.requirements.ofBlock(st, be);
    if (requirement.isEmpty) return false;
    if (requirement.isInvalid) return false;
    // Block doesn't need to be placed twice (doors, beds, double plants)
    if (st['half'] == 'upper') return true;
    if (st['part'] == 'head' && st.key.endsWith('_bed')) return true;
    if (st.key == 'minecraft:piston_head') return true;
    if (st.key == 'create:belt') return st['part'] == 'middle';
    return false;
  }

  // ---- launching ---------------------------------------------------------------------------

  void launchBlockOrBelt(CannonEnv env, Pos target, SlotStack icon, BState blockState, List<int>? nbt) {
    if (blockState.key == 'create:belt') {
      var st = stripBeltIfNotLast(blockState);
      if (st.key == 'create:belt') {
        // The casings of each segment come from the block entities of the schematic.
        final world = printer.world!;
        final rel = target - printer.anchor!;
        final length = _beltLength(nbt);
        final casings = List<int>.filled(length, 0);
        var current = rel;
        for (var i = 0; i < length; i++) {
          final seg = world.blockAt(current);
          if (seg.state.key != 'create:belt') break;
          casings[i] = _beltCasing(seg.nbt);
          final next = nextBeltSegment(seg.state, current, st['part'] != 'end');
          if (next == null) break;
          current = next;
        }
        launchBelt(env, target, st, casings);
      } else if (st != BState.air) {
        launchBlock(env, target, icon, st, null);
      }
      return;
    }
    launchBlock(env, target, icon, blockState, env.prepareBlockEntityData(blockState, nbt));
  }

  static int _beltLength(List<int>? nbt) {
    final v = _intTag(nbt, 'Length');
    return v == null || v < 1 ? 1 : v;
  }

  static int _beltCasing(List<int>? nbt) {
    final parsed = nbt == null ? null : BinaryNbt.read(nbt);
    final c = parsed?.root.kind == NbtKind.compound ? parsed!.root.asCompound['Casing'] : null;
    if (c == null || c.kind != NbtKind.string) return 0;
    return switch (c.value as String) {
      'ANDESITE' => 1,
      'BRASS' => 2,
      _ => 0,
    };
  }

  static int? _intTag(List<int>? nbt, String key) {
    final parsed = nbt == null ? null : BinaryNbt.read(nbt);
    if (parsed == null || parsed.root.kind != NbtKind.compound) return null;
    final v = parsed.root.asCompound[key];
    return v != null && v.value is int ? v.value as int : null;
  }

  void launchBelt(CannonEnv env, Pos target, BState st, List<int> casings) {
    blocksPlaced++;
    flyingBlocks.add(LaunchedBelt.launch(env.cannonPos, target, const SlotStack('create:belt_connector', 1), st, casings));
    env.playFiringSound();
  }

  void launchBlock(CannonEnv env, Pos target, SlotStack stack, BState st, List<int>? data) {
    if (!st.isAir) blocksPlaced++;
    flyingBlocks.add(LaunchedBlock.launch(env.cannonPos, target, stack, st, data));
    env.playFiringSound();
  }

  void launchEntity(CannonEnv env, Pos target, SlotStack stack, SchematicEntity entity) {
    blocksPlaced++;
    final abs = (
      entity.relativePos.$1 + printer.anchor!.$1,
      entity.relativePos.$2 + printer.anchor!.$2,
      entity.relativePos.$3 + printer.anchor!.$3,
    );
    flyingBlocks.add(LaunchedEntity.launch(env.cannonPos, target, stack, entity, abs));
    env.playFiringSound();
  }

  // ---- fuel and paper -----------------------------------------------------------------------

  Future<void> refillFuelIfPossible(CannonEnv env) async {
    if (env.hasCreativeCrate) return;
    final shots = shotsPerGunpowder(env);
    if (remainingFuel > shots) {
      remainingFuel = shots;
      sendUpdate = true;
      return;
    }
    if (remainingFuel > 0) return;
    if (!inventory[CannonSlot.gunpowder].isEmpty) {
      inventory[CannonSlot.gunpowder] = inventory[CannonSlot.gunpowder].shrink(1);
    } else if (!await env.takeExternalGunpowder()) {
      return;
    }
    remainingFuel += shots;
    if (statusMsg == 'noGunpowder') {
      if (blocksPlaced > 0) state = CannonState.running;
      statusMsg = 'ready';
    }
    sendUpdate = true;
  }

  Future<void> tickPaperPrinter(CannonEnv env) async {
    final blueprint = inventory[CannonSlot.blueprint];
    final paper = inventory[CannonSlot.bookInput];
    final out = inventory[CannonSlot.checklistOutput];
    final outputFull = out.count >= 64; // the slot limit
    if (printer.isErrored) return;
    if (!printer.isLoaded) {
      if (!blueprint.isEmpty) await initializePrinter(env, blueprint);
      return;
    }
    if (paper.isEmpty || outputFull) {
      if (bookPrintingProgress != 0) sendUpdate = true;
      bookPrintingProgress = 0;
      dontUpdateChecklist = false;
      return;
    }
    if (bookPrintingProgress >= 1) {
      bookPrintingProgress = 0;
      if (!dontUpdateChecklist) await updateChecklist(env);
      dontUpdateChecklist = true;
      final extracted = paper;
      inventory[CannonSlot.bookInput] = paper.shrink(1);
      var stack = await env.createChecklistStack(checklist, clipboard: env.isClipboard(extracted));
      stack = stack.withCount(inventory[CannonSlot.checklistOutput].count + 1);
      inventory[CannonSlot.checklistOutput] = stack;
      sendUpdate = true;
      return;
    }
    bookPrintingProgress += 0.05;
    sendUpdate = true;
  }

  /// `updateChecklist`.
  Future<void> updateChecklist(CannonEnv env) async {
    checklist.required.clear();
    checklist.damageRequired.clear();
    checklist.blocksNotLoaded = false;
    if (printer.isLoaded && !printer.isErrored) {
      blocksToPlace = blocksPlaced;
      blocksToPlace += printer.markAllBlockRequirements(
        checklist,
        env.view,
        (p, s, be, r, ro, n) => shouldPlace(env, p, s, be, r, ro, n),
      );
      printer.markAllEntityRequirements(checklist);
    }
    checklist.gathered.clear();
    await env.findInventories();
    for (final stack in await env.attachedStacks()) {
      if (!stack.isEmpty) checklist.collect(stack.item, stack.count);
    }
    sendUpdate = true;
  }

  // ---- packet ---------------------------------------------------------------------------------

  /// `ConfigureSchematicannonPacket.handle`.
  void configure(CannonOption option, bool set) {
    switch (option) {
      case CannonOption.dontReplace:
      case CannonOption.replaceAny:
      case CannonOption.replaceEmpty:
      case CannonOption.replaceSolid:
        replaceMode = option.index;
      case CannonOption.skipMissing:
        skipMissing = set;
      case CannonOption.skipBlockEntities:
        replaceBlockEntities = set;
      case CannonOption.play:
        state = CannonState.running;
        statusMsg = 'running';
      case CannonOption.pause:
        state = CannonState.paused;
        statusMsg = 'paused';
      case CannonOption.stop:
        state = CannonState.stopped;
        statusMsg = 'stopped';
    }
    sendUpdate = true;
  }
}
