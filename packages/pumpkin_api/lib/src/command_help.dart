// Binding-free building blocks of the command API: the command tree model,
// usage and help text, argument parsers, suggestion filtering and the cooldown
// tracker. Nothing here imports the WIT bindings, so it runs (and is tested)
// on the Dart VM.

/// Thrown from a command handler to tell the sender the command failed. The
/// [message] is shown to the sender.
///
/// ```dart
/// if (home == null) throw CommandException('You have no home called $name.');
/// ```
class CommandException implements Exception {
  /// The text shown to the sender.
  final String message;

  CommandException(this.message);

  @override
  String toString() => 'CommandException: $message';
}

/// A [CommandException] that tells the sender how the command is used.
///
/// Thrown by `CommandContext.failUsage`. The message reads
/// `Usage: /home [name]`, with one line per way to run the command.
final class UsageException extends CommandException {
  /// The usage lines, like `/warp set <name>`.
  final List<String> usage;

  /// What was wrong, or `null` for a plain usage reminder.
  final String? problem;

  UsageException(this.usage, [this.problem])
    : super(_format(usage, problem));

  static String _format(List<String> usage, String? problem) {
    final buffer = StringBuffer();
    if (problem != null) buffer.writeln(problem);
    if (usage.length == 1) {
      buffer.write('Usage: ${usage.single}');
    } else {
      buffer.write('Usage:');
      for (final line in usage) {
        buffer.write('\n  $line');
      }
    }
    return buffer.toString();
  }
}

/// How a node of a command tree is matched.
enum SpecKind {
  /// The command name itself (the root of the tree).
  root,

  /// A fixed word, a subcommand.
  literal,

  /// A value the sender types.
  argument,
}

/// One node of a command tree, as plain data. The builder fills these in, then
/// turns them into host `Command`/`CommandNode`s; usage and help text are
/// generated from them.
final class SpecNode {
  /// The command name, subcommand word or argument key.
  final String name;

  final SpecKind kind;

  /// Shown instead of [name] in `<...>`/`[...]` for arguments, e.g.
  /// `red|green|blue` for a choice.
  final String? label;

  /// Whether the argument may be left out when the parent can run by itself.
  final bool optional;

  /// What this command, subcommand or argument is for.
  String? description;

  /// Other words that match this node (commands and subcommands).
  List<String> aliases;

  /// The permission node the sender needs for this node, if any.
  String? permission;

  /// Whether running the command with this node last does something.
  bool runnable = false;

  final List<SpecNode> children = [];

  /// The node this one hangs off, `null` for the root.
  SpecNode? parent;

  SpecNode(
    this.name,
    this.kind, {
    this.label,
    this.optional = false,
    this.description,
    this.aliases = const [],
    this.permission,
  });

  /// `<name>`, `[name]`, the literal word, or `/name` for the root.
  String get token => switch (kind) {
    SpecKind.root => '/$name',
    SpecKind.literal => name,
    SpecKind.argument => optional ? '[${label ?? name}]' : '<${label ?? name}>',
  };

  /// Adds [child] under this node.
  void add(SpecNode child) {
    child.parent = this;
    children.add(child);
  }

  /// The nodes from the root down to this one.
  List<SpecNode> get trail {
    final nodes = <SpecNode>[];
    for (SpecNode? node = this; node != null; node = node.parent) {
      nodes.add(node);
    }
    return nodes.reversed.toList();
  }
}

/// One way to run a command: its usage line, what it does and what the sender
/// needs.
final class CommandPath {
  /// Like `/warp set <name>`.
  final String usage;

  /// The description of the last command or subcommand on the path.
  final String? description;

  /// Permission nodes the sender needs along the path.
  final List<String> permissions;

  const CommandPath(this.usage, this.description, this.permissions);

  @override
  String toString() => usage;
}

