// What a computer sees of a peripheral (`IPeripheral` in CC: Tweaked).
//
// A peripheral is attached to the computer's sides by whoever hosts the
// computer: a block entity next to it, or a command. Methods take and return
// Lua values; they run on the server tick, so they never need to wait.
import '../lua/lua.dart';

/// How a peripheral reaches the computer it is attached to
/// (`IComputerAccess`).
abstract interface class PeripheralAccess {
  int get computerId;

  /// The name the computer knows the peripheral by (its side).
  String get attachmentName;

  void queueEvent(String name, List<Object?> args);
}

abstract interface class Peripheral {
  /// The main type, returned by `peripheral.getType`.
  String get type;

  /// Further types, tested by `peripheral.hasType`.
  Set<String> get additionalTypes;

  /// The names of the methods programs may call.
  List<String> get methodNames;

  /// Calls the method [method] for [computer]. Throws [LuaError] to fail.
  List<Object?> call(PeripheralAccess computer, String method, List<Object?> args);

  /// The peripheral was attached to [computer]'s side.
  void attach(PeripheralAccess computer);

  /// The peripheral was removed from [computer].
  void detach(PeripheralAccess computer);

  /// Whether [other] is the same device (so replacing it is not a change).
  bool sameAs(Peripheral other);
}

/// A peripheral made of named Lua-callable methods; the base of the
/// peripherals in this package.
abstract class MethodPeripheral implements Peripheral {
  final Map<String, List<Object?> Function(PeripheralAccess, List<Object?>)> _methods = {};

  /// Registers the method [name].
  void method(String name, List<Object?> Function(PeripheralAccess computer, List<Object?> args) body) {
    _methods[name] = body;
  }

  @override
  Set<String> get additionalTypes => const {};

  @override
  List<String> get methodNames => _methods.keys.toList();

  @override
  List<Object?> call(PeripheralAccess computer, String method, List<Object?> args) {
    final body = _methods[method];
    if (body == null) throw LuaError.message('No such method $method');
    return body(computer, args);
  }

  @override
  void attach(PeripheralAccess computer) {}

  @override
  void detach(PeripheralAccess computer) {}

  @override
  bool sameAs(Peripheral other) => identical(this, other);
}
