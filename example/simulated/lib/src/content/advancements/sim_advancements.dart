// The advancement tree of Simulated on the host side: what the plugin registers
// and who it awards.
//
// The definitions, the two plugin triggers and the pure matching tables are in
// `sim_advancement_data.dart` (exported here); this file is the half that needs
// the host: `Advancements.registerTrigger` / `registerJson`, the two watchers for
// the criteria the host never fires, and `award` / `awardNearby` -- the port of
// `SimulatedAdvancement.awardTo` / `awardToNearby`.
//
// Java registers the mod's triggers in code (`SimAdvancementTriggers.register`)
// and ships the definitions in the mod's datapack; a Pumpkin plugin registers
// both at load, so a client that has the mod sees the same tree.
//
// Host: this file uses `pumpkin_api` (the data file is pure).
//
// Java: dev.simulated_team.simulated.data.advancements.SimAdvancements
//       dev.simulated_team.simulated.data.advancements.SimulatedAdvancement
//       dev.simulated_team.simulated.data.advancements.SimAdvancementTriggers
// create's internals are not exported from the barrel yet.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/core/module.dart' show CreateContext;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'sim_advancement_data.dart';

export 'sim_advancement_data.dart';

/// The advancements of the mod.
///
/// The constants are the ids of `SimAdvancements`' fields, so a call site reads
/// like the Java one: `SimAdvancements.award(player, SimAdvancements.steamlessEngine)`.
abstract final class SimAdvancements {
  // `SimAdvancements`: `ROOT`, `APPLIED_KINEMATICS`, ... in declaration order.
  static const String root = 'root';
  static const String appliedKinematics = 'applied_kinematics';
  static const String oppositeAttract = 'opposite_attract';
  static const String aCalculatedConnection = 'a_calculated_connection';
  static const String youSpinMeRightRound = 'you_spin_me_right_round';
  static const String learningTheRopes = 'learning_the_ropes';
  static const String stuckTogether = 'stuck_together';
  static const String notGonnaSugarcoatIt = 'not_gonna_sugarcoat_it';
  static const String iDeclareThee = 'i_declare_thee';
  static const String measureOnceBuildTwice = 'measure_once_build_twice';
  static const String getAGrip = 'get_a_grip';
  static const String gotAGrip = 'got_a_grip';
  static const String unpoweredSteering = 'unpowered_steering';
  static const String steamlessEngine = 'steamless_engine';
  static const String thatShouldDoForNow = 'that_should_do_for_now';
  static const String whatGoesDown = 'what_goes_down';
  static const String mustComeUp = 'must_come_up';
  static const String rewindTime = 'rewind_time';
  static const String iPaidForTheWholeTypewriter = 'i_paid_for_the_whole_typewriter';
  static const String noPressure = 'no_pressure';
  static const String canWeGetMuchHigher = 'can_we_get_much_higher';
  static const String convolutedCircumvolutions = 'convoluted_circumvolutions';
  static const String theDefinitionOfUp = 'the_definition_of_up';
  static const String thataway = 'thataway';
  static const String farFromHome = 'far_from_home';
  static const String speedIsKey = 'speed_is_key';
  static const String bigBeam = 'big_beam';
  static const String nearsighted = 'nearsighted';
  static const String myEye = 'my_eye';
  static const String callOfTheVoid = 'call_of_the_void';

  /// Every advancement of the tab, in the Java declaration order.
  static const List<String> ids = simAdvancementIds;

  /// The context the awards need (`getServer`); `null` before [install].
  static CreateContext? _ctx;

  /// The plugin logger, `null` before [install].
  static Logger? _log;

  /// `SimAdvancementTriggers.addSimple(modid, id + "_builtin")`: the criterion trigger
  /// [award] fires. [id] is the bare path (`'unpowered_steering'`).
  static String triggerOf(String id) => simBuiltinTrigger(id);

  /// The registered advancement id (`simulated:<path>`).
  static String idOf(String id) => simAdvancementId(id);

