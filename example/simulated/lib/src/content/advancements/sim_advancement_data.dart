// The advancement tree of Simulated as data (pure): the definitions of the mod's
// datapack, the criteria the host does not evaluate, and the two plugin triggers
// that stand in for them.
//
// The definitions are the mod's generated resources, verbatim:
//   simulated/common/src/generated/resources/data/simulated/advancement/*.json
// `SimAdvancements.SIM_ADVANCEMENTS` declares them in [simAdvancementIds] order, and the
// criteria they carry are the ones `SimulatedAdvancement`'s builder adds -- `awardedForFree`
// / `whenIconCollected` (`InventoryChangeTrigger.TriggerInstance.hasItems`) and
// `whenIconPlaced` (`ItemUsedOnLocationTrigger.TriggerInstance.placedBlock`).
//
// The host fires neither of those two vanilla triggers for a plugin (no inventory diff, no
// block-placement criterion context), so [simAdvancementsRegisteredJson] rewrites exactly
// them to the plugin's own triggers (`simulated:inventory_check` /
// `simulated:placed_block_check`), leaving the criterion key and the requirement groups
// intact and tagging each criterion `<id>/<criterion>` -- the same shape Create's port uses
// (`example/create/lib/src/content/advancement_data.dart`).
//
// Pure: no host imports, so the tests run on the plain Dart VM.
//
// Java: dev.simulated_team.simulated.data.advancements.SimAdvancements
//       dev.simulated_team.simulated.data.advancements.SimulatedAdvancement
//       dev.simulated_team.simulated.data.advancements.SimAdvancementTriggers
import 'dart:convert';

/// The plugin trigger that stands in for `minecraft:inventory_changed`: a criterion fires it
/// with `plugin_tag` = `<advancement>/<criterion>`.
const String inventoryCheckTrigger = 'simulated:inventory_check';

/// The plugin trigger that stands in for `minecraft:placed_block`: a criterion fires it with
/// `plugin_tag` = `<advancement>/<criterion>`.
const String placedBlockCheckTrigger = 'simulated:placed_block_check';

/// `SimulatedAdvancement.id`: the advancement path under `simulated:`.
///
/// [id] may be bare (`'unpowered_steering'`, what the constants here hold) or already
/// namespace prefixed; both give the path.
String simAdvancementPath(String id) =>
    id.startsWith('simulated:') ? id.substring('simulated:'.length) : id;

/// The criterion trigger of [id] (`SimAdvancementTriggers.addSimple(modid, id + "_builtin")`,
/// which `SimAdvancements.create` hands every definition).
String simBuiltinTrigger(String id) => 'simulated:${simAdvancementPath(id)}_builtin';

/// `simulated:<path>`: the registered advancement id.
String simAdvancementId(String path) => 'simulated:${simAdvancementPath(path)}';

/// The advancements of the mod, in the Java declaration order (`SimAdvancements.SIM_ADVANCEMENTS`),
/// which is also the order their `after(...)` parents are declared in.
const List<String> simAdvancementIds = [
  'root',
  'applied_kinematics',
  'opposite_attract',
  'a_calculated_connection',
  'you_spin_me_right_round',
  'learning_the_ropes',
  'stuck_together',
  'not_gonna_sugarcoat_it',
  'i_declare_thee',
  'measure_once_build_twice',
  'get_a_grip',
  'got_a_grip',
  'unpowered_steering',
  'steamless_engine',
  'that_should_do_for_now',
  'what_goes_down',
  'must_come_up',
  'rewind_time',
  'i_paid_for_the_whole_typewriter',
  'no_pressure',
  'can_we_get_much_higher',
  'convoluted_circumvolutions',
  'the_definition_of_up',
  'thataway',
  'far_from_home',
  'speed_is_key',
  'big_beam',
  'nearsighted',
  'my_eye',
  'call_of_the_void',
];

