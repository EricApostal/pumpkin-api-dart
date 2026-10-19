// `FlapDisplaySection` (pure): one run of flaps of a display board line. The server side is the
// text and its width / cycle; the flap animation state (`spinning`, `tick`, `refresh`) is what the
// client keeps and is ported for completeness.
//
// Java -> Dart: `Component` -> [Txt] (the plain text is what the flaps show; the exact JSON of a
// text read from NBT is kept so it is written back unchanged).
import 'dart:convert';
import 'dart:math' as math;

import '../../redstone/support/text.dart' show Txt, plainTextOfJson, tryParseJson;
import '../util/ctag.dart';

/// `FlapDisplaySection`.
class FlapDisplaySection {
  /// `LOADED_FLAP_CYCLES`.
  static final Map<String, List<String>> loadedFlapCycles = {};

  /// `flap_display.cycles.<key>` of the English lang file.
  static const Map<String, String> kFlapCycles = {
    'alphabet': ' ;A;B;C;D;E;F;G;H;I;J;K;L;M;N;O;P;Q;R;S;T;U;V;X;Y;Z',
    'arrival_time': '   ; min;now;15s;30s;45s',
    'fluid_units': 'mB;B ',
    'instant': ' ; ',
    'numeric': ' ;0;1;2;3;4;5;6;7;8;9',
    'pixel': '█;▓;▒',
    'shortened_numbers': ' ;K;M',
  };

  // ignore: constant_identifier_names
  static const double MONOSPACE = 7;
  // ignore: constant_identifier_names
  static const double WIDE_MONOSPACE = 9;

  double size;
  bool singleFlap;
  bool hasGap;
  bool rightAligned = false;
  bool wideFlaps = false;
  bool sendTransition = false;
  String cycle;
  Txt? component;
  String? _componentJson;

  // Client
  List<String>? cyclingOptions;
  late List<bool> spinning;
  int spinningTicks = 0;
  late String text;

  FlapDisplaySection(double width, this.cycle, this.singleFlap, this.hasGap) : size = width {
    spinning = List<bool>.filled(singleFlap ? 1 : math.max(0, (width / MONOSPACE).toInt()), false);
    text = ' ' * spinning.length;
  }

  /// `rightAligned()`.
  FlapDisplaySection setRightAligned() {
    rightAligned = true;
    return this;
  }

  /// `wideFlaps()`.
  FlapDisplaySection setWideFlaps() {
    wideFlaps = true;
    return this;
  }

  /// `setText(component)`.
  void setText(Txt? component) {
    this.component = component;
    _componentJson = null;
    sendTransition = true;
  }

  /// `refresh(transition)`.
  void refresh(bool transition) {
    final c = component;
    if (c == null) return;

    var newText = c.plain;

    if (!singleFlap) {
      if (rightAligned) newText = newText.trim();
      newText = newText.toUpperCase();
      newText = newText.substring(0, math.min(spinning.length, newText.length));
      final whitespace = ' ' * (spinning.length - newText.length);
      newText = rightAligned ? whitespace + newText : newText + whitespace;
      if (text.isNotEmpty) {
        for (var i = 0; i < spinning.length; i++) {
          spinning[i] = spinning[i] || (transition && text[i] != newText[i]);
        }
      }
    } else if (text.isNotEmpty) {
      spinning[0] = spinning[0] || (transition && newText != text);
    }

    text = newText;
    spinningTicks = 0;
  }

  /// `tick(instant, random)`: the number of flaps that are spinning.
  int tickFlaps(bool instant, math.Random randomSource) {
    final options = cyclingOptions;
    if (options == null) return 0;
    final max = math.max(4, (options.length * 1.75).toInt());
    if (spinningTicks > max) return 0;

    spinningTicks++;
    if (spinningTicks <= max && spinningTicks < 2) return spinningTicks == 1 ? 0 : spinning.length;

    var spinningFlaps = 0;
    for (var i = 0; i < spinning.length; i++) {
      final increasingChance = (8 - spinningTicks).clamp(1, 10);
      var continueSpin = !instant && randomSource.nextInt(increasingChance * max ~/ 4) != 0;
      continueSpin = continueSpin && (max > 5 || spinningTicks < 2);
      spinning[i] = spinning[i] && continueSpin;

      if (i > 0 && randomSource.nextInt(3) > 0) spinning[i - 1] = spinning[i - 1] && continueSpin;
      if (i < spinning.length - 1 && randomSource.nextInt(3) > 0) spinning[i + 1] = spinning[i + 1] && continueSpin;
      if (spinningTicks > max) spinning[i] = false;

      if (spinning[i]) spinningFlaps++;
    }

    return spinningFlaps;
  }

  /// `getSize()`.
  double getSize() => size;

  /// `write(registries)`. The `Transition` marker is consumed by the client write ([clearTransition]);
  /// a save-only write leaves it for the next client update.
  CTag write({bool clearTransition = true}) {
    final tag = CTag();
    tag.putFloat('Width', size);
    tag.putString('Cycle', cycle);
    if (rightAligned) tag.putMarker('RightAligned');
    if (singleFlap) tag.putMarker('SingleFlap');
    if (hasGap) tag.putMarker('Gap');
    if (wideFlaps) tag.putMarker('Wide');
    final c = component;
    if (c != null) tag.putString('Text', _componentJson ?? jsonEncode(c.toJson()));
    if (sendTransition) tag.putMarker('Transition');
    if (clearTransition) sendTransition = false;
    return tag;
  }

  /// `load(tag, registries)`.
  static FlapDisplaySection load(CTag tag) {
    final width = tag.getFloat('Width');
    final cycle = tag.getString('Cycle');
    final singleFlap = tag.contains('SingleFlap');
    final hasGap = tag.contains('Gap');

    final section = FlapDisplaySection(width, cycle, singleFlap, hasGap);
    section.cyclingOptions = getFlapCycle(cycle);
    section.rightAligned = tag.contains('RightAligned');
    section.wideFlaps = tag.contains('Wide');

    if (!tag.contains('Text')) return section;

    section._setComponentFromJson(tag.getString('Text'));
    section.refresh(tag.getBoolean('Transition'));
    return section;
  }

  /// `update(tag, registries)`.
  void update(CTag tag) {
    final text = tag.getString('Text');
    if (text.isNotEmpty) _setComponentFromJson(text);
    cyclingOptions ??= getFlapCycle(cycle);
    refresh(tag.getBoolean('Transition'));
  }

  void _setComponentFromJson(String json) {
    final parsed = tryParseJson(json);
    component = Txt.literal(plainTextOfJson(parsed));
    _componentJson = json;
  }

  /// `renderCharsIndividually()`.
  bool renderCharsIndividually() => !singleFlap;

  /// `getText()`.
  Txt? getText() => component;

  /// `getFlapCycle(key)`: the cycle options of `create.flap_display.cycles.<key>` (a missing key
  /// translates to itself, like Java).
  static List<String> getFlapCycle(String key) =>
      loadedFlapCycles.putIfAbsent(key, () => (kFlapCycles[key] ?? 'create.flap_display.cycles.$key').split(';'));
}
