// All computers of a server and how they share the server tick.
import 'computer.dart';

final class ComputerManager {
  final ComputerServices services;
  final Map<int, Computer> _computers = {};
  int _rotation = 0;

  ComputerManager(this.services);

  /// All computers, in id order.
  List<Computer> get computers =>
      (_computers.values.toList()..sort((a, b) => a.id.compareTo(b.id)));

  Computer? operator [](int id) => _computers[id];

  /// Creates and registers the computer [id]. It starts off.
  Computer create(int id, ComputerFamily family, {String? label}) {
    if (_computers.containsKey(id)) {
      throw StateError('Computer $id already exists');
    }
    final computer = Computer(id: id, family: family, services: services, label: label);
    _computers[id] = computer;
    return computer;
  }

  /// Stops and forgets the computer [id].
  void remove(int id) => _computers.remove(id)?.unload();

  /// Advances every computer by one tick. Computers take turns being first so
  /// that when the tick budget runs out, the same ones do not always starve.
  void tick() {
    final list = _computers.values.toList();
    if (list.isEmpty) return;
    final config = services.config;
    var left = config.tickBudgetMicros;
    for (var i = 0; i < list.length; i++) {
      final computer = list[(i + _rotation) % list.length];
      final budget = left <= 0 ? 0 : (left < config.sliceMicros ? left : config.sliceMicros);
      left -= computer.tick(budget);
    }
    _rotation = (_rotation + 1) % list.length;
  }

  /// Stops every computer (server shutdown or plugin unload).
  void unloadAll() {
    for (final computer in _computers.values) {
      computer.unload();
    }
  }
}
