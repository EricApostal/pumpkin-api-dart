import 'dart:async';
import 'dart:math' as math;

import 'package:wasm_components/wasm_components.dart' show Option;

import 'bindings.g.dart';
import 'events.dart';
import 'events.g.dart';

TextComponent _formText(Object text) => switch (text) {
  String() => TextComponent.text(plain: text),
  TextComponent() => text,
  _ => throw ArgumentError.value(text, 'text', 'Expected a String or TextComponent'),
};

/// Helpers to create the images shown next to the buttons of a [SimpleForm].
abstract final class FormImages {
  /// An image loaded from an HTTP(S) [url].
  static FormImage url(String url) => FormImage(type: ImageType.url, data: url);

  /// An image from a texture [path], e.g. `textures/items/diamond`.
  static FormImage path(String path) => FormImage(type: ImageType.path, data: path);
}

/// Builds a Bedrock simple form: a title, some text and a list of buttons.
///
/// Texts can be given as a [String] or as a [TextComponent]. The [Form]
/// returned by [build] owns its text components, so it can be shown once.
///
/// ```dart
/// final form = (SimpleFormBuilder('Menu', 'Pick one')
///   ..button('Spawn')
///   ..button('Shop', image: FormImages.url('https://example.com/shop.png')))
///     .build();
/// ```
final class SimpleFormBuilder {
  final Object _title;
  final Object _content;
  final List<(Object, FormImage?)> _buttons = [];

  /// Starts a simple form with a [title] and [content] text.
  SimpleFormBuilder(Object title, [Object content = '']) : _title = title, _content = content;

  /// Adds a button, optionally with an [image].
  void button(Object text, {FormImage? image}) => _buttons.add((text, image));

  /// Creates the [Form]. Its response is the index of the pressed button.
  Form build() => FormSimple(
    SimpleForm(
      title: _formText(_title),
      content: _formText(_content),
      buttons: [
        for (final (text, image) in _buttons)
          SimpleFormButton(
            text: _formText(text),
            image: image == null ? Option.none : Option.some(image),
          ),
      ],
    ),
  );
}

/// Builds a Bedrock modal form: a title, some text and two buttons.
///
/// The buttons default to the translated "Yes" and "No".
final class ModalFormBuilder {
  final Object _title;
  final Object _content;

  /// Label of the first (confirm) button, `null` for the translated "Yes".
  Object? button1;

  /// Label of the second (cancel) button, `null` for the translated "No".
  Object? button2;

  /// Starts a modal form with a [title] and [content] text.
  ModalFormBuilder(Object title, [Object content = '']) : _title = title, _content = content;

  /// Creates the [Form]. Its response is `true` for the first button.
  Form build() => FormModal(
    ModalForm(
      title: _formText(_title),
      content: _formText(_content),
      button1: button1 != null
          ? _formText(button1!)
          : TextComponent.translate(key: 'gui.yes', with_: []),
      button2: button2 != null
          ? _formText(button2!)
          : TextComponent.translate(key: 'gui.no', with_: []),
    ),
  );
}

/// Builds a Bedrock custom form made of labels, toggles, sliders, dropdowns
/// and text inputs. Elements are numbered in the order they are added, and
/// [CustomFormResponse] reads their values back by that index.
final class CustomFormBuilder {
  final Object _title;
  final List<CustomFormElement Function()> _elements = [];

  /// Starts a custom form with a [title].
  CustomFormBuilder(Object title) : _title = title;

  /// Adds static text.
  void label(Object text) =>
      _elements.add(() => CustomFormElementLabel(_formText(text)));

  /// Adds an on/off switch.
  void toggle(Object text, {bool initial = false}) =>
      _elements.add(() => CustomFormElementToggle((_formText(text), initial)));

  /// Adds a numeric slider from [min] to [max].
  void slider(
    Object text, {
    required double min,
    required double max,
    double step = 1,
    double? initial,
  }) => _elements.add(
    () => CustomFormElementSlider((_formText(text), min, max, step, initial ?? min)),
  );

  /// Adds a slider that moves through the named [steps].
  void stepSlider(Object text, List<String> steps, {int initial = 0}) => _elements.add(
    () => CustomFormElementStepSlider((_formText(text), List.of(steps), initial)),
  );

  /// Adds a dropdown listing [options]; the response is the chosen index.
  void dropdown(Object text, List<String> options, {int initial = 0}) => _elements.add(
    () => CustomFormElementDropdown((_formText(text), List.of(options), initial)),
  );

  /// Adds a text input.
  void input(Object text, {String placeholder = '', String initial = ''}) =>
      _elements.add(() => CustomFormElementInput((_formText(text), placeholder, initial)));

  /// Creates the [Form].
  Form build() => FormCustom(
    CustomForm(
      title: _formText(_title),
      elements: [for (final element in _elements) element()],
    ),
  );
}

