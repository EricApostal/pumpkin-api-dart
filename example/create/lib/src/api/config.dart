/// `AllConfigs` for all modules: a service of the `infrastructure` module.
///
/// ```dart
/// final configs = ctx.services.require<CreateConfigs>();
/// final maxBelt = configs.server.kinetics.maxBeltLength.value;
/// configs.server.kinetics.maxBeltLength.onChange((v) => ...);
/// final impact = configs.stress.impact('mechanical_press');
/// ```
///
/// Values come from the manifest defaults and the `create_config` section of the plugin's
/// `config.json` (nested like the toml: `{"server": {"kinetics": {"maxBeltLength": 30}}}`).
/// `/create config` changes them at runtime and the synced `create-server.toml` is pushed to
/// NeoForge clients.
library;

export '../infrastructure/config/create_configs.dart';
