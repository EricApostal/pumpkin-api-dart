// The plugin's model of the world: computers, their records on disk, the
// operating system image and the clock they share. It contains no commands
// and no chat, so the pieces that will be driven by blocks later (creating a
// computer, attaching peripherals, reading its terminal) are all here.
import 'dart:typed_data';

import 'package:pumpkin_api/pumpkin_api.dart';

import '../machine/computer.dart';
import '../machine/craftos.dart';
import '../machine/filesystem.dart' show FileSystemException, WritableMount;
import '../machine/manager.dart';
import '../machine/mounts.dart';
import '../machine/peripheral.dart';
import '../machine/peripherals.dart';
import '../machine/side.dart';
import '../machine/zip.dart';
import '../lua/lua.dart' show ProtoCache;
import 'config.dart';
import 'records.dart';
import 'storage.dart';

final class CcService implements ComputerServices {
  final DataFolder _folder;
  final PluginConfig pluginConfig;
  final ProtoCache _cache = ProtoCache();
  final Stopwatch _clock = Stopwatch()..start();
  final WirelessNetwork wireless = WirelessNetwork();
  final Map<int, ComputerRecord> _records = {};
  final Map<String, Peripheral> _peripherals = {};

  late final ComputerManager manager = ComputerManager(this);
  late final MachineConfig _machineConfig = pluginConfig.toMachineConfig();
  CraftOsImage _image = CraftOsImage.fallback();

  int _nextId = 0;
  bool _dirty = false;
  int _ticks = 0;
  int _dayTime = 0;
  int _worldAge = 0;

  CcService._(this._folder, this.pluginConfig);

  /// Loads the configuration, the OS image and the saved computers.
  factory CcService.load(DataFolder folder) {
    final config = _readConfig(folder);
    final service = CcService._(folder, config);
    service._loadImage();
    service._loadRecords();
    return service;
  }

  static PluginConfig _readConfig(DataFolder folder) {
    try {
      return PluginConfig.fromJson(folder.readJson('config.json'));
    } on FileException catch (e) {
      if (!e.isNotFound) logger.error('Could not read config.json: $e');
    } on FormatException catch (e) {
      logger.error('config.json is not valid JSON, using the defaults: $e');
    }
    final defaults = const PluginConfig();
    try {
      folder.writeAsString('config.json', defaults.toJsonText());
    } on FileException catch (e) {
      logger.error('Could not write config.json: $e');
    }
    return defaults;
  }

  // -- ComputerServices -------------------------------------------------------

  @override
  CraftOsImage get image => _image;

  @override
  ProtoCache get cache => _cache;

  @override
  MachineConfig get config => _machineConfig;

  @override
  int get nowMicros => _clock.elapsedMicroseconds;

  @override
  double get timeOfDay => ((_dayTime + 6000) % 24000) / 1000.0;

  @override
  int get day => (_worldAge + 6000) ~/ 24000 + 1;

  @override
  WritableMount createRootMount(int id, int quota) =>
      StoreMount(DataFolderStore(_folder, 'computers/$id'), quota);

  @override
  void log(String message) => logger.warn(message);

  // -- The operating system image ---------------------------------------------

  /// Looks for the CC: Tweaked jar in the data folder, or falls back to the
  /// built-in BIOS.
  void _loadImage() {
    final candidates = <String>[];
    if (pluginConfig.jar.isNotEmpty) {
      candidates.add(pluginConfig.jar);
    } else {
      try {
        for (final entry in _folder.list()) {
          if (!entry.isDirectory && entry.name.toLowerCase().endsWith('.jar')) {
            candidates.add(entry.name);
          }
        }
      } on FileException catch (e) {
        logger.error('Could not list the data folder: $e');
      }
    }
    for (final name in candidates) {
      try {
        final bytes = Uint8List.fromList(_folder.readAsBytes(name));
        _image = CraftOsImage.fromJar(bytes, name);
        logger.info('CraftOS image: ${_image.source}, mod version ${_image.modVersion ?? 'unknown'}');
        return;
      } on FileException catch (e) {
        logger.warn('Could not read $name: $e');
      } on ZipException catch (e) {
        logger.warn('$name is not a usable CC: Tweaked jar: $e');
      } on FileSystemException catch (e) {
        logger.warn('$name: ${e.message}');
      }
    }
    logger.warn(
      'No CC: Tweaked jar found in the data folder: computers run the minimal '
      'built-in BIOS. Put the mod jar there (see the README) and restart.',
    );
  }

