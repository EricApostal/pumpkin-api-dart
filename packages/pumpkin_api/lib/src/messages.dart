import 'bindings.g.dart' hide Text;
import 'files.dart';
import 'message_format.dart';

export 'message_format.dart';

/// A chat message under construction: styled text that can have children,
/// click and hover actions. Build it with a chain, send it with `send`:
///
/// ```dart
/// player.send(Text('Welcome, ').gold() + Text(name).yellow().bold());
/// sender.send(Text('[Click]').green().runCommand('/home').hover('Go home'));
/// ```
///
/// A [Text] is plain Dart data and can be reused and sent many times: every
/// send builds a fresh host `TextComponent` (those are consumed when sent).
/// Style methods change this object and return it for chaining.
final class Text {
  final String _content;
  final bool _legacy;
  final List<Text> _children = [];

  NamedColor? _color;
  RgbColor? _rgb;
  bool _rainbow = false;
  bool? _bold, _italic, _underlined, _strikethrough, _obfuscated;
  String? _insertion;
  String? _clickKind;
  String? _clickValue;
  Text? _hover;

  /// Plain text, shown exactly as written (no color code processing).
  Text(String plain) : _content = plain, _legacy = false;

  /// Text with legacy color codes: `&a` and `§a` both work, for example
  /// `Text.legacy('&aGreen &lbold')`.
  Text.legacy(String legacy) : _content = MessageFormat.colorize(legacy), _legacy = true;

  /// An empty text, useful as the root of [add]ed parts.
  Text.empty() : _content = '', _legacy = false;

  /// All [parts] one after another, with [separator] between them.
  factory Text.join(Iterable<Object> parts, {Object separator = ''}) {
    final result = Text.empty();
    var first = true;
    for (final part in parts) {
      if (!first) result.add(separator);
      first = false;
      result.add(part);
    }
    return result;
  }

  static Text _of(Object o) => switch (o) {
    Text() => o,
    String() => Text.legacy(o),
    _ => throw ArgumentError.value(o, 'part', 'Expected a String or Text'),
  };

  /// Appends [part] (a [Text], or a `String` with legacy codes) and returns
  /// this text. The child inherits this text's style.
  Text add(Object part) {
    _children.add(_of(part));
    return this;
  }

  /// A new text with this followed by [other] (a [Text] or a `String` with
  /// legacy codes). Neither operand is changed.
  Text operator +(Object other) => Text.empty().add(this).add(other);

  /// Sets a named color.
  Text color(NamedColor color) {
    _color = color;
    _rgb = null;
    return this;
  }

  /// Sets an RGB color.
  Text rgb(int r, int g, int b) {
    _rgb = RgbColor(r: r, g: g, b: b);
    _color = null;
    return this;
  }

  /// Rainbow colors.
  Text rainbow() {
    _rainbow = true;
    return this;
  }

  /// Black text.
  Text black() => color(NamedColor.black);

  /// Dark blue text.
  Text darkBlue() => color(NamedColor.darkBlue);

  /// Dark green text.
  Text darkGreen() => color(NamedColor.darkGreen);

  /// Dark aqua text.
  Text darkAqua() => color(NamedColor.darkAqua);

  /// Dark red text.
  Text darkRed() => color(NamedColor.darkRed);

  /// Dark purple text.
  Text darkPurple() => color(NamedColor.darkPurple);

  /// Gold (orange) text.
  Text gold() => color(NamedColor.gold);

  /// Gray text.
  Text gray() => color(NamedColor.gray);

  /// Dark gray text.
  Text darkGray() => color(NamedColor.darkGray);

  /// Blue text.
  Text blue() => color(NamedColor.blue);

  /// Green text.
  Text green() => color(NamedColor.green);

  /// Aqua (cyan) text.
  Text aqua() => color(NamedColor.aqua);

  /// Red text.
  Text red() => color(NamedColor.red);

  /// Light purple (pink) text.
  Text lightPurple() => color(NamedColor.lightPurple);

