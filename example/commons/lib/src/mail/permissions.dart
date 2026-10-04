import '../core/permissions.dart';

/// Permission nodes of the mail module.
abstract final class MailPerms {
  static const read = PermNode(
    'commons:mail.read',
    'Read, list and delete your mail',
  );
  static const send = PermNode(
    'commons:mail.send',
    'Send mail with /mail send',
  );
  static const block = PermNode(
    'commons:mail.block',
    'Block players from mailing you',
  );
  static const bypass = PermNode(
    'commons:mail.bypass',
    'Send mail without the cooldown',
    PermDefault.op,
  );

  static const all = [read, send, block, bypass];
}