  /// Whether `SimulatedAdvancement.awardTo` can grant [id] (it has a `_builtin` criterion).
  static bool canAward(String id) => simHasBuiltinTrigger(id);

  /// Registers the definitions and their triggers, and installs the two watchers for the
  /// criteria the host never fires.
  ///
  /// Called once, from the plugin's `onLoad`. Every entry is registered on its own, so one
  /// definition the host rejects does not cost the rest of the tab.
  static void install(CreateContext ctx) {
    _ctx = ctx;
    _log = ctx.log;
    var triggers = 0;
    for (final trigger in simAdvancementTriggers()) {
      try {
        Advancements.registerTrigger(trigger);
        triggers++;
      } on Object catch (e) {
        _log?.warn('Could not register the criterion trigger $trigger: $e');
      }
    }
    var definitions = 0;
    for (final path in simAdvancementIds) {
      try {
        Advancements.registerJson(simAdvancementId(path), simAdvancementsRegisteredJson(path));
        definitions++;
      } on Object catch (e) {
        _log?.warn('Could not register the advancement ${simAdvancementId(path)}: $e');
      }
    }
    _log?.info(
      'Advancements: $definitions/${simAdvancementIds.length} definitions and $triggers triggers; '
      '${simInventoryCriteria.length} inventory and ${simPlacedCriteria.length} placed criteria '
      'are evaluated by the plugin.',
    );

    // The host fires neither `minecraft:inventory_changed` nor `minecraft:placed_block`, so
    // the criteria rewritten to the plugin triggers are evaluated here.
    if (simInventoryCriteria.isNotEmpty) _SimInventoryWatcher(_log).install(ctx);
    if (simPlacedCriteria.isNotEmpty) _SimPlacedWatcher(_log).install(ctx);
  }

  /// Forgets the installed state (plugin unload). The host keeps the registered definitions,
  /// as it does for a datapack reload, and a later [install] replaces them.
  static void clear() {
    _ctx = null;
    _log = null;
  }

  /// `SimulatedAdvancement.awardTo(player)`: fires the `_builtin` criterion trigger of [id]
  /// for [player].
  ///
  /// Java does nothing when the player already has it and throws for an advancement whose
  /// criteria are external; here both are logged and dropped, so an award can never take a
  /// caller (an event handler or a payload) down. The player handle is not kept past the
  /// call.
  static void award(Player player, String id) {
    final log = _log;
    if (!canAward(id)) {
      // Java: `throw new UnsupportedOperationException("... uses external Triggers")`.
      log?.debug('Advancement ${simAdvancementId(id)} uses external triggers, it cannot be awarded');
      return;
    }
    final trigger = triggerOf(id);
    try {
      unawaited(
        player.fireCriterion(trigger).catchError((Object e) {
          log?.debug('Awarding $trigger failed: $e');
          return 0;
        }),
      );
    } on Object catch (e) {
      // `fireCriterion` throws when the handle already went invalid.
      log?.debug('Awarding $trigger failed: $e');
    }
  }

  /// `SimulatedAdvancement.awardToNearby(pos, level, radius)`: [award] to every player within
  /// [radius] blocks of [pos] in [world] (`10` by default, Java's two-argument overload).
  static void awardNearby(World world, Pos pos, String id, {double radius = 10}) {
    final ctx = _ctx;
    if (ctx == null) return;
    unawaited(_awardNearby(ctx, world, pos, id, radius));
  }