  /// Yellow text.
  Text yellow() => color(NamedColor.yellow);

  /// White text.
  Text white() => color(NamedColor.white);

  /// Bold on (or off with `false`).
  Text bold([bool value = true]) {
    _bold = value;
    return this;
  }

  /// Italic on (or off).
  Text italic([bool value = true]) {
    _italic = value;
    return this;
  }

  /// Underline on (or off).
  Text underlined([bool value = true]) {
    _underlined = value;
    return this;
  }

  /// Strikethrough on (or off).
  Text strikethrough([bool value = true]) {
    _strikethrough = value;
    return this;
  }

  /// Obfuscated ("magic") on (or off).
  Text obfuscated([bool value = true]) {
    _obfuscated = value;
    return this;
  }

  /// Text inserted into the chat box when the player shift-clicks this.
  Text insertion(String text) {
    _insertion = text;
    return this;
  }

  /// Runs [command] (with the leading `/`) when clicked.
  Text runCommand(String command) => _click('run', command);

  /// Puts [command] into the chat box when clicked.
  Text suggestCommand(String command) => _click('suggest', command);

  /// Opens [url] when clicked.
  Text openUrl(String url) => _click('url', url);

  /// Copies [text] to the clipboard when clicked.
  Text copyToClipboard(String text) => _click('copy', text);

  Text _click(String kind, String value) {
    _clickKind = kind;
    _clickValue = value;
    return this;
  }

  /// Shows [text] (a [Text] or a legacy `String`) when hovered.
  Text hover(Object text) {
    _hover = _of(text);
    return this;
  }

  /// Builds a fresh host component. It is consumed when passed to the host,
  /// so call this once per use (or use [Messages.component] / `send`).
  TextComponent build() {
    final c = _legacy
        ? TextComponent.fromLegacyString(input: _content)
        : TextComponent.text(plain: _content);
    final color = _color;
    if (color != null) c.colorNamed(color: color);
    final rgb = _rgb;
    if (rgb != null) c.colorRgb(color: rgb);
    if (_rainbow) c.rainbow();
    final b = _bold, i = _italic, u = _underlined, s = _strikethrough, o = _obfuscated;
    if (b != null) c.bold(value: b);
    if (i != null) c.italic(value: i);
    if (u != null) c.underlined(value: u);
    if (s != null) c.strikethrough(value: s);
    if (o != null) c.obfuscated(value: o);
    final insertion = _insertion;
    if (insertion != null) c.insertion(text: insertion);
    final value = _clickValue;
    if (value != null) {
      switch (_clickKind) {
        case 'run':
          c.clickRunCommand(command: value);
        case 'suggest':
          c.clickSuggestCommand(command: value);
        case 'url':
          c.clickOpenUrl(url: value);
        case 'copy':
          c.clickCopyToClipboard(text: value);
      }
    }
    final hover = _hover;
    if (hover != null) c.hoverShowText(text: hover.build());
    for (final child in _children) {
      c.addChild(child: child.build());
    }
    return c;
  }

  @override
  String toString() => '$_content${_children.join()}';
}

/// Conversions for the things plugins send as messages.
abstract final class Messages {
  /// Turns a message into a host component, consuming nothing of yours except
  /// a [TextComponent] you pass in (it is handed over as is).
  ///
  /// [message] can be a `String` with `&`/`§` color codes, a [Text], or a
  /// ready [TextComponent].
  static TextComponent component(Object message) => switch (message) {
    String() => TextComponent.fromLegacyString(input: MessageFormat.colorize(message)),
    Text() => message.build(),
    TextComponent() => message,
    _ => throw ArgumentError.value(message, 'message', 'Expected a String, Text or TextComponent'),
  };
}

/// Sending messages to a command sender (a player or the console).
extension MessageCommandSender on CommandSender {
  /// Sends [message] to this sender: a `String` with `&`/`§` color codes, a
  /// [Text], or a [TextComponent] (which is consumed).
  ///
  /// ```dart
  /// sender.send('&aDone!');
  /// ```
  void send(Object message) => sendMessage(text: Messages.component(message));

