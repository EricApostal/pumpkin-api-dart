// The seam between Simulated's blocks and a computer mod.
//
// Java keeps its compat in `compat/computercraft` and implements CC: Tweaked's
// `IPeripheral`, so `simulated` depends on CC there. The port inverts that: this
// file declares the shape a computer sees (the same shape as `IPeripheral`) and
// the peripherals of `compat/computercraft` are written against it. `simulated`
// therefore never imports `cc_tweaked` and stays usable without CC installed;
// `cc_tweaked` holds the thin adapter (`lib/src/compat/simulated_peripherals.dart`)
// that turns a [SimPeripheral] into one of its own `Peripheral`s.
//
// Pure: no host imports.
//
// Java: dan200.computercraft.api.peripheral.IPeripheral / IComputerAccess,
//       dev.simulated_team.simulated.compat.computercraft.peripherals.SimPeripheral:10-30

/// How a peripheral reaches the computer it is attached to (`IComputerAccess`).
abstract interface class SimComputerAccess {
  /// `getID`.
  int get computerId;

  /// `getAttachmentName`: the side the computer knows the peripheral by.
  String get attachmentName;

  /// `queueEvent`: wakes the computer's `os.pullEvent` with [name].
  void queueEvent(String name, List<Object?> args);
}

/// What a computer sees of a peripheral (`IPeripheral`).
abstract interface class SimPeripheral {
  /// `getType`: the name `peripheral.getType` returns.
  String get type;

  /// `getAdditionalTypes`: the names `peripheral.hasType` also accepts.
  Set<String> get additionalTypes;

  /// The names programs may call, as `@LuaFunction` exposes them.
  List<String> get methodNames;

  /// Calls [method]. Throws [SimPeripheralException] to fail the Lua call.
  List<Object?> call(SimComputerAccess computer, String method, List<Object?> args);

  /// `attach`.
  void attach(SimComputerAccess computer);

  /// `detach`.
  void detach(SimComputerAccess computer);

  /// `equals(IPeripheral)`: whether [other] is this very peripheral, so a
  /// computer must not treat a replacement as the same device.
  bool sameAs(SimPeripheral other);
}

/// A Lua error raised by a peripheral method; the adapter turns it into the
/// computer mod's own error type.
final class SimPeripheralException implements Exception {
  final String message;

  const SimPeripheralException(this.message);

  @override
  String toString() => message;
}

/// A method of a peripheral: `(computer, args) -> Lua values`.
typedef SimLuaMethod = List<Object?> Function(SimComputerAccess computer, List<Object?> args);

/// `SimPeripheral<T extends BlockEntity>`: the base of the peripherals of this
/// package, over the block entity (or the source interface standing in for it)
/// that provides their state.
///
/// Java collects the methods with `@LuaFunction` reflection; the port registers
/// them with [method] in the constructor, keeping the Java name, arity and
/// return value of each.
abstract class SimBlockPeripheral<T> implements SimPeripheral {
  final T blockEntity;

  final Map<String, SimLuaMethod> _methods = {};

  SimBlockPeripheral(this.blockEntity);

  /// Registers the method [name].
  void method(String name, SimLuaMethod body) => _methods[name] = body;

  @override
  Set<String> get additionalTypes => const {};

  @override
  List<String> get methodNames => List.unmodifiable(_methods.keys);

  @override
  List<Object?> call(SimComputerAccess computer, String method, List<Object?> args) {
    final body = _methods[method];
    if (body == null) throw SimPeripheralException('No such method $method');
    return body(computer, args);
  }

  @override
  void attach(SimComputerAccess computer) {}

  @override
  void detach(SimComputerAccess computer) {}

  /// `SimPeripheral.equals`: `iPeripheral == this`, so a new peripheral for the
  /// same block entity is a different device and CC re-attaches it.
  @override
  bool sameAs(SimPeripheral other) => identical(this, other);

  /// `SimPeripheral.vecList`: a vector as Lua sees it, `{x, y, z}`.
  static List<double> vecList(double x, double y, double z) => [x, y, z];
}

/// The Lua type name of [value], for the argument errors of [simNumberArg] and
/// friends.
String simLuaType(Object? value) => switch (value) {
  null => 'nil',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  List() => 'table',
  Map() => 'table',
  _ => 'userdata',
};

/// The [index]th argument as a number, or an error like the one CC's
/// `@LuaFunction` produces for a `double` parameter.
double simNumberArg(List<Object?> args, int index, String method) {
  final value = index < args.length ? args[index] : null;
  if (value is num) return value.toDouble();
  throw SimPeripheralException(
    'bad argument #${index + 1} to \'$method\' (number expected, got ${simLuaType(value)})',
  );
}

/// The [index]th argument as an `int`, or an error like the one CC's
/// `@LuaFunction` produces for an `int` parameter (a fractional number is not
/// one).
int simIntArg(List<Object?> args, int index, String method) {
  final value = simNumberArg(args, index, method);
  if (value != value.truncateToDouble()) {
    throw SimPeripheralException(
      'bad argument #${index + 1} to \'$method\' (number has no integer representation)',
    );
  }
  return value.toInt();
}

/// The [index]th argument as a string, or an error like the one CC's
/// `@LuaFunction` produces for a `String` parameter.
String simStringArg(List<Object?> args, int index, String method) {
  final value = index < args.length ? args[index] : null;
  if (value is String) return value;
  throw SimPeripheralException(
    'bad argument #${index + 1} to \'$method\' (string expected, got ${simLuaType(value)})',
  );
}

/// Degrees of [radians], the `Math.toDegrees` of the Java peripherals.
double simDegrees(double radians) => radians * 180.0 / 3.141592653589793;

/// Radians of [degrees], the `Math.toRadians` of the Java peripherals.
double simRadians(double degrees) => degrees * 3.141592653589793 / 180.0;
