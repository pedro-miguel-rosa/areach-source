# AReach spatial validation matrix

This pipeline requires real iPhones for Nearby Interaction, UWB distance/direction,
AR world tracking, camera permissions, Bluetooth restoration, ActivityKit, and
thermal/battery behavior. The simulator build and the standalone harnesses only
validate source integration and deterministic policy.

## Acquisition and render lifecycle

`BodyPoseDetector` produces fresh Vision detections, and
`SpatialBodyTrackManager` keeps short-lived predicted tracks through brief
misses. `SpatialTargetMatcher` builds the strict evidence matrix, performs the
one-to-one assignment, and writes verified body identity only after the normal
confidence, ambiguity, and confirmation gates pass.

Rendering is a separate state path. `renderMatches` can expose an exact,
plausible singleton, or ambiguous group anchor without writing a verified body
association. `AReachSpatialRuntime` reprojects valid phone/world anchors on the
display link and otherwise uses the retained body or screen point until the
independent render grace period expires.

Camera visibility is a second render-only decision after those states are
constructed. The matcher keeps every recoverable `renderMatch` alive, then
`SpatialRenderVisibilitySelector` chooses at most three cards for both the
direct matcher output and `renderSnapshot()`. New cards are distance-eligible
inside 4 m, with a strong proximity preference at 3 m; selected cards may
remain visible until 5 m. A fresh UWB, body-depth, or world-transform distance
is preferred for that decision when its quality and uncertainty are usable.
Only fresh, sufficiently precise, and mutually consistent distance evidence can
enforce the 4 m/5 m boundary; weak, stale, or conflicting distance remains
ranking context rather than an automatic hard rejection. Missing distance still
lowers ranking but does not automatically hide a physically plausible card.

Selection also scores camera-center relevance and uses a 0.75 s incumbent
hysteresis window with a 0.12 replacement margin. Hidden cards remain in the
render-only state and can re-enter when a visible slot becomes available.
Selection never writes a body track into `SpatialAssociationState`, so a
plausible singleton or group card can be useful immediately while strict
identity confirmation continues in parallel.

## Device matrix

Use the same event credential and current app build on every device. Record the
viewer model/iOS version, target model/iOS version, distance, pocket orientation,
whether the target is locked, and whether the overlay is correct, absent, or
incorrect.

| ID | Setup | Expected behavior |
| --- | --- | --- |
| A | 2 phones, both foreground | Camera viewer discovers and ranges the target; one stable overlay appears after repeated evidence. |
| B | Viewer foreground, target background and unlocked | Target remains a passive responder; viewer keeps ranging without Vision on the target. |
| C | Viewer foreground, target locked on a table | BLE presence and inbound NI response continue where iOS permits; target is not proactively ranged. |
| D | Viewer foreground, target locked in a front pocket | Distance-only observations are accepted as tentative only with fresh high-quality body-depth agreement; no guess under ambiguity. |
| E | Viewer foreground, target locked in a back/hip pocket | Same as D, with pocket geometry and occlusion recorded separately. |
| F | 5 nearby attendees | Camera-interest ranking favors visible bodies and rotates irrelevant peers promptly. In Overview/Attendees, foreground ranging keeps a small hardware-safe working set and eventually ranges every eligible attendee. |
| G | 10 nearby attendees | All peers remain discoverable; no more than the learned small NI/Bluetooth pools are active. Foreground ranging rotates fairly without treating the peer count as a session count. |
| H | 20 nearby attendees | Every presence peer eventually receives a ranging opportunity; no peer starves behind verified peers. This is a physical validation target, not a claim that 20 simultaneous NI sessions are supported. |
| I | Two people shoulder-to-shoulder, one event phone | A group fallback card is shown around the pair; no body is marked as the verified identity. |
| J | Two people cross | Body track continuity survives the crossing, with no rapid identity swap. |
| K | Viewer pans rapidly across a crowd | Native rendering remains responsive; Vision cadence adapts and stale probes are reclaimed. |
| L | Target locked/backgrounded for 30–60 minutes | Passive Bluetooth restoration and responder behavior remain bounded; inspect battery and wake frequency. |
| M | Leave Camera for Overview/Attendees, then return without leaving the event | The native nearby service remains alive; the attendee screen keeps distance presence, and Camera reattaches AR assistance without requiring an event restart. |
| N | Drop/recover local-network discovery while both phones remain in the same live event | Bonjour rebuilds from lifecycle events, resolved identities and recoverable spatial state are retained, and ranging renegotiates with a new transaction. |
| O | Force both phones to initiate at the same time | The lower stable peer ID keeps outbound ownership; the other yields locally and accepts inbound without a peer-loss event or transport close. |
| P | Two people shoulder-to-shoulder, both with event phones | Both attendee cards can share the stable group anchor while exact identity remains unresolved. |
| Q | The pair from I/P separates | Strict matching promotes clear assignments and cards move to individual body anchors. |
| R | Equal-distance off-viewport peers | With one person in view and a second peer at a similar distance behind, to the side, or just beyond any current image edge, the peer whose fresh spatial projection is outside the viewport never becomes the visible body’s exact identity; if direction is unavailable, exact identity is withheld. Panning toward that peer makes it eligible again once its projection enters the new camera viewport. |
| S | 3–5 foreground attendees across two ranging rotations | All peers remain present; each receives a fresh range opportunity, released peers re-enter the queue, local outbound ownership never exceeds the active/pending initiator count, and no attendee requires an event restart to recover. A retained attendee-list measurement is marked as last measured while waiting and is removed after its bounded display window. |
| T | 3 phones present, camera sees one person, Vision occasionally reports two near-identical observations | Duplicate observations reduce to one unique physical body before object-tracker seeding; matcher-visible body tracks stay at one and the single person never gets two body-attached attendee overlays. |
| U | Two people stand shoulder-to-shoulder with overlapping boxes | Two distinct core skeletons remain two unique bodies and two tracks; both attendee overlays remain possible when identity evidence is sufficient. |
| V | Two people cross in front of the camera | Body count remains two through the crossing and the existing persistent track IDs continue without duplicate suppression merging the people. |
| W | One person partly hides another | Keep both tracks while distinct root/torso/core-joint evidence remains; ambiguous or missing evidence must not trigger a destructive merge. |
| X | Three phones join A, B, then C; B ranges both while A↔C is delayed | All three direct peer pairs eventually receive fresh distance. Simultaneous Bonjour connection attempts converge on one authenticated transport per pair; a stalled pair retries without leaving the event. |

