// Host-touching services of the content module: sounds, advancements and the
// inventory criterion watcher.
import 'package:pumpkin_api/pumpkin_api.dart';

import '../api/advancements.dart';
import '../api/sounds.dart';
import '../manifest/manifest.dart';
import 'advancement_data.dart';

SoundCategory _category(String name) => switch (name) {
  'MASTER' => SoundCategory.master,
  'MUSIC' => SoundCategory.music,
  'RECORDS' => SoundCategory.records,
  'WEATHER' => SoundCategory.weather,
  'BLOCKS' => SoundCategory.blocks,
  'HOSTILE' => SoundCategory.hostile,
  'NEUTRAL' => SoundCategory.neutral,
  'PLAYERS' => SoundCategory.players,
  'AMBIENT' => SoundCategory.ambient,
  'VOICE' => SoundCategory.voice,
  _ => SoundCategory.blocks,
};

final class _SoundEvent {
  final String key;
  final double volume;
  final double pitch;
  const _SoundEvent(this.key, this.volume, this.pitch);
}

final class _SoundEntry {
  final SoundCategory category;
  final List<_SoundEvent> events;
  const _SoundEntry(this.category, this.events);
}

/// `AllSoundEvents` entries played by name.
final class CreateSoundsImpl implements CreateSounds {
  final Map<String, _SoundEntry> _entries = {};

  CreateSoundsImpl() {
    for (final def in kSoundEvents) {
      final events = <_SoundEvent>[];
      if (def.kind == 'wrapped') {
        for (var i = 0; i < def.registeredEvents.length; i++) {
          final w = i < def.wrapped.length ? def.wrapped[i] : null;
          events.add(_SoundEvent('create:${def.registeredEvents[i]}', w?.volume ?? 1, w?.pitch ?? 1));
        }
      } else {
        events.add(_SoundEvent('create:${def.registeredEvents.first}', 1, 1));
      }
      _entries[def.key] = _SoundEntry(_category(def.category), events);
    }
  }

  @override
  bool has(String name) => _entries.containsKey(name);

  @override
  void play(World world, (double, double, double) pos, String name, {double volume = 1, double pitch = 1}) {
    final entry = _entries[name];
    if (entry == null) throw ArgumentError.value(name, 'name', 'Unknown Create sound');
    for (final e in entry.events) {
      world.playCustomSound(
        soundName: e.key,
        category: entry.category,
        pos: pos,
        volume: e.volume * volume,
        pitch: e.pitch * pitch,
      );
    }
  }

  @override
  void playAtBlock(World world, (int, int, int) pos, String name, {double volume = 1, double pitch = 1}) =>
      play(world, (pos.$1 + 0.5, pos.$2 + 0.5, pos.$3 + 0.5), name, volume: volume, pitch: pitch);
}

/// `CreateAdvancement.awardTo`.
final class CreateAdvancementsImpl implements CreateAdvancements {
  final AdvancementTree tree;

  CreateAdvancementsImpl(this.tree);

  @override
  bool canAward(String id) => tree.awardable.contains(id);

  @override
  Future<bool> award(Player player, String id) async {
    if (!tree.awardable.contains(id)) {
      throw UnsupportedError('Advancement $id uses external triggers, it cannot be awarded directly');
    }
    return (await player.fireCriterion('create:${id}_builtin')) > 0;
  }

  @override
  bool isAlreadyAwardedTo(Player player, String id) {
    final progress = player.advancementProgress('create:$id');
    if (progress == null) return true;
    return progress.isDone;
  }
}

/// Fires the inventory based criteria. The host does not evaluate `minecraft:inventory_changed`, so
/// the advancements that Create gives for holding an item use [inventoryCheckTrigger]; this checks
/// the inventory of each player once a second until the player has all of them.
final class InventoryAdvancementWatcher {
  final AdvancementTree tree;
  final Logger log;
  final Map<String, int> _counters = {};
  final Set<String> _finished = {};

  InventoryAdvancementWatcher(this.tree, this.log);

  static const int intervalTicks = 20;

  void install(Context context) {
    if (tree.inventoryCriteria.isEmpty) return;
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
    for (final c in tree.inventoryCriteria) {
      final progress = player.advancementProgress('create:${c.advancementId}');
      if (progress != null && progress.isCriterionDone(c.criterion)) continue;
      open.add(c);
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
    for (final c in open) {
      if (c.matches(held, Tags.item)) {
        await player.fireCriterion(inventoryCheckTrigger, matcher: c.tag);
      }
    }
  }
}