/// What a player did with a form. Use a `switch` to handle the cases:
///
/// ```dart
/// switch (response) {
///   case SimpleFormResponse(:final button): ...
///   case ModalFormResponse(:final accepted): ...
///   case CustomFormResponse(): ...
///   case FormClosed(): ...
/// }
/// ```
sealed class FormResponse {
  const FormResponse();

  /// Parses the raw response [data] sent by the client; `null` means the form
  /// was closed.
  factory FormResponse.parse(String? data) {
    if (data == null) return const FormClosed();
    Object? value;
    try {
      value = _JsonReader(data).read();
    } on FormatException {
      if (data == 'true') return const ModalFormResponse(true);
      if (data == 'false') return const ModalFormResponse(false);
      final index = int.tryParse(data);
      return index == null ? const FormClosed() : SimpleFormResponse(index);
    }
    return switch (value) {
      int() => SimpleFormResponse(value),
      bool() => ModalFormResponse(value),
      List() => CustomFormResponse(List<Object?>.of(value)),
      _ => const FormClosed(),
    };
  }
}

/// A button of a simple form was pressed.
final class SimpleFormResponse extends FormResponse {
  /// Index of the pressed button.
  final int button;
  const SimpleFormResponse(this.button);
}

/// A modal form was answered.
final class ModalFormResponse extends FormResponse {
  /// `true` if the first button was pressed.
  final bool accepted;
  const ModalFormResponse(this.accepted);
}

/// A custom form was submitted.
final class CustomFormResponse extends FormResponse {
  /// The raw value of every element: `bool` for toggles, `num` for sliders,
  /// `int` indexes for dropdowns and step sliders, `String` for inputs and
  /// `null` for labels.
  final List<Object?> values;
  const CustomFormResponse(this.values);

  /// The value of the toggle at [index].
  bool toggleAt(int index) => values[index] as bool;

  /// The value of the slider at [index].
  double sliderAt(int index) => (values[index] as num).toDouble();

  /// The selected option of the dropdown or step slider at [index].
  int choiceAt(int index) => (values[index] as num).toInt();

  /// The text of the input at [index].
  String textAt(int index) => values[index] as String;
}

/// The player closed the form without answering.
final class FormClosed extends FormResponse {
  const FormClosed();
}

class _PendingForm {
  final int id;
  final String player;
  final void Function(FormResponse) handler;
  _PendingForm(this.id, this.player, this.handler);
}

final List<_PendingForm> _pendingForms = [];
bool _formsInstalled = false;

extension FormContextApi on Context {
  /// Starts listening for Bedrock form responses. Call this once in
  /// `onLoad`; without it, [FormPlayerApi.showForm] can't deliver responses.
  void handleFormResponses() {
    if (_formsInstalled) return;
    _formsInstalled = true;
    listen(Events.bedrockFormResponse, (server, event) {
      final name = event.player.getName();
      final index = _pendingForms.indexWhere(
        (form) => form.id == event.formId && form.player == name,
      );
      if (index < 0) return;
      final pending = _pendingForms.removeAt(index);
      pending.handler(
        FormResponse.parse(event.responseData.hasValue ? event.responseData.requireValue() : null),
      );
    });
  }
}

extension FormPlayerApi on Player {
  /// Whether this player is connected through Bedrock Edition and can see forms.
  bool get isBedrock {
    final bedrock = asBedrock();
    if (!bedrock.hasValue) return false;
    bedrock.requireValue().dispose();
    return true;
  }

  /// Shows a Bedrock [form] and returns the player's response. A form closed
  /// by the player completes with [FormClosed].
  ///
  /// Requires [FormContextApi.handleFormResponses] to have been called, and
  /// throws [StateError] if the player is not a Bedrock player. The [form] is
  /// consumed. Don't use this player object after the `await`: it is only
  /// valid inside the callback that received it.
  Future<FormResponse> showForm(Form form) {
    final completer = Completer<FormResponse>();
    showFormCallback(form, completer.complete);
    return completer.future;
  }

  /// Like [showForm], but calls [onResponse] instead of returning a future.
  void showFormCallback(Form form, void Function(FormResponse response) onResponse) {
    if (!_formsInstalled) {
      throw StateError('Call Context.handleFormResponses() in onLoad before showing forms.');
    }
    final bedrock = asBedrock();
    if (!bedrock.hasValue) {
      throw StateError('Forms can only be shown to Bedrock players.');
    }
    final handle = bedrock.requireValue();
    final int id;
    try {
      id = handle.openForm(form: form);
    } finally {
      handle.dispose();
    }
    _pendingForms.add(_PendingForm(id, getName(), onResponse));
  }
}

