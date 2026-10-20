// The C ABI the Dart `JoltPhysicsPipeline` calls through the core module's
// linear memory.
//
// One `World` per `PhysicsPipeline`; body/joint handles are 1-based indices into
// per-world tables (0 is always invalid, like a null pointer). Poses are doubles
// in, floats in the module's memory (Sable's `marten::Real` is `f32`; see
// `sable_rapier/src/main/rust/marten/src/lib.rs`).
//
// Every function cites the Rapier behaviour it replaces. Paths are relative to
// `sable_rapier/src/main/rust/rapier/src/` unless they start with `sable/`.
//
// Build: see `build.sh`. The module has no imports, its own memory and a
// single-threaded job system (`JobSystemSingleThreaded`); see
// `/tmp/joltspike/ADR.md` §3.
#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Body/BodyLockMulti.h>
#include <Jolt/Physics/Body/MassProperties.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayer.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CompoundShape.h>
#include <Jolt/Physics/Collision/Shape/EmptyShape.h>
#include <Jolt/Physics/Collision/Shape/MutableCompoundShape.h>
#include <Jolt/Physics/Constraints/FixedConstraint.h>
#include <Jolt/Physics/Constraints/HingeConstraint.h>
#include <Jolt/Physics/Constraints/SixDOFConstraint.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include <cstdarg>
#include <cstdint>
#include <cstdlib>
#include <new>
#include <unordered_map>
#include <unordered_set>
#include <vector>

JPH_NAMESPACE_BEGIN
// Jolt's trace sink. It may only write through `host.call`, which this module
// does not import, so diagnostics are dropped (ADR §3, "Caveats").
static void TraceImpl(const char *inFMT, ...) { (void)inFMT; }
JPH_NAMESPACE_END

using namespace JPH;

namespace {

// ---------------------------------------------------------------------------
// Object layers
//
// Rapier had two interaction groups (`groups.rs:1-9`): LEVEL_GROUP collides with
// LEVEL_GROUP|ROPE_GROUP and ROPE_GROUP with LEVEL_GROUP. Everything Sable
// creates is in LEVEL_GROUP, so "dynamic collides with dynamic and with the
// static world" is the same relation.
// ---------------------------------------------------------------------------
constexpr ObjectLayer LAYER_STATIC = 0;
constexpr ObjectLayer LAYER_DYNAMIC = 1;

class BPLayerImpl final : public BroadPhaseLayerInterface {
public:
    uint GetNumBroadPhaseLayers() const override { return 2; }
    BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer inLayer) const override {
        return BroadPhaseLayer(inLayer == LAYER_STATIC ? 0 : 1);
    }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char *GetBroadPhaseLayerName(BroadPhaseLayer inLayer) const override {
        return inLayer == BroadPhaseLayer(0) ? "STATIC" : "DYNAMIC";
    }
#endif
};

class ObjectVsBPImpl final : public ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(ObjectLayer inLayer1, BroadPhaseLayer inLayer2) const override {
        return inLayer1 == LAYER_DYNAMIC || inLayer2 == BroadPhaseLayer(1);
    }
};

class ObjectPairImpl final : public ObjectLayerPairFilter {
public:
    bool ShouldCollide(ObjectLayer a, ObjectLayer b) const override {
        return a == LAYER_DYNAMIC || b == LAYER_DYNAMIC;
    }
};

BPLayerImpl g_bp_layer;
ObjectVsBPImpl g_object_vs_bp;
ObjectPairImpl g_object_pair;

// ---------------------------------------------------------------------------
// Voxel colliders
//
// `VoxelColliderData` in `marten/src/level.rs:81-100`: per-block collision boxes
// in 0..1 voxel space, a friction multiplier, a buoyancy volume, restitution and
// a fluid flag. The registry is process-wide in Rapier (`lib.rs`, the
// `PHYSICS_STATE` static), so it is global here too; ids are 0-based in the ABI
// and 1-based once packed into a chunk word (`voxel_collider.rs:34-92`).
// ---------------------------------------------------------------------------
struct VoxelBox {
    float min[3];
    float max[3];
};

struct VoxelCollider {
    float friction = 1.0f;
    float volume = 0.0f;
    float restitution = 0.0f;
    bool fluid = false;
    std::vector<VoxelBox> boxes;
};

std::vector<VoxelCollider> g_colliders;

// The placeholder shape of a body whose blocks have not been uploaded yet
// (`EmptyShape.h:26-33` documents exactly this use). Created on first use: a
// global with a dynamic initializer would register an atexit handler from a
// static constructor, which the reactor startup path cannot run.
const Shape *g_empty_shape = nullptr;

// Voxel physics state ids, `marten/src/level.rs:137-151`:
// 0 Empty, 1 Face, 2 Edge, 3 Corner, 4 Interior.
constexpr uint8_t STATE_EMPTY = 0;
constexpr uint8_t STATE_INTERIOR = 4;

struct Key3 {
    int32_t x;
    int32_t y;
    int32_t z;

    bool operator==(const Key3 &o) const { return x == o.x && y == o.y && z == o.z; }
};

struct Key3Hash {
    size_t operator()(const Key3 &k) const {
        // Plot-yard coordinates reach ~160k and world coordinates reach ~30M,
        // so nothing may be truncated.
        uint64_t h = uint64_t(uint32_t(k.x)) * 0x9E3779B97F4A7C15ull;
        h ^= uint64_t(uint32_t(k.y)) * 0xC2B2AE3D27D4EB4Full;
        h ^= uint64_t(uint32_t(k.z)) * 0x165667B19E3779F9ull;
        h ^= h >> 29;
        return size_t(h);
    }
};

// One block that contributes collision boxes. Its index in `BodyRec::blocks` is
// stored as the Jolt sub-shape user data, so the block's boxes can be removed
// again (`MutableCompoundShape::GetSubShape(i).mUserData`).
struct BlockEntry {
    Key3 pos;
    uint32_t collider_id = 0;  // 1-based, 0 = no collider
    bool solid = false;
    bool alive = false;
};

struct BodyRec {
    BodyID id;
    uint32_t sable_id = 0;
    bool sub_level = false;
    bool dynamic = true;
    bool alive = false;
    // Sable's center of mass in plot coordinates. Sub-shapes are built at
    // `block - com`, which makes the body's Jolt origin the Sable rotation
    // point: Rapier did the same by giving the body a zero mass-properties
    // center of mass (`lib.rs:1109-1159`) and offsetting anchors by the tracked
    // center of mass (`joints.rs:63-100`, `RapierPhysicsPipeline.java:450-456`).
    Vec3 com = Vec3::sZero();
    std::vector<BlockEntry> blocks;
    std::unordered_map<Key3, uint32_t, Key3Hash> block_index;
    Ref<MutableCompoundShape> compound;
    bool has_compound = false;
};

enum class JointKind : uint32_t { Hinge = 0, Fixed = 1, SixDOF = 2 };

struct JointRec {
    JointKind kind = JointKind::Hinge;
    uint32_t body_a = 0;  // 0 = static world
    uint32_t body_b = 0;
    bool alive = false;

    // Sable's joint frame, plot-local (`joints.rs:63-100`).
    Vec3 pos_a = Vec3::sZero();
    Vec3 pos_b = Vec3::sZero();
    Vec3 axis_a = Vec3::sAxisY();
    Vec3 axis_b = Vec3::sAxisY();
    Quat rot_a = Quat::sIdentity();
    Quat rot_b = Quat::sIdentity();
    bool has_rot_a = false;
    bool has_rot_b = false;
    uint32_t locked_mask = 0;

    bool contacts_enabled = true;

    // Motor / limit state, per Jolt SixDOF axis order
    // (TranslationX, Y, Z, RotationX, Y, Z), which is Rapier's `JointAxis`
    // order too (`joints.rs:105-112`).
    bool motor_on[6] = {};
    float motor_target[6] = {};
    float motor_frequency[6] = {};
    float motor_damping[6] = {};
    bool motor_has_max_force[6] = {};
    float motor_max_force[6] = {};
    bool limit_on[6] = {};
    float limit_min[6] = {};
    float limit_max[6] = {};

    Constraint *constraint = nullptr;  // owned by the constraint manager
};

struct World {
    TempAllocatorImpl *temp = nullptr;
    JobSystemSingleThreaded *jobs = nullptr;
    PhysicsSystem *physics = nullptr;
    class ContactListenerImpl *listener = nullptr;

    Vec3 gravity = Vec3(0.0f, -9.81f, 0.0f);
    float drag = 0.0f;

    std::vector<BodyRec> bodies;  // handle = index + 1
    std::vector<uint32_t> free_bodies;
    std::vector<JointRec> joints;  // handle = index + 1
    std::vector<uint32_t> free_joints;

