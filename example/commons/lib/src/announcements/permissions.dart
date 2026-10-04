import '../core/permissions.dart';

/// Permission nodes of the announcements module.
abstract final class AnnouncementPerms {
  static const admin = PermNode(
    'commons:announcements.admin',
    'Broadcast with /announce and manage /announcements',
    PermDefault.op,
  );

  static const all = [admin];
}