  /// Whether the real ROM is in use.
  bool get hasRom => _image.rom != null;

  // -- Records ------------------------------------------------------------------

  void _loadRecords() {
    try {
      final json = _folder.readJson('computers.json');
      if (json is Map<String, Object?>) {
        final next = json['next_id'];
        if (next is num) _nextId = next.toInt();
        final list = json['computers'];
        if (list is List<Object?>) {
          for (final item in list) {
            if (item is! Map<String, Object?>) continue;
            final record = ComputerRecord.fromJson(item);
            _records[record.id] = record;
            if (record.id >= _nextId) _nextId = record.id + 1;
          }
        }
      }
    } on FileException catch (e) {
      if (!e.isNotFound) logger.error('Could not read computers.json: $e');
    } on FormatException catch (e) {
      logger.error('computers.json is not valid, starting without computers: $e');
    }
    var inWorld = 0;
    for (final record in _records.values) {
      // Computers that stand in a block run while their chunk is loaded: the
      // block entity load event brings them up (`resume`), the unload event
      // takes them down (`suspend`).
      if (record.location != null) {
        inWorld++;
        continue;
      }
      _instantiate(record);
      if (record.on) manager[record.id]!.turnOn();
    }
    final suffix = inWorld == 0 ? '.' : ', $inWorld in blocks (started when their chunk loads).';
    logger.info('Loaded ${_records.length} computer(s)$suffix');
  }

  Computer _instantiate(ComputerRecord record) {
    final computer = manager.create(record.id, record.family, label: record.label);
    computer.onChanged = () => _recordChanged(record, computer);
    for (final entry in record.peripherals.entries) {
      final side = ComputerSide.parse(entry.key);
      if (side != null) _attach(computer, side, entry.value);
    }
    return computer;
  }

  void _recordChanged(ComputerRecord record, Computer computer) {
    record.label = computer.label;
    record.on = computer.isOn;
    _dirty = true;
  }

  void save() {
    final json = {
      'next_id': _nextId,
      'computers': [for (final r in _records.values) r.toJson()],
    };
    try {
      _folder.writeJson('computers.json', json);
      _dirty = false;
    } on FileException catch (e) {
      logger.error('Could not save computers.json: $e');
    }
  }

  // -- Computers ----------------------------------------------------------------

  List<ComputerRecord> get records => _records.values.toList();

  ComputerRecord? record(int id) => _records[id];

  Computer? computer(int id) => manager[id];

  int countOwnedBy(String owner) => _records.values.where((r) => r.owner == owner).length;

  /// Creates a new computer with the next id.
  Computer create({
    required ComputerFamily family,
    required String owner,
    required String ownerName,
  }) {
    final record = ComputerRecord(
      id: _nextId++,
      family: family,
      owner: owner,
      ownerName: ownerName,
    );
    _records[record.id] = record;
    final computer = _instantiate(record);
    save();
    return computer;
  }

  /// Brings the computer [id] of a block at [location] up: creates its record
  /// when this server has none (a world copied from elsewhere; the id is kept
  /// and later ids start after it) and its machine, and turns it on when it was
  /// on. [family], [owner] and [label] only matter for a new record; [on], when given, replaces the
  /// power state the record has.
  Computer resumeAt(
    int id,
    ComputerLocation location, {
    ComputerFamily family = ComputerFamily.advanced,
    String owner = 'unknown',
    String ownerName = 'unknown',
    String? label,
    bool? on,
  }) {
    var record = _records[id];
    if (record == null) {
      record = ComputerRecord(id: id, family: family, owner: owner, ownerName: ownerName, label: label, on: on ?? false);
      _records[id] = record;
      if (id >= _nextId) _nextId = id + 1;
    }
    record.location = location;
    if (on != null) record.on = on;
    _dirty = true;
    final existing = manager[id];
    if (existing != null) return existing;
    final computer = _instantiate(record);
    if (record.on) computer.turnOn();
    return computer;
  }

