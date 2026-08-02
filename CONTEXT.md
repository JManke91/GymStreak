# GymStreak

A strength-training app: the user keeps reusable **routines**, performs them as **workouts** on iPhone or Apple Watch, and reviews what they lifted over time. The vocabulary below is the language the codebase and its documentation use; it exists mainly to keep the watch ↔ iPhone sync boundary unambiguous, where several superficially similar concepts have very different guarantees.

## Language

### Planning

**Routine**:
A reusable plan for one training session — an ordered list of exercise slots, each with its planned sets.
_Avoid_: Workout plan, program, template (as a noun for the whole routine)

**Routine exercise**:
One exercise slot within a routine, together with its planned sets and any alternatives the user may swap to. Identity belongs to the slot, not to the exercise placed in it, so swapping preserves history.
_Avoid_: Exercise (unqualified), slot

**Exercise**:
An entry in the user's exercise library — a movement that can be placed into any routine.
_Avoid_: Lift, movement

**Template intent**:
A request to change a routine that originated from performing a workout — accepted weight increases, edited set values, exercises added or removed mid-workout. Deliberately distinct from the workout itself: it is ordered per routine, mergeable against concurrent edits, and losable without harming the record of what was performed.
_Avoid_: Template update (when the request rather than the resulting change is meant), routine edit

### Performing and recording

**Workout**:
One performed training session. A workout is derived from a routine but never depends on it afterwards.
_Avoid_: Session (unqualified), training

**Workout history**:
The permanent, denormalized record of a performed workout. It is copied rather than referenced so it survives editing or deleting the routine it came from, and it is the one thing in the sync path that must never be lost.
_Avoid_: Log, past workout, session data

**Progressive overload**:
An increase to a routine's prescribed load, offered when performance indicates the current target has been outgrown. Accepting one produces template intent.
_Avoid_: Weight bump, auto-increase

### Sync

**Sync entry**:
One durable, frozen unit of work in the watch's outgoing queue. A workout that also carries template intent produces two of them — one for the history, one for the template intent — precisely so the fate of the second cannot affect the first.
_Avoid_: Queue item, pending workout

**Frozen payload**:
The exact bytes of a sync entry, fixed at the moment it becomes durable and never rebuilt afterwards. Retries resend the identical bytes; a retried step never reconstructs what it is sending.
_Avoid_: Snapshot, cached payload

**Terminal acknowledgment**:
The iPhone's confirmation that it has durably committed a sync entry's meaning — not that the transfer arrived. Only this retires an entry from the watch's queue; transport-level delivery never does.
_Avoid_: Ack (unqualified), receipt, confirmation

**Optimistic fold**:
The watch's local overlay of unresolved template intent on top of the last routine the iPhone confirmed, so the user immediately sees a change they accepted, even while it is still in flight.
_Avoid_: Local override, pending state

**Authority**:
The iPhone's claim to be the source of truth for routines, expressed as a versioned generation the watch chooses to accept. It is receiver-authorized: the watch validates every claim against its own record and can refuse one.
_Avoid_: Master, owner, source of truth (unqualified)

**Orphaned workout**:
A workout found in Apple Health that carries GymStreak's identity but has no corresponding workout history on the iPhone. It may be reconstructed from its routine, with planned values standing in for what was actually performed — a deliberately lossy last resort.
_Avoid_: Missing workout, lost workout, unsynced workout