For D, E, I, J, P, and Q, repeat with the target phone in a hand and with a
second phone at a similar range. Ambiguous bodies may use a group fallback, but
the desired identity failure mode is no wrong attendee card. A peer with
clearly contradictory spatial evidence should produce no card.

## Instruments signposts

- Ranging peer release selected and Ranging peer acquisition selected expose
  runtime role, presence size, active/pending/local session counts, learned
  hardware and proactive budgets, waiting count, fairness release reason, and
  acquisition reason.
- Inbound ranging capacity preemption and Ranging request busy expose the
  authenticated requester, yielded foreground peer when applicable, real
  hardware occupancy, and the reason an inbound request was accepted or
  declined. Busy summaries include active responder count and foreground
  proactive capacity.

Filter the `io.areach.spatial` subsystem and inspect these intervals/events:

- `Nearby presence phase`, `Nearby runtime role`, and `Background responder state`
  confirm startup ordering and that camera acquisition stops when the native view
  leaves the window.
- `Maximum discovered peer count`, `Nearby presence pool count`, `First BLE
  advertisement`, `First Bonjour discovery`, and `Bluetooth attendee discovered`
  measure presence scale and startup latency.
- `Nearby peer link state`, `Ranging transaction started`, `Ranging request
  sent`, `Ranging collision won`, `Outbound ranging yielded`, `Nearby ranging
  message ignored`, and `Ranging retry scheduled` expose per-peer negotiation,
  transaction IDs, collision ownership, stale-message handling, and recovery.
- `Nearby network duplicate connection pending authentication` shows crossed
  candidates and their directions; `Nearby network duplicate connection kept`
  and `Nearby network duplicate connection replaced` show which authenticated
  route won. `Ranging transport connection reset` identifies a peer-specific
  control path dropped after a ranging request timeout so its next attempt can
  authenticate over a fresh connection.
- `Nearby peer measurement tier` exposes each peer's current
  `presenceOnly`, `distanceOnly`, `directionAvailable`, `projectable`, or
  `cameraAssisted`
  evidence level alongside its link state. `projectable` is used for a fresh
  world transform before camera assistance converges; `directionAvailable`
  specifically indicates a fresh direct NI direction without a world
  transform.
