// The host wiring of the mod that is not a block entity: the gust entities and the advancement the
// mounted potato cannon awards.
//
// Java: `content/blocks/hot_air/gust/GustEntity` (spawned through `Balloon.spawnGust`), and
// `index/AeroAdvancements` (the datapack file plus the `aeronautics:<id>_builtin` trigger
// `AeroAdvancementTriggers` registers).
//
// Host: this file uses `pumpkin_api`.
import 'dart:async';

import 'package:create/src/common/pos.dart' show Pos;
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

/// The root of the mod's advancement tab, from the mod's generated resources
/// (`data/aeronautics/advancement/root.json`).
const String _rootAdvancementJson = '''
{
  "criteria": {"0": {"trigger": "minecraft:inventory_changed"}},
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

/// The runtime of the mod, on the host side.
abstract final class AeroRuntime {
  static CreateContext? _ctx;

  /// Registers the advancements and installs the gust host. Called once, from `onLoad`.
  static void install(CreateContext ctx) {
    _ctx = ctx;
    GustHost().install(ctx);
    _registerAdvancements(ctx);
  }

  /// `AeroAdvancements`: the tab root and `HEAVIER_ARTILLERY`, and the criterion trigger the
  /// cannon fires.
  ///
  /// Java ships both advancement files in the mod's datapack and registers the trigger in code
  /// (`AeroAdvancementTriggers.register`); the port registers the two definitions as plugin
  /// advancements with the same ids, so a client that has the mod sees the same tree.
  static void _registerAdvancements(CreateContext ctx) {
    try {
      Advancements.registerTrigger(heavierArtilleryTrigger);
      Advancements.registerJson('aeronautics:root', _rootAdvancementJson);
      Advancements.registerJson(heavierArtilleryAdvancement, _heavierArtilleryJson);
    } on Object catch (e, s) {
      ctx.log.error('Registering the Aeronautics advancements failed', error: e, stackTrace: s);
    }
  }

  /// `SimulatedAdvancement.awardToNearby(pos, level, radius)`: fires [advancement]'s trigger for
  /// every player within [radius] of [pos].
  static void awardNearby(World world, Pos pos, String advancement, {double radius = advancementRadius}) {
    final runtime = _ctx;
    if (runtime == null) return;
    final center = (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5);
    List<Player> nearby;
    try {
      nearby = runtime.host.getServer().playersNear(center, radius, worldName: world.getName());
    } on Object catch (e) {
      runtime.log.debug('advancement $advancement: no player list ($e)');
      return;
    }
    for (final player in nearby) {
      unawaited(player.fireCriterion(advancement).catchError((Object e) {
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