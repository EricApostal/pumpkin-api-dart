// The throttle lever's state, kept apart from the block entity so it runs on the
// VM in tests.
//
// The lever is a redstone source whose strength is a number the player drags
// between 0 and 15. `inverted` flips which end of the track means "full".
//
// Pure: no host imports.
//
// Java: dev.simulated_team.simulated.content.blocks.throttle_lever.ThrottleLeverBlockEntity
final class ThrottleLeverLogic {
  /// The redstone signal, 0 to 15.
  int state = 0;

  /// Ticks left before the neighbours are updated again.
  int lastChange = 0;

  /// Whether the lever's direction is inverted.
  bool inverted = false;

  /// The lever value in `[0, 1]`.
  double get throttle => state / 15;

  /// The value with [inverted] applied, 0 to 15.
  int get outputSignal => inverted ? 15 - state : state;

  /// `changeState(back)`: nudge the lever by one step.
  ///
  /// Returns true when the value changed (and so the neighbours need an update
  /// once [lastChange] runs out).
  bool changeState({bool back = false}) {
    final previous = state;
    state = (state + (back ? -1 : 1)).clamp(0, 15);
    if (previous != state) {
      lastChange = 15;
      return true;
    }
    return false;
  }

  /// `setSignal(signal)`: set the lever from a client drag.
  void setSignal(int signal, {bool playSound = true}) {
    final clamped = signal.clamp(0, 15);
    state = inverted ? 15 - clamped : clamped;
    lastChange = 2;
  }

  /// `tick()`: run down the neighbour-update timer.
  ///
  /// Returns true when the timer reached zero this tick and the neighbours must
  /// be updated.
  bool tick() {
    if (lastChange <= 0) return false;
    lastChange--;
    return lastChange == 0;
  }

  /// `read`.
  void read(int state, int lastChange, {required bool inverted}) {
    this.state = state.clamp(0, 15);
    this.lastChange = lastChange;
    this.inverted = inverted;
  }

  /// `write`.
  Map<String, Object?> write() => {'State': state, 'ChangeTimer': lastChange};

  /// The comparator output (`getSignal`): the raw state, not the inverted one.
  int get comparatorOutput => state;
}