- `Ranging health transition`, `Ranging health degraded`, `Ranging health
  healthy`, `Ranging soft recovery started`, `Ranging hard recovery started`,
  `Fresh ranging transaction after health failure`, `Ranging recovery failed`,
  and `Ranging recovery succeeded` expose useful-measurement ages, role,
  transaction boundaries, bounded attempts, and recovery latency.
- `Distance health transition`, `Distance health degraded`, `Distance recovery
  started`, `Distance hard recovery started`, and `Distance recovery
  succeeded` report scalar-distance liveness independently from generic NI
  liveness. `Distance stalled with spatial measurements still flowing` proves
  when fresh direction/transform continued while scalar distance stopped.
  These events include role and relevant measurement ages; they are emitted on
  state changes, not every NI callback.
- `Ranging contention retry scheduled` reports `rangeBusy`/collision delay and
  reason separately from negotiation-failure retry attempts. Contention must
  stay short and must not increase hard recovery counters.
- `Ranging recovery waiting for transport`, `Ranging transport refresh
  requested`, and `Ranging Bonjour discovery refreshed` show when a retained
  attendee is waiting on transport and how the shared BLE/Bonjour refresh gate
  restores an authenticated ranging path.
- `World transform became stale` and `Distance became stale` prove that raw
  sensor clocks, rather than callback activity or display smoothing, control
  stale-data suppression.
- `Nearby discovery started`, `First authenticated transport`, `First identity
  resolution`, `First NI update latency`, `First UWB distance latency`, `First
  world transform received`, `First camera assistance enabled`, `First camera
  assistance converged`, and `First blue phone marker rendered` provide the
  first-event latency chain. The marker event is emitted only after a real
  projectable world transform exists.
- `Nearby ranging state`, `Probe selected`, `First useful probe measurement`,
  `Probe promoted to candidate`, `Probe evicted`, `Ranging peer release
  selected`, `Foreground peer deferred after remote stop`, and `Ranging slot
  rotated` expose acquisition fairness, active responder peer IDs, release
  ownership/reason, and the short-lived same-edge defer used during foreground
  rotation.
- `Orphaned outbound ranging ownership cleared` should normally be absent. If
  emitted, it identifies a local initiator entry that lost its active/pending
  session bookkeeping; the scheduler clears it before allocating again. The
  `Nearby ranging state` summary reports the orphaned outbound count, expected
  to be zero after pool reconciliation.
- `First UWB distance latency`, `First world transform received`, and the
  `distance-only updates`/`direction updates`/`camera-assisted updates` fields
  distinguish pocketed scalar ranging from projectable ranging.
- `Vision body analysis`, `Vision depth sampling`, `Vision 3D body analysis`,
  `AR frame callback cadence`, `Processed Vision cadence`, and `Vision frame
  coalesced` expose backpressure, cadence, and thermal degradation.
- `Vision duplicate body suppressed` reports raw Vision observations, unique
  physical detections, detector and matcher body counts, and suppression or
  retirement counts. It is emitted when the diagnostic state changes rather
  than on every frame. In DEBUG Camera, the compact body line shows
  `raw → unique → tracked` with per-stage suppression counts.
- `Fusion candidate counts`, `Fusion association state`, `Fusion association
  modes`, and `Fusion render states` expose gated pairs, tentative/verified
  counts, ambiguity rejection, strict association mode, normalized distance
  residual, exact/plausible/group render counts, and group size.
- `Directional candidate rejected` and `Distance-only identity rejected`,
  together with the camera-session summary counters, distinguish hard
  camera-direction contradictions from scalar candidates that remain outside
  exact acquisition, reacquisition, and switching.
- `Fusion render visibility` exposes all render candidates, distance-eligible
  candidates, reliable/weak distance evidence, selected cards,
  distance/capacity suppression, incumbent retention, replacements, and
  selection changes. `Fusion render states`
  separates all exact/plausible/group render records from the currently
  visible counts.
- `Overlay visibility selection changed` and `Overlay visibility replacement`
  identify meaningful card-set transitions without per-frame card logging.
- `Singleton plausible render started`, `Singleton plausible render promoted to
  exact`, `Singleton plausible render expired`, `Group fallback started`, `Group
  fallback promoted to exact`, and `Group fallback expired` expose render-only
  acquisition, retention, and promotion without treating fallback rendering as
  verified identity evidence.
- `Render body-loss grace started`, `Render body-loss grace recovered`,
  `Render body-loss grace expired`, `Direction contradiction started`,
  `Direction contradiction recovered`, and `Direction contradiction expired`
  distinguish bounded render continuity from actual identity/render expiry.