/// Lists every way to run the tree under [root]. An optional argument folds
/// into its parent's line: `/home [name]`, not `/home` and `/home <name>`.
///
/// With [from], only the paths through that node are returned (a node that is
/// an optional argument stands for its parent).
List<CommandPath> commandPaths(SpecNode root, {SpecNode? from}) {
  var start = root;
  if (from != null) {
    start = from.optional && from.parent != null ? from.parent! : from;
  }
  final paths = <CommandPath>[];
  void walk(SpecNode node) {
    final folded = node.children.any((c) => c.optional && c.runnable);
    if (node.runnable && !folded) paths.add(_pathOf(node));
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(start);
  return paths;
}

CommandPath _pathOf(SpecNode node) {
  final trail = node.trail;
  String? description;
  final permissions = <String>[];
  for (final step in trail) {
    // The last command or subcommand on the path describes the line.
    // Arguments don't.
    if (step.kind != SpecKind.argument) description = step.description;
    if (step.permission != null) permissions.add(step.permission!);
  }
  final tokens = [for (final step in trail) step.token];
  return CommandPath(tokens.join(' '), description, permissions);
}

/// The usage lines of [root], one per way to run it.
List<String> usageLines(SpecNode root, {SpecNode? from}) => [
  for (final path in commandPaths(root, from: from)) path.usage,
];

/// Everything the plugin registered through the command builder, for help
/// listings.
final class CommandRegistry {
  final List<SpecNode> _roots = [];

  /// The registered command trees, in registration order.
  List<SpecNode> get roots => List.unmodifiable(_roots);

  /// Records [root] (replacing a command with the same name).
  void add(SpecNode root) {
    _roots.removeWhere((r) => r.name == root.name);
    _roots.add(root);
  }

  /// The tree of the command called [nameOrAlias], if there is one.
  SpecNode? find(String nameOrAlias) {
    final wanted = nameOrAlias.startsWith('/')
        ? nameOrAlias.substring(1)
        : nameOrAlias;
    for (final root in _roots) {
      if (root.name == wanted || root.aliases.contains(wanted)) return root;
    }
    return null;
  }

  /// Forgets everything.
  void clear() => _roots.clear();
}

/// The help listing: one `usage - description` line per way to run each
/// registered command, sorted by command name.
///
/// [command] limits it to one command. [canUse] decides whether the sender
/// may see a line, given the permission nodes along its path.
List<String> helpLines(
  CommandRegistry registry, {
  String? command,
  bool Function(List<String> permissions)? canUse,
  Set<String> hidden = const {},
}) {
  final roots = [
    for (final root in registry.roots)
      if (!hidden.contains(root.name) &&
          (command == null || registry.find(command) == root))
        root,
  ]..sort((a, b) => a.name.compareTo(b.name));
  final lines = <String>[];
  for (final root in roots) {
    for (final path in commandPaths(root)) {
      if (canUse != null && !canUse(path.permissions)) continue;
      final description = path.description;
      lines.add(
        description == null || description.isEmpty
            ? path.usage
            : '${path.usage} - $description',
      );
    }
  }
  return lines;
}

/// The suggestions from [options] that start with what is already [typed],
/// ignoring case, sorted and without duplicates.
List<String> filterSuggestions(Iterable<String> options, String typed) {
  final lower = typed.toLowerCase();
  final seen = <String>{};
  final matches = [
    for (final option in options)
      if (option.toLowerCase().startsWith(lower) && seen.add(option)) option,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return matches;
}

/// Checks [raw] against [choices] ignoring case and returns the choice as it
/// was written in [choices].
///
/// Throws a [CommandException] listing the options when there is no match.
String matchChoice(String raw, List<String> choices) {
  final lower = raw.toLowerCase();
  for (final choice in choices) {
    if (choice.toLowerCase() == lower) return choice;
  }
  throw CommandException(
    'Unknown option "$raw". Choose one of: ${choices.join(', ')}.',
  );
}

/// Parses durations like `10s`, `5m`, `1h30m`, `2d`, `1w`, `250ms`, case
/// insensitive. A bare number is read as seconds. Returns `null` when [text]
/// isn't a duration.
///
/// ```dart
/// parseDuration('1h30m'); // Duration(hours: 1, minutes: 30)
/// parseDuration('45');    // Duration(seconds: 45)
/// ```
Duration? parseDuration(String text) {
  final input = text.trim().toLowerCase();
  if (input.isEmpty) return null;
  final bare = int.tryParse(input);
  if (bare != null) return bare < 0 ? null : Duration(seconds: bare);

  var total = Duration.zero;
  var index = 0;
  var any = false;
  while (index < input.length) {
    var digitsEnd = index;
    while (digitsEnd < input.length && _isDigit(input.codeUnitAt(digitsEnd))) {
      digitsEnd++;
    }
    if (digitsEnd == index) return null;
    final amount = int.parse(input.substring(index, digitsEnd));
    var unitEnd = digitsEnd;
    while (unitEnd < input.length && !_isDigit(input.codeUnitAt(unitEnd))) {
      unitEnd++;
    }
    final unit = switch (input.substring(digitsEnd, unitEnd)) {
      'ms' => Duration(milliseconds: amount),
      's' || 'sec' || 'secs' => Duration(seconds: amount),
      'm' || 'min' || 'mins' => Duration(minutes: amount),
      'h' || 'hr' || 'hrs' => Duration(hours: amount),
      'd' => Duration(days: amount),
      'w' => Duration(days: amount * 7),
      _ => null,
    };
    if (unit == null) return null;
    total += unit;
    any = true;
    index = unitEnd;
  }
  return any ? total : null;
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// Like [parseDuration], but throws a [CommandException] that explains the
/// format.
Duration parseDurationOrThrow(String text) =>
    parseDuration(text) ??
    (throw CommandException(
      '"$text" is not a duration. Use something like 30s, 5m, 1h or 1h30m.',
    ));

/// Formats [duration] for people: `1h 30m`, `45s`, `1.5s`. Rounds up to the
/// next 100 milliseconds below ten seconds, to whole seconds above, so a
/// "wait" message never says `0s`.
String formatDuration(Duration duration) {
  if (duration <= Duration.zero) return '0s';
  if (duration < const Duration(seconds: 10)) {
    final tenths = (duration.inMilliseconds + 99) ~/ 100;
    final whole = tenths ~/ 10;
    final fraction = tenths % 10;
    return fraction == 0 ? '${whole}s' : '$whole.${fraction}s';
  }
  var seconds = (duration.inMilliseconds + 999) ~/ 1000;
  final parts = <String>[];
  for (final (unit, size) in const [
    ('d', 86400),
    ('h', 3600),
    ('m', 60),
    ('s', 1),
  ]) {
    final count = seconds ~/ size;
    seconds -= count * size;
    if (count > 0) parts.add('$count$unit');
  }
  return parts.join(' ');
}

/// Remembers when each key last used something, to rate limit commands.
///
/// Pure and clock-injectable: pass [now] in tests.
///
/// ```dart
/// final tracker = CooldownTracker();
/// final wait = tracker.remaining('Steve', const Duration(seconds: 30));
/// if (wait != null) throw CommandException('Wait ${formatDuration(wait)}');
/// tracker.mark('Steve');
/// ```
final class CooldownTracker {
  final DateTime Function() _now;
  final Map<String, DateTime> _last = {};

  CooldownTracker({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// How long [key] still has to wait for [cooldown], or `null` if it can go
  /// ahead.
  Duration? remaining(String key, Duration cooldown) {
    final last = _last[key];
    if (last == null) return null;
    final left = last.add(cooldown).difference(_now());
    return left > Duration.zero ? left : null;
  }

  /// Records that [key] just used it.
  void mark(String key) => _last[key] = _now();

  /// Forgets [key], e.g. because the attempt failed.
  void clear(String key) => _last.remove(key);

  /// Forgets every key.
  void reset() => _last.clear();
}