  /// Sends the template [key] of [catalog] filled with [values] (a `Map` for
  /// `{name}` or a `List` for `{0}`).
  void sendTemplate(MessageCatalog catalog, String key, [Object? values]) =>
      send(catalog.text(key, values));
}

/// Sending messages and effects to a player.
extension MessagePlayer on Player {
  /// Sends [message] (a `String` with `&`/`§` codes, a [Text] or a
  /// [TextComponent], which is consumed) as a chat message.
  void send(Object message) =>
      sendSystemMessage(text: Messages.component(message), overlay: false);

  /// Sends the template [key] of [catalog] filled with [values].
  void sendTemplate(MessageCatalog catalog, String key, [Object? values]) =>
      send(catalog.text(key, values));

  /// Shows [message] above the hotbar.
  void actionBar(Object message) => showActionbar(text: Messages.component(message));

  /// Shows a [title] with an optional [subtitle]. If any of the timings is
  /// given, the fade in/stay/fade out are set (defaults: 0.5s, 3.5s, 1s).
  ///
  /// ```dart
  /// player.title('&6Round 1', subtitle: '&7Fight!', stay: Duration(seconds: 2));
  /// ```
  void title(
    Object title, {
    Object? subtitle,
    Duration? fadeIn,
    Duration? stay,
    Duration? fadeOut,
  }) {
    if (fadeIn != null || stay != null || fadeOut != null) {
      sendTitleAnimation(
        fadeIn: MessageFormat.ticks(fadeIn ?? const Duration(milliseconds: 500)),
        stay: MessageFormat.ticks(stay ?? const Duration(milliseconds: 3500)),
        fadeOut: MessageFormat.ticks(fadeOut ?? const Duration(seconds: 1)),
      );
    }
    if (subtitle != null) showSubtitle(text: Messages.component(subtitle));
    showTitle(text: Messages.component(title));
  }
}

/// Broadcasting to everyone.
extension MessageServer on Server {
  /// Sends [message] (a `String` with color codes or a [Text]) to every
  /// online player. A fresh component is built for each player.
  void broadcastText(Object message) {
    if (message is TextComponent) {
      throw ArgumentError.value(message, 'message', 'A TextComponent can only be sent once; use a String or Text');
    }
    for (final p in getAllPlayers()) {
      p.send(message);
    }
  }
}

/// Broadcasting in one world.
extension MessageWorld on World {
  /// Sends [message] (a `String` with color codes or a [Text]) to the players
  /// of this world; with [overlay] above the hotbar instead of in chat.
  void broadcastText(Object message, {bool overlay = false}) {
    if (message is TextComponent) {
      broadcastSystemMessage(message: message, overlay: overlay);
    } else {
      broadcastSystemMessage(message: Messages.component(message), overlay: overlay);
    }
  }
}

/// Loading message catalogs from the plugin's data folder.
extension MessageCatalogFiles on DataFolder {
  /// Loads a [MessageCatalog] from the JSON file [path] (an object of
  /// strings), with [defaults] for keys it lacks. If the file is missing or
  /// lacks keys, it is (re)written with all keys so server owners can edit
  /// it. Needs the `fs.write.data` permission.
  ///
  /// ```dart
  /// final messages = context.files.messageCatalog('messages.json', defaults: {
  ///   'home.set': '&aHome {name} set!',
  /// });
  /// ```
  MessageCatalog messageCatalog(
    String path, {
    required Map<String, String> defaults,
    String prefix = '',
  }) {
    String? json;
    if (exists(path)) json = readAsString(path);
    final catalog = MessageCatalog.fromJson(defaults, json, prefix: prefix);
    if (json == null || catalog.missingKeys.isNotEmpty) {
      writeAsString(path, catalog.toJson());
    }
    return catalog;
  }
}
