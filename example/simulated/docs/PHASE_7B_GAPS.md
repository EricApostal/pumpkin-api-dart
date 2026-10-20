// What this package does not have yet: the second half of Simulated's server
// content, and the host features the first half needs.
//
// The phase-7a slice is in place (see the barrel `lib/simulated.dart`); this
// file is the checklist for phase 7b, so the gaps are written down where the
// next workstream will look.

# Simulated: what phase 7a covers, and what is missing

## In place

| Java | Port |
|---|---|
| `PhysicsAssemblerBlock(Entity)`, `DisassemblyPrevention` | `content/blocks/physics_assembler/` — search, assemble, disassemble, alignment, primary check |
| `util/SimAssemblyHelper`, `util/assembly/SimAssemblyContraption`, `SimAssemblyException` | `util/` — assembly search, move, entity moves, split listener |
| `util/SimMathUtils`, `SimLevelUtil` | `util/` |
| `SteeringWheelBlockEntity` | `content/blocks/steering_wheel/` — angle machine, generated speed, comparator output |
| `ThrottleLeverBlock(Entity)` | `content/blocks/throttle_lever/` — lever state, redstone output |
| `SymmetricSailBlock` | `content/blocks/symmetric_sail/` — lift provider + dye |
| `HoneyGlueEntity`, `HoneyGlueMaxSizing` | `content/entities/honey_glue/` |
| `SpringBlockEntity`, `SpringItemHandler` (length) | `content/blocks/spring/` |
| `TorsionSpringBlockEntity` | `content/blocks/torsion_spring/` |
| `SwivelBearingBlockEntity`, `SwivelBearingPlateBlockEntity` | `content/blocks/swivel_bearing/` |
| `api/` (10) | `api/` — `BearingSlowdownController`, `SimpleResourceManager`, sounds, `IDirectionalAnalogOutput`, `CustomStressImpactTooltipProvider`, `AnalogSignalSource` |
| `config/` (10) | `config/sim_config.dart` — all five server sections, `SimStress` |
| `service/` (14) | `service/sim_services.dart` — `canStickTo`, dye colours, host seam; the loader-only ones are gone |
| `index/`, `registrate/` | `index/sim_blocks.dart`, `sim_items.dart`, `sim_registry.dart`, `sim_lift_providers.dart` |

## Missing from phase 7b

Not started, in the order of the ticket:

- **redstone (33 files)** — `linked_typewriter`, `redstone_accumulator`, `redstone_inductor`, `directional_receiver`, `modulating_receiver`, `analog_transmission`, `directional_gearshift`.
- **rope (19)** — `rope_winch`, `rope_connector`, the rope physics object wiring (`api/physics_rope.dart` exists in sable).
- **lasers (12)** — `laser_pointer`, `laser_sensor`, `optical_sensor` (needs `SimBlockConfig.laserPointerRange` / `opticalSensorRange`, both already in the config).
- **auger (10)** — `auger_shaft`, `auger_cog`, encasing.
- **docking (9)** — `docking_connector`, `paired_docking_connector`; needs `SimInventoryService` equivalents (battery/tank/inventory) that the host does not expose.
- **nav table (7)** — `nav_table`, `navigation_target` datapack registry, `SimNavigationTargets`.
- **sensors** — `altitude_sensor`, `gimbal_sensor`, `velocity_sensor`.
- **diagrams** — `contraption_diagram` item and its GUI (the item key is registered, the behaviour is not).
- **end sea** — the end dimension overrides.
- **misc content** — `handle`, `nameplate`, `portable_engine`, `merging_glue`, `physics_staff`, `plunger_launcher`, `absorbed` blocks.
- **`compat/` (25)** — deliberately out of scope (other mods).
- **`ponder/` (48)** — client only, out of scope.

## Host gaps that block the slice from being playable

Each is marked in the code where it happens.

1. **Constraint motors — assembler done, bearing pending.** sable's
   `PhysicsConstraintHandle` now has `setMotor`. The assembler's disassembly
   alignment uses it: `PhysicsAssembler._attachAlignmentConstraint` builds the
   spherical joint and `AssemblyAlignmentMotors` (`util/physics_constraints.dart`)
   drives the six axes each tick, so a tilted sub-level is pulled onto the grid
   instead of only being placed when it happens to be close. The swivel bearing
   still computes gains without applying them
   (`SwivelBearingLogic.motorFor` is tested): attaching its hinge needs the
   rotary joint plus the plate's sub-level, which is the same shape but has no
   caller yet.
2. **Sub-level actors inside plots** — `ServerLevelPlot.actorAt` is `null` in sable, so the spring, the swivel plate and the propeller never receive `sable$physicsTick`. The block entities implement `BlockEntitySubLevelActor`; the plot needs the plugin's store behind that hook.
3. **Honey glue as an assembly input** — `PumpkinSimAssemblyWorld.honeyGluesIn` returns nothing: the volumes are plugin entities and the tracker exists (`honeyGlueTrackerOf`), but no entity spawn/remove listener fills it yet.
4. **Sound playback** — `SimSoundIds` is filled by nobody; `playSound` is a no-op. The sound keys and their ids are registered.
5. **Neighbour redstone** — `bestNeighbourSignal` returns a cached value refreshed by nothing; the swivel bearing's lock state therefore stays at its default. `World.getBestNeighborSignal` is async and cannot be awaited from `tick()`.
6. **Entities in a box** — no box query in the plugin API, so
   `PumpkinSimAssemblyEntities.entitiesIn` filters `World.getEntities()` by the
   entity's real bounding box (shared shape with Aeronautics'
   `HostPropellerPushWorld`; both switch to a box query together when the host
   grows one). Movement and removal now work
   (`setPositionRotationDelta` carrying velocity, `Entity.remove`); only
   *spawning* a moved super glue box is a stub, because the plugin API cannot
   summon a vanilla entity type. Honey glue volumes are re-created in the
   plugin's tracker instead.
7. **Chunk serialization for plots** — sable's `PlotChunkHost` gaps (documented in sable) still apply, so a sub-level's plot chunks cannot be saved or loaded by the host.
