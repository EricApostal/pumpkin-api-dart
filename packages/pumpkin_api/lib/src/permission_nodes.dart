import 'package:wasm_components/wasm_components.dart' show OkResult, ErrorResult;

import 'bindings.g.dart';
import 'logger.dart';

/// Who has a permission when nobody set it explicitly.
final class PermissionDefaultKind {
  final PermissionLevel? _opLevel;
  final bool _allow;

  const PermissionDefaultKind._(this._allow, this._opLevel);

  /// Everybody.
  static const allow = PermissionDefaultKind._(true, null);

  /// Nobody.
  static const deny = PermissionDefaultKind._(false, null);

  /// Operators of at least [level] (default: owner level 4).
  const PermissionDefaultKind.op([PermissionLevel level = PermissionLevel.four])
    : _allow = false,
      _opLevel = level;

  /// The generated equivalent.
  PermissionDefault toWit() {
    final level = _opLevel;
    if (level != null) return PermissionDefaultOp(level);
    return _allow ? const PermissionDefaultAllow() : const PermissionDefaultDeny();
  }
}

/// A permission node a plugin defines, such as `teleport:command.home`.
///
/// ```dart
/// const home = PermissionNode('teleport:command.home',
///     description: 'Use /home', defaultValue: PermissionDefaultKind.allow);
///
/// context.registerPermissions([home]);
/// if (player.can(home)) { ... }
/// ```
final class PermissionNode {
  final String node;
  final String description;

  /// Who has it by default. (Named `defaultValue` since `default` is a
  /// keyword.)
  final PermissionDefaultKind defaultValue;

  /// Nodes this one grants or revokes along with itself, e.g. a parent
  /// `teleport:*` with children set to true.
  final List<PermissionChild> children;

  const PermissionNode(
    this.node, {
    this.description = '',
    this.defaultValue = const PermissionDefaultKind.op(),
    this.children = const [],
  });

  /// The generated record to register.
  Permission toWit() => Permission(
    node: node,
    description: description,
    default_: defaultValue.toWit(),
    children: children,
  );

  @override
  String toString() => node;
}

/// Registering permission nodes.
extension PermissionNodesApi on Context {
  /// Registers [nodes] with the server and returns how many were new.
  /// Nodes that are already registered (for example after a reload) are
  /// skipped; other failures are logged as warnings.
  int registerPermissions(Iterable<PermissionNode> nodes) {
    var registered = 0;
    for (final node in nodes) {
      switch (registerPermission(permission: node.toWit())) {
        case OkResult():
          registered++;
        case ErrorResult(value: final message):
          if (message.toLowerCase().contains('already')) {
            Logger('permissions').debug('${node.node} is already registered');
          } else {
            Logger('permissions').warn('Cannot register ${node.node}: $message');
          }
      }
    }
    return registered;
  }
}

/// Permission checks with typed nodes.
extension PlayerPermissionCheck on Player {
  /// Whether this player has [node] (explicit setting, else its default).
  bool can(PermissionNode node) => hasPermission(node: node.node);
}

/// Permission checks for command senders (players and the console).
extension SenderPermissionCheck on CommandSender {
  /// Whether this sender has [node]. Needs the [server] the command runs on.
  bool can(Server server, PermissionNode node) =>
      hasPermission(server: server, node: node.node);
}
