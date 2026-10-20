// `ArrivalSoundQueue` (pure): the bells, note blocks and whistles of a carriage, sounded in
// order from the front of the train to the back when it arrives at a station.
import 'dart:math' as math;

import '../../api/block_state.dart';
import '../../common/data.dart';
import '../../common/pos.dart';
import '../util/ctag.dart';
import 'carriage_contraption_entity.dart';
import 'contraption_data.dart';
import 'train_level.dart';

class ArrivalSoundQueue {
  int offset = 0;
  int min = 0x7fffffff;
  int max = -0x80000000;
  final Map<int, List<Pos>> sources = {};

  ArrivalSoundQueue();

  /// `firstTick()`.
  int? firstTick() => sources.isEmpty ? null : min + offset;

  /// `lastTick()`.
  int? lastTick() => sources.isEmpty ? null : max + offset;

  bool tick(CarriageContraptionEntity entity, int tick, bool backwards) {
    tick = tick - offset;
    if (!sources.containsKey(tick)) return backwards ? tick > min : tick < max;
    final contraption = entity.getContraption();
    for (final blockPos in sources[tick]!) {
      play(entity, contraption?.data.getBlocks()[blockPos]);
    }
    return backwards ? tick > min : tick < max;
  }

  /// `getFirstWhistle(entity)`: `(low, pitch)` of the first whistle, or `null`.
  Pair<bool, int>? getFirstWhistle(CarriageContraptionEntity entity) {
    final firstTick = this.firstTick();
    final lastTick = this.lastTick();
    if (firstTick == null || lastTick == null || firstTick > lastTick) return null;
    for (var i = firstTick; i <= lastTick; i++) {
      if (!sources.containsKey(i - offset)) continue;
      final contraption = entity.getContraption();
      for (final blockPos in sources[i - offset]!) {
        final info = contraption?.data.getBlocks()[blockPos];
        if (info == null) continue;
        final state = info.state;
        if (state.key == whistleKey && info.nbt != null) {
          final pitch = info.nbt!.getInt('Pitch');
          final size = state['size'];
          return Pair.of(size == 'large', (size == 'small' ? 12 : 0) - pitch);
        }
      }
    }
    return null;
  }

  void serialize(CTag tagIn) {
    final tag = CTag();
    tag.putInt('Offset', offset);
    tag.putCompoundList('Sources', [
      for (final e in sources.entries)
        for (final pos in e.value)
          CTag()
            ..putInt('Tick', e.key)
            ..putBlockPos('Pos', pos),
    ]);
    tagIn.putCompound('SoundQueue', tag);
  }

  void deserialize(CTag tagIn) {
    final tag = tagIn.getCompound('SoundQueue');
    offset = tag.getInt('Offset');
    for (final c in tag.getCompoundList('Sources')) {
      add(c.getInt('Tick'), c.getBlockPos('Pos'));
    }
  }

  void add(int offset, Pos localPos) {
    sources.putIfAbsent(offset, () => []).add(localPos);
    min = math.min(offset, min);
    max = math.max(offset, max);
  }

  static const String whistleKey = 'create:steam_whistle';
  static const String hauntedBellKey = 'create:haunted_bell';

  /// `isPlayable(state)`: a bell, a note block or a steam whistle.
  static bool isPlayable(BState state) {
    if (state.key == 'minecraft:bell' || state.key == hauntedBellKey) return true;
    if (state.key == 'minecraft:note_block') return true;
    if (state.key == whistleKey) return true;
    return false;
  }

  /// `NoteBlockInstrument.getSoundEvent()` by the name of the `instrument` property.
  static String instrumentSound(String? instrument) {
    final name = instrument ?? 'harp';
    return switch (name) {
      'zombie' => 'minecraft:block.note_block.imitate.zombie',
      'skeleton' => 'minecraft:block.note_block.imitate.skeleton',
      'creeper' => 'minecraft:block.note_block.imitate.creeper',
      'dragon' => 'minecraft:block.note_block.imitate.ender_dragon',
      'wither_skeleton' => 'minecraft:block.note_block.imitate.wither_skeleton',
      'piglin' => 'minecraft:block.note_block.imitate.piglin',
      // `NoteBlockInstrument.CUSTOM_HEAD.getSoundEvent()` is the UI click.
      'custom_head' => 'minecraft:ui.button.click',
      _ => 'minecraft:block.note_block.$name',
    };
  }

  static void play(CarriageContraptionEntity entity, ContraptionBlockInfo? info) {
    if (info == null) return;
    final state = info.state;

    if (state.key == 'minecraft:bell' || state.key == hauntedBellKey) {
      if (state.key == hauntedBellKey) {
        _playSimple(entity, 'create:haunted_bell_use', 1, 1);
      } else {
        _playSimple(entity, 'minecraft:block.bell.use', 1, 1);
      }
    }

    if (state.key == 'minecraft:note_block') {
      final f = math.pow(2, (state.intValue('note') - 12) / 12.0).toDouble();
      _playSimple(entity, instrumentSound(state['instrument']), 1, f);
    }

    if (state.key == whistleKey && info.nbt != null) {
      final pitch = info.nbt!.getInt('Pitch');
      final size = state['size'];
      final f = math.pow(2, ((size == 'small' ? 12 : 0) - pitch) / 12.0).toDouble();
      _playSimple(entity, size == 'large' ? 'create:whistle_train_low' : 'create:whistle_train', 1, f);
    }
  }

  static void _playSimple(CarriageContraptionEntity entity, String event, double volume, double pitch) {
    TrainFx.effects.playSound(entity.dimension, entity.position, event, 5 * volume, pitch);
  }
}
