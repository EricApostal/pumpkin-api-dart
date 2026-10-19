// Declares the global content of the mod on the CreateRegistry: damage types, sounds,
// particles, menus, data components, synced registries, tags, criterion triggers and
// advancements. All from the manifest, in the order of the Java registries.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../core/registry.dart';
import '../manifest/manifest.dart';
import 'advancement_data.dart';
import 'components.dart';
import 'tag_data.dart';

DamageScaling _scaling(String s) => switch (s) {
  'never' => DamageScaling.never,
  'always' => DamageScaling.always,
  _ => DamageScaling.whenCausedByLivingNonPlayer,
};

DamageEffects? _effects(String? s) => s == null ? null : DamageEffects.fromWireName(s);

DeathMessageType _deathMessage(String? s) =>
    s == null ? DeathMessageType.default_ : (DeathMessageType.fromWireName(s.replaceAll('_', '-')) ?? DeathMessageType.default_);

/// How each particle type's options are written on the wire (the `StreamCodec` of its data class).
ParticleOptions _particleOptions(String key) => switch (key) {
  'rotation_indicator' || 'air_flow' || 'air' || 'steam_jet' || 'cube' => ParticleOptions.bytes,
  'fluid_particle' || 'basin_fluid' || 'fluid_drip' => ParticleOptions.bytes,
  _ => ParticleOptions.none,
};

/// Registers the content of the `content` module.
void registerGlobalContent(CreateRegistry registry, AdvancementTree advancements) {
  // Data components (registration order of AllDataComponents).
  for (final c in createComponents) {
    registry.dataComponent(c.key, codec: c.codec, persistent: true);
  }

  // Menu types (AllMenuTypes).
  for (final m in kMenuTypes) {
    registry.menu('create:${m.key}');
  }

  // Damage types (AllDamageTypes.bootstrap order).
  for (final d in kDamageTypes) {
    registry.damageType(
      DamageTypeSpec(
        key: 'create:${d.key}',
        messageId: d.messageId,
        scaling: _scaling(d.scaling),
        exhaustion: d.exhaustion,
        effects: _effects(d.effects),
        deathMessageType: _deathMessage(d.deathMessageType),
      ),
    );
  }

  // Sound events: the main event of each entry, then its `_compounded_n` events.
  for (final s in kSoundEvents) {
    for (final ev in s.registeredEvents) {
      registry.sound(SoundSpec('create:$ev'));
    }
  }

  // Particle types (AllParticleTypes).
  for (final p in kParticleTypes) {
    registry.particle(ParticleSpec('create:${p.key}', options: _particleOptions(p.key)));
  }

  // The `create:*` registries with sync(true). `potato_projectile/type` is a datapack registry
  // (reloadable, not synced to clients), so it is not declared here.
  for (final r in kCustomRegistries) {
    if (!r.syncedToClient) continue;
    registry.syncedRegistry('create:${r.key}', [for (final e in r.entries) 'create:${e.key}']);
  }

  // `AllIngredients` (`create:simple_datagen`) is not declared to the handshake. Its registry is
  // `neoforge:ingredient_serializer` (`NeoForgeRegistries.Keys.INGREDIENT_TYPES`, `sync(true)`),
  // which the client already has from NeoForge and Create in the same Java order. A declaration
  // sends a snapshot the client *replaces* its registry with, so listing the one entry the plugin
  // knows would drop `neoforge:simple` and the other types the client has. Nothing needs those ids
  // on the wire: item ingredients travel as item lists and fluid ingredients as the
  // `neoforge:simple` id (`recipe_network.dart`); `create:simple_datagen` is only the
  // `neoforge:ingredient_type` discriminator of datapack JSON, resolved by the client's own mod.

  // Tags.
  for (final t in manifestTags()) {
    final kind = switch (t.kind) {
      ManifestTagKind.block => TagKind.block,
      ManifestTagKind.item => TagKind.item,
      ManifestTagKind.fluid => TagKind.fluid,
      ManifestTagKind.entityType => TagKind.entityType,
    };
    registry.tag(kind, t.tag, t.entries);
  }

  // Advancement triggers and the advancement tree.
  for (final t in advancements.triggers) {
    registry.criterionTrigger(t);
  }
  for (final e in advancements.json.entries) {
    registry.advancementJsonText('create:${e.key}', e.value);
  }
}
