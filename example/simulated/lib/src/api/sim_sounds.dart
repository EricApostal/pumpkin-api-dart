// The sound events of Simulated, as data.
//
// Java builds these through a `SoundEventRegistry` that also writes
// `sounds.json`. The port keeps the same keys and the same subtitle/file
// metadata (so the datapack can still be generated from it) and registers the
// keys as sound events through Create's registry.
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.index.SimSoundEvents

/// The sound source category (`SoundSource`).
enum SimSoundSource { master, player, neutral, block, hostile, ambient, voice, weather, ui }

/// One sound file variant of an event.
final class SimSoundFile {
  /// The path under `assets/<namespace>/sounds/`, without the extension.
  final String name;
  final double volume;
  final double pitch;
  final int weight;

  const SimSoundFile(this.name, {this.volume = 1, this.pitch = 1, this.weight = 1});
}

/// One sound event.
final class SimSoundEntry {
  /// `simulated:<path>`.
  final String key;

  /// The subtitle translation key, or `null`.
  final String? subtitle;

  final SimSoundSource source;

  /// The file variants of the event.
  final List<SimSoundFile> files;

  const SimSoundEntry(
    this.key, {
    this.subtitle,
    this.source = SimSoundSource.block,
    this.files = const [],
  });
}

/// The sound events of the mod.
abstract final class SimSoundEvents {
  static const String _namespace = 'simulated';

  static SimSoundEntry _entry(
    String path, {
    String? subtitle,
    SimSoundSource source = SimSoundSource.block,
    List<String> files = const [],
  }) => SimSoundEntry(
    '$_namespace:$path',
    subtitle: subtitle == null ? null : 'subtitles.simulated.$subtitle',
    source: source,
    files: [for (final f in files) SimSoundFile(f)],
  );

  static List<String> _variants(String base, int count) =>
      [for (var i = 1; i <= count; i++) '$base$i'];

  static final SimSoundEntry absorberEats = _entry(
    'block.absorber.eats',
    subtitle: 'block.absorber.eats',
    files: _variants('block/absorber/foulbeast', 2),
  );

  static final SimSoundEntry plungerPlace = _entry(
    'block.plunger.place',
    subtitle: 'block.generic.place',
    files: _variants('block/plunger/place', 3),
  );

  static final SimSoundEntry assemblerShift =
      _entry('block.physics_assembler.shift', files: const ['block/physics_assembler/shift']);

  static final SimSoundEntry assemblerTick = _entry(
    'block.physics_assembler.tick',
    subtitle: 'block.physics_assembler.tick',
    files: _variants('block/physics_assembler/tick', 4),
  );

  static final SimSoundEntry assemblerFail = _entry(
    'block.physics_assembler.fail',
    subtitle: 'block.physics_assembler.fail',
    files: _variants('block/physics_assembler/fail', 3),
  );

  static final SimSoundEntry dockingConnectorDocks = _entry(
    'block.docking_connector.dock',
    subtitle: 'block.docking_connector.dock',
    files: _variants('block/docking_connector/dock', 4),
  );

  static final SimSoundEntry dockingConnectorExtends = _entry(
    'block.docking_connector.extend',
    subtitle: 'block.docking_connector.extend',
    files: const ['block/docking_connector/retract'],
  );

  static final SimSoundEntry dockingConnectorRetracts = _entry(
    'block.docking_connector.retract',
    subtitle: 'block.docking_connector.retract',
    files: const ['block/docking_connector/retract'],
  );

  static final SimSoundEntry ropeWinchStretch = _entry(
    'block.rope_winch.stretch',
    subtitle: 'block.rope_winch.stretch',
    files: _variants('block/rope_winch/rope_stretch', 3),
  );

  static final SimSoundEntry linkedTypewriterTap = _entry(
    'block.linked_typewriter.tap',
    subtitle: 'block.linked_typewriter.tap',
    files: _variants('block/linked_typewriter/tap', 5),
  );

  static final SimSoundEntry linkedTypewriterUntap = _entry(
    'block.linked_typewriter.untap',
    files: const ['block/linked_typewriter/untap'],
  );

  static final SimSoundEntry linkedTypewriterDing = _entry(
    'block.linked_typewriter.ding',
    files: const ['block/linked_typewriter/ding'],
  );

  /// Played when a structure is assembled into a sub-level.
  static final SimSoundEntry simulatedContraptionMoves = _entry(
    'block.physics_assembler.assemble',
    subtitle: 'block.physics_assembler.assemble',
    files: _variants('block/physics_assembler/assemble', 5),
  );

