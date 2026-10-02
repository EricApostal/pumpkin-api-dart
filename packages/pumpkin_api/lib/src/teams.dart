import 'bindings.g.dart';

TextComponent _teamText(Object text) => switch (text) {
  String() => TextComponent.text(plain: text),
  TextComponent() => text,
  _ => throw ArgumentError.value(text, 'text', 'Expected a String or TextComponent'),
};

/// Builds [TeamSettings] with sensible defaults (friendly fire on, white,
/// nametags and collisions always, empty display name, prefix and suffix).
///
/// Texts can be a [String] or a [TextComponent]; a component can only be used
/// by one [build].
///
/// ```dart
/// final settings = (TeamSettingsBuilder()
///   ..displayName = 'Red Team'
///   ..color = NamedColor.red
///   ..friendlyFire = false).build();
/// ```
final class TeamSettingsBuilder {
  /// Display name, a [String] or [TextComponent]; empty if `null`.
  Object? displayName;

  /// Whether members can hurt each other.
  bool friendlyFire = true;

  /// Whether members see invisible teammates.
  bool seeFriendlyInvisibles = false;

  /// Who can see the nametags of members.
  NametagVisibility nametagVisibility = NametagVisibility.always;

  /// How members collide with others.
  CollisionRule collisionRule = CollisionRule.always;

  /// Team color, also used for glowing.
  NamedColor color = NamedColor.white;

  /// Text shown before member names, a [String] or [TextComponent].
  Object? prefix;

  /// Text shown after member names, a [String] or [TextComponent].
  Object? suffix;

  /// Creates [TeamSettings] from the current values.
  TeamSettings build() => TeamSettings(
    displayName: _teamText(displayName ?? ''),
    friendlyFire: friendlyFire,
    seeFriendlyInvisibles: seeFriendlyInvisibles,
    nametagVisibility: nametagVisibility,
    collisionRule: collisionRule,
    color: color,
    prefix: _teamText(prefix ?? ''),
    suffix: _teamText(suffix ?? ''),
  );
}

/// A handle to a team of a [Scoreboard]. It stores only the team's name, so
/// it can be kept around, but it uses [scoreboard] for every call: the
/// scoreboard object must still be valid (or kept with `keep()`).
final class ScoreboardTeam {
  /// The scoreboard the team belongs to.
  final Scoreboard scoreboard;

  /// The team's internal name.
  final String name;

  /// Refers to the team [name] of [scoreboard], which may not exist yet.
  ScoreboardTeam(this.scoreboard, this.name);

  /// The current settings, or `null` if the team doesn't exist.
  TeamSettings? get settings {
    final value = scoreboard.getTeam(name: name);
    return value.hasValue ? value.requireValue() : null;
  }

  /// Replaces the team's settings. The [settings] are consumed.
  void update(TeamSettings settings) => scoreboard.updateTeam(name: name, settings: settings);

  void _change(TeamSettings Function(TeamSettings settings) change) {
    final current = settings;
    if (current != null) update(change(current));
  }

  /// Whether the team exists on the scoreboard.
  bool get exists => scoreboard.getTeam(name: name).hasValue;

  /// The display name, or `null` if the team doesn't exist.
  TextComponent? get displayName => settings?.displayName;

  /// Sets the display name ([String] or [TextComponent]).
  void setDisplayName(Object text) =>
      _change((s) => s.copyWith(displayName: _teamText(text)));

  /// The prefix, or `null` if the team doesn't exist.
  TextComponent? get prefix => settings?.prefix;

  /// Sets the prefix ([String] or [TextComponent]).
  void setPrefix(Object text) => _change((s) => s.copyWith(prefix: _teamText(text)));

  /// The suffix, or `null` if the team doesn't exist.
  TextComponent? get suffix => settings?.suffix;

  /// Sets the suffix ([String] or [TextComponent]).
  void setSuffix(Object text) => _change((s) => s.copyWith(suffix: _teamText(text)));

  /// The team color, or `null` if the team doesn't exist.
  NamedColor? get color => settings?.color;
  set color(NamedColor? value) {
    if (value != null) _change((s) => s.copyWith(color: value));
  }

  /// Whether members can hurt each other (`true` if the team doesn't exist).
  bool get friendlyFire => settings?.friendlyFire ?? true;
  set friendlyFire(bool value) => _change((s) => s.copyWith(friendlyFire: value));

  /// Whether members see invisible teammates.
  bool get seeFriendlyInvisibles => settings?.seeFriendlyInvisibles ?? false;
  set seeFriendlyInvisibles(bool value) =>
      _change((s) => s.copyWith(seeFriendlyInvisibles: value));

  /// Who can see the nametags of members, `null` if the team doesn't exist.
  NametagVisibility? get nametagVisibility => settings?.nametagVisibility;
  set nametagVisibility(NametagVisibility? value) {
    if (value != null) _change((s) => s.copyWith(nametagVisibility: value));
  }

  /// How members collide with others, `null` if the team doesn't exist.
  CollisionRule? get collisionRule => settings?.collisionRule;
  set collisionRule(CollisionRule? value) {
    if (value != null) _change((s) => s.copyWith(collisionRule: value));
  }

  /// The names of the players and entities in the team.
  List<String> get members => scoreboard.getTeamPlayers(teamName: name);

  /// Adds a player or entity by name.
  void add(String member) => scoreboard.addPlayerToTeam(teamName: name, playerName: member);

  /// Removes a player or entity by name.
  void remove(String member) =>
      scoreboard.removePlayerFromTeam(teamName: name, playerName: member);

  /// Whether [member] is in the team.
  bool contains(String member) => members.contains(member);

  /// Removes everybody from the team.
  void clear() => scoreboard.clearTeamPlayers(teamName: name);

  /// Deletes the team from the scoreboard.
  void unregister() => scoreboard.removeTeam(name: name);
}

extension ScoreboardTeams on Scoreboard {
  /// Creates a team and returns a handle to it. [settings] can be built with
  /// [TeamSettingsBuilder]; it is consumed.
  ScoreboardTeam registerTeam(String name, TeamSettings settings) {
    createTeam(name: name, settings: settings);
    return ScoreboardTeam(this, name);
  }

  /// The team [name], or `null` if there is none.
  ScoreboardTeam? findTeam(String name) =>
      getTeam(name: name).hasValue ? ScoreboardTeam(this, name) : null;

  /// All teams of the scoreboard.
  List<ScoreboardTeam> get allTeams => [
    for (final name in getTeams()) ScoreboardTeam(this, name),
  ];

  /// The team that the player or entity [member] belongs to, if any.
  ScoreboardTeam? teamOf(String member) {
    final name = getPlayerTeam(playerName: member);
    return name.hasValue ? ScoreboardTeam(this, name.requireValue()) : null;
  }
}

extension PlayerTeams on Player {
  /// The name of the team this player is on, or `null`.
  String? get teamName {
    final name = getTeam();
    return name.hasValue ? name.requireValue() : null;
  }
}