    BodyRec ground;  // the static level body
    std::unordered_set<uint64_t> disabled_pairs;
};

inline uint64_t pairKey(const Body &a, const Body &b) {
    uint64_t ia = a.GetID().GetIndexAndSequenceNumber();
    uint64_t ib = b.GetID().GetIndexAndSequenceNumber();
    return ia < ib ? (ia << 32) | ib : (ib << 32) | ia;
}

// `jolt_joint_set_contacts_enabled`: Jolt has no per-body-pair collision switch,
// so contacts between the two bodies of a joint are rejected in
// `OnContactValidate` (the Jolt-idiomatic place for pair filtering).
class ContactListenerImpl final : public ContactListener {
public:
    World *world = nullptr;

    ValidateResult OnContactValidate(const Body &inBody1, const Body &inBody2, RVec3Arg,
                                     const CollideShapeResult &) override {
        if (world->disabled_pairs.count(pairKey(inBody1, inBody2)) != 0) {
            return ValidateResult::RejectAllContactsForThisBodyPair;
        }
        return ValidateResult::AcceptAllContactsForThisBodyPair;
    }

    // `SablePhysicsHooks::modify_solver_contacts` multiplies the contact
    // friction by the block's multiplier and raises its restitution
    // (`hooks.rs:23-120`: `contact.friction *= friction_multiplier`,
    // `contact.restitution = contact.restitution.max(restitution)`). Jolt
    // exposes the same two values per manifold in `ContactSettings`.
    void OnContactAdded(const Body &inBody1, const Body &inBody2,
                        const ContactManifold &inManifold,
                        ContactSettings &ioSettings) override {
        applyBlockMaterial(inBody1, inManifold.mSubShapeID1, ioSettings);
        applyBlockMaterial(inBody2, inManifold.mSubShapeID2, ioSettings);
    }

private:
    static void applyBlockMaterial(const Body &inBody, SubShapeID inSubShape,
                                   ContactSettings &ioSettings) {
        const uint32_t collider_id = colliderIdOf(inBody, inSubShape);
        if (collider_id == 0 || collider_id > g_colliders.size()) {
            return;
        }
        const VoxelCollider &collider = g_colliders[collider_id - 1];
        ioSettings.mCombinedFriction *= collider.friction;
        if (collider.restitution > ioSettings.mCombinedRestitution) {
            ioSettings.mCombinedRestitution = collider.restitution;
        }
    }

