# Kinetics across plugin components — one network, one owner, one door

Java has **one** torque network table per level for the whole server:
`TorquePropagator.networks` is a `static Map<LevelAccessor, Map<Long, KineticNetwork>>`
(`TorquePropagator.java:11`), so a Create shaft and an Aeronautics propeller
bearing are edges of the same graph. In the port each plugin is its own wasm
component and each one compiles its own copy of `package:create`, so
`KineticsRuntime` — the block entity store, the `KineticBlockRegistry` and the
per-level network map — exists **once per component**. Measured on this port
before the wire-up (same host, same `create.wasm`):

```
create:mechanical_bearing        Size 3, Speed=16   (joined)
aeronautics:propeller_bearing    no network, speed 0
simulated:swivel_bearing         no network, speed 0
simulated:torsion_spring         no network, speed 0
simulated:steering_wheel         no network, speed 0
```

A shaft could not drive an addon's block at all: the shaft's neighbours were
looked up in Create's component, where the addon's block entity does not exist.
This is the same shape as the sub-level problem (`docs/sable-core-port.md`,
"Cross-plugin ownership") and takes the same decision.

## The decision

**Create's plugin owns the kinetic network.** It is the component that runs
`KineticsModule`: the network table, the `IRotate` rules, the stress table, the
config. Every *source of rotation* in a real setup is a Create block — water
wheel, windmill bearing, steam engine, creative motor, hand crank — and the
addons' blocks are `IRotate`s that extend Create's `KineticBlockEntity`, i.e. they
are *consumers* of that one network by design. The addons are also addons: Java
has no Aeronautics without Create.

The other components **ask** it, over one door: the IPC channel
`create.kinetics` (`lib/src/plugin/kinetics_api.dart`). Only data crosses it.

Ownership is *discovered*, not assumed: a consumer's `ping` on its first world
tick asks whether an owner is loaded (`{"op": "ping"}` → `{"ok": true,
"protocol": 1}`). Without Create the bridge stays disarmed and the component
propagates locally, which is the single-plugin case — the behaviour that existed
before this wire-up, kept as the fallback.

## The mechanism

```
 consumer component (aeronautics / simulated / offroad)      owner component (create)
 ────────────────────────────────────────────────────────    ────────────────────────
 register → the rules of its kinetic blocks, as wire defs  →  blocks.registerForeign(key, def, plugin)
          + stress values (impact / capacity / generatedRpm)   stressTable.register(...)

 attach   → {world, pos, blockKey, generatedSpeed,          →  foreign.announce(...)  → creates a
             addedStress, addedCapacity}                        ForeignKineticNode, joins the network
                                                                (RotationPropagator.handleAdded)
 detach   → {world, pos}                                   →  foreign.detach(...)

                                                           ←  apply: {world, pos, speed, source,
                                                              network, capacity, stress,
                                                              networkSize, overStressed}
 applyNetworkVerdict(...)  ←  runs in the consumer's own block entity: speedValue, source,
                              network, capacity, stress, then `onSpeedChanged` + `sendData`
```

* **A foreign node is a `KineticNode` made of data** (`lib/src/kinetics/foreign.dart`).
  The owner's propagation sees `ForeignKineticNode`, so the existing propagator,
  stress accounting and network membership work unchanged — there is no second
  propagation implementation. What the owner holds for such a node is exactly what
  the propagation reads: the connection rule (**its registered `KineticBlockDef`**),
  the scalar state (`generatedSpeed`, the two stress contributions) and the values
  it computes itself (speed, source, network, capacity, stress, size).
* **The rule crosses as data** (`lib/src/kinetics/wire_def.dart`). The owner cannot
  name an addon's def class, so the addon registers a `WireKineticDef` — a small
  rule vocabulary (axis rule + shaft rule + cog flags + kinetic flags) with a JSON
  form — **in both components**: the same object goes to its own runtime (the
  local fallback) and to the owner. One description, no drift, and a rule outside
  the vocabulary is *refused loudly* (`register` answers with the unsupported
  keys) rather than approximated: an approximated rule would connect blocks Java
  does not connect.
* **A consumer does not propagate while hosted.** `KineticLevel.hosted` is `true`,
  so `KineticNodeMixin.attachKinetics` / `detachKinetics` / `kineticRemove` /
  `kineticInitialize` / `kineticTickEnd` announce instead of building a second
  network, and a generator (`GeneratingNodeMixin.updateGeneratedRotation`) reports
  its new `generatedSpeed` instead of creating a network of its own. Its block
  entities keep ticking: the verdict arrives as the network's answer, and the
  block's own reactions (`onSpeedChanged`, `isActive`, the client NBT) run in the
  component that owns the entity.
* **The verdict is pushed once per world tick**, after that world's block entities
  ticked; only nodes whose verdict changed since the last push are sent.

## Two defects this wire-up flushed out

Neither is a design choice; both were *found by* the live measurement and are
fixed in the same change, because without them the mechanism looks like it does
not work.

1. **A component that hosts Create's content never ran the framework's per-world
   tick.** `CreatePlugin.onLoad` registers the one `worldTick` listener that runs
   `BlockEntityStore.tickWorld` (the flush of `markChanged`/`sendData`), the saved
   data and `CreateContext.onWorldTick` handlers. The addon plugins install the
   store's *event* listeners (which is why their block entities tick) but never
   that listener, so their block entities were written to the host **once**, at
   creation, and never again: `data get block` answered `Speed: 0f`,
   `NeedsSpeedUpdate: 1b` while the block entity in that component was turning at
   16 RPM. Every client-visible field of an addon block entity was frozen at its
   creation values — for a propeller bearing, the rotation the client uses.
   Fixed by `installHostedWorldTick` (`lib/src/plugin/host_module_state.dart`),
   which the addons now call; the store passed to it must be the plugin's own
   (`core.blockEntities` is a second store that was never installed, and its
   `tickWorld` flushes nothing — the first attempt at this fix passed the wrong
   one and the bearing stayed at `0f`).
