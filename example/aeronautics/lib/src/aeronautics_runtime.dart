// The host wiring of the mod that is not a block entity: the gust entities and the advancements of
// the tab.
//
// Java: `content/blocks/hot_air/gust/GustEntity` (spawned through `Balloon.spawnGust`), and
// `index/AeroAdvancements` (the ten datapack files of `data/aeronautics/advancement/` plus the
// `aeronautics:<id>_builtin` triggers `AeroAdvancementTriggers` registers).
//
// Host: this file uses `pumpkin_api`.
// ignore_for_file: implementation_imports
import 'dart:async';

import 'package:create/src/common/pos.dart' show Pos;
import 'package:create/src/content/advancement_data.dart' show InventoryCriterion;
import 'package:create/src/core/module.dart' show CreateContext;
import 'package:pumpkin_api/pumpkin_api.dart';

import 'content/blocks/hot_air/gust/gust_host.dart';
import 'hot_air/balloon_save.dart';

/// The advancement the mounted potato cannon awards nearby (`AeroAdvancements.HEAVIER_ARTILLERY`).
const String heavierArtilleryAdvancement = 'aeronautics:heavier_artillery';

/// Its criterion trigger (`AeroAdvancementTriggers.addSimple("aeronautics", "heavier_artillery_builtin")`).
const String heavierArtilleryTrigger = 'aeronautics:heavier_artillery_builtin';

/// `CreateAdvancement.awardToNearby(pos, level)`: the radius it awards within.
const double advancementRadius = 10;

/// The advancement ids, in the declaration order of `AeroAdvancements.AERO_ADVANCEMENTS`.
abstract final class AeroAdvancementIds {
  static const String root = 'aeronautics:root';
  static const String highFashion = 'aeronautics:high_fashion';
  static const String headInTheClouds = 'aeronautics:head_in_the_clouds';
  static const String songOfTheSky = 'aeronautics:song_of_the_sky';
  static const String forEveryAction = 'aeronautics:for_every_action';
  static const String inThrustWeTrust = 'aeronautics:in_thrust_we_trust';
  static const String heavierArtillery = 'aeronautics:heavier_artillery';
  static const String ghostbuster = 'aeronautics:ghostbuster';
  static const String unidentifiedFloatingObject = 'aeronautics:unidentified_floating_object';
  static const String nowAvailableInPink = 'aeronautics:now_available_in_pink';
}

/// The criterion trigger of [advancement] (`AeroAdvancementTriggers.addSimple("aeronautics",
/// "<path>_builtin")`): the id of an advancement this mod awards itself plus `_builtin`.
///
/// Firing the advancement id itself would fire a trigger no criterion uses — `SimpleSimulatedTrigger`
/// is registered under `<path>_builtin` and the criterion names the same — so every award goes
/// through this.
String aeroTriggerOf(String advancement) =>
    advancement.endsWith('_builtin') ? advancement : '${advancement}_builtin';

/// The trigger that stands in for `minecraft:inventory_changed` for the three criteria the host
/// does not evaluate (`root` = Java's `awardedForFree`, `high_fashion` and `song_of_the_sky` =
/// `whenIconCollected`). Create's port does exactly this (`create:inventory_check`).
const String aeroInventoryCheckTrigger = 'aeronautics:inventory_check';

/// The three inventory criteria, rewritten to [aeroInventoryCheckTrigger]: the advancement path,
/// the criterion name, and the items (or `#tags`) the player must hold. The root's list is empty
/// (`awardedForFree` hands `hasItems()` nothing), so it matches on the first check.
const List<InventoryCriterion> aeroInventoryCriteria = [
  InventoryCriterion('root', '0', []),
  InventoryCriterion('high_fashion', '0', ['aeronautics:aviators_goggles']),
  InventoryCriterion('song_of_the_sky', '0', ['aeronautics:music_disc_cloud_skipper']),
];