    static uint32_t colliderIdOf(const Body &inBody, SubShapeID inSubShape) {
        const Shape *shape = inBody.GetShape();
        if (shape->GetSubType() != EShapeSubType::MutableCompound) {
            return 0;
        }
        const CompoundShape *compound = static_cast<const CompoundShape *>(shape);
        if (!compound->IsSubShapeIDValid(inSubShape)) {
            return 0;
        }
        SubShapeID remainder;
        const uint32_t index = compound->GetSubShapeIndexFromID(inSubShape, remainder);
        if (index >= compound->GetNumSubShapes()) {
            return 0;
        }
        return compound->GetSubShape(index).mUserData;
    }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
World *worldOf(uint32_t handle) {
    return reinterpret_cast<World *>(static_cast<uintptr_t>(handle));
}

BodyRec *bodyOf(World *w, uint32_t handle) {
    if (w == nullptr || handle == 0 || handle > w->bodies.size()) {
        return nullptr;
    }
    BodyRec &rec = w->bodies[handle - 1];
    return rec.alive ? &rec : nullptr;
}

JointRec *jointOf(World *w, uint32_t handle) {
    if (w == nullptr || handle == 0 || handle > w->joints.size()) {
        return nullptr;
    }
    JointRec &rec = w->joints[handle - 1];
    return rec.alive ? &rec : nullptr;
}

uint32_t allocBodySlot(World *w, const BodyRec &rec) {
    if (!w->free_bodies.empty()) {
        uint32_t index = w->free_bodies.back();
        w->free_bodies.pop_back();
        w->bodies[index] = rec;
        return index + 1;
    }
    w->bodies.push_back(rec);
    return uint32_t(w->bodies.size());
}

uint32_t allocJointSlot(World *w, const JointRec &rec) {
    if (!w->free_joints.empty()) {
        uint32_t index = w->free_joints.back();
        w->free_joints.pop_back();
        w->joints[index] = rec;
        return index + 1;
    }
    w->joints.push_back(rec);
    return uint32_t(w->joints.size());
}

// `joints.rs:105-112`: Rapier's `JointAxesMask` bit order.
inline bool axisLocked(uint32_t mask, int axis) { return (mask & (1u << axis)) != 0; }

// A rotation as Jolt's two-axis constraint frame.
void frameAxes(QuatArg inRotation, Vec3 &out_x, Vec3 &out_y) {
    out_x = inRotation * Vec3::sAxisX();
    out_y = inRotation * Vec3::sAxisY();
}

// A unit vector perpendicular to `inAxis`, used as the hinge's normal axis.
Vec3 perpendicular(QuatArg inRotation, Vec3Arg inAxis) {
    Vec3 candidate = inRotation * Vec3::sAxisZ();
    Vec3 perp = candidate - inAxis * candidate.Dot(inAxis);
    if (perp.LengthSq() < 1.0e-6f) {
        candidate = inRotation * Vec3::sAxisX();
        perp = candidate - inAxis * candidate.Dot(inAxis);
    }
    if (perp.LengthSq() < 1.0e-6f) {
        candidate = inRotation * Vec3::sAxisY();
        perp = candidate - inAxis * candidate.Dot(inAxis);
    }
    return perp.Normalized();
}

MassProperties massPropertiesOf(float inMass, const float *inInertia) {
    MassProperties mp;
    mp.mMass = inMass > 0.0f ? inMass : 1.0f;
    mp.mInertia = Mat44::sZero();
    if (inInertia != nullptr) {
        for (int column = 0; column < 3; ++column) {
            mp.mInertia.SetColumn4(column, Vec4(inInertia[column * 3], inInertia[column * 3 + 1],
                                                inInertia[column * 3 + 2], 0.0f));
        }
    }
    mp.mInertia.SetColumn4(3, Vec4(0.0f, 0.0f, 0.0f, 1.0f));
    // A degenerate tensor (a tracker that has not scanned the plot yet) would
    // make `SetMassProperties` divide by zero; keep the body solvable instead.
    if (!(mp.mInertia.GetDiagonal3().ReduceMin() > 0.0f)) {
        const float i = 0.4f * mp.mMass;
        mp.mInertia = Mat44::sScale(Vec3(i, i, i));
        mp.mInertia.SetColumn4(3, Vec4(0.0f, 0.0f, 0.0f, 1.0f));
    }
    return mp;
}

Ref<MutableCompoundShape> buildCompound(const BodyRec &rec) {
    Ref<MutableCompoundShape> compound = new MutableCompoundShape();
    for (uint32_t i = 0; i < rec.blocks.size(); ++i) {
        const BlockEntry &block = rec.blocks[i];
        if (!block.alive || !block.solid || block.collider_id == 0 ||
            block.collider_id > g_colliders.size()) {
            continue;
        }
        const VoxelCollider &collider = g_colliders[block.collider_id - 1];
        const Vec3 origin{float(block.pos.x), float(block.pos.y), float(block.pos.z)};
        for (const VoxelBox &box : collider.boxes) {
            const Vec3 lo(box.min[0], box.min[1], box.min[2]);
            const Vec3 hi(box.max[0], box.max[1], box.max[2]);
            const Vec3 half = (hi - lo) * 0.5f;
            if (half.ReduceMin() <= 0.0f) {
                continue;
            }
            // Density is irrelevant: the body's mass and inertia come from
            // Sable (`jolt_body_set_mass`, `lib.rs:1109-1159`), and a zero-mass
            // compound keeps `GetCenterOfMass()` at the origin so the shape's
            // local space is exactly `block - com`.
            Ref<BoxShape> shape = new BoxShape(half);
            compound->AddShape(origin - rec.com + (lo + hi) * 0.5f, Quat::sIdentity(), shape,
                               block.collider_id);
        }
    }
    return compound;
}

// A body's shape is rebuilt from its blocks, offset by its center of mass.
// Rebuilding is O(blocks) and only runs on bulk changes (chunk add/remove, a new
// center of mass) and on single-block changes (`addBlockShapes` /
// `removeBlockShapes` do those incrementally).
void rebuildShape(World *w, BodyRec &rec) {
    BodyInterface &bi = w->physics->GetBodyInterface();
    const EActivation activation = rec.dynamic ? EActivation::Activate : EActivation::DontActivate;

    if (rec.blocks.empty()) {
        if (rec.has_compound) {
            rec.compound = nullptr;
            rec.has_compound = false;
            bi.SetShape(rec.id, g_empty_shape, false, activation);
        }
        return;
    }

    Ref<MutableCompoundShape> compound = buildCompound(rec);
    rec.compound = compound;
    rec.has_compound = true;
    // `SetShape` updates the broadphase and the body's bounding box, unlike
    // mutating the shape in place (`BodyInterface.h:167-176`).
    bi.SetShape(rec.id, compound, false, activation);
}

void addBlockShapes(World *w, BodyRec &rec, uint32_t block_index) {
    if (!rec.has_compound) {
        rebuildShape(w, rec);
        return;
    }
    BlockEntry &block = rec.blocks[block_index];
    if (!block.alive || !block.solid) {
        return;
    }
    const VoxelCollider &collider = g_colliders[block.collider_id - 1];
    const Vec3 origin{float(block.pos.x), float(block.pos.y), float(block.pos.z)};
    for (const VoxelBox &box : collider.boxes) {
        const Vec3 lo(box.min[0], box.min[1], box.min[2]);
        const Vec3 hi(box.max[0], box.max[1], box.max[2]);
        const Vec3 half = (hi - lo) * 0.5f;
        if (half.ReduceMin() <= 0.0f) {
            continue;
        }
        Ref<BoxShape> shape = new BoxShape(half);
        rec.compound->AddShape(origin - rec.com + (lo + hi) * 0.5f, Quat::sIdentity(), shape,
                               block.collider_id);
    }
    w->physics->GetBodyInterface().NotifyShapeChanged(rec.id, rec.com, false,
                                                      EActivation::Activate);
}

// Removes every sub-shape whose user data is `block_index`. Sub-shape indices
// shift when one is removed, so the scan collects indices first and removes
// them from the back (`MutableCompoundShape::RemoveShape`).
void removeBlockShapes(World *w, BodyRec &rec, uint32_t block_index) {
    if (!rec.has_compound) {
        return;
    }
    std::vector<uint32_t> indices;
    const uint32_t count = rec.compound->GetNumSubShapes();
    for (uint32_t i = 0; i < count; ++i) {
        if (rec.compound->GetSubShape(i).mUserData == block_index) {
            indices.push_back(i);
        }
    }
    if (indices.empty()) {
        return;
    }
    for (auto it = indices.rbegin(); it != indices.rend(); ++it) {
        rec.compound->RemoveShape(*it);
    }
    if (rec.compound->GetNumSubShapes() == 0) {
        rec.compound = nullptr;
        rec.has_compound = false;
        w->physics->GetBodyInterface().SetShape(rec.id, g_empty_shape, false,
                                               EActivation::DontActivate);
        return;
    }
    w->physics->GetBodyInterface().NotifyShapeChanged(rec.id, rec.com, false,
                                                      EActivation::Activate);
}

// A packed chunk word is `(colliderId + 1) << 16 | voxelState`
// (`lib.rs:796-925`, `RapierPhysicsPipeline.java:335-356`).
struct PackedBlock {
    uint32_t collider_id;
    uint8_t state;
};

PackedBlock unpack(uint32_t inPacked) {
    PackedBlock block;
    block.collider_id = inPacked >> 16;
    block.state = uint8_t(inPacked & 0xFFFF);
    return block;
}

// `lib.rs:761-793` (`insert_block_octree`): a block is solid when its
// neighbourhood state is neither Empty nor Interior, it has a collider and that
// collider has at least one collision box.
bool isSolid(const PackedBlock &inBlock) {
    if (inBlock.state == STATE_EMPTY || inBlock.state == STATE_INTERIOR) {
        return false;
    }
    if (inBlock.collider_id == 0 || inBlock.collider_id > g_colliders.size()) {
        return false;
    }
    return !g_colliders[inBlock.collider_id - 1].boxes.empty();
}

void setBlock(World *w, BodyRec &rec, const Key3 &pos, const PackedBlock &inBlock) {
    const bool solid = isSolid(inBlock);
    auto it = rec.block_index.find(pos);
    if (it != rec.block_index.end()) {
        const uint32_t index = it->second;
        BlockEntry &existing = rec.blocks[index];
        if (existing.collider_id != inBlock.collider_id || existing.solid != solid) {
            removeBlockShapes(w, rec, index);
            existing.collider_id = inBlock.collider_id;
            existing.solid = solid;
            existing.alive = true;
            addBlockShapes(w, rec, index);
        }
        return;
    }
    if (!solid) {
        return;
    }
    BlockEntry entry;
    entry.pos = pos;
    entry.collider_id = inBlock.collider_id;
    entry.solid = true;
    entry.alive = true;
    const uint32_t index = uint32_t(rec.blocks.size());
    rec.blocks.push_back(entry);
    rec.block_index.emplace(pos, index);
    addBlockShapes(w, rec, index);
}

void eraseBlock(World *w, BodyRec &rec, const Key3 &pos) {
    auto it = rec.block_index.find(pos);
    if (it == rec.block_index.end()) {
        return;
    }
    const uint32_t index = it->second;
    removeBlockShapes(w, rec, index);
    rec.blocks[index].alive = false;
    rec.blocks[index].solid = false;
    rec.block_index.erase(it);
}

SpringSettings springOf(float inFrequency, float inDamping) {
    // `config.rs:8-12`: 550 Hz / damping ratio 4 for joints. A motor configured
    // with a non-positive frequency would make Jolt assert.
    const float frequency = inFrequency > 0.0f ? inFrequency : 550.0f;
    const float damping = inDamping >= 0.0f ? inDamping : 4.0f;
    return SpringSettings(ESpringMode::FrequencyAndDamping, frequency, damping);
}

Constraint *buildConstraint(World *w, JointRec &rec) {
    BodyRec *rec_a = rec.body_a == 0 ? &w->ground : bodyOf(w, rec.body_a);
    BodyRec *rec_b = rec.body_b == 0 ? &w->ground : bodyOf(w, rec.body_b);
    if (rec_a == nullptr || rec_b == nullptr) {
        return nullptr;
    }

    BodyID ids[2] = {rec_a->id, rec_b->id};
    BodyLockMultiWrite lock(w->physics->GetBodyLockInterface(), ids, 2);
    Body *body_a = lock.GetBody(0);
    Body *body_b = lock.GetBody(1);
    if (body_a == nullptr || body_b == nullptr) {
        return nullptr;
    }

    // Anchors are plot-local positions minus the tracked center of mass
    // (`joints.rs:63-100`), which is the body's local origin here.
    const Vec3 pos_a = rec.pos_a - rec_a->com;
    const Vec3 pos_b = rec.pos_b - rec_b->com;

    switch (rec.kind) {
        case JointKind::Hinge: {
            HingeConstraintSettings settings;
            settings.mSpace = EConstraintSpace::LocalToBodyCOM;
            settings.mPoint1 = RVec3(pos_a);
            settings.mPoint2 = RVec3(pos_b);
            settings.mHingeAxis1 = rec.axis_a.Normalized();
            settings.mHingeAxis2 = rec.axis_b.Normalized();
            settings.mNormalAxis1 = perpendicular(rec.rot_a, settings.mHingeAxis1);
            settings.mNormalAxis2 = perpendicular(rec.rot_b, settings.mHingeAxis2);
            settings.mMotorSettings.mSpringSettings = springOf(0.0f, 0.0f);
            if (rec.limit_on[5]) {
                settings.mLimitsMin = rec.limit_min[5];
                settings.mLimitsMax = rec.limit_max[5];
            }
            if (rec.motor_on[5]) {
                settings.mMotorSettings.mSpringSettings =
                    springOf(rec.motor_frequency[5], rec.motor_damping[5]);
                if (rec.motor_has_max_force[5]) {
                    settings.mMotorSettings.SetTorqueLimit(rec.motor_max_force[5]);
                }
            }
            HingeConstraint *hinge =
                static_cast<HingeConstraint *>(settings.Create(*body_a, *body_b));
            if (hinge != nullptr && rec.motor_on[5]) {
                hinge->SetMotorState(EMotorState::Position);
                hinge->SetTargetAngle(rec.motor_target[5]);
            }
            return hinge;
        }
        case JointKind::Fixed: {
            FixedConstraintSettings settings;
            settings.mSpace = EConstraintSpace::LocalToBodyCOM;
            settings.mPoint1 = RVec3(pos_a);
            settings.mPoint2 = RVec3(pos_b);
            Vec3 x_a, y_a, x_b, y_b;
            frameAxes(rec.has_rot_a ? rec.rot_a : Quat::sIdentity(), x_a, y_a);
            frameAxes(rec.has_rot_b ? rec.rot_b : Quat::sIdentity(), x_b, y_b);
            settings.mAxisX1 = x_a;
            settings.mAxisY1 = y_a;
            settings.mAxisX2 = x_b;
            settings.mAxisY2 = y_b;
            return settings.Create(*body_a, *body_b);
        }
        case JointKind::SixDOF: {
            SixDOFConstraintSettings settings;
            settings.mSpace = EConstraintSpace::LocalToBodyCOM;
            settings.mPosition1 = RVec3(pos_a);
            settings.mPosition2 = RVec3(pos_b);
            Vec3 x_a, y_a, x_b, y_b;
            frameAxes(rec.has_rot_a ? rec.rot_a : Quat::sIdentity(), x_a, y_a);
            frameAxes(rec.has_rot_b ? rec.rot_b : Quat::sIdentity(), x_b, y_b);
            settings.mAxisX1 = x_a;
            settings.mAxisY1 = y_a;
            settings.mAxisX2 = x_b;
            settings.mAxisY2 = y_b;
            for (int axis = 0; axis < 6; ++axis) {
                const auto e = SixDOFConstraintSettings::EAxis(axis);
                if (axisLocked(rec.locked_mask, axis)) {
                    // A locked axis is driven to 0 (`MakeFixedAxis`).
                    settings.MakeFixedAxis(e);
                }
                if (rec.limit_on[axis]) {
                    settings.SetLimitedAxis(e, rec.limit_min[axis], rec.limit_max[axis]);
                }
                if (rec.motor_on[axis]) {
                    settings.mMotorSettings[axis].mSpringSettings =
                        springOf(rec.motor_frequency[axis], rec.motor_damping[axis]);
                    if (rec.motor_has_max_force[axis]) {
                        if (axis < 3) {
                            settings.mMotorSettings[axis].SetForceLimit(rec.motor_max_force[axis]);
                        } else {
                            settings.mMotorSettings[axis].SetTorqueLimit(rec.motor_max_force[axis]);
                        }
                    }
                }
            }
            SixDOFConstraint *six =
                static_cast<SixDOFConstraint *>(settings.Create(*body_a, *body_b));
            if (six != nullptr) {
                for (int axis = 0; axis < 6; ++axis) {
                    if (!rec.motor_on[axis]) {
                        continue;
                    }
                    const auto e = SixDOFConstraintSettings::EAxis(axis);
                    six->SetMotorState(e, EMotorState::Position);
                    if (axis < 3) {
                        Vec3 target = six->GetTargetPositionCS();
                        target.SetComponent(axis, rec.motor_target[axis]);
                        six->SetTargetPositionCS(target);
                    } else {
                        // Rotation motors act on body 2's constraint space; a
                        // single-axis target is applied through the Euler
                        // decomposition Jolt exposes.
                        const Vec3 angles = six->GetTargetOrientationCS().GetEulerAngles();
                        Vec3 target = angles;
                        target.SetComponent(axis - 3, rec.motor_target[axis]);
                        six->SetTargetOrientationCS(Quat::sEulerAngles(target));
                    }
                }
            }
            return six;
        }
    }
    return nullptr;
}

void destroyConstraint(World *w, JointRec &rec) {
    if (rec.constraint != nullptr) {
        w->physics->RemoveConstraint(rec.constraint);
        rec.constraint = nullptr;
    }
}

// Rebuilds a joint's constraint from its recorded frame. Jolt's constraint
// frames are immutable after creation (only limits and motors have setters), so
// a frame change recreates it. `joints::tick` (`joints.rs:53-101`) rewrites the
// frames every tick, so this only runs when a value actually changed.
bool refreshConstraint(World *w, JointRec &rec) {
    destroyConstraint(w, rec);
    Constraint *constraint = buildConstraint(w, rec);
    if (constraint == nullptr) {
        return false;
    }
    rec.constraint = constraint;
    w->physics->AddConstraint(constraint);
    return true;
}

void updateDisabledPair(World *w, JointRec &rec) {
    if (rec.body_a == 0 || rec.body_b == 0) {
        return;
    }
    BodyRec *a = bodyOf(w, rec.body_a);
    BodyRec *b = bodyOf(w, rec.body_b);
    if (a == nullptr || b == nullptr) {
        return;
    }
    const Body *body_a = w->physics->GetBodyLockInterface().TryGetBody(a->id);
    const Body *body_b = w->physics->GetBodyLockInterface().TryGetBody(b->id);
    if (body_a == nullptr || body_b == nullptr) {
        return;
    }
    const uint64_t key = pairKey(*body_a, *body_b);
    if (rec.contacts_enabled) {
        w->disabled_pairs.erase(key);
    } else {
        w->disabled_pairs.insert(key);
    }
}

}  // namespace