- `Render anchor source changed` and `Render anchor jitter suppressed` expose
  anchor-source hand-offs and the per-card dead-zone filter without emitting a
  sample for every display frame.
- `Native render cadence`, `First overlay acquired`, `Overlay targets lost`, and
  `Overlay targets reacquired` measure the display-link path independently of
  Vision FPS.

Export a DEBUG replay snapshot after a problematic run. It contains structured
sensor/fusion state, including exact/plausible/group render modes for new
captures, and no camera pixels; do not ship or collect it in release builds.

## Deterministic checks

Run these from the repository root. They cover generic and scalar-distance
health transitions and bounded recovery decisions, contention versus failure
retry policy, adaptive filters, transaction arrival ordering,
duplicate/stale control messages, BLE first-attempt and exact retry timing,
disappearance cleanup, startup ordering, scalar fallback, association
reacquisition, render-only singleton/group fallback, depth-aware clustering,
render continuity/anchor stabilization, duplicate-body policy and temporal
track recovery, Camera-interest scheduling, foreground fairness with 3, 5, 10,
and 20 peers, and Camera pools of 20, 24, 30, and 50 peers. Foreground tests
also cover responder-slot rotation under a waiting backlog and a cooldown that
lets the remote phone use another edge without preventing inbound Camera work.
Inbound admission covers spare hardware capacity, safe foreground yield,
busy-without-safe-yield, background responder, Camera, and suspended roles.
They do not replace physical Camera/body-count validation.

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialBodyDuplicatePolicy.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialBodyDuplicateHarness.swift \
  -o /tmp/areach-spatial-body-duplicate-harness && \
  /tmp/areach-spatial-body-duplicate-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialBodyDuplicatePolicy.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssignment.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialBodyTrackManager.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialBodyTrackManagerHarness.swift \
  -o /tmp/areach-spatial-body-track-manager-harness && \
  /tmp/areach-spatial-body-track-manager-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialMeasurementTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialDirectionalAssociationPolicy.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssociationLifecycle.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialDirectionalAssociationHarness.swift \
  -o /tmp/areach-spatial-directional-harness && \
  /tmp/areach-spatial-directional-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingHealthPolicy.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialMeasurementTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialMeasurementFilters.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingScheduler.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialPeerLinkState.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRangingHealthHarness.swift \
  -o /tmp/areach-spatial-health-harness
/tmp/areach-spatial-health-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingHealthPolicy.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingScheduler.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialPeerLinkState.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialBluetoothRetryPolicy.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRangingNegotiationHarness.swift \
  -o /tmp/areach-spatial-negotiation-harness && \
  /tmp/areach-spatial-negotiation-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingHealthPolicy.swift \
  apps/mobile/modules/areach-spatial/ios/NearbyDiscovery/SpatialRangingScheduler.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRangingSchedulerHarness.swift \
  -o /tmp/areach-spatial-scheduler-harness
/tmp/areach-spatial-scheduler-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialDepthMeasurement.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialDistanceAssociationHarness.swift \
  -o /tmp/areach-spatial-distance-harness
/tmp/areach-spatial-distance-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssociationLifecycle.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialAssociationReacquisitionHarness.swift \
  -o /tmp/areach-spatial-association-harness
/tmp/areach-spatial-association-harness
```

```sh
SWIFT_MODULECACHE_PATH=/tmp/areach-swift-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/areach-clang-module-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialMeasurementTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssociationLifecycle.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialBodyClusterer.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRenderFallbackHarness.swift \
  -o /tmp/areach-spatial-render-fallback-harness
/tmp/areach-spatial-render-fallback-harness
```

```sh
SWIFT_MODULECACHE_PATH=/private/tmp/areach-spatial-render-visibility-swift-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/areach-spatial-render-visibility-clang-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialDepthMeasurement.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssociationLifecycle.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialRenderVisibility.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRenderVisibilityHarness.swift \
  -o /tmp/areach-spatial-render-visibility-harness && \
  /tmp/areach-spatial-render-visibility-harness