  /// Played when a sub-level is placed back into the world.
  static final SimSoundEntry simulatedContraptionStops = _entry(
    'block.physics_assembler.disassemble',
    subtitle: 'block.physics_assembler.disassemble',
    files: const ['block/physics_assembler/disassemble'],
  );

  static final SimSoundEntry portableEngineAmbient = _entry(
    'block.portable_engine.ambient',
    subtitle: 'block.portable_engine.ambient',
    files: _variants('block/portable_engine/ambient', 5),
  );

  static final SimSoundEntry portableEnginePuff = _entry(
    'block.portable_engine.puff',
    files: _variants('block/portable_engine/puff', 5),
  );

  static final SimSoundEntry portableEngineRoars = _entry(
    'block.portable_engine.activate',
    subtitle: 'block.portable_engine.activate',
  );

  static final SimSoundEntry augerShaftEncasing = _entry(
    'block.auger_shaft.encase',
    subtitle: 'block.auger_shaft.encase',
  );

  static final SimSoundEntry plungerLaunch = _entry(
    'item.plunger_launcher.fwoomp',
    subtitle: 'item.plunger_launcher.fwoomp',
    source: SimSoundSource.player,
    files: const ['item/plunger_launcher/fwoomp'],
  );

  static final SimSoundEntry plungerRelease = _entry(
    'item.plunger_launcher.release',
    subtitle: 'item.plunger_launcher.release',
    source: SimSoundSource.player,
    files: _variants('block/plunger/break', 4),
  );

  static final SimSoundEntry honeyAdded = _entry(
    'item.honey_glue.use',
    subtitle: 'item.honey_glue.use',
    source: SimSoundSource.player,
  );

  static final SimSoundEntry staffIdle = _entry(
    'item.physics_staff.idle',
    source: SimSoundSource.player,
    files: const ['item/physics_staff/idle'],
  );

  static final SimSoundEntry staffIgnite = _entry(
    'item.physics_staff.ignite',
    subtitle: 'item.physics_staff.ignite',
    source: SimSoundSource.player,
    files: _variants('item/physics_staff/ignite', 3),
  );

  static final SimSoundEntry staffExtinguish = _entry(
    'item.physics_staff.extinguish',
    subtitle: 'item.physics_staff.extinguish',
    source: SimSoundSource.player,
    files: _variants('item/physics_staff/extinguish', 3),
  );

  static final SimSoundEntry staffLock = _entry(
    'item.physics_staff.lock',
    subtitle: 'item.physics_staff.lock',
    source: SimSoundSource.player,
    files: _variants('item/physics_staff/lock', 3),
  );

  static final SimSoundEntry staffUnlock = _entry(
    'item.physics_staff.unlock',
    subtitle: 'item.physics_staff.unlock',
    source: SimSoundSource.player,
    files: _variants('item/physics_staff/lock', 3),
  );

  static final SimSoundEntry diagramCheckmark = _entry(
    'gui.contraption_diagram.check',
    source: SimSoundSource.player,
    files: const ['gui/contraption_diagram/check'],
  );

  static final SimSoundEntry diagramErase = _entry(
    'gui.contraption_diagram.erase',
    source: SimSoundSource.player,
    files: const ['gui/contraption_diagram/erase'],
  );

  static final SimSoundEntry diagramTap = _entry(
    'gui.contraption_diagram.tap',
    source: SimSoundSource.player,
    files: _variants('gui/contraption_diagram/tap', 2),
  );

  /// Every event, in registration order.
  static final List<SimSoundEntry> all = [
    absorberEats,
    plungerPlace,
    assemblerShift,
    assemblerTick,
    assemblerFail,
    dockingConnectorDocks,
    dockingConnectorExtends,
    dockingConnectorRetracts,
    ropeWinchStretch,
    linkedTypewriterTap,
    linkedTypewriterUntap,
    linkedTypewriterDing,
    simulatedContraptionMoves,
    simulatedContraptionStops,
    portableEngineAmbient,
    portableEnginePuff,
    portableEngineRoars,
    augerShaftEncasing,
    plungerLaunch,
    plungerRelease,
    honeyAdded,
    staffIdle,
    staffIgnite,
    staffExtinguish,
    staffLock,
    staffUnlock,
    diagramCheckmark,
    diagramErase,
    diagramTap,
  ];
}