/// The root of the mod's advancement tab, from the mod's generated resources
/// (`data/aeronautics/advancement/root.json`), with its criterion moved off
/// `minecraft:inventory_changed` (the host never fires it, so Java's `awardedForFree` would never
/// grant the tab root) onto [aeroInventoryCheckTrigger].
const String _rootAdvancementJson = '''
{
  "criteria": {"0": {"conditions": {"plugin_tag": "root/0"}, "trigger": "aeronautics:inventory_check"}},
  "display": {
    "announce_to_chat": false,
    "background": "aeronautics:textures/gui/advancement.png",
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.root.desc"},
    "icon": {"id": "aeronautics:white_envelope"},
    "show_toast": false,
    "title": {"translate": "advancement.aeronautics.root"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `HEAVIER_ARTILLERY` ("Fire a vegetable from a Mounted Potato Cannon"), verbatim from the mod's
/// generated resources.
const String _heavierArtilleryJson = '''
{
  "parent": "aeronautics:root",
  "criteria": {
    "0": {
      "conditions": "aeronautics:heavier_artillery_builtin",
      "trigger": "aeronautics:heavier_artillery_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.heavier_artillery.desc"},
    "icon": {"id": "aeronautics:mounted_potato_cannon"},
    "title": {"translate": "advancement.aeronautics.heavier_artillery"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `HIGH_FASHION` ("Obtain a pair of Aviator's Goggles"), with `whenIconCollected`'s
/// `minecraft:inventory_changed` criterion moved onto [aeroInventoryCheckTrigger].
const String _highFashionJson = '''
{
  "parent": "aeronautics:root",
  "criteria": {"0": {"conditions": {"plugin_tag": "high_fashion/0"}, "trigger": "aeronautics:inventory_check"}},
  "display": {
    "announce_to_chat": false,
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.high_fashion.desc"},
    "icon": {"id": "aeronautics:aviators_goggles"},
    "title": {"translate": "advancement.aeronautics.high_fashion"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `HEAD_IN_THE_CLOUDS` ("Fill an airtight Envelope structure with hot air"), verbatim.
const String _headInTheCloudsJson = '''
{
  "parent": "aeronautics:root",
  "criteria": {
    "0": {
      "conditions": "aeronautics:head_in_the_clouds_builtin",
      "trigger": "aeronautics:head_in_the_clouds_builtin"
    }
  },
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.head_in_the_clouds.desc"},
    "icon": {"id": "aeronautics:adjustable_burner"},
    "title": {"translate": "advancement.aeronautics.head_in_the_clouds"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `SONG_OF_THE_SKY` ("Toss a music disc into the clouds to create something new"), with
/// `whenIconCollected`'s criterion moved onto [aeroInventoryCheckTrigger].
const String _songOfTheSkyJson = '''
{
  "parent": "aeronautics:head_in_the_clouds",
  "criteria": {"0": {"conditions": {"plugin_tag": "song_of_the_sky/0"}, "trigger": "aeronautics:inventory_check"}},
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.song_of_the_sky.desc"},
    "icon": {"id": "aeronautics:music_disc_cloud_skipper"},
    "title": {"translate": "advancement.aeronautics.song_of_the_sky"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `FOR_EVERY_ACTION` ("Place and power a Propeller to generate Thrust"), verbatim.
const String _forEveryActionJson = '''
{
  "parent": "aeronautics:head_in_the_clouds",
  "criteria": {
    "0": {
      "conditions": "aeronautics:for_every_action_builtin",
      "trigger": "aeronautics:for_every_action_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.for_every_action.desc"},
    "icon": {"id": "aeronautics:wooden_propeller"},
    "title": {"translate": "advancement.aeronautics.for_every_action"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `IN_THRUST_WE_TRUST` ("Assemble a Propeller Bearing to generate more Thrust"), verbatim.
const String _inThrustWeTrustJson = '''
{
  "parent": "aeronautics:for_every_action",
  "criteria": {
    "0": {
      "conditions": "aeronautics:in_thrust_we_trust_builtin",
      "trigger": "aeronautics:in_thrust_we_trust_builtin"
    }
  },
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.in_thrust_we_trust.desc"},
    "icon": {"id": "aeronautics:propeller_bearing"},
    "title": {"translate": "advancement.aeronautics.in_thrust_we_trust"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `GHOSTBUSTER` ("Kill a Phantom using a Mounted Potato Cannon"), verbatim.
const String _ghostbusterJson = '''
{
  "parent": "aeronautics:heavier_artillery",
  "criteria": {
    "0": {
      "conditions": "aeronautics:ghostbuster_builtin",
      "trigger": "aeronautics:ghostbuster_builtin"
    }
  },
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.ghostbuster.desc"},
    "frame": "goal",
    "icon": {"id": "minecraft:phantom_membrane"},
    "title": {"translate": "advancement.aeronautics.ghostbuster"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `UNIDENTIFIED_FLOATING_OBJECT` ("Crystallize Levitite Blend into Levitite"), verbatim.
const String _unidentifiedFloatingObjectJson = '''
{
  "parent": "aeronautics:head_in_the_clouds",
  "criteria": {
    "0": {
      "conditions": "aeronautics:unidentified_floating_object_builtin",
      "trigger": "aeronautics:unidentified_floating_object_builtin"
    }
  },
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.unidentified_floating_object.desc"},
    "icon": {"id": "aeronautics:levitite"},
    "title": {"translate": "advancement.aeronautics.unidentified_floating_object"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// `NOW_AVAILABLE_IN_PINK` ("Crystallize Levitite Blend into Pearlescent Levitite"), verbatim.
const String _nowAvailableInPinkJson = '''
{
  "parent": "aeronautics:unidentified_floating_object",
  "criteria": {
    "0": {
      "conditions": "aeronautics:now_available_in_pink_builtin",
      "trigger": "aeronautics:now_available_in_pink_builtin"
    }
  },
  "display": {
    "description": {"color": "#DBA213", "translate": "advancement.aeronautics.now_available_in_pink.desc"},
    "frame": "goal",
    "hidden": true,
    "icon": {"id": "aeronautics:pearlescent_levitite"},
    "title": {"translate": "advancement.aeronautics.now_available_in_pink"}
  },
  "requirements": [["0"]],
  "sends_telemetry_event": true
}''';

/// The ten definitions of `AeroAdvancements`, in declaration order (the parent of every child
/// comes first, as the bootstrap relies on).
const List<(String, String)> aeroAdvancementDefinitions = [
  (AeroAdvancementIds.root, _rootAdvancementJson),
  (AeroAdvancementIds.highFashion, _highFashionJson),
  (AeroAdvancementIds.headInTheClouds, _headInTheCloudsJson),
  (AeroAdvancementIds.songOfTheSky, _songOfTheSkyJson),
  (AeroAdvancementIds.forEveryAction, _forEveryActionJson),
  (AeroAdvancementIds.inThrustWeTrust, _inThrustWeTrustJson),
  (AeroAdvancementIds.heavierArtillery, _heavierArtilleryJson),
  (AeroAdvancementIds.ghostbuster, _ghostbusterJson),
  (AeroAdvancementIds.unidentifiedFloatingObject, _unidentifiedFloatingObjectJson),
  (AeroAdvancementIds.nowAvailableInPink, _nowAvailableInPinkJson),
];

/// The `aeronautics:<path>_builtin` criterion triggers (`AeroAdvancementTriggers.addSimple`), one
/// per definition that has one. The three inventory based ones (`root`, `high_fashion`,
/// `song_of_the_sky`) have none: Java builds them from an `InventoryChangeTrigger` instead.
const List<String> aeroBuiltinTriggers = [
  'aeronautics:head_in_the_clouds_builtin',
  'aeronautics:for_every_action_builtin',
  'aeronautics:in_thrust_we_trust_builtin',
  heavierArtilleryTrigger,
  'aeronautics:ghostbuster_builtin',
  'aeronautics:unidentified_floating_object_builtin',
  'aeronautics:now_available_in_pink_builtin',
];

/// The runtime of the mod, on the host side.
abstract final class AeroRuntime {
  static CreateContext? _ctx;

  /// Registers the advancements and installs the gust host. Called once, from `onLoad`.
  static void install(CreateContext ctx) {
    _ctx = ctx;
    GustHost().install(ctx);
    _registerAdvancements(ctx);
    AeroInventoryWatcher(ctx.log).install(ctx);
  }

  /// `AeroAdvancements`: the whole tab, and the criterion trigger of every definition that has one.
  ///
  /// Java ships the ten advancement files in the mod's datapack and registers the triggers in code
  /// (`AeroAdvancementTriggers.register`); the port registers the definitions as plugin
  /// advancements with the same ids, so a client that has the mod sees the same tree. The three
  /// criteria of `minecraft:inventory_changed` are rewritten onto [aeroInventoryCheckTrigger] by
  /// [aeroInventoryCriteria], because the host never fires that vanilla trigger.
  static void _registerAdvancements(CreateContext ctx) {
    try {
      for (final trigger in aeroBuiltinTriggers) {
        Advancements.registerTrigger(trigger);
      }
      Advancements.registerTrigger(aeroInventoryCheckTrigger);
      for (final (id, json) in aeroAdvancementDefinitions) {
        Advancements.registerJson(id, json);
      }
    } on Object catch (e, s) {
      ctx.log.error('Registering the Aeronautics advancements failed', error: e, stackTrace: s);
    }
  }

  /// `SimulatedAdvancement.awardToNearby(pos, level, radius)`: fires the builtin criterion trigger
  /// of [advancement] for every player within [radius] of [pos].
  static void awardNearby(World world, Pos pos, String advancement, {double radius = advancementRadius}) {
    final runtime = _ctx;
    if (runtime == null) return;
    final trigger = aeroTriggerOf(advancement);
    final center = (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    List<Player> nearby;
    try {
      nearby = runtime.host.getServer().playersNear(center, radius, worldName: world.getName());
    } on Object catch (e) {
      runtime.log.debug('advancement $advancement: no player list ($e)');
      return;
    }
    for (final player in nearby) {
      unawaited(player.fireCriterion(trigger).catchError((Object e) {
        runtime.log.debug('advancement $advancement failed: $e');
        return 0;
      }));
    }
  }

  /// Forgets the installed state (plugin unload).
  static void clear() {
    _ctx = null;
    AeroBalloonSave.clear();
  }
}

/// Fires the three inventory based criteria (`root`, `high_fashion`, `song_of_the_sky`).
///
/// The host never evaluates `minecraft:inventory_changed` (`AeroInventoryCheck`), so those
/// advancements use [aeroInventoryCheckTrigger] and this checks the inventory of each player once
/// a second. The root's criterion names no item (`awardedForFree`), so it satisfies on the first
/// check — that is the port's "granted for free". Create's port does the same
/// (`InventoryAdvancementWatcher`).
final class AeroInventoryWatcher {
  final Logger log;
  final Map<String, int> _counters = {};
  final Set<String> _finished = {};

  AeroInventoryWatcher(this.log);

  static const int intervalTicks = 20;

  void install(CreateContext context) {
    context.listen(Events.playerTick, (server, event) async {
      final player = event.player;
      final id = player.getName();
      final n = (_counters[id] ?? (id.hashCode & 15)) + 1;
      _counters[id] = n;
      if (n % intervalTicks != 0 || _finished.contains(id)) return;
      await _check(player, id);
    });
    context.listen(Events.playerLeave, (server, event) {
      final id = event.player.getName();
      _counters.remove(id);
      _finished.remove(id);
    });
  }

  Future<void> _check(Player player, String id) async {
    // Skip the criteria the player already has.
    final open = <InventoryCriterion>[];
    for (final criterion in aeroInventoryCriteria) {
      final progress = player.advancementProgress('aeronautics:${criterion.advancementId}');
      if (progress != null && progress.isCriterionDone(criterion.criterion)) continue;
      open.add(criterion);
    }
    if (open.isEmpty) {
      _finished.add(id);
      return;
    }
    final held = <String>{};
    final inventory = player.getInventory().asInventory();
    for (final stack in inventory.getAllItems()) {
      if (stack == null) continue;
      held.add(await stack.getRegistryKey());
    }
    for (final criterion in open) {
      if (!criterion.matches(held, Tags.item)) continue;
      try {
        await player.fireCriterion(aeroInventoryCheckTrigger, matcher: criterion.tag);
      } on Object catch (e) {
        log.debug('advancement ${criterion.advancementId} failed: $e');
      }
    }
  }
}