// ---------------------------------------------------------------------------
// Build-level shims (see ADR §3): wasi-libc++ routes a few error paths through
// WASI imports this module must not have.
// ---------------------------------------------------------------------------
extern "C" int sched_yield(void) { return 0; }

namespace std {
inline namespace __2 {
[[noreturn]] void __libcpp_verbose_abort(const char *, ...) noexcept { __builtin_trap(); }
}  // namespace __2
}  // namespace std

extern "C" [[noreturn]] void __cxa_pure_virtual() { __builtin_trap(); }
extern "C" [[noreturn]] void __cxa_deleted_virtual() { __builtin_trap(); }

void *operator new(std::size_t n) {
    void *p = std::malloc(n ? n : 1);
    if (p == nullptr) __builtin_trap();
    return p;
}
void *operator new[](std::size_t n) { return ::operator new(n); }
void *operator new(std::size_t n, std::align_val_t a) {
    void *p = std::aligned_alloc(static_cast<std::size_t>(a), n ? n : 1);
    if (p == nullptr) __builtin_trap();
    return p;
}
void *operator new[](std::size_t n, std::align_val_t a) { return ::operator new(n, a); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete[](void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }
void operator delete[](void *p, std::size_t) noexcept { std::free(p); }
void operator delete(void *p, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void *p, std::align_val_t) noexcept { std::free(p); }
void operator delete(void *p, std::size_t, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void *p, std::size_t, std::align_val_t) noexcept { std::free(p); }

// Jolt formats diagnostics through vsnprintf; wasi-libc's implementation pulls
// stdio (and therefore WASI imports).
extern "C" int vsnprintf(char *buf, std::size_t n, const char *, va_list) {
    if (n > 0) buf[0] = '\0';
    return 0;
}

// ---------------------------------------------------------------------------
// The ABI
// ---------------------------------------------------------------------------
extern "C" {

__attribute__((export_name("jolt_abi_version"))) uint32_t jolt_abi_version() { return 1u; }

__attribute__((export_name("jolt_version"))) uint32_t jolt_version() { return JPH_VERSION_ID; }

__attribute__((export_name("jolt_alloc"))) uint32_t jolt_alloc(uint32_t inBytes) {
    return uint32_t(uintptr_t(std::malloc(inBytes ? inBytes : 1)));
}

__attribute__((export_name("jolt_free"))) void jolt_free(uint32_t inPtr) {
    std::free(reinterpret_cast<void *>(uintptr_t(inPtr)));
}

// ---- Scene lifecycle ------------------------------------------------------

__attribute__((export_name("jolt_world_create"))) uint32_t jolt_world_create(double gx, double gy,
                                                                            double gz, double drag) {
    RegisterDefaultAllocator();
    if (Factory::sInstance == nullptr) {
        Factory::sInstance = new Factory();
        RegisterTypes();
    }
    if (g_empty_shape == nullptr) {
        g_empty_shape = new EmptyShape();
    }

    World *w = new World();
    w->gravity = Vec3(float(gx), float(gy), float(gz));
    w->drag = float(drag);
    w->temp = new TempAllocatorImpl(16 * 1024 * 1024);
    w->jobs = new JobSystemSingleThreaded(256);
    w->physics = new PhysicsSystem();
    w->physics->Init(4096, 0, 16384, 16384, g_bp_layer, g_object_vs_bp, g_object_pair);
    w->physics->SetGravity(w->gravity);

    // `lib.rs:372-386`: 18 solver iterations / 2 PGS / 2 stabilization
    // (`PhysicsConfigData.java:8-34`).
    PhysicsSettings settings = w->physics->GetPhysicsSettings();
    settings.mNumVelocitySteps = 18;
    settings.mNumPositionSteps = 2;
    // `lib.rs:644-660`: activation threshold 0.15 on sub-level bodies. Jolt's
    // sleep threshold is global, so it carries the same value.
    settings.mPointVelocitySleepThreshold = 0.15f;
    w->physics->SetPhysicsSettings(settings);

    w->listener = new ContactListenerImpl();
    w->listener->world = w;
    w->physics->SetContactListener(w->listener);

    // The static level body (`initialize`, `lib.rs:390-440`). Its shape starts
    // empty and is filled from global chunk sections; it never moves.
    BodyCreationSettings ground(new EmptyShape(), RVec3::sZero(), Quat::sIdentity(),
                                EMotionType::Static, LAYER_STATIC);
    ground.mFriction = 0.525f;
    w->ground.id = w->physics->GetBodyInterface().CreateAndAddBody(ground,
                                                                  EActivation::DontActivate);
    w->ground.dynamic = false;
    w->ground.alive = true;

    return uint32_t(uintptr_t(w));
}

__attribute__((export_name("jolt_world_destroy"))) void jolt_world_destroy(uint32_t inWorld) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    for (BodyRec &rec : w->bodies) {
        if (!rec.alive) {
            continue;
        }
        bi.RemoveBody(rec.id);
        bi.DestroyBody(rec.id);
        rec.alive = false;
    }
    for (JointRec &rec : w->joints) {
        destroyConstraint(w, rec);
        rec.alive = false;
    }
    bi.RemoveBody(w->ground.id);
    bi.DestroyBody(w->ground.id);
    w->physics->SetContactListener(nullptr);
    delete w->listener;
    delete w->physics;
    delete w->jobs;
    delete w->temp;
    delete w;
}

__attribute__((export_name("jolt_world_set_gravity"))) void jolt_world_set_gravity(
    uint32_t inWorld, double gx, double gy, double gz) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    w->gravity = Vec3(float(gx), float(gy), float(gz));
    w->physics->SetGravity(w->gravity);
}

