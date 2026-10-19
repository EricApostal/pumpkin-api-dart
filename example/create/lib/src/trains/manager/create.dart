// ignore_for_file: constant_identifier_names, non_constant_identifier_names
// `Create` of the Java mod, reduced to what the trains need: the one railway manager
// (`Create.RAILWAYS`), resource ids and the shared random source. Pure.
import 'dart:math';

import 'global_railway_manager.dart';

abstract final class Create {
  static const String ID = 'create';

  /// `Create.RAILWAYS`: the one railway manager (server side).
  static GlobalRailwayManager RAILWAYS = GlobalRailwayManager();

  /// `Create.RANDOM`.
  static final Random RANDOM = Random();

  /// `Create.asResource(path)`.
  static String asResource(String path) => '$ID:$path';
}
