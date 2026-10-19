// `KineticNetwork`: the stress accounting of one connected set of kinetic
// blocks (pure). Direct port of Create's `KineticNetwork`.
import 'node.dart';

class KineticNetwork {
  final KineticLevel level;
  final int id;
  bool initialized = false;

  /// Sources and their added capacity per RPM.
  final Map<KineticNode, double> sources = {};

  /// Members and their stress impact per RPM.
  final Map<KineticNode, double> members = {};

  double _currentCapacity = 0;
  double _currentStress = 0;
  double _unloadedCapacity = 0;
  double _unloadedStress = 0;
  int _unloadedMembers = 0;

  KineticNetwork(this.level, this.id);

  double get currentCapacity => _currentCapacity;
  double get currentStress => _currentStress;

  void initFromTE(double maxStress, double currentStress, int members) {
    _unloadedCapacity = maxStress;
    _unloadedStress = currentStress;
    _unloadedMembers = members;
    initialized = true;
    updateStress();
    updateCapacity();
  }

  void addSilently(KineticNode be, double lastCapacity, double lastStress) {
    if (members.containsKey(be)) return;
    if (be.isSource) {
      _unloadedCapacity -= lastCapacity * _stressMultiplierForSpeed(be.generatedSpeed);
      final addedStressCapacity = be.calculateAddedStressCapacity();
      sources[be] = addedStressCapacity;
    }

    _unloadedStress -= lastStress * _stressMultiplierForSpeed(be.theoreticalSpeed);
    final stressApplied = be.calculateStressApplied();
    members[be] = stressApplied;

    _unloadedMembers--;
    if (_unloadedMembers < 0) _unloadedMembers = 0;
    if (_unloadedCapacity < 0) _unloadedCapacity = 0;
    if (_unloadedStress < 0) _unloadedStress = 0;
  }

  void add(KineticNode be) {
    if (members.containsKey(be)) return;
    if (be.isSource) sources[be] = be.calculateAddedStressCapacity();
    members[be] = be.calculateStressApplied();
    _updateFromNetwork(be);
    be.networkDirty = true;
  }

  void updateCapacityFor(KineticNode be, double capacity) {
    sources[be] = capacity;
    updateCapacity();
  }

  void updateStressFor(KineticNode be, double stress) {
    members[be] = stress;
    updateStress();
  }

  void remove(KineticNode be) {
    if (!members.containsKey(be)) return;
    if (be.isSource) sources.remove(be);
    members.remove(be);
    be.updateFromNetwork(0, 0, 0);

    if (members.isEmpty) {
      level.networks.remove(id);
      return;
    }

    members.keys.first.networkDirty = true;
  }

  void sync() {
    for (final be in members.keys.toList()) {
      _updateFromNetwork(be);
    }
  }

  void _updateFromNetwork(KineticNode be) => be.updateFromNetwork(_currentCapacity, _currentStress, size);

  void updateCapacity() {
    final newMaxStress = calculateCapacity();
    if (_currentCapacity != newMaxStress) {
      _currentCapacity = newMaxStress;
      sync();
    }
  }

  void updateStress() {
    final newStress = calculateStress();
    if (_currentStress != newStress) {
      _currentStress = newStress;
      sync();
    }
  }

  void updateNetwork() {
    final newStress = calculateStress();
    final newMaxStress = calculateCapacity();
    if (_currentStress != newStress || _currentCapacity != newMaxStress) {
      _currentStress = newStress;
      _currentCapacity = newMaxStress;
      sync();
    }
  }

  double calculateCapacity() {
    var presentCapacity = 0.0;
    for (final be in sources.keys.toList()) {
      if (!identical(level.nodeAt(be.kpos), be)) {
        sources.remove(be);
        continue;
      }
      presentCapacity += getActualCapacityOf(be);
    }
    return presentCapacity + _unloadedCapacity;
  }

  double calculateStress() {
    var presentStress = 0.0;
    for (final be in members.keys.toList()) {
      if (!identical(level.nodeAt(be.kpos), be)) {
        members.remove(be);
        continue;
      }
      presentStress += getActualStressOf(be);
    }
    return presentStress + _unloadedStress;
  }

  double getActualCapacityOf(KineticNode be) => sources[be]! * _stressMultiplierForSpeed(be.generatedSpeed);

  double getActualStressOf(KineticNode be) => members[be]! * _stressMultiplierForSpeed(be.theoreticalSpeed);

  static double _stressMultiplierForSpeed(double speed) => speed.abs();

  int get size => _unloadedMembers + members.length;
}