__attribute__((export_name("jolt_world_set_drag"))) void jolt_world_set_drag(uint32_t inWorld,
                                                                             double inDrag) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    // `lib.rs:668-700`: damping is set when a sub-level body is created, so
    // this affects bodies created afterwards.
    w->drag = float(inDrag);
}

__attribute__((export_name("jolt_world_set_solver"))) void jolt_world_set_solver(
    uint32_t inWorld, int32_t inVelocitySteps, int32_t inPositionSteps) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    PhysicsSettings settings = w->physics->GetPhysicsSettings();
    if (inVelocitySteps > 0) {
        settings.mNumVelocitySteps = uint(inVelocitySteps);
    }
    if (inPositionSteps > 0) {
        settings.mNumPositionSteps = uint(inPositionSteps);
    }
    w->physics->SetPhysicsSettings(settings);
}

// `lib.rs:511-552`: one `pipeline.step` per call; Sable drives the substeps
// (`RapierPhysicsPipeline.java:157-170`).
__attribute__((export_name("jolt_world_step"))) void jolt_world_step(uint32_t inWorld,
                                                                     double inTimeStep) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    w->physics->Update(float(inTimeStep), 1, w->temp, w->jobs);
}

// ---- Bodies ---------------------------------------------------------------

__attribute__((export_name("jolt_sublevel_create"))) uint32_t jolt_sublevel_create(
    uint32_t inWorld, uint32_t inSableId, double px, double py, double pz, double qx, double qy,
    double qz, double qw) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return 0;
    }
    BodyCreationSettings settings(new EmptyShape(), RVec3(px, py, pz),
                                  Quat(float(qx), float(qy), float(qz), float(qw)),
                                  EMotionType::Dynamic, LAYER_DYNAMIC);
    // `lib.rs:644-700`: CCD on, gyroscopic forces on, damping = universal drag,
    // friction 0.525 (`lib.rs:690-698`).
    settings.mMotionQuality = EMotionQuality::LinearCast;
    settings.mApplyGyroscopicForce = true;
    settings.mLinearDamping = w->drag;
    settings.mAngularDamping = w->drag;
    settings.mFriction = 0.525f;
    settings.mRestitution = 0.0f;
    settings.mAllowSleeping = true;
    settings.mOverrideMassProperties = EOverrideMassProperties::MassAndInertiaProvided;
    settings.mMassPropertiesOverride = massPropertiesOf(1.0f, nullptr);

    BodyID id = w->physics->GetBodyInterface().CreateAndAddBody(settings,
                                                               EActivation::DontActivate);
    if (id.IsInvalid()) {
        return 0;
    }

    BodyRec rec;
    rec.id = id;
    rec.sable_id = inSableId;
    rec.sub_level = true;
    rec.dynamic = true;
    rec.alive = true;
    return allocBodySlot(w, rec);
}

__attribute__((export_name("jolt_box_create"))) uint32_t jolt_box_create(
    uint32_t inWorld, uint32_t inSableId, double inMass, double hx, double hy, double hz, double px,
    double py, double pz, double qx, double qy, double qz, double qw) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return 0;
    }
    // `boxes.rs:28-70`: cuboid, mass, friction 0.45, CCD on.
    BodyCreationSettings settings(new BoxShape(Vec3(float(hx), float(hy), float(hz))),
                                  RVec3(px, py, pz),
                                  Quat(float(qx), float(qy), float(qz), float(qw)),
                                  EMotionType::Dynamic, LAYER_DYNAMIC);
    settings.mFriction = 0.45f;
    settings.mRestitution = 0.0f;
    // Rapier's dynamic bodies have zero damping unless a body sets it
    // (`RigidBodyBuilder::dynamic()`); Sable only sets it on sub-levels
    // (`lib.rs:668-700`).
    settings.mMotionQuality = EMotionQuality::LinearCast;
    // Scale the shape's own inertia to the requested mass
    // (`CalculateInertia`): the cuboid's tensor is what Rapier used
    // (`ColliderBuilder::cuboid(...).mass(mass)`, `boxes.rs:55-62`).
    settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
    settings.mMassPropertiesOverride.mMass = inMass > 0.0 ? float(inMass) : 1.0f;
    settings.mLinearDamping = 0.0f;
    settings.mAngularDamping = 0.0f;

    BodyID id = w->physics->GetBodyInterface().CreateAndAddBody(settings, EActivation::Activate);
    if (id.IsInvalid()) {
        return 0;
    }

    BodyRec rec;
    rec.id = id;
    rec.sable_id = inSableId;
    rec.dynamic = true;
    rec.alive = true;
    return allocBodySlot(w, rec);
}

__attribute__((export_name("jolt_body_destroy"))) void jolt_body_destroy(uint32_t inWorld,
                                                                         uint32_t inBody) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    // Any joint that references the body dies with it (`removeSubLevel`,
    // `lib.rs:717-760`).
    for (uint32_t i = 0; i < w->joints.size(); ++i) {
        JointRec &joint = w->joints[i];
        if (!joint.alive || (joint.body_a != inBody && joint.body_b != inBody)) {
            continue;
        }
        destroyConstraint(w, joint);
        joint.alive = false;
        w->free_joints.push_back(i);
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    bi.RemoveBody(rec->id);
    bi.DestroyBody(rec->id);
    rec->alive = false;
    rec->blocks.clear();
    rec->block_index.clear();
    rec->compound = nullptr;
    rec->has_compound = false;
    w->free_bodies.push_back(inBody - 1);
}

__attribute__((export_name("jolt_body_is_valid"))) int32_t jolt_body_is_valid(uint32_t inWorld,
                                                                              uint32_t inBody) {
    return bodyOf(worldOf(inWorld), inBody) != nullptr ? 1 : 0;
}

__attribute__((export_name("jolt_body_set_pose"))) void jolt_body_set_pose(
    uint32_t inWorld, uint32_t inBody, double px, double py, double pz, double qx, double qy,
    double qz, double qw) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    // `teleportObject` (`lib.rs:1161-1189`): move and wake.
    w->physics->GetBodyInterface().SetPositionAndRotation(
        rec->id, RVec3(px, py, pz), Quat(float(qx), float(qy), float(qz), float(qw)),
        EActivation::Activate);
}

// Writes `position.xyz, orientation.xyzw` as seven f32 into `out` (`getPose`,
// `lib.rs:554-581`). The center of mass position equals Sable's pose position
// because the shape is built relative to the center of mass.
__attribute__((export_name("jolt_body_get_pose"))) void jolt_body_get_pose(uint32_t inWorld,
                                                                           uint32_t inBody,
                                                                           uint32_t out) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    const RVec3 position = bi.GetCenterOfMassPosition(rec->id);
    const Quat rotation = bi.GetRotation(rec->id);
    float *dest = reinterpret_cast<float *>(uintptr_t(out));
    dest[0] = float(position.GetX());
    dest[1] = float(position.GetY());
    dest[2] = float(position.GetZ());
    dest[3] = rotation.GetX();
    dest[4] = rotation.GetY();
    dest[5] = rotation.GetZ();
    dest[6] = rotation.GetW();
}