```

```sh
SWIFT_MODULECACHE_PATH=/private/tmp/areach-spatial-render-continuity-swift-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/areach-spatial-render-continuity-clang-cache \
swiftc -parse-as-library \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialRangingTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Runtime/SpatialMeasurementTuning.swift \
  apps/mobile/modules/areach-spatial/ios/Matching/SpatialAssociationLifecycle.swift \
  apps/mobile/modules/areach-spatial/tests/SpatialRenderContinuityHarness.swift \
  -o /tmp/areach-spatial-render-continuity-harness && \
  /tmp/areach-spatial-render-continuity-harness
```

The negotiation harness command above remains the source-of-truth for BLE
retry and transaction arrival-order coverage. A successful harness run proves
deterministic policy only; UWB, camera/AR, Bluetooth restoration, background
execution, thermal behavior, and final overlay appearance still require
physical iPhones.

## Focused physical reliability runs

For every run, record both phone models and iOS versions, event duration,
approximate range, orientation/pocket placement, lock/background state, health
signposts, whether distance remained available, render mode, and whether the
overlay was correct, absent, or incorrect. The safe failure mode for an
ambiguous identity is a plausible/group card without an incorrect exact body
claim; clearly contradictory spatial evidence should still produce no card.

| Test | Setup | Expected behavior |
| --- | --- | --- |
| 1 — Static | Two iPhones 1–3 m apart; Camera open for 10+ minutes. | Distance remains available; a supported projectable marker stays stable; no permanent link loss. |
| 2 — Walk together | Carry both phones and walk for several minutes. | Marker follows responsively without visible multi-step trailing; distance updates naturally. |
| 3 — Change range | Move from about 1 m to 5–8 m and back. | Distance reacts promptly; direction may degrade gracefully; automatic recovery follows improving conditions. |
| 4 — Body block | Cover or block one phone with clothing/body for a few seconds. | Health may become degraded or distance-only, then recovers without event navigation. |
| 5 — Turn away | Rotate phones/body until NI direction degrades, then restore orientation. | Solid positional marker is suppressed when transform freshness expires; distance may remain; direction returns automatically. |
| 6 — Total NI interruption | Briefly interrupt radio/line-of-sight while BLE/Bonjour presence remains. | Watchdog enters bounded soft/hard recovery, then returns with a fresh transaction; attendee presence remains. |
| 7 — Long Camera session | Keep Camera open 20–30 minutes with intermittent walking. | No zombie ranging state, stale marker, or manual event reset. |
| 8 — Camera leave/return | Camera → Overview/Attendees → Camera within the same live event. | Foreground proximity remains alive; the current AR session is reattached; spatial ranging resumes. |
| 9 — Background/foreground | Exercise supported app background and foreground transitions. | Presence remains within platform limits; foreground recovery is automatic. |
| 10 — Repeated failures | Force multiple temporary occlusions or radio interruptions. | Each recovery is bounded and autonomous; no stale transaction or session buildup. |
| 11 — Equal-distance opposite-side/FOV | Stand near two attendee phones at similar range; point only at the person in front, then repeat with the second person behind, far to the side, and just outside the current image edge. Rotate/pan toward the second person, reverse the setup, and repeat with direction temporarily unavailable. | A peer whose fresh projection is behind or outside the current viewport never appears as the visible person’s exact card; equal distance without direction withholds exact identity until direction or projectable evidence recovers. After rotation, the newly visible peer can become eligible when its projection enters the new viewport. |
| 12 — Foreground plus background crowd | Put one attendee near the camera and four peers farther away. | At most three cards render; the center/nearby candidates win, while all peers remain discoverable and strict matching continues. |
| 13 — Render cap | Place five plausible attendees between about 2–4 m and pan slowly. | Only three cards are visible at once; card changes are stable rather than rotating every frame, and hidden render matches can re-enter. |
| 14 — Distance boundary | Walk a selected attendee from about 3.8 m to 4.6 m, then beyond 5 m. | The selected card remains through the short hysteresis/retention range, then disappears when the retained distance limit is exceeded. |
| 15 — Noisy distance boundary | Keep an attendee near 4 m while ranging is intermittent or uncertain. | One weak/noisy distance sample does not flicker-hide the card; a consistent reliable distance beyond 5 m eventually removes it. |
| 16 — Ambiguous close group | Two people stand shoulder-to-shoulder with one event phone. | One group card appears at the stable cluster anchor without a fake exact body assignment. |
| 17 — Two phones in a group | Two close people both have event phones, then separate. | Both cards share the group anchor while ambiguous; after separation strict matching moves them toward individual bodies. |
| 18 — Overlap with depth separation | Make two bodies overlap in the image while reliable depth places them more than the cluster range apart. | They are not collapsed into one physical group merely because their 2D boxes overlap. |
| 19 — Static attendee stability | One viewer and one attendee 1.5–2 m apart; keep the attendee mostly still and hold the viewer normally for 30–60 s. | After acquisition, the card remains continuously visible, does not repeat bubble-in/bubble-out, and small Vision/ranging interruptions do not create obvious shaking. |
| 20 — Short body occlusion | Briefly cover part of the attendee for about 0.5 s, then uncover them. | The existing card and motion state remain; it converges smoothly after recovery without a new appearance animation or position teleport. |
| 21 — Departure and re-entry | Walk the attendee fully out of frame and keep them out, then return. | The card disappears after the bounded render-continuity grace period; re-entry is a clean new acquisition. |
| 22 — FOV edge continuity | Hold the attendee near the left/right image edge and make small camera movements, then move clearly outside the frame. | Tiny projection noise does not cause rapid hide/show flicker; persistent fresh outside-viewport evidence eventually removes the card. |
| 23 — 3 attendees / join-order starvation | A joins the event, B joins, then C joins afterward. A opens Attendees and keeps the event active. Repeat with different join orders. | B receives a fresh distance and C eventually receives one; C does not remain unranged because it joined later. Presence stays visible while peers wait for their next ranging opportunity. |
| 24 — 5 attendee foreground pool | Keep five phones in one event with the viewer in Overview or Attendees. Record active/pending/outbound counts and each peer's first distance. | Every peer remains discoverable, the proactive NI working set stays within the reported learned/configured capacity, and every eligible peer eventually receives a ranging opportunity without permanent starvation. |
| 25 — Camera request against a busy foreground target | A opens Camera. B, C, and D remain in Overview or Attendees after establishing foreground ranging. Point A toward B, then C, then D. | Each target can eventually provide fresh NI evidence to Camera/matching. A target is not permanently blocked by its low-priority local proximity work; only a locally initiated foreground session yields, and total sessions stay within learned hardware capacity. |
| 26 — Two-phone distance-stall recovery | Keep two iPhones about 1–2 m apart with Attendees open for at least 10 minutes. Watch the distance-health signposts if distance becomes unavailable. | Distance remains periodically refreshed. If it stalls, last-measured/Updating distance may appear briefly and automatic recovery restores `Xm away` without leaving or re-entering the event. |
| 27 — Direction alive / distance dead | Reproduce the condition where NI direction or world-transform callbacks continue but scalar distance stops; confirm using per-peer age diagnostics. | Generic spatial health may remain healthy for Camera, while distance health degrades independently. A bounded soft recovery is followed by a fresh transaction/session if distance does not return; direction alone never prevents that recovery. |
| 28 — Three-phone triangle stall recovery | Place three phones about 1 m apart in one event and keep the live screen active. Exercise Attendees and Camera without navigating away. | All peers remain present and receive fair ranging opportunities. A peer cannot remain indefinitely on Updating distance; contention resolves automatically and Camera can reacquire fresh spatial evidence. |
| 29 — Recovery does not depend on Camera transition | Start in Attendees, switch to Camera and back, then repeat while leaving the UI on Attendees or Camera. | Screen transitions may reattach consumers, but the same distance recovery occurs automatically without navigation. Camera identity still requires its existing fresh distance, direction, and transform evidence. |
| 30 — One phone loses transport to all peers | With three phones in the same event, keep the live screen open and temporarily interrupt Bonjour/network discovery on one phone while preserving the event. Do not navigate away or restart the app. | The affected phone keeps attendee presence, marks distance unhealthy, retries the local NI session, refreshes BLE and Bonjour discovery on bounded intervals, and renegotiates each peer as transport returns. All three phones eventually show fresh distances without an event restart. |
| 31 — Three-phone late-join pair recovery | Join A, then B, then C. Keep B connected to both while A↔C is the edge showing Updating distance. Leave all phones in the event without navigating away. | A↔C retries and obtains fresh distance automatically. Logs show whether simultaneous Bonjour connections were reconciled and whether a stalled control path was reset; B’s healthy links remain available. |

Repeat the static, range-change, and body-block runs with a second phone at a
similar distance. Repeat crowd and crossing cases from the device matrix to
verify one-to-one identity gates under ambiguity. The 10- and 20-attendee
rotation cases still require real-device runs before claiming that attendee
count as physically validated.