/// A minimal JSON reader over UTF-16 code units. `dart:convert` is avoided
/// because it depends on `double.parse`, which the standalone Wasm toolchain
/// can't import, and string indexing is not available either.
class _JsonReader {
  final List<int> _s;
  int _i = 0;

  _JsonReader(String source) : _s = source.codeUnits;

  static const _quote = 34, _comma = 44, _minus = 45, _plus = 43, _dot = 46;
  static const _lbracket = 91, _rbracket = 93, _lbrace = 123, _rbrace = 125;
  static const _backslash = 92, _zero = 48, _nine = 57, _lowerE = 101, _upperE = 69;

  Object? read() {
    final value = _value();
    _space();
    if (_i != _s.length) throw const FormatException('trailing data');
    return value;
  }

  void _space() {
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == 32 || c == 10 || c == 13 || c == 9) {
        _i++;
      } else {
        break;
      }
    }
  }

  bool _word(String word) {
    final units = word.codeUnits;
    if (_i + units.length > _s.length) return false;
    for (var k = 0; k < units.length; k++) {
      if (_s[_i + k] != units[k]) return false;
    }
    _i += units.length;
    return true;
  }

  Object? _value() {
    _space();
    if (_i >= _s.length) throw const FormatException('unexpected end');
    final c = _s[_i];
    if (c == _lbracket) return _array();
    if (c == _quote) return _string();
    if (c == _lbrace) return _object();
    if (_word('true')) return true;
    if (_word('false')) return false;
    if (_word('null')) return null;
    return _number();
  }

  List<Object?> _array() {
    _i++;
    final result = <Object?>[];
    _space();
    if (_i < _s.length && _s[_i] == _rbracket) {
      _i++;
      return result;
    }
    while (true) {
      result.add(_value());
      _space();
      if (_i >= _s.length) throw const FormatException('unterminated array');
      if (_s[_i] == _comma) {
        _i++;
      } else if (_s[_i] == _rbracket) {
        _i++;
        return result;
      } else {
        throw const FormatException('bad array');
      }
    }
  }

  Object? _object() {
    // Forms never answer with objects; skip over one.
    var depth = 0;
    while (_i < _s.length) {
      final c = _s[_i];
      if (c == _quote) {
        _string();
        continue;
      }
      if (c == _lbrace) depth++;
      if (c == _rbrace && --depth == 0) {
        _i++;
        return null;
      }
      _i++;
    }
    throw const FormatException('unterminated object');
  }

  String _string() {
    _i++;
    final out = <int>[];
    while (_i < _s.length) {
      final c = _s[_i++];
      if (c == _quote) return String.fromCharCodes(out);
      if (c != _backslash) {
        out.add(c);
        continue;
      }
      if (_i >= _s.length) break;
      final e = _s[_i++];
      switch (e) {
        case 110:
          out.add(10);
        case 116:
          out.add(9);
        case 114:
          out.add(13);
        case 98:
          out.add(8);
        case 102:
          out.add(12);
        case 117:
          if (_i + 4 > _s.length) throw const FormatException('bad escape');
          out.add(int.parse(String.fromCharCodes(_s.sublist(_i, _i + 4)), radix: 16));
          _i += 4;
        default:
          out.add(e);
      }
    }
    throw const FormatException('unterminated string');
  }

  static bool _isDigit(int c) => c >= _zero && c <= _nine;

  int _digits() {
    final start = _i;
    while (_i < _s.length && _isDigit(_s[_i])) {
      _i++;
    }
    if (_i == start) throw const FormatException('bad number');
    return start;
  }

  num _number() {
    final negative = _i < _s.length && _s[_i] == _minus;
    if (negative) _i++;
    final intStart = _digits();
    var mantissa = int.parse(String.fromCharCodes(_s.sublist(intStart, _i)));
    var exponent = 0;
    var isDouble = false;
    if (_i < _s.length && _s[_i] == _dot) {
      isDouble = true;
      _i++;
      final fractionStart = _digits();
      final fraction = String.fromCharCodes(_s.sublist(fractionStart, _i));
      mantissa = int.parse('$mantissa$fraction');
      exponent -= fraction.length;
    }
    if (_i < _s.length && (_s[_i] == _lowerE || _s[_i] == _upperE)) {
      isDouble = true;
      _i++;
      var expNegative = false;
      if (_i < _s.length && (_s[_i] == _plus || _s[_i] == _minus)) {
        expNegative = _s[_i] == _minus;
        _i++;
      }
      final expStart = _digits();
      final expValue = int.parse(String.fromCharCodes(_s.sublist(expStart, _i)));
      exponent += expNegative ? -expValue : expValue;
    }
    if (!isDouble) return negative ? -mantissa : mantissa;
    final magnitude = mantissa * math.pow(10, exponent).toDouble();
    return negative ? -magnitude : magnitude;
  }
}