__attribute__((export_name("jolt_body_set_com"))) void jolt_body_set_com(uint32_t inWorld,
                                                                         uint32_t inBody,
                                                                         double x, double y,
                                                                         double z) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    const Vec3 com{float(x), float(y), float(z)};
    if ((com - rec->com).LengthSq() < 1.0e-12f) {
        return;
    }
    rec->com = com;
    // The shape is stored as `block - com`, so a new center of mass moves every
    // sub-shape (`setCenterOfMass`, `lib.rs:583-605`).
    rebuildShape(w, *rec);
}

// `setMassProperties` (`lib.rs:1109-1159`): explicit mass and inertia tensor,
// center of mass at the body origin.
__attribute__((export_name("jolt_body_set_mass"))) void jolt_body_set_mass(uint32_t inWorld,
                                                                           uint32_t inBody,
                                                                           double inMass,
                                                                           uint32_t inInertia) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    const float *inertia = inInertia != 0 ? reinterpret_cast<const float *>(uintptr_t(inInertia))
                                          : nullptr;
    const MassProperties mp = massPropertiesOf(float(inMass), inertia);
    BodyLockWrite lock(w->physics->GetBodyLockInterface(), rec->id);
    Body *body = &lock.GetBody();
    if (body == nullptr || body->GetMotionProperties() == nullptr) {
        return;
    }
    body->GetMotionProperties()->SetMassProperties(EAllowedDOFs::All, mp);
}

__attribute__((export_name("jolt_body_wake"))) void jolt_body_wake(uint32_t inWorld,
                                                                   uint32_t inBody) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    w->physics->GetBodyInterface().ActivateBody(rec->id);
}

__attribute__((export_name("jolt_body_is_active"))) int32_t jolt_body_is_active(uint32_t inWorld,
                                                                                uint32_t inBody) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return 0;
    }
    return w->physics->GetBodyInterface().IsActive(rec->id) ? 1 : 0;
}

// `addLinearAngularVelocities` (`lib.rs:1208-1248`).
__attribute__((export_name("jolt_body_add_velocities"))) void jolt_body_add_velocities(
    uint32_t inWorld, uint32_t inBody, double lx, double ly, double lz, double ax, double ay,
    double az, int32_t wake) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    if (wake == 0 && !bi.IsActive(rec->id)) {
        return;
    }
    // `set_linvel(linvel() + delta)` (`lib.rs:1224-1240`); Jolt only has
    // absolute setters.
    bi.SetLinearVelocity(rec->id,
                         bi.GetLinearVelocity(rec->id) + Vec3(float(lx), float(ly), float(lz)));
    bi.SetAngularVelocity(rec->id,
                          bi.GetAngularVelocity(rec->id) + Vec3(float(ax), float(ay), float(az)));
    if (wake != 0) {
        bi.ActivateBody(rec->id);
    }
}

__attribute__((export_name("jolt_body_get_linear_velocity"))) void jolt_body_get_linear_velocity(
    uint32_t inWorld, uint32_t inBody, uint32_t out) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    const Vec3 v = w->physics->GetBodyInterface().GetLinearVelocity(rec->id);
    float *dest = reinterpret_cast<float *>(uintptr_t(out));
    dest[0] = v.GetX();
    dest[1] = v.GetY();
    dest[2] = v.GetZ();
}

__attribute__((export_name("jolt_body_get_angular_velocity"))) void jolt_body_get_angular_velocity(
    uint32_t inWorld, uint32_t inBody, uint32_t out) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    const Vec3 v = w->physics->GetBodyInterface().GetAngularVelocity(rec->id);
    float *dest = reinterpret_cast<float *>(uintptr_t(out));
    dest[0] = v.GetX();
    dest[1] = v.GetY();
    dest[2] = v.GetZ();
}

// `applyForce` (`lib.rs:1309-1350`): the force and the point are plot-local; the
// force is rotated into world space and applied as an impulse at the center of
// mass plus the torque of its lever arm.
__attribute__((export_name("jolt_body_add_impulse"))) void jolt_body_add_impulse(
    uint32_t inWorld, uint32_t inBody, double lx, double ly, double lz, double fx, double fy,
    double fz, int32_t wake) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    if (wake == 0 && !bi.IsActive(rec->id)) {
        return;
    }
    const Quat rotation = bi.GetRotation(rec->id);
    const Vec3 force = rotation * Vec3(float(fx), float(fy), float(fz));
    const Vec3 lever = rotation * Vec3(float(lx), float(ly), float(lz));
    bi.AddImpulse(rec->id, force);
    bi.AddAngularImpulse(rec->id, lever.Cross(force));
    if (wake != 0) {
        bi.ActivateBody(rec->id);
    }
}

// `applyForceAndTorque` (`lib.rs:1352-1393`).
__attribute__((export_name("jolt_body_add_impulse_and_torque")))
void jolt_body_add_impulse_and_torque(uint32_t inWorld, uint32_t inBody, double fx, double fy,
                                      double fz, double tx, double ty, double tz, int32_t wake) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    if (wake == 0 && !bi.IsActive(rec->id)) {
        return;
    }
    const Quat rotation = bi.GetRotation(rec->id);
    bi.AddImpulse(rec->id, rotation * Vec3(float(fx), float(fy), float(fz)));
    bi.AddAngularImpulse(rec->id, rotation * Vec3(float(tx), float(ty), float(tz)));
    if (wake != 0) {
        bi.ActivateBody(rec->id);
    }
}

// `RigidBodyHandle.applyForcesAndReset`: a world-space force at the center of
// mass. Jolt clears forces after every `Update` (`PhysicsSystem.cpp:2496`), so
// accumulating here matches `reset_forces` + `add_force` inside one tick.
__attribute__((export_name("jolt_body_add_force"))) void jolt_body_add_force(uint32_t inWorld,
                                                                             uint32_t inBody,
                                                                             double fx, double fy,
                                                                             double fz) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    w->physics->GetBodyInterface().AddForce(rec->id, Vec3(float(fx), float(fy), float(fz)),
                                            EActivation::DontActivate);
}

__attribute__((export_name("jolt_body_add_force_at"))) void jolt_body_add_force_at(
    uint32_t inWorld, uint32_t inBody, double px, double py, double pz, double fx, double fy,
    double fz) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    w->physics->GetBodyInterface().AddForce(rec->id, Vec3(float(fx), float(fy), float(fz)),
                                            RVec3(px, py, pz), EActivation::DontActivate);
}

__attribute__((export_name("jolt_body_add_torque"))) void jolt_body_add_torque(
    uint32_t inWorld, uint32_t inBody, double tx, double ty, double tz) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    w->physics->GetBodyInterface().AddTorque(rec->id, Vec3(float(tx), float(ty), float(tz)),
                                             EActivation::DontActivate);
}

// `RigidBody::velocity_at_point` (`buoyancy.rs:143-152`).
__attribute__((export_name("jolt_body_velocity_at_point"))) void jolt_body_velocity_at_point(
    uint32_t inWorld, uint32_t inBody, double px, double py, double pz, uint32_t out) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    BodyInterface &bi = w->physics->GetBodyInterface();
    const Vec3 linear = bi.GetLinearVelocity(rec->id);
    const Vec3 angular = bi.GetAngularVelocity(rec->id);
    const RVec3 center = bi.GetCenterOfMassPosition(rec->id);
    const Vec3 offset = Vec3(RVec3(px, py, pz) - center);
    const Vec3 velocity = linear + angular.Cross(offset);
    float *dest = reinterpret_cast<float *>(uintptr_t(out));
    dest[0] = velocity.GetX();
    dest[1] = velocity.GetY();
    dest[2] = velocity.GetZ();
}

__attribute__((export_name("jolt_body_mass"))) double jolt_body_mass(uint32_t inWorld,
                                                                    uint32_t inBody) {
    World *w = worldOf(inWorld);
    BodyRec *rec = bodyOf(w, inBody);
    if (rec == nullptr) {
        return 0.0;
    }
    const Body *body = w->physics->GetBodyLockInterface().TryGetBody(rec->id);
    if (body == nullptr || body->GetMotionProperties() == nullptr) {
        return 0.0;
    }
    const float inverse_mass = body->GetMotionProperties()->GetInverseMass();
    return inverse_mass > 0.0f ? double(1.0f / inverse_mass) : 0.0;
}

// ---- Voxel colliders ------------------------------------------------------

__attribute__((export_name("jolt_voxel_collider_new"))) uint32_t jolt_voxel_collider_new(
    double inFriction, double inVolume, double inRestitution, int32_t inFluid) {
    VoxelCollider collider;
    collider.friction = float(inFriction);
    collider.volume = float(inVolume);
    collider.restitution = float(inRestitution);
    collider.fluid = inFluid != 0;
    g_colliders.push_back(collider);
    return uint32_t(g_colliders.size() - 1);
}

