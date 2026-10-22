// The `content` module: the global content of the mod that no content package owns (damage types,
// enchantments, sounds, particles, components, tags, advancements) and the plain materials.
import 'dart:convert';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart';
import '../api/payloads.dart';
import '../api/sounds.dart';
import '../core/module.dart';
import '../core/registry.dart';
import '../infrastructure/config/create_configs.dart';
import '../manifest/manifest.dart';
import 'advancement_data.dart';
import 'content_registrations.dart';
import 'content_services.dart';
import 'enchantments.dart';
import 'experience_nugget_host.dart';
import 'material_blocks.dart';
import 'material_content.dart';

/// Registers damage types, enchantments, sounds, particles, menu types, data components, the
/// `create:*` synced registries, tags, advancement triggers and the advancement tree, the map
/// decoration, the entity data serializer and the `create:simple_datagen` ingredient type; provides
/// [CreateAdvancements] and [CreateSounds].
///
/// Also registers the plain materials (`AllBlocks` ores and storage blocks, `AllItems`
/// ingredients) that no content package owns; see `material_content.dart`.
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
    // The plain materials (ores, storage blocks, ingredients) that no content package owns.
    for (final item in createMaterialItems()) {
      registry.item(item);
    }
    for (final block in createMaterialBlocks()) {
      registry.block(block);
    }
    for (final e in CreateEnchantments.definitions()) {
      registry.enchantment(e);
    }
    // The station's map decoration and the entity data serializers: id-bearing
    // registries the host numbers (`applyRegistry` registers them, `contentRegistries`
    // names `minecraft:map_decoration_type` and `neoforge:entity_data_serializers` for
    // them). Only the station decoration is registered; the ids after it resolve to the
    // client's own entries, which are the same ones in the same order.
    if (kMapDecorations.isNotEmpty) {
      final station = kMapDecorations.first;
      registry.mapDecoration(
        MapDecorationSpec(
          'create:${station.key}',
          assetName: station.assetId,
          showOnItemFrame: station.showOnItemFrame,
          mapColor: station.mapColor,
          explorationMapElement: station.explorationMapElement,
          trackCount: station.trackCount,
        ),
      );
    }
    for (final s in kEntityDataSerializers) {
      registry.entityDataSerializer('create:${s.key}');
    }
    // The synced server config as NeoForge clients get it with the handshake (defaults; the
    // infrastructure module pushes the configured values when they differ).
    registry.neoForgeConfigFile(
      CreateConfigs.serverFile,
      _utf8(CreateConfigs().serverToml()),
    );
  }

  @override
  void onLoad(CreateContext ctx) {
    final log = ctx.log;
    ctx.services.provide<CreateAdvancements>(
      CreateAdvancementsImpl(
        _tree,
        () => ctx.services.find<PayloadBus>()?.roster.players ?? const <Player>[],
      ),
    );
    ctx.services.provide<CreateSounds>(CreateSoundsImpl());

    CreateEnchantments.configure(ctx.host).catchError((Object e, StackTrace s) {
      log.error('Could not configure the enchantments: $e');
    });

    InventoryAdvancementWatcher(_tree, log).install(ctx.host);
    // `ExperienceNuggetItem.use`: a right click in the air with an experience nugget.
    ExperienceNuggetHost().install(ctx.host);
  }
}

List<int> _utf8(String s) => utf8.encode(s);