2. **A generator of another component has to own a network before it propagates.**
   `GeneratingNodeMixin.applyNewSpeed` does that locally (`setSpeed` + `setNetwork`
   + `attachKinetics`); the owner has to do it for a foreign source, or its
   `_propagateNewSource` meets a sourceless node whose conveyed speed is 0 and
   destroys the block instead of driving it. `ForeignKineticNodes.announce` now
   seeds `setNetwork(kpos.packed)` and `setSpeed(generatedSpeed)` for a source.

## What it costs

* **One extra IPC round trip per node change.** A node that appears (or whose
  generator speed changes) announces itself; the owner answers with the verdict on
  the next tick, so a block that starts turning in another component turns one
  tick later than a local one. The propagation itself is unchanged and runs
  entirely in the owner.
* **A rule vocabulary to maintain.** A consumer block whose `IRotate` rule cannot
  be said in `WireKineticDef` terms is not connected across components (it is
  reported in the log, not silently mis-connected). Extending the vocabulary is
  the supported way to support such a block.
* **The owner is a single point of truth, and therefore of failure.** If the owner
  is not loaded, consumers fall back to local (partial) networks; if the owner
  unloads, `create.kinetics` requests fail and the bridge disarms.
* **No cross-component *object* sharing**, so a custom `KineticBlockEntity`
  override of `propagateRotationTo`, `isCustomConnection`, `addPropagationLocations`
  or `shaftHalvesModifier` would not be visible to the owner. Every addon block in
  the corpus uses the base implementations (the rule-driven ones): checked across
  `aeronautics/`, `simulated/` and `offroad/`, none overrides any of the four.
  A consumer that needs one must say so — an override is not representable in the
  wire protocol today, and that is the honest limit of this design.
* **The network id that a consumer's block entity stores is the owner's.** Its
  saved `Network.Id`/`Speed`/`Size` are what the owner computed, which is what the
  client reads — the fields the acceptance measurement is taken on.

## Deviations from Java, stated

1. **The owner is a plugin, not a classpath static.** Java's `TorquePropagator` is
   reachable from any mod because all of them are in one JVM; here the same table
   is reachable from any component only over IPC. Cost: a round trip, and a plugin
   that is not loaded changes the ownership question (handled by the probe).
2. **A consumer's own propagation still exists** (it is what the fallback runs). In
   a server with Create loaded it is inert — every node path goes through the
   owner — but a server with a kinetic addon and no Create keeps the old,
   component-local behaviour rather than refusing to move.
3. **The rule of an addon's block is `WireKineticDef`, not the addon's class.** The
   addon no longer has a private def implementation for its blocks
   (`simulated`'s `SwivelBearingDef` was removed in favour of
   `WireKineticDef.facingBackUnlessFlag`, and the aeronautics/offroad defs are wire
   defs too), so the two components cannot disagree — at the price of the
   vocabulary in `wire_def.dart` instead of a per-block class.

## Where the halves live

| Piece | File |
|---|---|
| The rule vocabulary + JSON form | `lib/src/kinetics/wire_def.dart` |
| A foreign node, and per-world registry + pending pushes | `lib/src/kinetics/foreign.dart` |
| Owner side: `create.kinetics` (`ping`/`register`/`update`/`detach`/`apply`) | `lib/src/plugin/kinetics_api.dart` |
| Consumer side: the bridge and `installConsumerKinetics` | `lib/src/plugin/kinetic_ipc_bridge.dart` |
| The level seams (`hosted`, `nodeAttached/Detached/Changed`) | `lib/src/kinetics/node.dart`, `runtime.dart` |
| Owner installation (channel + per-tick flush) | `lib/src/plugin/create_plugin.dart` |

## How it is proved

* Headless: `test/kinetics_across_components_test.dart` — a Create motor drives a
  foreign node, a foreign generator drives a Create shaft, an unregistered foreign
  block never connects, a detached node leaves the network, and the wire defs are
  pinned against the Create def classes they were written from (so a rule change on
  one side fails the test on the other).
* Live: `~/pumpkin-harness/kin-cross.sh` — a real server (create + aeronautics +
  simulated, scratch wasms), three columns of `creative_motor (y-62) → shaft (y-61)
  → block (y-60)`, and `data get block` on each block: the measurement the failure
  was taken with (`Network.Size`, `Speed`, `Source`).
  Result on this host (all three columns `Speed: 16f | Size: 3`, one network id per
  column, shared by its shaft):

  ```
  col x=-16 create:mechanical_bearing        Speed: 16f | Size: 3 | Id: -4398046507070L | Source: [-16,-61,0]
  col x=0   aeronautics:propeller_bearing    Speed: 16f | Size: 3 | Id: 4034L            | Source: [0,-61,0]
  col x=16  simulated:swivel_bearing         Speed: 16f | Size: 3 | Id: 4398046515138L   | Source: [16,-61,0]
  ```

  The failure this closes, on the same fields and with the same host: the first
  two columns' addon blocks answered `Speed: 0f` with no `Network` at all while
  `create:mechanical_bearing` joined (`Size 3`, `Speed 16f`).