__attribute__((export_name("jolt_voxel_collider_add_box"))) void jolt_voxel_collider_add_box(
    uint32_t inIndex, double minx, double miny, double minz, double maxx, double maxy,
    double maxz) {
    if (inIndex >= g_colliders.size()) {
        return;
    }
    VoxelBox box;
    box.min[0] = float(minx);
    box.min[1] = float(miny);
    box.min[2] = float(minz);
    box.max[0] = float(maxx);
    box.max[1] = float(maxy);
    box.max[2] = float(maxz);
    g_colliders[inIndex].boxes.push_back(box);
}

__attribute__((export_name("jolt_voxel_collider_clear_boxes"))) void
jolt_voxel_collider_clear_boxes(uint32_t inIndex) {
    if (inIndex >= g_colliders.size()) {
        return;
    }
    g_colliders[inIndex].boxes.clear();
}

__attribute__((export_name("jolt_voxel_collider_count"))) uint32_t jolt_voxel_collider_count() {
    return uint32_t(g_colliders.size());
}

// ---- Voxel world ----------------------------------------------------------

// `addChunk` (`lib.rs:796-925`): `data` holds 4096 packed words indexed
// `bx + (bz << 4) + (by << 8)`; `global != 0` targets the static level, else the
// section belongs to `inBody`.
__attribute__((export_name("jolt_chunk_add"))) void jolt_chunk_add(
    uint32_t inWorld, int32_t sx, int32_t sy, int32_t sz, uint32_t inData, int32_t global,
    uint32_t inBody) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    const uint32_t *data = reinterpret_cast<const uint32_t *>(uintptr_t(inData));
    if (data == nullptr) {
        return;
    }
    BodyRec *rec = global != 0 ? &w->ground : bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }

    const int32_t base_x = sx << 4;
    const int32_t base_y = sy << 4;
    const int32_t base_z = sz << 4;
    for (int32_t bx = 0; bx < 16; ++bx) {
        for (int32_t bz = 0; bz < 16; ++bz) {
            for (int32_t by = 0; by < 16; ++by) {
                const PackedBlock block = unpack(data[bx + (bz << 4) + (by << 8)]);
                if (!isSolid(block)) {
                    continue;
                }
                setBlock(w, *rec, Key3{base_x + bx, base_y + by, base_z + bz}, block);
            }
        }
    }
    rebuildShape(w, *rec);
}

// `removeChunk` (`lib.rs:927-993`).
__attribute__((export_name("jolt_chunk_remove"))) void jolt_chunk_remove(
    uint32_t inWorld, int32_t sx, int32_t sy, int32_t sz, int32_t global, uint32_t inBody) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    BodyRec *rec = global != 0 ? &w->ground : bodyOf(w, inBody);
    if (rec == nullptr) {
        return;
    }
    const int32_t base_x = sx << 4;
    const int32_t base_y = sy << 4;
    const int32_t base_z = sz << 4;
    for (int32_t bx = 0; bx < 16; ++bx) {
        for (int32_t bz = 0; bz < 16; ++bz) {
            for (int32_t by = 0; by < 16; ++by) {
                eraseBlock(w, *rec, Key3{base_x + bx, base_y + by, base_z + bz});
            }
        }
    }
    rebuildShape(w, *rec);
}

// `changeBlock` (`lib.rs:995-1107`). `x,y,z` are absolute block coordinates
// (`RapierPhysicsPipeline.java:386-406`). The block belongs to a sub-level when
// it lies inside that body's recorded blocks, otherwise to the static level.
__attribute__((export_name("jolt_block_change"))) void jolt_block_change(uint32_t inWorld,
                                                                        int32_t x, int32_t y,
                                                                        int32_t z,
                                                                        uint32_t inPacked) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return;
    }
    const PackedBlock block = unpack(inPacked);
    const Key3 pos{x, y, z};

    for (BodyRec &rec : w->bodies) {
        if (!rec.alive || rec.block_index.find(pos) == rec.block_index.end()) {
            continue;
        }
        setBlock(w, rec, pos, block);
        return;
    }
    setBlock(w, w->ground, pos, block);
    w->physics->GetBodyInterface().NotifyShapeChanged(w->ground.id, Vec3::sZero(), false,
                                                      EActivation::DontActivate);
}

// ---- Constraints ----------------------------------------------------------

__attribute__((export_name("jolt_joint_create_hinge"))) uint32_t jolt_joint_create_hinge(
    uint32_t inWorld, uint32_t inBodyA, uint32_t inBodyB, double ax, double ay, double az,
    double bx, double by, double bz, double aax, double aay, double aaz, double bax, double bay,
    double baz) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return 0;
    }
    JointRec rec;
    rec.kind = JointKind::Hinge;
    rec.body_a = inBodyA;
    rec.body_b = inBodyB;
    rec.alive = true;
    rec.pos_a = Vec3(float(ax), float(ay), float(az));
    rec.pos_b = Vec3(float(bx), float(by), float(bz));
    rec.axis_a = Vec3(float(aax), float(aay), float(aaz));
    rec.axis_b = Vec3(float(bax), float(bay), float(baz));
    // `joints.rs:304-380`: contacts are enabled for revolute joints.
    rec.contacts_enabled = true;
    const uint32_t handle = allocJointSlot(w, rec);
    if (!refreshConstraint(w, w->joints[handle - 1])) {
        w->joints[handle - 1].alive = false;
        w->free_joints.push_back(handle - 1);
        return 0;
    }
    return handle;
}

__attribute__((export_name("jolt_joint_create_fixed"))) uint32_t jolt_joint_create_fixed(
    uint32_t inWorld, uint32_t inBodyA, uint32_t inBodyB, double ax, double ay, double az,
    double bx, double by, double bz, double qx, double qy, double qz, double qw) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return 0;
    }
    JointRec rec;
    rec.kind = JointKind::Fixed;
    rec.body_a = inBodyA;
    rec.body_b = inBodyB;
    rec.alive = true;
    rec.pos_a = Vec3(float(ax), float(ay), float(az));
    rec.pos_b = Vec3(float(bx), float(by), float(bz));
    rec.rot_a = Quat(float(qx), float(qy), float(qz), float(qw));
    rec.has_rot_a = true;
    // `joints.rs:390-475`: fixed joints start with contacts disabled.
    rec.contacts_enabled = false;
    const uint32_t handle = allocJointSlot(w, rec);
    if (!refreshConstraint(w, w->joints[handle - 1])) {
        w->joints[handle - 1].alive = false;
        w->free_joints.push_back(handle - 1);
        return 0;
    }
    updateDisabledPair(w, w->joints[handle - 1]);
    return handle;
}

__attribute__((export_name("jolt_joint_create_sixdof"))) uint32_t jolt_joint_create_sixdof(
    uint32_t inWorld, uint32_t inBodyA, uint32_t inBodyB, double ax, double ay, double az,
    double qax, double qay, double qaz, double qaw, double bx, double by, double bz, double qbx,
    double qby, double qbz, double qbw, uint32_t inLockedMask) {
    World *w = worldOf(inWorld);
    if (w == nullptr) {
        return 0;
    }
    JointRec rec;
    rec.kind = JointKind::SixDOF;
    rec.body_a = inBodyA;
    rec.body_b = inBodyB;
    rec.alive = true;
    rec.pos_a = Vec3(float(ax), float(ay), float(az));
    rec.pos_b = Vec3(float(bx), float(by), float(bz));
    rec.rot_a = Quat(float(qax), float(qay), float(qaz), float(qaw));
    rec.rot_b = Quat(float(qbx), float(qby), float(qbz), float(qbw));
    rec.has_rot_a = true;
    rec.has_rot_b = true;
    rec.locked_mask = inLockedMask;
    // `joints.rs:565-720` (`addGenericConstraint`): contacts enabled.
    rec.contacts_enabled = true;
    const uint32_t handle = allocJointSlot(w, rec);
    if (!refreshConstraint(w, w->joints[handle - 1])) {
        w->joints[handle - 1].alive = false;
        w->free_joints.push_back(handle - 1);
        return 0;
    }
    return handle;
}

__attribute__((export_name("jolt_joint_destroy"))) void jolt_joint_destroy(uint32_t inWorld,
                                                                          uint32_t inJoint) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr) {
        return;
    }
    destroyConstraint(w, *rec);
    rec->alive = false;
    w->free_joints.push_back(inJoint - 1);
}

