// The small data types of contraptions (pure): a captured block, the assembly exception,
// the movement setting of a block and the limits of the config.
import 'dart:convert';

import '../../api/block_state.dart';
import '../../common/common.dart';
import 'nbt_map.dart';

/// `StructureTemplate.StructureBlockInfo`: a block of a contraption at a local position, its
/// state and the saved block entity data, `null` for a block without a block entity.
final class StructureBlockInfo {
  final Pos pos;
  final BState state;

  /// `saveWithFullMetadata` without the position (`x`, `y`, `z`), `null` without block entity.
  final NbtMap? nbt;

  const StructureBlockInfo(this.pos, this.state, [this.nbt]);

  StructureBlockInfo withState(BState newState) => StructureBlockInfo(pos, newState, nbt);

  StructureBlockInfo withNbt(NbtMap? newNbt) => StructureBlockInfo(pos, state, newNbt);

  StructureBlockInfo at(Pos newPos) => StructureBlockInfo(newPos, state, nbt);

  @override
  String toString() => 'StructureBlockInfo($pos, $state${nbt == null ? '' : ', nbt'})';
}

/// A reference to a block's name inside an [AssemblyException] message (`Block.getName()`).
final class BlockNameArg {
  /// `minecraft:stone`.
  final String blockKey;

  const BlockNameArg(this.blockKey);

  Object toJsonValue() {
    final i = blockKey.indexOf(':');
    final ns = i < 0 ? 'minecraft' : blockKey.substring(0, i);
    final path = (i < 0 ? blockKey : blockKey.substring(i + 1)).replaceAll('/', '.');
    return {'translate': 'block.$ns.$path'};
  }
}

/// `AssemblyException`: why a contraption could not be assembled. The message is a translatable
/// component (Create's lang key and its arguments), written to block entities as JSON.
final class AssemblyException implements Exception {
  /// The full translation key, `create.gui.assembly.exception.unmovableBlock`.
  final String translationKey;

  /// Numbers, strings and [BlockNameArg]s.
  final List<Object> args;
  Pos? _position;

  AssemblyException(this.translationKey, [this.args = const []]);

  AssemblyException._at(this.translationKey, this.args, Pos at) : _position = at;

  /// `new AssemblyException(langKey, args)`: the key below `create.gui.assembly.exception.`.
  AssemblyException.gui(String langKey, [List<Object> args = const []])
    : this('create.gui.assembly.exception.$langKey', args);

  static AssemblyException unmovableBlock(Pos pos, BState state) =>
      AssemblyException._at('create.gui.assembly.exception.unmovableBlock', [pos.$1, pos.$2, pos.$3, BlockNameArg(state.key)], pos);

  static AssemblyException unloadedChunk(Pos pos) =>
      AssemblyException._at('create.gui.assembly.exception.chunkNotLoaded', [pos.$1, pos.$2, pos.$3], pos);

  static AssemblyException structureTooLarge(int maxBlocksMoved) =>
      AssemblyException.gui('structureTooLarge', [maxBlocksMoved]);

  static AssemblyException tooManyPistonPoles(int maxPistonPoles) =>
      AssemblyException.gui('tooManyPistonPoles', [maxPistonPoles]);

  static AssemblyException noPistonPoles() => AssemblyException.gui('noPistonPoles');

  static AssemblyException notEnoughSails(int sails, int minimum) =>
      AssemblyException.gui('not_enough_sails', [sails, minimum]);

  static AssemblyException noContacts() => AssemblyException.gui('no_contacts');

  static AssemblyException tooManyContacts() => AssemblyException.gui('too_many_contacts');

  static AssemblyException columnConflict() => AssemblyException.gui('column_conflict');

  bool get hasPosition => _position != null;

  Pos? get position => _position;

  /// The message as the JSON of a text component.
  String toComponentJson() => jsonEncode({
    'translate': translationKey,
    if (args.isNotEmpty) 'with': [for (final a in args) a is BlockNameArg ? a.toJsonValue() : a],
  });

  /// `AssemblyException.write`: `LastException {Component, Position}`; nothing for `null`.
  static void write(NbtMap compound, AssemblyException? exception) {
    if (exception == null) return;
    final nbt = NbtMap()..putString('Component', exception.toComponentJson());
    final p = exception._position;
    if (p != null) nbt.putLong('Position', packBlockPos(p));
    compound.putCompound('LastException', nbt);
  }