  static Future<void> _awardNearby(
    CreateContext ctx,
    World world,
    Pos pos,
    String id,
    double radius,
  ) async {
    final log = _log;
    Server? server;
    try {
      server = ctx.host.getServer();
      // `new AABB(pos).inflate(radius)`: the block centre, as Java's box is centred on it.
      // The handles are borrowed (`playersNear` is valid "for this callback"), so they must
      // not be disposed here.
      final center = (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
      final nearby = server.playersNear(center, radius, worldName: world.getName());
      for (final player in nearby) {
        try {
          await player.fireCriterion(triggerOf(id));
        } on Object catch (e) {
          log?.debug('Awarding ${triggerOf(id)} failed: $e');
        }
      }
    } on Object catch (e) {
      log?.debug('Awarding ${triggerOf(id)} near ${pos.$1},${pos.$2},${pos.$3} failed: $e');
    } finally {
      server?.dispose();
    }
  }
}

/// Fires the inventory based criteria.
///
/// The host does not evaluate `minecraft:inventory_changed`, so the advancements the mod gives
/// for holding an item use [inventoryCheckTrigger]; this checks the inventory of each player
/// once a second until the player has all of them. The shape is Create's
/// `InventoryAdvancementWatcher` (`example/create/lib/src/content/content_services.dart`).
final class _SimInventoryWatcher {
  _SimInventoryWatcher(this.log);

  static const int intervalTicks = 20;

  final Logger? log;
  final Map<String, int> _counters = {};
  final Set<String> _finished = {};

  void install(CreateContext ctx) {
    ctx.listen(Events.playerTick, (server, event) async {
      final player = event.player;
      final id = player.getName();
      // Spread the first scan of every player over the interval, so a full server does not
      // read every inventory on the same tick.
      final n = (_counters[id] ?? (id.hashCode & 15)) + 1;
      _counters[id] = n;
      if (n % intervalTicks != 0 || _finished.contains(id)) return;
      try {
        await _check(player, id);
      } on Object catch (e) {
        log?.debug('The inventory advancement check of $id failed: $e');
      }
    });
    ctx.listen(Events.playerLeave, (server, event) {
      final id = event.player.getName();
      _counters.remove(id);
      _finished.remove(id);
    });
  }

  Future<void> _check(Player player, String id) async {
    // Skip the criteria the player already has.
    final open = <SimInventoryCriterion>[];
    for (final c in simInventoryCriteria) {
      final progress = player.advancementProgress(SimAdvancements.idOf(c.advancementId));
      if (progress != null && progress.isCriterionDone(c.criterion)) continue;
      open.add(c);
    }
    if (open.isEmpty) {
      _finished.add(id);
      return;
    }
    final held = <String>{};
    // `getInventory().asInventory()`: owned handles, each valid until disposed.
    final playerInventory = player.getInventory();
    final inventory = playerInventory.asInventory();
    final stacks = inventory.getAllItems();
    for (final stack in stacks) {
      if (stack == null) continue;
      try {
        held.add(await stack.getRegistryKey());
      } on Object catch (e) {
        log?.debug('Reading a held item of $id failed: $e');
      } finally {
        stack.dispose();
      }
    }
    stacks.clear();
    inventory.dispose();
    playerInventory.dispose();
    for (final c in open) {
      if (!c.matches(held)) continue;
      await player.fireCriterion(inventoryCheckTrigger, matcher: c.tag);
    }
  }
}

/// Fires the placed-block criteria.
///
/// The host does not evaluate `minecraft:placed_block`, so the five advancements whose second
/// criterion is a `minecraft:match_block` placement use [placedBlockCheckTrigger]; this fires
/// it for the placing player when the block that went down is the criterion's block.
///
/// Java's criterion is `ItemUsedOnLocationTrigger.TriggerInstance.placedBlock`, which fires for
/// any block a player places, so the host's own block-placement event is the one that matches
/// (and not the plugin block entities' `player-placed` hook, which is only called for the
/// blocks that ask for it).
final class _SimPlacedWatcher {
  _SimPlacedWatcher(this.log);

  final Logger? log;

  void install(CreateContext ctx) {
    ctx.listen(Events.blockPlace, (server, event) async {
      if (event.cancelled) return;
      final block = event.blockPlaced;
      for (final c in simPlacedCriteria) {
        if (!c.matches(block)) continue;
        try {
          await event.player.fireCriterion(placedBlockCheckTrigger, matcher: c.tag);
        } on Object catch (e) {
          log?.debug('The placed advancement check of ${c.tag} failed: $e');
        }
      }
    });
  }
}