__attribute__((export_name("jolt_joint_is_valid"))) int32_t jolt_joint_is_valid(
    uint32_t inWorld, uint32_t inJoint) {
    return jointOf(worldOf(inWorld), inJoint) != nullptr ? 1 : 0;
}

__attribute__((export_name("jolt_joint_set_frame"))) void jolt_joint_set_frame(
    uint32_t inWorld, uint32_t inJoint, int32_t inSide, double x, double y, double z, double qx,
    double qy, double qz, double qw) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr) {
        return;
    }
    const Vec3 position{float(x), float(y), float(z)};
    const Quat rotation{float(qx), float(qy), float(qz), float(qw)};
    bool changed = false;
    if (inSide == 0) {
        changed = (position - rec->pos_a).LengthSq() > 1.0e-12f;
        rec->pos_a = position;
        if (rec->kind != JointKind::Hinge) {
            rec->rot_a = rotation;
            rec->has_rot_a = true;
        }
    } else {
        changed = (position - rec->pos_b).LengthSq() > 1.0e-12f;
        rec->pos_b = position;
        if (rec->kind != JointKind::Hinge) {
            rec->rot_b = rotation;
            rec->has_rot_b = true;
        }
    }
    if (changed) {
        refreshConstraint(w, *rec);
    }
}

// Hinge axes are immutable in Jolt 5.6 (`HingeConstraint` exposes limits and
// motors only), so an axis change recreates the constraint.
__attribute__((export_name("jolt_joint_set_axis"))) void jolt_joint_set_axis(
    uint32_t inWorld, uint32_t inJoint, int32_t inSide, double x, double y, double z) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr || rec->kind != JointKind::Hinge) {
        return;
    }
    const Vec3 axis{float(x), float(y), float(z)};
    Vec3 &target = inSide == 0 ? rec->axis_a : rec->axis_b;
    if ((axis - target).LengthSq() < 1.0e-12f) {
        return;
    }
    target = axis;
    refreshConstraint(w, *rec);
}

__attribute__((export_name("jolt_joint_set_motor"))) void jolt_joint_set_motor(
    uint32_t inWorld, uint32_t inJoint, int32_t inAxis, double inTarget, double inStiffness,
    double inDamping, int32_t inHasMaxForce, double inMaxForce) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr || inAxis < 0 || inAxis > 5) {
        return;
    }
    rec->motor_on[inAxis] = true;
    rec->motor_target[inAxis] = float(inTarget);
    rec->motor_frequency[inAxis] = float(inStiffness);
    rec->motor_damping[inAxis] = float(inDamping);
    rec->motor_has_max_force[inAxis] = inHasMaxForce != 0;
    rec->motor_max_force[inAxis] = float(inMaxForce);

    if (rec->constraint == nullptr) {
        return;
    }
    if (rec->kind == JointKind::Hinge) {
        if (inAxis != 5) {
            return;
        }
        HingeConstraint *hinge = static_cast<HingeConstraint *>(rec->constraint);
        hinge->GetMotorSettings().mSpringSettings =
            springOf(rec->motor_frequency[5], rec->motor_damping[5]);
        if (rec->motor_has_max_force[5]) {
            hinge->GetMotorSettings().SetTorqueLimit(rec->motor_max_force[5]);
        }
        hinge->SetMotorState(EMotorState::Position);
        hinge->SetTargetAngle(rec->motor_target[5]);
        return;
    }
    if (rec->kind == JointKind::SixDOF) {
        SixDOFConstraint *six = static_cast<SixDOFConstraint *>(rec->constraint);
        const auto e = SixDOFConstraintSettings::EAxis(inAxis);
        six->GetMotorSettings(e).mSpringSettings =
            springOf(rec->motor_frequency[inAxis], rec->motor_damping[inAxis]);
        if (rec->motor_has_max_force[inAxis]) {
            if (inAxis < 3) {
                six->GetMotorSettings(e).SetForceLimit(rec->motor_max_force[inAxis]);
            } else {
                six->GetMotorSettings(e).SetTorqueLimit(rec->motor_max_force[inAxis]);
            }
        }
        six->SetMotorState(e, EMotorState::Position);
        if (inAxis < 3) {
            Vec3 target = six->GetTargetPositionCS();
            target.SetComponent(inAxis, rec->motor_target[inAxis]);
            six->SetTargetPositionCS(target);
        } else {
            const Vec3 angles = six->GetTargetOrientationCS().GetEulerAngles();
            Vec3 target = angles;
            target.SetComponent(inAxis - 3, rec->motor_target[inAxis]);
            six->SetTargetOrientationCS(Quat::sEulerAngles(target));
        }
    }
}

__attribute__((export_name("jolt_joint_set_limit"))) void jolt_joint_set_limit(
    uint32_t inWorld, uint32_t inJoint, int32_t inAxis, double inMin, double inMax) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr || inAxis < 0 || inAxis > 5) {
        return;
    }
    rec->limit_on[inAxis] = true;
    rec->limit_min[inAxis] = float(inMin);
    rec->limit_max[inAxis] = float(inMax);

    if (rec->constraint == nullptr) {
        return;
    }
    if (rec->kind == JointKind::Hinge) {
        if (inAxis == 5) {
            static_cast<HingeConstraint *>(rec->constraint)->SetLimits(float(inMin), float(inMax));
        }
        return;
    }
    if (rec->kind == JointKind::SixDOF) {
        SixDOFConstraint *six = static_cast<SixDOFConstraint *>(rec->constraint);
        if (inAxis < 3) {
            Vec3 lo = six->GetTranslationLimitsMin();
            Vec3 hi = six->GetTranslationLimitsMax();
            lo.SetComponent(inAxis, float(inMin));
            hi.SetComponent(inAxis, float(inMax));
            six->SetTranslationLimits(lo, hi);
        } else {
            Vec3 lo = six->GetRotationLimitsMin();
            Vec3 hi = six->GetRotationLimitsMax();
            lo.SetComponent(inAxis - 3, float(inMin));
            hi.SetComponent(inAxis - 3, float(inMax));
            six->SetRotationLimits(lo, hi);
        }
    }
}

// `lockConstraintAxes` (`joints.rs:170-215`). Locking axes changes which
// constraints SixDOF builds, so the constraint is recreated.
__attribute__((export_name("jolt_joint_lock_axes"))) void jolt_joint_lock_axes(
    uint32_t inWorld, uint32_t inJoint, uint32_t inMask) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr || rec->kind != JointKind::SixDOF || rec->locked_mask == inMask) {
        return;
    }
    rec->locked_mask = inMask;
    refreshConstraint(w, *rec);
}

__attribute__((export_name("jolt_joint_set_contacts_enabled"))) void
jolt_joint_set_contacts_enabled(uint32_t inWorld, uint32_t inJoint, int32_t inEnabled) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr) {
        return;
    }
    rec->contacts_enabled = inEnabled != 0;
    updateDisabledPair(w, *rec);
}

// Rapier's per-joint `impulses` array (`joints.rs:238-272`), in the same order
// (linear x/y/z, angular x/y/z).
__attribute__((export_name("jolt_joint_get_impulses"))) void jolt_joint_get_impulses(
    uint32_t inWorld, uint32_t inJoint, uint32_t out) {
    World *w = worldOf(inWorld);
    JointRec *rec = jointOf(w, inJoint);
    if (rec == nullptr || rec->constraint == nullptr) {
        return;
    }
    Vec3 linear = Vec3::sZero();
    Vec3 angular = Vec3::sZero();
    switch (rec->kind) {
        case JointKind::Hinge: {
            const HingeConstraint *hinge = static_cast<const HingeConstraint *>(rec->constraint);
            linear = hinge->GetTotalLambdaPosition();
            const Vector<2> rotation = hinge->GetTotalLambdaRotation();
            angular = Vec3(rotation[0], rotation[1],
                           hinge->GetTotalLambdaMotor() + hinge->GetTotalLambdaRotationLimits());
            break;
        }
        case JointKind::Fixed: {
            const FixedConstraint *fixed = static_cast<const FixedConstraint *>(rec->constraint);
            linear = fixed->GetTotalLambdaPosition();
            angular = fixed->GetTotalLambdaRotation();
            break;
        }
        case JointKind::SixDOF: {
            const SixDOFConstraint *six = static_cast<const SixDOFConstraint *>(rec->constraint);
            linear = six->GetTotalLambdaPosition();
            angular = six->GetTotalLambdaRotation();
            break;
        }
    }
    float *dest = reinterpret_cast<float *>(uintptr_t(out));
    dest[0] = linear.GetX();
    dest[1] = linear.GetY();
    dest[2] = linear.GetZ();
    dest[3] = angular.GetX();
    dest[4] = angular.GetY();
    dest[5] = angular.GetZ();
}

}  // extern "C"