  /// `AssemblyException.read`.
  static AssemblyException? read(NbtMap compound) {
    final nbt = compound.getCompoundOrNull('LastException');
    if (nbt == null) return null;
    final json = nbt.getString('Component');
    String key = 'create.gui.assembly.exception';
    var args = <Object>[];
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        key = decoded['translate'] as String? ?? key;
        final with_ = decoded['with'];
        if (with_ is List) {
          args = [
            for (final a in with_)
              if (a is Map<String, dynamic> && a['translate'] is String && (a['translate'] as String).startsWith('block.'))
                BlockNameArg(_blockKeyOfTranslation(a['translate'] as String))
              else if (a is num || a is String)
                a as Object,
          ];
        }
      }
    } on FormatException {
      // an unreadable message keeps the default key
    }
    final e = AssemblyException(key, args);
    if (nbt.contains('Position')) e._position = unpackBlockPos(nbt.getInt('Position'));
    return e;
  }

  static String _blockKeyOfTranslation(String t) {
    final parts = t.split('.');
    if (parts.length < 3) return 'minecraft:air';
    return '${parts[1]}:${parts.sublist(2).join('/')}';
  }

  @override
  String toString() => 'AssemblyException($translationKey, $args)';
}

/// `BlockPos.asLong`.
int packBlockPos(Pos p) => p.asLong;

/// `BlockPos.of(long)`.
Pos unpackBlockPos(int v) => posFromLong(v);

/// `ContraptionMovementSetting`: whether a block can be moved by a contraption.
enum ContraptionMovementSetting {
  /// Fully movable with no restrictions.
  movable,

  /// Can be mounted and moved, but a minecart contraption with it cannot be picked up.
  noPickup,

  /// Can never be moved by a contraption.
  unmovable;

  /// The value of a config enum (`MOVABLE`, `NO_PICKUP`, `UNMOVABLE`).
  static ContraptionMovementSetting fromConfig(String name) => switch (name) {
    'MOVABLE' => movable,
    'NO_PICKUP' => noPickup,
    _ => unmovable,
  };
}

/// The limits of `kinetics.contraptions` and friends, read when needed so `/create config`
/// changes apply at once.
abstract class ContraptionSettings {
  int get maxBlocksMoved;
  int get maxChassisRange;
  int get maxPistonPoles;
  int get maxRopeLength;
  int get minimumWindmillSails;
  int get windmillSailsPerRPM;

  /// `fluids.fluidTankCapacity` (buckets per tank block).
  int get fluidTankCapacity;
  bool get survivalContraptionPickup;
  bool get moveItemsToStorage;
  bool get minecartContraptionInContainers;
  bool get stabiliseStableContraptions;
  bool get noDropWhenContraptionReplaceBlocks;
  bool get seatHostileMobs;
  bool get trainsCauseDamage;

  /// The setting of the config-driven blocks (`minecraft:spawner`, `obsidian`, ...), `null`
  /// for blocks without a setting.
  ContraptionMovementSetting? movementSettingOf(String blockKey);
}

/// [ContraptionSettings] with Create's defaults, for tests and for plugins without configs.
class DefaultContraptionSettings implements ContraptionSettings {
  @override
  int maxBlocksMoved = 2048;
  @override
  int maxChassisRange = 16;
  @override
  int maxPistonPoles = 64;
  @override
  int maxRopeLength = 384;
  @override
  int minimumWindmillSails = 8;
  @override
  int windmillSailsPerRPM = 8;
  @override
  int fluidTankCapacity = 8;
  @override
  bool survivalContraptionPickup = true;
  @override
  bool moveItemsToStorage = true;
  @override
  bool minecartContraptionInContainers = false;
  @override
  bool stabiliseStableContraptions = false;
  @override
  bool noDropWhenContraptionReplaceBlocks = false;
  @override
  bool seatHostileMobs = true;
  @override
  bool trainsCauseDamage = true;

  /// Overrides by block key, on top of Create's defaults.
  final Map<String, ContraptionMovementSetting> movementSettings = {
    'minecraft:spawner': ContraptionMovementSetting.noPickup,
    'minecraft:budding_amethyst': ContraptionMovementSetting.noPickup,
    'minecraft:obsidian': ContraptionMovementSetting.unmovable,
    'minecraft:crying_obsidian': ContraptionMovementSetting.unmovable,
    'minecraft:respawn_anchor': ContraptionMovementSetting.unmovable,
    'minecraft:reinforced_deepslate': ContraptionMovementSetting.unmovable,
  };

  @override
  ContraptionMovementSetting? movementSettingOf(String blockKey) => movementSettings[blockKey];
}