  /// Brings the machine of computer [id] up again if it was suspended (for the
  /// debug command of a computer whose chunk is not loaded).
  Computer? resume(int id) {
    final existing = manager[id];
    if (existing != null) return existing;
    final record = _records[id];
    if (record == null) return null;
    final computer = _instantiate(record);
    if (record.on) computer.turnOn();
    return computer;
  }

  /// Stops the machine of computer [id] but keeps its record and disk (its
  /// chunk unloaded, or its block was broken). [location] is cleared when the
  /// block is gone.
  void suspend(int id, {bool blockRemoved = false}) {
    final record = _records[id];
    final computer = manager[id];
    if (computer != null) {
      if (record != null) record.on = computer.isOn;
      manager.remove(id);
    }
    final keys = _peripherals.keys.where((k) => k.startsWith('$id/')).toList();
    for (final key in keys) {
      _peripherals.remove(key);
    }
    if (record != null && blockRemoved) record.location = null;
    _dirty = true;
  }

  /// Stops and deletes a computer and everything on its disk.
  void remove(int id) {
    manager.remove(id);
    _records.remove(id);
    final keys = _peripherals.keys.where((k) => k.startsWith('$id/')).toList();
    for (final key in keys) {
      _peripherals.remove(key);
    }
    try {
      _folder.delete('computers/$id', recursive: true);
    } on FileException catch (e) {
      if (!e.isNotFound) logger.error('Could not delete the disk of computer $id: $e');
    }
    save();
  }

  // -- Peripherals ----------------------------------------------------------

  void _attach(Computer computer, ComputerSide side, PeripheralSpec spec) {
    final Peripheral peripheral = switch (spec.type) {
      'modem' => WirelessModem(network: wireless, advanced: spec.advanced),
      _ => MonitorPeripheral(spec.width, spec.height, advanced: spec.advanced),
    };
    _peripherals['${computer.id}/${side.luaName}'] = peripheral;
    computer.setPeripheral(side, peripheral);
  }

  /// Attaches a monitor or modem to [side] of computer [id].
  void attach(int id, ComputerSide side, PeripheralSpec spec) {
    final computer = manager[id]!;
    _records[id]!.peripherals[side.luaName] = spec;
    _attach(computer, side, spec);
    save();
  }

  void detach(int id, ComputerSide side) {
    _records[id]?.peripherals.remove(side.luaName);
    _peripherals.remove('$id/${side.luaName}');
    manager[id]?.setPeripheral(side, null);
    save();
  }

  /// The peripheral attached to [side] of computer [id], if any.
  Peripheral? peripheral(int id, ComputerSide side) => _peripherals['$id/${side.luaName}'];

  // -- The server tick ----------------------------------------------------------

  /// Updates the in-game clock from the world: [dayTime] is the time of day in
  /// ticks and [age] the age of the world in ticks.
  void syncWorldTime(int dayTime, int age) {
    _dayTime = dayTime;
    _worldAge = age;
  }

  /// Advances all computers by one server tick.
  void tick() {
    _ticks++;
    _dayTime++;
    _worldAge++;
    manager.tick();
    if (_dirty && _ticks % 100 == 0) save();
  }

  /// How many ticks the service has run.
  int get ticks => _ticks;

  /// Stops every computer and saves; computers that were on start again with
  /// the next load.
  void shutdown() {
    final wasOn = {for (final c in manager.computers) c.id: c.isOn};
    manager.unloadAll();
    for (final entry in wasOn.entries) {
      _records[entry.key]?.on = entry.value;
    }
    save();
  }
}
