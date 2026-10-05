// Redstone inputs and outputs of a computer (`RedstoneState` in CC: Tweaked).
//
// Programs write the *internal* outputs; the block entity that hosts the
// computer polls [updateOutput] once per tick, copies changes to the world
// and feeds neighbour levels back through [setInput].
import 'side.dart';

final class RedstoneState {
  final List<int> _internalOutput = List<int>.filled(6, 0);
  final List<int> _internalBundled = List<int>.filled(6, 0);
  final List<int> _externalOutput = List<int>.filled(6, 0);
  final List<int> _externalBundled = List<int>.filled(6, 0);
  final List<int> _input = List<int>.filled(6, 0);
  final List<int> _bundledInput = List<int>.filled(6, 0);
  bool _outputChanged = false;
  bool _inputChanged = false;

  int getInput(ComputerSide side) => _input[side.index];
  int getBundledInput(ComputerSide side) => _bundledInput[side.index];
  int getOutput(ComputerSide side) => _internalOutput[side.index];
  int getBundledOutput(ComputerSide side) => _internalBundled[side.index];

  void setOutput(ComputerSide side, int level) {
    if (_internalOutput[side.index] == level) return;
    _internalOutput[side.index] = level;
    _outputChanged = true;
  }

  void setBundledOutput(ComputerSide side, int mask) {
    if (_internalBundled[side.index] == mask) return;
    _internalBundled[side.index] = mask;
    _outputChanged = true;
  }

  /// Publishes the outputs set by programs. Returns a bit mask (bit `n` is
  /// side number `n`) of the sides whose output changed.
  int updateOutput() {
    if (!_outputChanged) return 0;
    var changed = 0;
    for (var i = 0; i < 6; i++) {
      if (_externalOutput[i] != _internalOutput[i]) {
        _externalOutput[i] = _internalOutput[i];
        changed |= 1 << i;
      }
      if (_externalBundled[i] != _internalBundled[i]) {
        _externalBundled[i] = _internalBundled[i];
        changed |= 1 << i;
      }
    }
    _outputChanged = false;
    return changed;
  }

  /// The output the world should see on [side].
  int getExternalOutput(ComputerSide side) => _externalOutput[side.index];

  int getExternalBundledOutput(ComputerSide side) => _externalBundled[side.index];

  /// Switches every output off (the computer shut down).
  void clearOutput() {
    _internalOutput.fillRange(0, 6, 0);
    _internalBundled.fillRange(0, 6, 0);
    _outputChanged = true;
  }

  /// Sets what the world feeds into [side]. Returns whether it changed.
  bool setInput(ComputerSide side, int level, int bundled) {
    var changed = false;
    if (_input[side.index] != level) {
      _input[side.index] = level;
      changed = true;
    }
    if (_bundledInput[side.index] != bundled) {
      _bundledInput[side.index] = bundled;
      changed = true;
    }
    _inputChanged |= changed;
    return changed;
  }

  /// Whether an input changed since the last call; the computer then gets a
  /// `redstone` event.
  bool pollInputChanged() {
    final changed = _inputChanged;
    _inputChanged = false;
    return changed;
  }
}
