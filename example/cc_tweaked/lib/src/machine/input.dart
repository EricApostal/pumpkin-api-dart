// Turns what a player does at a terminal into events for the computer
// (`UserComputerInput` and `EventComputerInput` in CC: Tweaked).
import 'terminal.dart';

/// Where input events end up.
typedef QueueEvent = void Function(String name, List<Object?> args);

/// Input from one player. It remembers pressed keys and buttons so that
/// releasing them can be reported when the player closes the terminal.
final class ComputerInput {
  final QueueEvent _queue;
  final Terminal _terminal;
  final Set<int> _keysDown = {};
  int _lastMouseX = 0;
  int _lastMouseY = 0;
  int _lastMouseDown = -1;

  ComputerInput(this._queue, this._terminal);

  int _clampX(int x) => x < 1 ? 1 : (x > _terminal.width ? _terminal.width : x);

  int _clampY(int y) => y < 1 ? 1 : (y > _terminal.height ? _terminal.height : y);

  /// A key (GLFW key code) went down; [repeat] is true for key repeat.
  void keyDown(int key, {bool repeat = false}) {
    if (key < 0) return;
    _keysDown.add(key);
    _queue('key', [key.toDouble(), repeat]);
  }

  void keyUp(int key) {
    if (key < 0) return;
    _keysDown.remove(key);
    _queue('key_up', [key.toDouble()]);
  }

  /// A typed character, one byte of the terminal's character set.
  void charTyped(int byte) => _queue('char', [String.fromCharCode(byte & 0xFF)]);

  /// Pasted text. Stops at the first character a terminal cannot type.
  void paste(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length && i < 512; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0 || c == 10 || c == 13 || c > 255) break;
      out.writeCharCode(c);
    }
    if (out.isNotEmpty) _queue('paste', [out.toString()]);
  }

  bool get _mouseSupport => _terminal.isColour;

  void mouseClick(int button, int x, int y) {
    if (!_mouseSupport || button < 1 || button > 3) return;
    _lastMouseX = _clampX(x);
    _lastMouseY = _clampY(y);
    _queue('mouse_click', [button.toDouble(), _lastMouseX.toDouble(), _lastMouseY.toDouble()]);
    _lastMouseDown = button;
  }

  void mouseUp(int button, int x, int y) {
    if (!_mouseSupport || button < 1 || button > 3) return;
    _lastMouseX = _clampX(x);
    _lastMouseY = _clampY(y);
    if (_lastMouseDown == button) {
      _queue('mouse_up', [button.toDouble(), _lastMouseX.toDouble(), _lastMouseY.toDouble()]);
      _lastMouseDown = -1;
    }
  }

  void mouseDrag(int button, int x, int y) {
    if (!_mouseSupport || button < 1 || button > 3) return;
    final cx = _clampX(x);
    final cy = _clampY(y);
    if (button == _lastMouseDown && (cx != _lastMouseX || cy != _lastMouseY)) {
      _queue('mouse_drag', [button.toDouble(), cx.toDouble(), cy.toDouble()]);
      _lastMouseX = cx;
      _lastMouseY = cy;
    }
  }

  void mouseScroll(int direction, int x, int y) {
    if (!_mouseSupport || direction == 0) return;
    _lastMouseX = _clampX(x);
    _lastMouseY = _clampY(y);
    _queue('mouse_scroll', [direction.toDouble(), _lastMouseX.toDouble(), _lastMouseY.toDouble()]);
  }

  /// Reports the release of everything still held, when the player stops
  /// using the terminal.
  void releaseInputs() {
    for (final key in _keysDown.toList()) {
      _queue('key_up', [key.toDouble()]);
    }
    _keysDown.clear();
    if (_lastMouseDown != -1) {
      _queue('mouse_up', [_lastMouseDown.toDouble(), _lastMouseX.toDouble(), _lastMouseY.toDouble()]);
      _lastMouseDown = -1;
    }
  }
}
