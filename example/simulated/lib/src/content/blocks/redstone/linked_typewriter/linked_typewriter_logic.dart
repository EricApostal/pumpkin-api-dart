// The linked typewriter's server state: who is using it, what has been typed,
// which keys are down, and what a save packet does to the key table.
//
// The rules are the ones in `LinkedTypewriterBlockEntity`, and the ones that are
// easy to get wrong are here:
//
//  * only the current user may press keys (`checkUser`);
//  * the typed text is capped at 25 characters and drops the *oldest* one, so it
//    reads like a scrolling display;
//  * key 259 is backspace and deletes one character instead of typing one;
//  * a save packet clears the table first, then adds the sent entries — unless
//    `clearAll` is set, in which case the table stays empty.
//
// Pure: no host imports.
// create's internals are pure but not exported from the barrel yet.
// ignore_for_file: implementation_imports
//
// Java: dev.simulated_team.simulated.content.blocks.redstone.linked_typewriter
//         .LinkedTypewriterBlockEntity
//       …network.packets.linked_typewriter.TypewriterKeySavePacket
import 'package:create/src/common/pos.dart' show Pos;

import 'linked_typewriter_entries.dart';

/// `LinkedTypewriterBlockEntity`, without the level.
final class LinkedTypewriterLogic {
  /// The GLFW code of backspace.
  static const int backspaceKey = 259;

  /// The length at which the text drops its oldest character.
  ///
  /// It is 25 in Java, and the check runs *after* the append, so the text holds
  /// at most 24 characters.
  static const int typedEntryTrimThreshold = 25;

  /// The key table.
  final LinkedTypewriterEntries entries;

  /// What the player has typed.
  String typedEntry = '';

  /// The keys currently held down.
  final Set<int> pressedKeys = <int>{};

  /// The uuid of the player using the typewriter, or `null`.
  String? currentUser;

  LinkedTypewriterLogic([LinkedTypewriterEntries? entries]) : entries = entries ?? LinkedTypewriterEntries();

  /// `isInUse()`.
  bool get isInUse => currentUser != null;

  /// `checkUser(user)`.
  bool checkUser(String user) => currentUser == user;

  /// `tryStartUsing`: succeeds only when nobody else is using it.
  bool connectUser(String user) {
    if (isInUse && currentUser != user) return false;
    currentUser = user;
    return true;
  }

  /// `disconnectUser()`: forgets the user and the held keys, and deactivates
  /// every entry (the caller sends the block entity data and the sound).
  ///
  /// Returns the user that was disconnected, or `null` when it was unused.
  String? disconnectUser() {
    final user = currentUser;
    if (user == null) return null;
    pressedKeys.clear();
    entries.deactivateAll();
    currentUser = null;
    return user;
  }

  /// `onKeyInteraction(user, toBind, key, press)`: a key event from the client.
  ///
  /// With [toBind] and [press] the key is *bound* instead of pressed.
  void onKeyInteraction({required String user, KeyboardEntry? toBind, required int key, required bool press}) {
    if (!checkUser(user)) return;
    if (press && toBind != null) {
      entries.setKey(key, toBind);
      return;
    }
    if (press) {
      pressKey(key);
    } else {
      releaseKey(key);
    }
  }

  /// `pressKey(key)`: appends to the typed text (backspace deletes), then
  /// activates the key.
  void pressKey(int key) {
    pressedKeys.add(key);
    if (key == backspaceKey) {
      if (typedEntry.isNotEmpty) typedEntry = typedEntry.substring(0, typedEntry.length - 1);
    } else {
      typedEntry += String.fromCharCode(key);
    }
    if (typedEntry.length >= typedEntryTrimThreshold) typedEntry = typedEntry.substring(1);
    entries.activateKey(key);
  }

  /// `releaseKey(key)`.
  void releaseKey(int key) {
    pressedKeys.remove(key);
    entries.deactivateKey(key);
  }

  /// `invalidate()`: every held key is forgotten and every entry deactivated.
  void invalidate() {
    pressedKeys.clear();
    entries.deactivateAll();
  }
}

/// `TypewriterKeySavePacket.handle`, without the block entity.
abstract final class TypewriterSaveLogic {
  /// The key count that awards `I_PAID_FOR_THE_WHOLE_TYPEWRITER`.
  static const int fullKeyboardKeys = 26;

  /// Applies a save packet: every sent entry is stamped with [pos], the table is
  /// cleared, and the entries are added unless [clearAll].
  ///
  /// Returns whether the table now has at least [fullKeyboardKeys] keys (the
  /// `TypewriterKeySavePacket.handle` (`TypewriterKeySavePacket.java:52`) condition
  /// for `I_PAID_FOR_THE_WHOLE_TYPEWRITER`). The port has no save-packet handler
  /// (`declared-only` in `SimHandledPayloads`), so this bool is for the caller the
  /// port gains when it ports the handler.
  static bool apply(
    LinkedTypewriterEntries entries,
    Map<int, KeyboardEntry> changedKeys,
    Pos pos, {
    required bool clearAll,
  }) {
    for (final entry in changedKeys.values) {
      entry.setLocation(pos);
    }
    entries.clearAll();
    if (!clearAll) entries.addAll(changedKeys);
    return entries.size >= fullKeyboardKeys;
  }
}