/// The definition of each advancement of [simAdvancementIds], verbatim from the mod's
/// generated resources (`data/simulated/advancement/<path>.json`).
///
/// `criteria` with `trigger` `minecraft:inventory_changed` or `minecraft:placed_block` are
/// the ones the host never fires; [simAdvancementsRegisteredJson] rewrites those two keys and
/// nothing else. The `_builtin` criterion's `conditions` is the trigger id as a string, the
/// shape `registerSimple` writes
/// (`SimulatedCriterionTriggerBase.SimpleSimulatedTrigger.createCriterion`).
const Map<String, String> simAdvancementJson = {
  // `root`
  'root': r'''{
  "criteria": {
    "1": {
      "trigger": "minecraft:inventory_changed"
    }
  },
  "display": {
    "announce_to_chat": false,
    "background": "simulated:textures/gui/advancement.png",
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.root.desc"
    },
    "icon": {
      "id": "simulated:contraption_diagram"
    },
    "show_toast": false,
    "title": {
      "translate": "advancement.simulated.root"
    }
  },
  "requirements": [
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `applied_kinematics`
  'applied_kinematics': r'''{
  "parent": "simulated:root",
  "criteria": {
    "1": {
      "conditions": {
        "items": [
          {
            "items": "simulated:physics_assembler"
          }
        ]
      },
      "trigger": "minecraft:inventory_changed"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.applied_kinematics.desc"
    },
    "icon": {
      "id": "simulated:physics_assembler"
    },
    "title": {
      "translate": "advancement.simulated.applied_kinematics"
    }
  },
  "requirements": [
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `opposite_attract`
  'opposite_attract': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:opposite_attract_builtin",
      "trigger": "simulated:opposite_attract_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.opposite_attract.desc"
    },
    "icon": {
      "id": "simulated:redstone_magnet"
    },
    "title": {
      "translate": "advancement.simulated.opposite_attract"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `a_calculated_connection`
  'a_calculated_connection': r'''{
  "parent": "simulated:opposite_attract",
  "criteria": {
    "0": {
      "conditions": "simulated:a_calculated_connection_builtin",
      "trigger": "simulated:a_calculated_connection_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.a_calculated_connection.desc"
    },
    "icon": {
      "id": "simulated:docking_connector"
    },
    "title": {
      "translate": "advancement.simulated.a_calculated_connection"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `you_spin_me_right_round`
  'you_spin_me_right_round': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:you_spin_me_right_round_builtin",
      "trigger": "simulated:you_spin_me_right_round_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.you_spin_me_right_round.desc"
    },
    "icon": {
      "id": "simulated:swivel_bearing"
    },
    "title": {
      "translate": "advancement.simulated.you_spin_me_right_round"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `learning_the_ropes`
  'learning_the_ropes': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:learning_the_ropes_builtin",
      "trigger": "simulated:learning_the_ropes_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.learning_the_ropes.desc"
    },
    "icon": {
      "id": "simulated:rope_coupling"
    },
    "title": {
      "translate": "advancement.simulated.learning_the_ropes"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `stuck_together`
  'stuck_together': r'''{
  "parent": "simulated:learning_the_ropes",
  "criteria": {
    "1": {
      "conditions": {
        "items": [
          {
            "items": "simulated:plunger_launcher"
          }
        ]
      },
      "trigger": "minecraft:inventory_changed"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.stuck_together.desc"
    },
    "icon": {
      "id": "simulated:plunger_launcher"
    },
    "title": {
      "translate": "advancement.simulated.stuck_together"
    }
  },
  "requirements": [
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `not_gonna_sugarcoat_it`
  'not_gonna_sugarcoat_it': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:not_gonna_sugarcoat_it_builtin",
      "trigger": "simulated:not_gonna_sugarcoat_it_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.not_gonna_sugarcoat_it.desc"
    },
    "icon": {
      "id": "simulated:honey_glue"
    },
    "title": {
      "translate": "advancement.simulated.not_gonna_sugarcoat_it"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `i_declare_thee`
  'i_declare_thee': r'''{
  "parent": "simulated:not_gonna_sugarcoat_it",
  "criteria": {
    "0": {
      "conditions": "simulated:i_declare_thee_builtin",
      "trigger": "simulated:i_declare_thee_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.i_declare_thee.desc"
    },
    "icon": {
      "id": "simulated:white_nameplate"
    },
    "title": {
      "translate": "advancement.simulated.i_declare_thee"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `measure_once_build_twice`
  'measure_once_build_twice': r'''{
  "parent": "simulated:not_gonna_sugarcoat_it",
  "criteria": {
    "0": {
      "conditions": "simulated:measure_once_build_twice_builtin",
      "trigger": "simulated:measure_once_build_twice_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.measure_once_build_twice.desc"
    },
    "icon": {
      "id": "simulated:contraption_diagram"
    },
    "title": {
      "translate": "advancement.simulated.measure_once_build_twice"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `get_a_grip`
  'get_a_grip': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:get_a_grip_builtin",
      "trigger": "simulated:get_a_grip_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.get_a_grip.desc"
    },
    "icon": {
      "id": "simulated:iron_handle"
    },
    "title": {
      "translate": "advancement.simulated.get_a_grip"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `got_a_grip`
  'got_a_grip': r'''{
  "parent": "simulated:get_a_grip",
  "criteria": {
    "0": {
      "conditions": "simulated:got_a_grip_builtin",
      "trigger": "simulated:got_a_grip_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.got_a_grip.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:iron_handle"
    },
    "title": {
      "translate": "advancement.simulated.got_a_grip"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `unpowered_steering`
  'unpowered_steering': r'''{
  "parent": "simulated:get_a_grip",
  "criteria": {
    "0": {
      "conditions": "simulated:unpowered_steering_builtin",
      "trigger": "simulated:unpowered_steering_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.unpowered_steering.desc"
    },
    "icon": {
      "id": "simulated:steering_wheel"
    },
    "title": {
      "translate": "advancement.simulated.unpowered_steering"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `steamless_engine`
  'steamless_engine': r'''{
  "parent": "simulated:unpowered_steering",
  "criteria": {
    "0": {
      "conditions": "simulated:steamless_engine_builtin",
      "trigger": "simulated:steamless_engine_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.steamless_engine.desc"
    },
    "icon": {
      "id": "simulated:red_portable_engine"
    },
    "title": {
      "translate": "advancement.simulated.steamless_engine"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `that_should_do_for_now`
  'that_should_do_for_now': r'''{
  "parent": "simulated:steamless_engine",
  "criteria": {
    "0": {
      "conditions": "simulated:that_should_do_for_now_builtin",
      "trigger": "simulated:that_should_do_for_now_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.that_should_do_for_now.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:red_portable_engine"
    },
    "title": {
      "translate": "advancement.simulated.that_should_do_for_now"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `what_goes_down`
  'what_goes_down': r'''{
  "parent": "simulated:get_a_grip",
  "criteria": {
    "1": {
      "conditions": {
        "items": [
          {
            "items": "simulated:spring"
          }
        ]
      },
      "trigger": "minecraft:inventory_changed"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.what_goes_down.desc"
    },
    "icon": {
      "id": "simulated:spring"
    },
    "title": {
      "translate": "advancement.simulated.what_goes_down"
    }
  },
  "requirements": [
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `must_come_up`
  'must_come_up': r'''{
  "parent": "simulated:what_goes_down",
  "criteria": {
    "0": {
      "conditions": "simulated:must_come_up_builtin",
      "trigger": "simulated:must_come_up_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.must_come_up.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:spring"
    },
    "title": {
      "translate": "advancement.simulated.must_come_up"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `rewind_time`
  'rewind_time': r'''{
  "parent": "simulated:what_goes_down",
  "criteria": {
    "0": {
      "conditions": "simulated:rewind_time_builtin",
      "trigger": "simulated:rewind_time_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.rewind_time.desc"
    },
    "icon": {
      "id": "simulated:torsion_spring"
    },
    "title": {
      "translate": "advancement.simulated.rewind_time"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `i_paid_for_the_whole_typewriter`
  'i_paid_for_the_whole_typewriter': r'''{
  "parent": "simulated:get_a_grip",
  "criteria": {
    "0": {
      "conditions": "simulated:i_paid_for_the_whole_typewriter_builtin",
      "trigger": "simulated:i_paid_for_the_whole_typewriter_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.i_paid_for_the_whole_typewriter.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:linked_typewriter"
    },
    "title": {
      "translate": "advancement.simulated.i_paid_for_the_whole_typewriter"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `no_pressure`
  'no_pressure': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:no_pressure_builtin",
      "trigger": "simulated:no_pressure_builtin"
    },
    "1": {
      "conditions": {
        "location": {
          "type": "minecraft:match_block",
          "blocks": "simulated:altitude_sensor"
        }
      },
      "trigger": "minecraft:placed_block"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.no_pressure.desc"
    },
    "icon": {
      "id": "simulated:altitude_sensor"
    },
    "title": {
      "translate": "advancement.simulated.no_pressure"
    }
  },
  "requirements": [
    [
      "0"
    ],
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `can_we_get_much_higher`
  'can_we_get_much_higher': r'''{
  "parent": "simulated:no_pressure",
  "criteria": {
    "0": {
      "conditions": "simulated:can_we_get_much_higher_builtin",
      "trigger": "simulated:can_we_get_much_higher_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.can_we_get_much_higher.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:altitude_sensor"
    },
    "title": {
      "translate": "advancement.simulated.can_we_get_much_higher"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `convoluted_circumvolutions`
  'convoluted_circumvolutions': r'''{
  "parent": "simulated:no_pressure",
  "criteria": {
    "1": {
      "conditions": {
        "items": [
          {
            "items": "simulated:gyroscopic_mechanism"
          }
        ]
      },
      "trigger": "minecraft:inventory_changed"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.convoluted_circumvolutions.desc"
    },
    "icon": {
      "id": "simulated:gyroscopic_mechanism"
    },
    "title": {
      "translate": "advancement.simulated.convoluted_circumvolutions"
    }
  },
  "requirements": [
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `the_definition_of_up`
  'the_definition_of_up': r'''{
  "parent": "simulated:convoluted_circumvolutions",
  "criteria": {
    "0": {
      "conditions": "simulated:the_definition_of_up_builtin",
      "trigger": "simulated:the_definition_of_up_builtin"
    },
    "1": {
      "conditions": {
        "location": {
          "type": "minecraft:match_block",
          "blocks": "simulated:gimbal_sensor"
        }
      },
      "trigger": "minecraft:placed_block"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.the_definition_of_up.desc"
    },
    "icon": {
      "id": "simulated:gimbal_sensor"
    },
    "title": {
      "translate": "advancement.simulated.the_definition_of_up"
    }
  },
  "requirements": [
    [
      "0"
    ],
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `thataway`
  'thataway': r'''{
  "parent": "simulated:no_pressure",
  "criteria": {
    "0": {
      "conditions": "simulated:thataway_builtin",
      "trigger": "simulated:thataway_builtin"
    },
    "1": {
      "conditions": {
        "location": {
          "type": "minecraft:match_block",
          "blocks": "simulated:navigation_table"
        }
      },
      "trigger": "minecraft:placed_block"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.thataway.desc"
    },
    "icon": {
      "id": "simulated:navigation_table"
    },
    "title": {
      "translate": "advancement.simulated.thataway"
    }
  },
  "requirements": [
    [
      "0"
    ],
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `far_from_home`
  'far_from_home': r'''{
  "parent": "simulated:thataway",
  "criteria": {
    "0": {
      "conditions": "simulated:far_from_home_builtin",
      "trigger": "simulated:far_from_home_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.far_from_home.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "simulated:navigation_table"
    },
    "title": {
      "translate": "advancement.simulated.far_from_home"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `speed_is_key`
  'speed_is_key': r'''{
  "parent": "simulated:no_pressure",
  "criteria": {
    "0": {
      "conditions": "simulated:speed_is_key_builtin",
      "trigger": "simulated:speed_is_key_builtin"
    },
    "1": {
      "conditions": {
        "location": {
          "type": "minecraft:match_block",
          "blocks": "simulated:velocity_sensor"
        }
      },
      "trigger": "minecraft:placed_block"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.speed_is_key.desc"
    },
    "icon": {
      "id": "simulated:velocity_sensor"
    },
    "title": {
      "translate": "advancement.simulated.speed_is_key"
    }
  },
  "requirements": [
    [
      "0"
    ],
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `big_beam`
  'big_beam': r'''{
  "parent": "simulated:no_pressure",
  "criteria": {
    "0": {
      "conditions": "simulated:big_beam_builtin",
      "trigger": "simulated:big_beam_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.big_beam.desc"
    },
    "icon": {
      "id": "simulated:laser_pointer"
    },
    "title": {
      "translate": "advancement.simulated.big_beam"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `nearsighted`
  'nearsighted': r'''{
  "parent": "simulated:big_beam",
  "criteria": {
    "0": {
      "conditions": "simulated:nearsighted_builtin",
      "trigger": "simulated:nearsighted_builtin"
    },
    "1": {
      "conditions": {
        "location": {
          "type": "minecraft:match_block",
          "blocks": "simulated:optical_sensor"
        }
      },
      "trigger": "minecraft:placed_block"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.nearsighted.desc"
    },
    "icon": {
      "id": "simulated:optical_sensor"
    },
    "title": {
      "translate": "advancement.simulated.nearsighted"
    }
  },
  "requirements": [
    [
      "0"
    ],
    [
      "1"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `my_eye`
  'my_eye': r'''{
  "parent": "simulated:big_beam",
  "criteria": {
    "0": {
      "conditions": "simulated:my_eye_builtin",
      "trigger": "simulated:my_eye_builtin"
    }
  },
  "display": {
    "announce_to_chat": false,
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.my_eye.desc"
    },
    "icon": {
      "id": "simulated:laser_sensor"
    },
    "title": {
      "translate": "advancement.simulated.my_eye"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
  // `call_of_the_void`
  'call_of_the_void': r'''{
  "parent": "simulated:applied_kinematics",
  "criteria": {
    "0": {
      "conditions": "simulated:call_of_the_void_builtin",
      "trigger": "simulated:call_of_the_void_builtin"
    }
  },
  "display": {
    "description": {
      "color": "#DBA213",
      "translate": "advancement.simulated.call_of_the_void.desc"
    },
    "frame": "goal",
    "hidden": true,
    "icon": {
      "id": "minecraft:end_portal_frame"
    },
    "title": {
      "translate": "advancement.simulated.call_of_the_void"
    }
  },
  "requirements": [
    [
      "0"
    ]
  ],
  "sends_telemetry_event": true
}''',
};

/// Whether [path]'s definition carries a `<id>_builtin` criterion, so it can be granted by a
/// trigger the plugin fires.
///
/// The five criteria of the tree that are only `minecraft:inventory_changed` do not
/// (`awardedForFree` / `whenIconCollected`): Java's `SimulatedAdvancement.awardTo` throws
/// `UnsupportedOperationException` for them, and `SimAdvancements.award` refuses them.
bool simHasBuiltinTrigger(String path) =>
    simAdvancementJson[simAdvancementPath(path)]?.contains('"${simBuiltinTrigger(path)}"') ?? false;

/// Every criterion trigger [simAdvancementJson] needs registered
/// (`SimAdvancementTriggers.register` registers the mod's own, one per advancement): the
/// `_builtin` trigger of every advancement that has one, then the two the plugin fires.
List<String> simAdvancementTriggers() => [
  for (final path in simAdvancementIds)
    if (simHasBuiltinTrigger(path)) simBuiltinTrigger(path),
  inventoryCheckTrigger,
  placedBlockCheckTrigger,
];

/// One criterion of the tree that the host does not evaluate; the plugin fires its trigger.
final class SimExternalCriterion {
  /// The advancement's path (`'root'`).
  final String advancementId;

  /// The criterion's key in the definition (`'1'`).
  final String criterion;

  /// The `plugin_tag` condition the rewrite writes (`SimulatedAdvancement.keyIndex`).
  String get tag => '$advancementId/$criterion';

  const SimExternalCriterion(this.advancementId, this.criterion);
}

/// An `minecraft:inventory_changed` criterion (`InventoryChangeTrigger`): the player must hold
/// at least one of [anyOf] (`whenIconCollected` / `whenItemCollected`), or anything at all
/// when it is empty (`awardedForFree`).
final class SimInventoryCriterion extends SimExternalCriterion {
  /// The item keys of the criterion's `items` predicate.
  final List<String> anyOf;

  const SimInventoryCriterion(super.advancementId, super.criterion, this.anyOf);

  /// Whether a player holding [heldItemKeys] satisfies the criterion.
  bool matches(Iterable<String> heldItemKeys) {
    if (anyOf.isEmpty) return true;
    for (final key in heldItemKeys) {
      if (anyOf.contains(key)) return true;
    }
    return false;
  }
}

/// A `minecraft:placed_block` criterion (`ItemUsedOnLocationTrigger` with a `minecraft:match_block`
/// location): the player must place one of [blocks] (`whenIconPlaced`).
final class SimPlacedCriterion extends SimExternalCriterion {
  /// The block keys of the criterion's `location.blocks` predicate.
  final List<String> blocks;

  const SimPlacedCriterion(super.advancementId, super.criterion, this.blocks);

  /// Whether placing [blockKey] satisfies the criterion.
  bool matches(String blockKey) => blocks.contains(blockKey);
}

/// The five `minecraft:inventory_changed` criteria, in tree order.
const List<SimInventoryCriterion> simInventoryCriteria = [
  SimInventoryCriterion('root', '1', const []),
  SimInventoryCriterion('applied_kinematics', '1', ['simulated:physics_assembler']),
  SimInventoryCriterion('stuck_together', '1', ['simulated:plunger_launcher']),
  SimInventoryCriterion('what_goes_down', '1', ['simulated:spring']),
  SimInventoryCriterion('convoluted_circumvolutions', '1', ['simulated:gyroscopic_mechanism']),
];

/// The five `minecraft:placed_block` criteria, in tree order.
const List<SimPlacedCriterion> simPlacedCriteria = [
  SimPlacedCriterion('no_pressure', '1', ['simulated:altitude_sensor']),
  SimPlacedCriterion('the_definition_of_up', '1', ['simulated:gimbal_sensor']),
  SimPlacedCriterion('thataway', '1', ['simulated:navigation_table']),
  SimPlacedCriterion('speed_is_key', '1', ['simulated:velocity_sensor']),
  SimPlacedCriterion('nearsighted', '1', ['simulated:optical_sensor']),
];

/// The definition of [path] as the plugin registers it: verbatim, except that the criteria the
/// host never fires are rewritten to [inventoryCheckTrigger] / [placedBlockCheckTrigger], each
/// carrying its `<id>/<criterion>` `plugin_tag`.
///
/// Returns the constant [simAdvancementJson] entry unchanged when the definition has neither,
/// so the bytes registered are the mod's own.
String simAdvancementsRegisteredJson(String path) {
  final key = simAdvancementPath(path);
  final raw = simAdvancementJson[key];
  if (raw == null) throw ArgumentError.value(path, 'path', 'no such advancement');
  final doc = jsonDecode(raw) as Map<String, dynamic>;
  final criteria = doc['criteria'] as Map<String, dynamic>;
  var rewritten = false;
  for (final entry in criteria.entries.toList()) {
    final trigger = (entry.value as Map<String, dynamic>)['trigger'] as String;
    // `awardedForFree` / `whenIconCollected` / `whenIconPlaced` are the only predicates the
    // builder adds that the host does not evaluate; everything else is a `_builtin` trigger
    // the plugin fires itself.
    final replacement = switch (trigger) {
      'minecraft:inventory_changed' => inventoryCheckTrigger,
      'minecraft:placed_block' => placedBlockCheckTrigger,
      _ => null,
    };
    if (replacement == null) continue;
    criteria[entry.key] = {
      'trigger': replacement,
      'conditions': {'plugin_tag': '$key/${entry.key}'},
    };
    rewritten = true;
  }
  return rewritten ? jsonEncode(doc) : raw;
}
