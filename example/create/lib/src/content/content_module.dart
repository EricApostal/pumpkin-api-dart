// The `content` module: the non-block, non-entity global content of the mod.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart';
import '../api/sounds.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../infrastructure/config/create_configs.dart';
import '../manifest/manifest.dart';
import 'advancement_data.dart';
import 'content_registrations.dart';
import 'content_services.dart';
import 'enchantments.dart';

/// Registers damage types, enchantments, sounds, particles, menu types, data components, the
/// `create:*` synced registries, tags, advancement triggers and the advancement tree, the map
/// decoration and the entity data serializer; provides [CreateAdvancements] and [CreateSounds].
///
/// Not registered: mob effects (Create has none), creative tabs (not synced), the datapack registry
/// `create:potato_projectile/type` (reloadable, not synced; the datapack module ships the JSON).
final class ContentModule extends CreateModule {
  late final AdvancementTree _tree = AdvancementTree.fromManifest();

  @override
  String get name => 'content';

  @override
  void register(CreateRegistry registry) {
    registerGlobalContent(registry, _tree);
    for (final e in CreateEnchantments.definitions()) {
      registry.enchantment(e);
    }
    // The synced server config as NeoForge clients get it with the handshake (defaults; the
    // infrastructure module pushes the configured values when they differ).
    registry.neoForgeConfigFile(CreateConfigs.serverFile, _utf8(CreateConfigs().serverToml()));
  }

  @override
  void onLoad(CreateContext ctx) {
    final log = ctx.log;
    ctx.services.provide<CreateAdvancements>(CreateAdvancementsImpl(_tree));
    ctx.services.provide<CreateSounds>(CreateSoundsImpl());

    final station = kMapDecorations.first;
    try {
      ExtraRegistries.registerMapDecoration(
        MapDecorationSpec(
          'create:${station.key}',
          assetName: station.assetId,
          showOnItemFrame: station.showOnItemFrame,
          mapColor: station.mapColor,
          explorationMapElement: station.explorationMapElement,
          trackCount: station.trackCount,
        ),
      );
    } on HostException catch (e) {
      log.error('Could not register the station map decoration: ${e.message}');
    }

    for (final s in kEntityDataSerializers) {
      try {
        EntityRegistries.registerDataSerializer('create:${s.key}');
      } on HostException catch (e) {
        log.error('Could not register the entity data serializer ${s.key}: ${e.message}');
      }
    }

    CreateEnchantments.configure(ctx.host).catchError((Object e, StackTrace s) {
      log.error('Could not configure the enchantments: $e');
    });

    InventoryAdvancementWatcher(_tree, log).install(ctx.host);
  }
}

List<int> _utf8(String s) => utf8.encode(s);
