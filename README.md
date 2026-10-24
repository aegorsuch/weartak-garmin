# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently supporting the fenix 6 Pro family (6 Pro, 6S Pro, 6X Pro), fenix 7X,
and fenix 8 (47 mm and 51 mm variants).

## Project links

- Personal GitHub: https://github.com/aegorsuch/weartak-garmin
- Government repo: https://git.tak.gov/core/weartak-core/weartak-garmin

## Generic CoT and field-report hardening (WEARTAK-280)

Garmin's companion entity ingress already accepts arbitrary CoT point types.
Other `a-*` entities (including ADS-B aircraft and `a-f-Z` phones), spot markers
`b-m-p-s-m`, and shape centers now use a generic dot and label. Dots use blue
for friendly/assumed-friendly, red for hostile/suspect/joker/faker, green for
neutral, and yellow for unknown or non-affiliated types. Existing recognized
users retain team colors, and recognized explicit ground markers retain their
existing icons.

Known type families instead receive compact, affiliation-colored symbols:
fixed-wing aircraft (`a-*-A-C-F`), helicopters (`a-*-A-C-H`), military
air/UAS (`a-*-A-M`, including UAV `A-M-F-Q`), surface vessels (`a-*-S`),
and ground vehicles (`a-*-G-U-C-I-I`). Subtypes retain the family symbol.
SPI (`b-m-p-s-p-i`) uses a yellow crosshair. Unknown types retain the generic
dot; contacts retain their team dots and emergencies retain their alert icons.
Vehicle types are not treated as chat-capable team members merely because
their type contains `G-U-C`. Symbols are bounded vector strokes, not additional
retained images or entities.
The existing limits remain **999 retained entities** and **99 nearest drawn
items**, with alert priority. Ordinary points expire at the sender's `stale` /
`tStale` deadline or after five minutes without an update, whichever comes first.
Emergencies retain their separate explicit-cancellation behavior.

Coordinate-free `t-x-d-d` events remove the target (`link.uid` with `p-p`
relation, or the event UID), stop its Bloodhound target, and suppress older
replays for five minutes. Ordered deletes older than the displayed revision are
ignored. `u-d-c-c` circles support a numeric `radius` in meters or
`shape.ellipse` with equal numeric `major` and `minor` radii: greater than zero
and at most 100 km. Outlines are clipped, 32 segments each, with at most 16
drawn per frame. Other shapes, missing geometry, and near-polar circles use the
labeled center fallback; arbitrary polygon/ellipse geometry is not implemented.
The companion must relay these fields; the watch does not parse raw CoT XML.

Generic points never acquire a user-chat action. RGR/nPos sender replies are
offered only when a sender UID exists, and queued replies still reject a
missing destination. Repeated activation of the same active manual alert is
idempotent; changing its category or canceling and reactivating still creates a
new event. Transport retries retain their original `messageId`, including across
restart. The companion must deduplicate that ID before TAK writes; Garmin has
one phone transport, not multi-server fan-out.

The WearOS PPG concurrent-buffer bug has no equivalent here: Garmin's bounded
pressure buffer is updated and read in the same synchronous sensor callback.
Emergency/PLI location selection and CoT `ce` belong to the paired phone:
Garmin sends neither emergency nor PLI coordinates and cannot fix that phone
fallback by changing watch GPS state. No physical-device validation is implied.

### Fresh location on user actions

Opening the map, recentering on self, starting point/route navigation, changing
callsign/team/role, dropping/moving a self marker, and action-triggered PLI/chat
refreshes actively request a fix without waiting for GPS. With watch Location
Services enabled, the watch requests a one-shot local GPS fix and resumes
continuous updates afterward. The action uses its current best position
immediately; a returned fix updates the local map/navigation and PLI.
This does not override a disabled Location Services setting.

The phone also receives an immediate `location_request` control envelope:
`payload` contains `action` (`map`, `navigation`, `identity`, `self_marker`,
or `pli`), unique `requestId` / `messageId`, `createdAt`, and `relaySession`.
These hints are best-effort, like PLI, and never occupy the durable outbox or
block emergency writes on an older companion. Compatible companions actively
acquire a phone fix and republish PLI; they do not create another marker from
the hint. After the companion advertises `phoneLocation: true` in `relay_status`,
self marker events separately carry `locationSource: "phone"`, so
the companion publishes its best fix immediately and updates the **same UID**
when a fresh fix arrives. Explicit map-tap coordinates remain intentional.
Self markers without a watch fix can be handed off immediately; up to 20 local
pending records survive an acknowledgement/restart for up to 24 hours.

The companion returns resolved/fresh self-marker positions using ordinary
`entity` envelopes with the original `garmin-marker-...` UID, `lat`, `lon`,
`type`, `callSign`, `isPoint: true`, `time`, and `stale`. Garmin reconciles them
into the saved local marker without an incoming duplicate or outbound echo.
The `relay_result` acknowledgement contract is unchanged. Phone GPS never
becomes a synthetic contact or replaces the watch's own navigation fix.

### Route-start and compass parity (WEARTAK-252/253)

Starting a whole route closes the route/picker screens and returns to the main
menu, retaining active navigation. Garmin's main screen is a native menu rather
than a compass dashboard: its Bloodhound entry is hidden while any target is
active and restored when tracking stops. Active guidance and stop controls remain
available on the map's Bloodhound panel; the dedicated compass retains its
route/hound target icon. The own-package-name managed-configuration issue does not apply to
this Monkey C application.

## Routes (phone companion route protocol v1)

Updated iPhone and ATAK companions can send route geometry to the watch. Open
**Map > Layers > Routes** to browse routes and their nonblank named points.
Selecting a route opens whole-route details (named/total point counts,
source server, mission and sender), with **Select named point** and **Remove from this
watch**. Tapping a visible route line also selects the whole route. Tapping a
point offers both that point and its whole route in **Select Map Item**;
overlapping routes remain separate by source server. Point details include a
**Whole route** action. Details show the route, source server,
mission, sender UID and coordinates, with **Bloodhound** / **Stop Bloodhound** and
sender **Chat** when available. Bloodhound uses the existing GPS range/bearing
display and proximity alerts; this is not turn-by-turn navigation.

### Bloodhound picker (Garmin button-first layout)

The picker uses one native row per route, received point, visible contact, or
locally placed marker. Rows have a type glyph, name and a localized subtitle
(`Route / point count / nearest distance`, or `Marker`, `Point`, `Contact` and
distance). Distances use meters below 1 km and kilometers above it. Active route
subtitles show **Point X of N / remaining distance left**, and the active type
glyph is amber. Native rows are used on every supported Garmin: two independent in-row touch buttons and a custom amber
row background/border are **not** implemented on Garmin's Menu2. Native focus and
row colors remain device-specific; the amber glyph identifies the active row.

Selecting a row opens the approved Garmin action-menu fallback:

- **Show on map** (grey crosshair): centers tightly on a point without changing
  Bloodhound. For routes it enables the route layer and fits the entire received
  geometry with padding, including routes crossing the date line.
- **Bloodhound** (green ATAK hound): starts a point/marker/contact immediately.
  For a route it opens **Start nearest**, **Start from beginning**, **Cancel**.
  Nearest has a grey hound and **Location required** when no position is known;
  choosing it cannot change the active target. Nearest's available icon is green.
- **Stop Bloodhound** (red circle, white stop square): replaces the hound action
  for the sole active target, including whole routes.
- **Details** retains the existing route/point/contact details, point RGR/nPos,
  chat and removal flows.
- **Remove** provides direct deletion from the picker action menu (24 px trash
  glyph). Received items are dismissed locally, dropped markers use their existing
  delete workflow, and whole routes open the existing watch-only confirmation.
  **Cancel** returns without changing the target.

This menu fallback deliberately avoids touch-only controls and large image
assets. Action icons are 24 x 24 px. The picker refreshes on route delivery,
GPS updates, target changes and when shown again. **Remove All** now clears every
received route as well as received points/alerts, including when there are no
received points. It stops navigation of a removed route. Contacts and dropped
markers retain their existing separate removal controls. Native picker layout,
icon legibility and translations still
need physical-watch/native-speaker acceptance.

#### ATAK artwork attribution

The resized/composited hound and crosshair artwork in
`resources/images/picker-hound*.png` and `picker-crosshair.png` comes from
[deptofdefense/AndroidTacticalAssaultKit-CIV](https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV),
**GPLv3**: [`nav_bloodhound.png`](https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV/blob/main/atak/ATAK/app/src/main/res/drawable-xxxhdpi/nav_bloodhound.png)
and [`ic_crosshair.png`](https://github.com/deptofdefense/AndroidTacticalAssaultKit-CIV/blob/main/atak/ATAK/app/src/main/res/drawable-hdpi/ic_crosshair.png).
The source copies were provided by the user. The user approved their use and
will review licensing/distribution obligations before release; this attribution
is not a completed licensing review. The stop square and type glyphs are drawn
for this app rather than copied from ATAK.

### Follow a whole route with Bloodhound

The **Bloodhound** picker lists each received route once, with its name, total
vertex count and distance to its nearest vertex when GPS is available. Select a
route, choose **Bloodhound**, then **Start nearest** or **Start from beginning**. Nearest requires a
known position (otherwise the menu explains **Location required**, with no silent
fallback). It projects the position onto the closest route segment and selects
the next checkpoint at or ahead of that along-route position; equal projections
use the earliest segment. Beginning targets the first checkpoint. Explicit
`b-m-p-w` points are checkpoints; controls (`b-m-p-c`) and missing types remain
geometry rather than objectives. The final original vertex is always the
destination fallback, including routes containing only controls.
Both modes preserve original vertex indices and unnamed geometry, not the
filtered named-point list. Whole-route details also provide a **Bloodhound**
action; individual point Bloodhound remains available and does not auto-advance.

The existing map/compass shows the route name, **Point X of N** (one-based), and
remaining distance: current position to the target plus every remaining route
segment. The arrow continues to point at the current checkpoint. Arrival radii
are **10 m walking/swimming**, **20 m driving**, **100 m watercraft** and
**1000 m flying**, inclusive; absent/unrecognized methods use 10 m.
Entering a checkpoint's bubble remembers arrival, but advancement waits until
the closest-segment projection reaches/passes that checkpoint's along-route
position. Projection alone cannot skip an unvisited checkpoint. Dense/duplicate
checkpoints advance in order without discarding control-point geometry.
Entering the final destination bubble completes the route even if earlier
checkpoints were missed: **Route complete** clears the target.
Missing, unavailable or poor-quality GPS never advances the route; beginning can
wait for a usable fix.

Standalone guidance approximates ATAK's checkpoint/projection rules, not its
native spatial index, cue engine, road routing, turn instructions or off-route
recalculation. Connect IQ `Position.Info.accuracy` provides only a quality enum,
not horizontal circular error in meters: Garmin gates advancement on usable/good
quality but does **not** invent a CE value or inflate the method radius. Paired
ATAK navigation uses the phone's real GNSS uncertainty.

Select the active route again for **Stop Bloodhound**, open its Bloodhound
chooser/details for progress and **Stop route**, or tap the map's
Bloodhound panel. Starting a different route or selecting any other Bloodhound
target stops the previous route. Removing/resetting its route also stops it.
Geometry updates retain the original target index (or stop if that index no
longer exists), reset remembered arrivals, and move a standalone control target
to the next checkpoint/destination. Changed vertex order changes the target at
that index.
Standalone follow state is in memory. Switching away from a synchronized ordinary
point still stops its previous phone Bloodhound session, as with individual
route-point tracking.

### Two-way Android Companion route navigation (v1)

Compatible Android Companions advertise `routeNavigationVersion: 1` in
`relay_status`, in response to the watch's `relay_hello` capability. While that
capability is present, starting a whole route on either device starts navigation
on both. **ATAK owns advancement and completion**, so watch GPS cannot race the
phone or consume checkpoints. ATAK's method-dependent arrival radii are 10 m for
walking/swimming, 20 m for driving, 100 m for watercraft, and 1000 m for flying
(subject to ATAK preferences and GPS uncertainty). This is ATAK route guidance,
not a new Garmin turn-by-turn engine. Unpaired watches and older/iPhone companions
without this capability use the standalone checkpoint guidance above.

Garmin uses Connect IQ dictionary envelopes, never raw route CoT XML:

- Phone geometry arrives first through the existing bounded `route` protocol.
  `phone_route_navigation` then carries `version: 1`, the current `relaySession`,
  UUID `sessionId`, increasing integer `sequence`, `action` (`start`, `progress`,
  `stop`), `serverId`, `routeUid`, and zero-based original `targetPointIndex` for
  start/progress. Stop requires Boolean `completed`. Unknown or oversized routes,
  invalid indices, stale sessions and older sequences cannot change the target.
- Watch controls use `watch_route_navigation` with `version: 1`, `relaySession`,
  distinct UUID `requestId`, watch-proposed UUID `sessionId`, `serverId`,
  `routeUid`, `action` (`start` or `stop`), and `targetPointIndex` for start.
  `route_navigation_ack` must echo `relaySession`, `requestId`, `sessionId` and
  Boolean `ok` (with `error` when false). A successful start also requires its
  authoritative phone snapshot within eight seconds. No watch progress command
  is sent.

Stops, replacement targets, route removal and Remove All send session-scoped stop
controls. Phone-originated progress/stops do not echo. Rejected/timed-out starts
and transport failures display an error rather than silently claiming sync.
Disconnect clears phone-owned guidance rather than silently switching arrival
rules; standalone guidance can then be started explicitly. Snapshots follow the
existing 8-route / 64-vertices-per-route / 128-total-vertices watch limits, and
source-server identity remains part of every route selection/removal.

[RouteNavigation.mc](source/RouteNavigation.mc) contains pure nearest-index,
arrival advancement and remaining-distance logic. The simulator suite in
[RouteNavigationTests.mc](source/RouteNavigationTests.mc) covers missing GPS,
nearest-segment ties, dense checkpoints, method thresholds, projection/departure,
control-point/final fallback, poor-quality fixes, completion, original vertex
order, dateline distance, switching targets, route removal/reset/update, picker
summaries, GPS-dependent chooser refresh and standalone tracking.
[RouteNavigationSyncTests.mc](source/RouteNavigationSyncTests.mc) covers
two-way starts/stops, authoritative progress/completion, capability negotiation,
session/sequence rejection, acknowledgement failures/timeouts, disconnect,
removal/reset and replacement targets.
[BloodhoundPickerTests.mc](source/BloodhoundPickerTests.mc) covers icon resources,
point/route map focus (including date-line and polar coordinates), immediate
point/marker/contact tracking, active summaries, stop actions and stale/no-fix
rejection. New labels have resource entries in every
supported locale; physical watch acceptance and native-speaker review remain
required. The non-Pro fenix 6/6S are no longer supported (128 KiB memory limit).

The route-point list hides missing, empty and whitespace-only names, with a
localized **No named points** empty state when needed. It retains original vertex
numbers and coordinates so repeated point names remain distinguishable; selecting
a filtered row still targets that original vertex, not its position in the list.
All geometry and unnamed map-point/Bloodhound access remain unchanged.
Chat actions recheck the current sender before
opening a conversation when route metadata changes.

**Remove from this watch** requires a second confirmation, initially focused on
**Cancel**, and names the route and server. It removes only the current in-memory
watch copy and stops Bloodhound only if tracking one of that route's vertices.
It sends no route-delete command to the phone or TAK server, does not affect
another server's route with the same UID, and does not delete individual vertices.
The confirmation warns that subsequent phone updates or refresh/reconnect replay
may restore the route; this is not a permanent source-route dismissal.

**Show Routes** controls route lines and point hit-testing without stopping an
active Bloodhound target. Point selection and tracking identities include the
source server and route UID, so identical UIDs on different servers stay separate.
All vertices are selectable; the watch does not simplify the route. Geometry
updates move the active target at its vertex index. Removal of that route stops
tracking. A changed vertex order therefore changes the target at that index.
Geometry updates immediately reevaluate proximity; invalid or not-yet-available
map bounds temporarily skip route drawing and hit-testing until bounds recover.

**Routes > Refresh** requests an authoritative reset/replay from the current phone
companion. Route snapshots and phone-relay disable clear routes and stop route
tracking; routes are held in memory, not saved across watch restarts. Refresh after
a failed handoff repairs the watch display. Route delivery uses SDK handoff rather
than end-to-end acknowledgements; physical phone/watch acceptance is still needed.
Route-point range/bearing and proximity alerts run locally with either companion.
Synthetic route-point IDs are not sent as native ATAK Bloodhound targets because
intermediate vertices need not exist as ATAK point map items. Switching from a
synchronized ordinary point to a route vertex stops the previous phone track.
Existing ordinary-point Bloodhound synchronization is unchanged; the iPhone
companion does not provide phone Bloodhound coordination.

The watch advertises numeric `routeVersion: 1` in `relay_hello` and
`entity_sync_request`. Companions gate route messages on that capability:

| Message | Payload |
| --- | --- |
| `route` | `routeVersion`, `serverId`, `uid`, `name`, `points: [{lat, lon, name?, type?}]`, optional `missionName`, `senderUid`, `method` |
| `route_remove` | `routeVersion`, `serverId`, `uid` |
| `routes_reset` | `routeVersion` |
| `routes_error` | `routeVersion`, `error` |

Each route is replaced atomically after validation. Bounds are **8 routes**,
**2–64 vertices per route**, **128 vertices total**, and **6,000 UTF-8 bytes per
serialized envelope** on the companion. Text bounds in UTF-8 bytes are server ID
64, UID 128, route/point name and point type 64, method 32, mission/sender UID 128,
error 256. `method` is `Walking`, `Swimming`, `Driving`, `Watercraft` or `Flying`;
older companions may omit it and point `type`. Latitude and
longitude must be finite and within geographic ranges. Over-capacity/invalid
updates produce an explicit error and retain the previous valid geometry, if any;
tracking that older geometry continues until corrected, removed or refreshed.
The ATAK companion automatically fills freed capacity after route removal or
shrinking geometry. Existing published routes take priority; new candidates are
selected in source-server/UID order. Immediately rejected SDK updates and removals
remain pending for the next map/link reconciliation, without resetting local
tracking. Invalid geometry is retained only for its originating ATAK map item,
never for a different server's route with the same UID.
No raw route CoT XML is logged by the adapters.

Bloodhound route target IDs use
`route-point:<server UTF-8 length>:<server><route UID UTF-8 length>:<UID>:<zero-based vertex index>`.
This length-prefixed encoding avoids delimiter collisions.

[RouteTests.mc](source/RouteTests.mc) covers atomic validation, capacity boundaries,
same-UID/different-server selection, individual point coordinates, active target
updates/removal, clipped-line hit thresholds, date-line/overlap selection,
whole-route menus, confirmation/cancellation, watch-only removal and unchanged
route envelope dispatch. Named-list tests cover blank names, duplicate names,
original source/index identities, named/total counts, empty state, unchanged
geometry and unnamed map/Bloodhound access.
New route labels use English fallback resources pending translation.
`monkey.jungle` limits compilation to `source` so nested Git worktrees are not
compiled as duplicate application sources. Test-enabled builds can be run with
`monkeydo ... fenix7x /t`; the full test-enabled fenix6pro build currently exceeds
that device's global-member limit.

### TAK-server Data Package delivery boundary

This repository contains only the Connect IQ watch application. `TakClient`
receives normalized route dictionaries over the existing phone relay; it does
not parse raw `b-m-r` route CoT, handle `b-f-t-r` package advertisements, download
`Marti/sync/content?hash=...`, or parse ZIP/XML. No new package capability is
advertised by this change. A `routeVersion: 1` watch can display package routes
**only after a compatible ATAK/iPhone companion imports and normalizes them**.
Package import is not operational end-to-end from this watch-only change.

The required companion implementation must:

- Accept route-only TAK Data Package ZIPs, validate the advertised SHA-256 and
  bounded download size, and fetch only from the configured TAK HTTPS origin
  with TLS validation. Bind credentials to that origin; reject untrusted
  redirects/URLs rather than forwarding credentials or permitting SSRF.
- Bound ZIP entry count, compressed/uncompressed sizes, expansion ratio and XML
  complexity; reject unsafe/duplicate archive paths without writing entries to
  arbitrary filesystem locations. Disable DTDs/external entities.
- Read `MissionPackageManifest` content entries, import only non-ignored route
  CoT through the companion's existing `b-m-r` route parser, and ignore package
  execution/import/delete instructions (`onReceiveImport`, `onReceiveDelete`).
  Do not execute arbitrary package contents or delete source/server data.
- Send validated routes through the existing route v1 envelopes and enforce
  their capacity/text/envelope limits without silently simplifying geometry;
  report failures through `routes_error`. No raw archives, URLs, credentials or
  XML should be sent to the watch.

Remaining physical-device acceptance: import a route-only TAK-server package on
each companion, check Connect IQ delivery/replay/error reporting, tap lines and
overlapping vertices (including across the date line), select an unnamed point
for GPS Bloodhound, cancel then confirm watch-only removal, and verify that the
phone/server route and other watch routes remain unchanged. Confirm label
wrapping, button navigation and memory use on supported devices.

## Rights and contacts

### Rights

Unlimited rights granted to TAK Product Center.

### Point of contact

Alex Gorsuch on chat.tak.gov or Signal.

### Repositories

The TAK Forge repository is canonical. GitHub is a secondary repository.

## Installation

1. Download the `.prg` matching your watch from the latest GitHub release.
2. Connect the watch to your computer with its USB cable and wait for it to
	appear as a removable drive.
3. Open the watch drive and navigate to `GARMIN/Apps`.
4. Drag only the matching `.prg` into the `GARMIN/Apps` folder. For a fēnix
	7X running version `5.8.3-9f1ec78`, use
	`WearTAK-Garmin-fenix7x-5.8.3-9f1ec78.prg`.
5. Safely eject the watch, disconnect the USB cable, and launch WearTAK from
	the watch's app list.

Do not copy the `.prg.debug.xml`, other device builds, or the `.iq` package to
the watch. The `.iq` package is the release bundle for Garmin's supported
distribution workflow; direct USB sideloading uses the device-specific `.prg`.
Garmin uses the watch's system language for localized app text.

The app uses Garmin Connect IQ phone messages (`Communications.transmit`/
`registerForPhoneAppMessages`) to relay watch input to the WearTAK ATAK
companion. ATAK owns TAK server connectivity, mTLS credentials, identity, and
the authoritative phone location for PLI; the watch provides a secondary
display and input surface.

This channel is routed through Garmin Connect Mobile and the Connect IQ Mobile
SDK on the phone side; it is unrelated to the direct BLE GATT link the ATAK
plugin already uses for Samsung/Wear OS watches. Garmin Connect Mobile is only
a runtime requirement for users pairing a Garmin watch specifically — it has
no effect on Samsung/Wear OS users of the same plugin. Connect IQ apps cannot
act as a BLE peripheral/GATT server, so the watch cannot use the plugin's
existing direct-BLE transport; the phone-side plugin needs a second,
Garmin-specific transport using the Connect IQ Mobile SDK to receive these
messages. The ATAK companion has a separate Garmin Connect IQ transport in its
TAK Forge repository.

Message envelopes are dictionaries of the form
`{"msgType": <string>, "payload": <dictionary>}`. The Bloodhound and settings
message families (`bloodhound_control`, `bloodhound_control_result`,
`set_settings`, `settings_set_ack`, `request_settings`, `watch_settings`) use the
same type names and payload field names as the WearOS WearTAK app's BLE
protocol; a narrow companion adapter normalizes the envelope and adds
session/correlation metadata for the Connect IQ link. Garmin payloads are
Connect IQ dictionaries rather than newline-delimited JSON, and the watch never
parses raw CoT XML — the companion must normalize ATAK markers, alerts, and chat
into the `entity`, `entities`, and `chat` envelopes.

### Phone-relayed remote users (WEARTAK-160)

The watch advertises `entitySyncVersion: 2`, `watchUid`, and its current
`relaySession` in `relay_hello`. Companion v2 `entity`, `entities`, and
`entity_remove` messages carry that session on the top-level envelope. Missing
or stale sessions cannot update or remove v2 phone-user records. Only one active
Companion watch link may receive the v2 user stream; ambiguous routing clears
phone-user copies until an exclusive route is available. The watch excludes
phone/watch UIDs, not matching callsigns, and accepts supported remote contacts
across ATAK contact types rather than only `a-*-G-U-C`.

A replacement `entities` payload carries `entities`, `replaceUsers: true`,
`scope: "phone-relay-users"`, `excludedUids`, `limit`, and `truncated`. It removes
only absent phone-relay user sources; direct-network users with the same UID and
dropped points survive. `entity_remove` uses `{uid, scope: "phone-relay-users"}`
with the same source-only semantics. When one source expires or is removed,
another source can supply its coordinates. Explicit relay stop/new session
clears phone-user copies; transport loss retains them only until their stale
deadline. Expiry is checked on ingress and the 60-second prune timer; legacy
users without a deadline retain the five-minute fallback. V2 user updates are
ignored until a current-session snapshot supplies distinct phone/watch UIDs,
including the watch's own UID; missing identity data fails closed.

Snapshots are limited to the nearest 50 entities and the watch bounds live
phone-user state at 50, requesting a fresh snapshot on overflow. The companion
reports truncation and the watch displays a warning. The existing 999-entity /
nearest-99 drawing limits remain; the watch warns before replacing the oldest
retained user at capacity. Pending phone changes coalesce by UID and cap at 512.
SDK handoff is not watch receipt or TAK delivery, and entity sync has no
delivery-ACK/retry guarantee; a new hello/sync rebuilds state and stale
deadlines clean up lost removals. `PhoneAppMessage` exposes data, not an
authenticated sender-phone/app identity, so session fencing relies on Garmin
Connect Mobile's app routing rather than independent authentication. Simulator
tests do not establish paired-hardware delivery behavior.

Garmin settings use a bounded UUID `transactionId` in the request or set payload.
The watch copies it to `watch_settings` and `settings_set_ack`; the companion only
confirms a settings write after both the positive acknowledgement and the matching,
exact supported-profile snapshot arrive, in either order. A negative save or
storage error returns a correlated failure and no success snapshot. Garmin
settings contain only callsign, team, role, reporting interval, and the explicit
phone-management flag; TAK server credentials and P12 data remain on the phone.
Legacy untagged settings requests still receive untagged responses for older
clients, but the current Android companion never treats an untagged response as
confirmation. Watch/phone link loss, a new settings attempt, and a changed profile
fence out delayed replies; confirmation expires after 15 seconds.

### Releasing phone-managed settings (WEARTAK-161)

Intentional phone Disconnect, disassociation, or unpair sends
`release_phone_management` with payload `{"requestId": "<UUID>"}` before stopping
the route. Its envelope must also carry the current `relaySession` from
`relay_hello`. The watch replies `phone_management_release_ack` with
`{"requestId": "<same UUID>", "ok": <Boolean>, "error": "<optional reason>"}`.
The companion must wait for a positive, correlated acknowledgement; timeout or
failure is not permission to claim the settings were unlocked. There is no
untagged/legacy release fallback. Invalid request IDs receive a negative reply
without a correlation ID.

Only an active matching relay session may release ownership, including an
idempotent repeat when already unmanaged. Missing/stale sessions and stopped
relays fail without changing settings. The watch persists only the management
flag before acknowledging; callsign, team, role, and reporting values remain.
The watch's explicit relay Disconnect/stop control uses the same release helper.
A storage failure retains the lock and reports failure (the local stop is
aborted). GCM/BLE interruptions, transmit errors/retries, suspension, and app
relaunch do not clear persisted ownership. Existing manual settings controls
remain available.

Unpairing outside Companion cannot itself unlock settings: use Companion's
acknowledged release before unpairing or the explicit watch relay stop while
active. The watch cannot distinguish two senders with access to the same GCM
route and current session. The phone must validate its intended association
before sending and keep the route open until the ACK arrives. Hardware
association/replay behavior still needs paired-device acceptance testing.

The watch can also use the iPhone WearTAK Companion's Garmin route without an
ATAK plugin or an Apple Watch. That route owns TAK connections and phone GPS;
it does not implement Bloodhound coordination. Authorize the watch through
Garmin Connect Mobile, select it in Companion, then enable **WearTAK Companion**
under the watch's **TAK Relay** submenu. **Companion Setup** provides an iPhone
setup hint. **ATAK Relay** remains available for Android users; both toggles
control and display the same underlying phone relay, not separate simultaneous
connections. The phone's authorized companion determines the destination.

For queued marker, delete, emergency, and chat events, `relay_hello` carries a
`relaySession`. A matching `relay_status` advertising `reliableDelivery: true`
enables correlated `relay_result` acknowledgements. SDK handoff alone no longer
removes these events: the phone acknowledges after at least one eligible server
socket accepts the write, not after remote TAK receipt. Missing acknowledgements
time out after 30 seconds; failed events remain queued with 5-to-60-second
exponential retry delays. Old callbacks and unrelated/malformed results cannot
complete a new attempt. Existing queue limits (20 events, 24-hour expiry) remain.
The iPhone persists stable event IDs and original CoT to suppress accepted
replays across restart; a crash between socket acceptance and ledger persistence
can still cause a duplicate. Replies are not an exactly-once delivery guarantee.

To preserve older companions, queue sending waits up to 15 seconds for capability
negotiation, then falls back to SDK handoff if reliable delivery has not been
negotiated in that watch process. A lost hello response never downgrades a process
that already negotiated reliable delivery. The simulator tests in
[ReliableRelayTests.mc](source/ReliableRelayTests.mc) exercise negotiation,
exact timeout/retry boundaries, capped backoff and reset, transmitted payloads,
stale callbacks, reconnects, malformed/duplicate results, storage failures,
in-flight replacement/expiry, and legacy fallback. Their clock, storage, and
transport are isolated; they never register live phone callbacks or start the
production outbox timer. Storage-failure cases verify events remain queued until
acknowledgement or handoff removal can be persisted.

### Chat transport contract (WEARTAK-118)

Garmin is the watch UI/transport, not the owner of ATAK group membership or
server routing. A group-aware companion normalizes inbound `chat` or
`chat_received` payloads as follows:

| Field | Meaning |
| --- | --- |
| `uid` | Message/event ID; never the reply destination |
| `senderUid`, `senderCallsign` | Individual sender identity |
| `msg` | Message text |
| `receivedAt` | Receive timestamp in epoch milliseconds |
| `conversationUid`, `conversationTitle` | Authoritative conversation identity/title |
| `isGroup` | Explicit Boolean identifying a group |

Direct conversations use `senderUid` as their destination; groups use
`conversationUid`. Legacy Garmin `chat` payloads containing only
`uid` (sender identity), `sender`, and `text` remain accepted. Missing group
destinations are rejected with an on-watch error rather than guessed from the
event ID. Conversation history is in-memory, bounded to 20 rooms and 20 total
received messages; it is not a synchronized phone history or a group directory.
Malformed or empty canonical `senderUid` values are rejected, even if a legacy
`uid` or `messageId` is present; event IDs must never become reply destinations.

For backward compatibility only, an older iPhone envelope retains `uid` as sender identity,
`sender`/`text` as display content, and `messageId` as event identity, with
`conversationUid`, `title`, and Boolean `isGroup`. The watch also accepts this
shape; `messageId` distinguishes it from ATAK's event-ID `uid` convention.
Without `receivedAt`, local arrival time orders the conversation. New companion
emitters must use the canonical fields above, including `conversationTitle`;
`title` is accepted only as an ingress compatibility alias.

Outbound `chat` payloads contain `roomUid`, `roomTitle`, `isGroup`, `msg`,
`text`, and `cs`, plus the existing queue-assigned `messageId` and `createdAt`.
All companions must consume these canonical outbound room fields; conversation
fields are inbound metadata, not alternate outbound routing.
Direct payloads also contain `recipientUid` and `replyTo`, both equal to the
individual UID. Group payloads omit these direct aliases. The companion resolves
the group UID to its authoritative membership and rejects unavailable or
unwritable groups; watch-side participant lists are not routing authority.
**All Chat Rooms** is one explicit broadcast destination, not iteration over
saved rooms or direct contacts.

The reviewed ATAK companion WEARTAK-118 branch implements the WearOS BLE route,
not a Connect IQ ingress adapter. Its native contact/group routing alone does
not establish Garmin support. The separate Garmin transport must map watch
`messageId` to the BLE envelope's `msgUid` and payload `uid`, preserve
`roomUid`/`roomTitle` (accepted aliases of BLE `rmUid`/`rmTitle`), `isGroup`,
`msg`, and `cs`, and invoke the companion chat handler. `replyTo` is not an ATAK
BLE chat destination field; the adapter must route using `roomUid`, including
direct conversations. It must preserve stable message IDs and translate relay
acknowledgements, rather than interpreting BLE handoff as TAK delivery.

On receive, the adapter must translate `ChatRelayPayloadBuilder`'s
`chat_received` envelope into a Connect IQ dictionary without changing the
canonical payload fields. The companion remains responsible for confirming
the phone's membership in named groups, suppressing self/watch echoes, resolving
actual `GroupContact`/`IndividualContact` recipients, and rejecting unavailable
contacts. `participantUids` may be retained as metadata but are not watch-side
routing authority. No production Connect IQ-to-native-chat path was verified
in that BLE-only branch; it must not advertise Garmin `chatGroups` based solely
on its WearOS group tests.

Non-broadcast group sending requires the current-session `relay_status` to
advertise `chatGroups: true` alongside the existing Boolean `reliableDelivery`.
Companions must advertise this only after both group receive normalization and
explicit group reply routing are proven. ATAK named groups must resolve to real
`GroupContact` destinations, not merely room-labelled server XML. Unavailable
groups must never fall back to broadcast. Older iPhone relays ignore `roomUid`, so
sending them a group without this gate could broadcast unintentionally.
Unsupported group sends show an error before enqueue. Already queued groups are
skipped when capability is absent; before admitting any new eligible event,
unsupported queued groups are removed with an explicit notification so they
cannot fill the outbox and block emergency alerts. In-flight events are protected.
Removal and admission are persisted together; storage/admission failure restores
the previous queue. Other pending events retain their existing relative order.
Reconnect, relay stop, or relay failure resets the capability. This does not
claim parity with companions that have not implemented this contract.

The current iOS companion WEARTAK-118 implementation intentionally does not
advertise `chatGroups`: its room-labelled CoT does not yet establish verified
member-destination routing. Garmin can display its group messages, but named-group
sends through that companion remain blocked. Explicit All Chat Rooms and direct
messages do not require this capability. This is a support boundary, not verified
end-to-end group parity; Android/ATAK group support likewise requires a proven
group-aware Garmin adapter.

`ChatConversationTests.mc` exercises pinned picker rows, selected direct rooms,
mixed receive ordering, destination mapping, legacy input, malformed groups,
deduplication, retention bounds, and capability-gated queue transmission.

> Important: Garmin relay behavior requires both the watch application and the
> ATAK companion's Garmin Connect IQ integration. A watch-side relay toggle alone
> does not establish a TAK server connection. Hardware end-to-end settings
> confirmation still needs acceptance testing on a paired watch.

## Current capabilities

The app opens to a native, scrollable Connect IQ menu. The Garmin-to-ATAK phone
relay depends on the companion's Garmin Connect IQ receiver. These are the watch
features currently available:

- Bloodhound is always first in the main menu unless explicitly requested
	otherwise. The remaining items, including new additions, stay alphabetized:
	Chat, Clear 2525D, Drop 2525D, Manual Alert, Map, and Settings.
- Open TAK Relay inside Network Preferences. ATAK Relay is the currently
	integrated option; iTAK and TAK Aware are marked Teaming, and WearTAK
	Companion is marked Developing. BLE relay status means a phone message was
	written; it does not acknowledge TAK-server delivery.
- Open the TAK Channels menu from the map's top-right Channels control. Channel
	requests require a compatible companion relay; the phone must keep any P12
	certificate material and send only channel names, directions, bit positions,
	and active state to the watch.
- Manual Alert becomes locally active even if the phone relay is stopped. When
	the relay is active, the alert is sent to the companion; selecting the active
	main-menu row again clears it.
- The main-menu header displays the selected **Top Display Metric**. Open
	**Settings > Display Preferences > Top Display Metric** (also available by
	tapping the header on supported touch models) for a simple native list:
	**Exertion**, **Heart Rate**, **Lat/Long**, **MGRS**, **Skin Temp**, **Steps**.
	The six choices sort by their localized displayed labels; existing Exertion,
	Heart Rate and Steps selections survive, while removed/invalid stored choices
	reset to Exertion. This does not remove any underlying sensor feature.
	Lat/Long uses signed decimal degrees (five decimals); MGRS reuses the map's
	UTM-grid formatter and is unavailable outside 80 S–84 N. Coordinates require
	location services and a usable/good watch fix no older than 60 seconds; without
	one the header says **Waiting for location**. Coordinate values use two lines
	to fit small, round watches. Steps is the watch's daily activity count.
	**Skin Temp** remains selectable but explicitly **Unavailable**: the current
	Connect IQ sensor API exposes temperature, not a verified skin measurement.
	Exertion, Heart Rate, Skin Temp and Steps show **Disabled** when physiological monitoring
	is explicitly off, ahead of any cached reading or unavailable capability.
	With monitoring on, missing physiological data shows **Unavailable**. Coordinates
	still work with monitoring off. Hiding Steps does not stop the watch's daily
	activity collector.
	The same list has independent **Enable alerts**, **Alert thresholds >**, and
	**Physiological monitors** rows, usable with buttons as well as touch. They use
	the existing physiological alert/heart-rate runtime; merely opening the screen,
	selecting a metric or opening thresholds never enables either setting.
	Thresholds remain editable while alerts are off; disabling clears pending
	physiological warning timers and active physiological alerts, not environmental
	alert settings or the manually activated emergency alert.
- The Settings row displays the configured callsign and is blank when the
	callsign is unset.
- Open and navigate the map.
- The main menu's Drop 2525D action opens a native scrollable list of
	Hostile, Neutral, Friendly, and Unknown marker types. The remembered default
	is marked; selecting a type drops at the current location. Clear 2525D opens
	the saved marker list or the Clear Last Marker action.
- Drop a 2525D point from the main menu or map; new point titles use the
	configured callsign and UTC time in `CALLSIGN_HHMMSSZ` format. With no callsign,
	the title is the UTC timestamp alone.
- Hold on the map to drop a point. The default starts as Unknown, then remembers
	the last successfully dropped or changed marker type across launches. Unknown
	can be selected again; title/remark-only edits do not change the default.
- Browse saved Dropped Markers newest first, with symbol, title, type, and local
	drop time. Edit or delete individual markers, or confirm Clear Last/Clear All.
- Set a callsign, choose one of 14 My Team colors, and select a MIL or LEO role
	with its subrole under Callsign and Device Preferences. The team color is used
	for the self marker and Bloodhound direction arrow; tracked point icons remain
	unchanged.
- Use **Chat** to open a conversation picker: **All Chat Rooms** is pinned
	first, **Select User for Chat** second, then direct and group conversations
	in newest-received order. User selection lists current map users (not dropped
	points or alerts), opens a direct conversation, and keeps it in the normal
	room list even before a reply arrives. Opening a room offers received messages,
	quick replies, and **Send** for text entry. Sending does not move a room ahead
	of a more recently received conversation.
- Configure Dynamic or Constant Reporting intervals, Wi-Fi battery-saving
	preferences, and Physiological Monitoring under Reporting Strategy. Reporting
	intervals control Garmin-to-companion PLI updates when the ATAK relay is
	connected; direct Sit(x) PLI transport is not implemented on Garmin.
	Physiological Monitoring controls heart-rate sampling. When the ATAK relay is
	connected, Garmin sends PLI updates using the selected reporting strategy;
	CoT stale time is twice the active interval plus 15 seconds. Dynamic mode uses
	the stationary, on-foot, vehicle, and alerting intervals according to current
	movement/speed and alert state. Wi-Fi preferences are stored only because
	active SSID detection is not implemented on Garmin. The adjacent BATDOK toggle
	adds an `includeBatdok` flag to Garmin PLI messages. The companion must consume
	that flag to add AMIST; the current companion implementation does not yet do so.
- Callsign, team, or role changes send an immediate PLI update when the relay is
	connected. Opening the map, sending a manual alert, or sending chat can also
	trigger a PLI update when location services have a recent fix; if the fix is
	stale, the watch requests a one-shot location update and resumes continuous
	tracking when it arrives. These action refreshes are throttled to avoid excess
	relay traffic. The companion continues to supply the authoritative phone
	location.
- Admin Preferences and Developer Preferences always appear in Settings but
	do nothing until developer mode is unlocked by tapping the version row eight
	times within 1.5 seconds. Admin Preferences holds the Network Preferences
	Lock; when locked, Network Preferences cannot be opened from Settings.
	Developer Preferences holds Verbose Logging and Diagnostics.
- The paired phone can manage watch identity and reporting. A `set_settings`
	message applies `callsign`, `team`, `role`, and `reportIntSecs`, and the watch
	replies with `settings_set_ack` followed by a `watch_settings` echo of the
	values it actually stored; `request_settings` returns the same echo on demand.
	Values are validated first, so an unsupported team or role is rejected without
	applying any part of the message. A `reportIntSecs` value also switches the
	watch to static reporting so the phone interval takes effect. While
	`phoneManagedSettings` is set, My Callsign, My Team, My Role, Reporting
	Strategy, and Network Preferences are read-only and show the phone-managed
	value; User Metrics and the other watch-local settings stay editable. Losing
	the relay returns control to the watch.
- View point details as native scrollable rows for marker type/drop time,
	distance, bearing, latitude/longitude, and MGRS, followed by Bloodhound,
	title, remark, marker-type, move, delete, and back actions.
- View self coordinates in latitude/longitude and MGRS.
- Tap the self marker to view separate latitude and longitude rows and MGRS.
- Tap a remote map user to open Range, **Chat**, **Bloodhound** / **Stop
	Bloodhound**, Remove locally, and Cancel. Chat opens that user's direct
	conversation; Bloodhound, directly below it, starts tracking the user with the
	existing range/bearing display and proximity alerts.
- Tap overlapping or closely spaced map markers to open a native text-only
	Select Map Item list with their titles/callsigns and details. Choose a row to
	open its usual actions, or Cancel/back to return to the map. Self is included
	when it overlaps; a single hit still opens directly. Only drawn, visible
	markers within the existing 14-pixel tap radius are listed.
- Pan, zoom, and recenter the map.
- Open Map Layers from the top-center stacked-layers control and TAK Channels
	from the adjacent control. Map Buttons hides zoom/snap and Channels controls
	while Layers and Back remain accessible. Team Colors and
	Default Roles show current received-user counts, including zero. Toggles exist
	only for nonempty metadata groups; group keys are case-insensitive, hidden
	filters persist, and a user must pass both team and role filters. Hidden users
	remain counted. Saved points, self, and non-user remote markers are not hidden.
	Reported team colors and callsigns are used when the phone-relay entity message
	includes them. The filter groups can only be formed when the relay supplies
	`callSign`/`callsign`, `team` or `__group.name`, and `role` or `__group.role`.
- Track a selected point with Bloodhound range, true bearing, proximity radius,
	vibration, and cancel controls.
- Bloodhound tracking is synchronized with the paired phone. Starting, moving, or
	stopping a target on the watch sends a `bloodhound_control` message, and ATAK
	can drive the watch with the same message; each command is acknowledged with
	`bloodhound_control_result`. Garmin negotiates `bloodhoundVersion: 1`; commands
	and results also carry the current `relaySession`, UUID `command_id`, UUID
	`session_id`, target UID, and action for exact correlation. Unacknowledged
	commands time out after 10 seconds, and when both sides start at once the
	lower session ID wins so exactly one target survives. Dropping the relay
	retires the session and leaves watch tracking untouched. Phone-initiated
	commands only apply to points the watch already holds; otherwise the watch
	replies with an error instead of inventing a marker. This is the same native
	ATAK tracking contract as the WearOS WearTAK app, so one ATAK plugin drives
	both watches.
- Open **Bloodhound** from the main menu while no target is active to browse incoming map points.
	Active remote alerts appear first with an **(Alert)** prefix, followed by
	**Remove All** and received points. Alerts disappear when their cancellation
	arrives or they expire; clearing a tracked alert also stops Bloodhound.
	The main-menu row counts new points; new or newly
	revised points vibrate once. **RGR** queues a reply and starts Bloodhound;
	**nPos** queues "In Position", stops tracking, and removes the point locally.
	**Remove locally** does not delete a remote TAK marker. **Bloodhound** can
	start without a reply when sender metadata is unavailable.
- Send and clear categorized manual alerts through the Garmin relay when it is
	active. The companion's Garmin Connect IQ integration uses the phone's ATAK
	location to create the alert, so the watch does not need a GPS fix.
- Show sensor readings for environment and physiology.
- Enable or disable heart-rate sampling with the Physiological Monitoring
	setting; disabling it clears active heart-rate and exertion alerts.
- Show the current watch position internally for mapping, coordinates, and
	Bloodhound calculations.
- Configure physiological, exertion, environmental, pressure, and battery alerts
	plus a BATDOK medical profile. Alert families default to off until the user
	enables them.
- Relay sustained resting-heart-rate and exertion alerts, atmospheric-pressure
	threshold alerts, and sustained pressure-rise immersion alerts through the
	companion when their preferences and the ATAK relay are enabled. The companion
	uses the phone location; end-to-end automated alerts still need device testing.
- Use localized app text based on the watch's system language. The manifest
	declares the supported languages for Garmin store/device metadata.
- Configure Chat and Navigation tools, including proximity vibration, radius,
	and intensity preferences.
- Pair a user account with the Sit(x) Device API using OAuth device authorization
	from Network Preferences > Sit(x) TAK. Device authorization, refresh, permitted
	group discovery, and group-specific access-token provisioning use the shared
	WearTAK public OAuth client. Connect IQ has no WebSocket/raw socket API, so
	this does not establish a live CoT connection.

The following are still planned capabilities and are not the current scope of
this build:

- full ATAK chat integration and quick replies
- completing and validating the WearTAK ATAK plugin connection and relay integration
- SOS and emergency alert workflows
- end-to-end phone-relay entity sync and delivery acknowledgement
- full shared TAK mission/overlay behaviors
- server-backed shared TAK map layers and broader operational features
- end-to-end acknowledgement, delivery retries, and validation of automated
	alert/cancellation behavior on physical devices
- Sit(x) Device API integration for missions, GeoChat, SOS, and other resources

## Using the app

1. In the ATAK companion, enable **Garmin Connect IQ**. On the watch main menu,
	open **Settings** > **Network Preferences** > **TAK Relay** and toggle
	**ATAK Relay** on. Toggle it off there to stop the watch-side relay. Garmin
	Connect Mobile must be paired with the watch; ATAK manages the TAK server
	connection.
2. To view or edit server channels, open **Map** and tap **Channels** beside
	Layers. Choose an enabled server profile and select channels to toggle them.
	If **TAK Relay Off** appears, select it to open Network Preferences and enable
	the relay first. This requires a companion build that supports Garmin channel
	relay messages.
3. Open **Device Preferences** to maintain user metrics. App text follows the
	watch's system language.
	Open **Display Preferences** > **Units** to choose **Metric** or **Imperial**.
	This setting applies to contact ranges, Bloodhound distance and radius labels,
	routes, and navigation. When a compatible active ATAK Companion relay supplies
	the phone's range-units preference, that preference takes precedence; the watch
	uses its saved setting otherwise.
4. Open **Alerting Preferences** to opt in to alerts. Warnings remain local to
	the watch; qualifying automated alerts use the same companion emergency CoT
	path as Samsung/Wear OS and require an active ATAK relay and a valid phone fix.
5. Select **Drop 2525D** from the main menu to choose a marker type and
	add it at the current location. **Clear 2525D** opens the saved
	marker list or Clear Last Marker. Open **Map** to edit points, view coordinates,
	or start Bloodhound. Long-press the map to place the current default marker.
	**Bloodhound** on the main menu (hidden while tracking) lists received 2525D map items and shows a
	new-item count. Select an item to navigate, send RGR/nPos, or remove it locally.
	Active remote alerts appear at the top, labeled **(Alert)**, and can be tracked.
	**Remove All** clears received points/alerts and routes locally and stops
	tracking a removed target; it leaves live users and your dropped markers intact.
6. Select **Manual Alert** from the main menu and choose an alphabetized alert
	type, including **911 Alert**, **Geofence Breached**, **In Contact**, and
	**Ring The Bell**. It is sent through an active Garmin relay; without one, its
	active state remains local. Use **+** at the bottom to enter and save a custom
	alert. Alert choices sort alphabetically by their displayed labels. The
	**Gunshot Injury** preset is removed; **Gunshot** and **Injury** remain.
	Each saved custom alert has an adjacent red trash-icon **Delete** row. Select
	**Manual Alert (Active)** to clear the current alert.
	In a chat conversation, use **+** below the built-in quick replies to save a
	custom quick-reply message without sending it. Saved messages appear as
	single-line rows, sorted alphabetically with the preset replies, and are
	available in every conversation. Select the message row to send it or its
	adjacent red trash-icon **Delete** row to remove it without sending.
	Native Garmin Menu2 does not expose separate trailing-icon controls, so
	these dedicated delete rows work with both touch and watch buttons; no
	long press or deletion submenu is required.
7. To configure Sit(x), open **Network Preferences** > **Sit(x) TAK**, turn on
	TAK, enter the organization under **Address**, authorize with the displayed
	code, and select a permitted **Group**. **Sit(x) State** will say that the
	group is ready but a WebSocket is unavailable on Connect IQ; this is not a live
	TAK data connection. **Re-auth** starts a new device authorization. A paired
	phone or watch-supported internet connection is required.

Manual alerts use the `emergency` message envelope with an `ALERT` or `CANCEL`
state and the selected alert type. Their CoT kinds are `b-a-o-tbl` for 911 Alert,
`b-a-o-pan` for Ring The Bell, `b-a-g` for Geofence Breached, `b-a-o-opn` for
In Contact, and `b-a-o` for all other built-in and custom alerts. All use
priority `1`; cancellation uses `b-a-o-can` with the same UID. The companion's Garmin Connect IQ integration
uses ATAK's phone location for both alert and cancellation, so the watch does
not need its own GPS fix. The watch still requires the relay to be active and
the phone must have a valid location fix. A successful watch-side transmit is
not an end-to-end delivery acknowledgement; validate alert and cancellation
handling with the companion integration on physical devices.

Marker create and update operations use the `marker` envelope when relay plumbing
is available. Deletion uses a `marker_delete` envelope with the Garmin marker UID,
for example `garmin-marker-point-1`; full ATAK handling remains future work.

### Incoming-point workflow and reply handoff

Remote alerts use the same `entity`/`entities` relay. CoT types beginning
`b-a-`, `isAlert: true`, or an `emergency` dictionary identify alerts.
They are shown above regular points with an **(Alert)** title prefix, including
while the picker is open. Cancellation uses the same alert UID with CoT type
`b-a-o-can`, `state: "CANCEL"`, `active: false`, or
`emergency: {cancel: true}` (also accepts `"true"`); cancellation does not
require coordinates. A normal non-alert update to the same UID removes its
alert status but retains the map entity. Alert cancellation/expiry stops
tracking that target. The companion must forward alert and cancellation
metadata; the watch cannot discover alerts that the companion does not relay.
Alerts support Bloodhound without point-specific RGR/nPos replies.

The watch accepts point metadata in an `entity` payload or each entry in
`entities`. A Boolean `isPoint` is authoritative. Otherwise, a
`takv.device` of `Map Marker`, or a non-user CoT atom with a human-entered
`how` beginning `h-`, identifies a point. Without these fields the watch still
displays the entity on the map but does not add a new-point notification.
The title uses `callSign`/`callsign` as before. A sender is taken from
`senderUID`, `senderUid`, or `link: {relation: "p-p", uid: ...}`; the watch
does not infer the sender from the marker UID.

`time` (or `tStart`) identifies a point revision. Repeated snapshots of the
same revision do not notify again. A newer revision can notify again after
RGR or local removal. Without a revision, repeated snapshots cannot be
distinguished from a deliberate resend. The watch retains up to 999 relayed
entities in memory and requests that limit from the companion. At capacity,
the oldest admitted entity is evicted; updates to existing entities do not
consume another slot. The five-minute inactivity limit remains; expired or evicted targets also stop
Bloodhound. A locally removed revision is suppressed for five minutes.

The map draws at most the 99 nearest visible items, including local saved
markers, relative to the watch location (or map center before a location is
available). Selection refreshes on location, entity, marker, and filter changes.
Hidden team/role groups do not consume drawing slots. User overlays and map
hit testing use the same selection; undrawn entities remain available for
incoming-point workflows, group counts, and Bloodhound. Native remote map
markers are allocated only for the selected items. Relayed entities are not
persisted across app restarts. The companion must honor the requested limit;
mission-item DataSync support is still not implemented.

Point replies use the existing `chat` envelope with `text`, `replyTo` and
additional `recipientUid`, `pointUid`, `messageId`, and `createdAt` fields.
For these replies, `replyTo` is the sender UID. Unsent replies are persisted,
limited to 20, and expire after 24 hours with a visible warning. Failed phone handoffs remain
queued for the next relay connection; their message IDs do not change.
Queue rejection leaves the point/tracking state unchanged and shows an error.
A successful Connect IQ transmit removes the queued reply and reports
**Handed to phone; TAK unconfirmed**. It is not a TAK delivery acknowledgement.

This change is watch-side only. The ATAK companion still needs to supply the
point/sender/revision metadata, route these replies to `recipientUid`, and
preserve `messageId` for receiver deduplication. Do not treat point replies as
end-to-end operational until that companion work and physical-device checks
are complete. The new UI strings use English fallbacks in non-English locales
pending translation.

### Offline store and forward

The same durable queue now holds marker creates/edits/deletions, manual and
automated alerts/cancellations, ordinary chat, and point replies. It survives
app restarts and uses a 24-hour expiry; PLI is not backlogged. A newer marker
operation replaces that marker's older queued operation. An alert cancellation
replaces its queued activation, including if the older phone handoff completes
late. Other chat messages remain separate and retain their IDs.

Dropping a point reports **Marker details stored and will be sent when connected
and/or location is updated**. Without a watch location, the queue retains its
UID, title and type, then creates the local saved marker at the next location
fix before attempting the phone handoff. Those eventual coordinates are not
claimed to be the original drop location. Location-pending markers do not block
alerts or chat. A local marker edit/delete is not committed when queue admission
fails; storage and capacity errors are surfaced rather than reporting success.

Garmin's queue is limited to 20 entries and a 512-unit text budget (Connect IQ
`String.length`) across each newly submitted payload's string fields.
Long titles, remarks or chat must be shortened; they are not silently truncated.
The watch tries queued handoffs every five seconds while its relay is active.
Failed handoffs remain queued; a failed relay must reconnect before replay.
The current phone handoff still does not confirm TAK-server or recipient
delivery. No direct Garmin Sit(x) data transport is introduced by this change.

### Plugins placeholders (WEARTAK-142 / WEARTAK-143 / WEARTAK-147 / WEARTAK-148)

**Settings > Tool Preferences > Plugins** includes **Everywhere Comms** and
**GoTenna**, **Sensor Manager**, and **Somewear Labs**, each with the exact
subtitle **Unfunded Request**. Everywhere Comms, GoTenna, and Somewear Labs use
native off toggles; selecting any of those rows or toggles has no effect and
leaves it off. Sensor Manager opens a placeholder configuration menu because
Connect IQ menu rows do not provide a separate built-in toggle plus drill-in
action on one row. Its configuration menu contains a persisted, default-off
**Enabled** toggle plus inert **Unfunded Request**, **Button is Placeholder**,
and **Scan** rows. These are placeholders only: no communications integration,
sensor scanning, pairing, BLE, permissions, relay traffic or saved enablement is
added beyond Sensor Manager's local enabled preference. DataSync retains its
existing behavior.

**Commands** and **Ditto** are also listed with the subtitle **Unavailable**
and native off toggles. Selecting their rows or toggles does nothing and keeps
them off; neither opens a configuration page or saves an enablement choice.
`Unavailable` denotes missing platform/integration support, not the
`Unfunded Request` status of Everywhere Comms and Somewear Labs.

All plugin entries, including additional entries supplied to `buildPluginsMenuWithItems`,
are sorted together by their displayed labels, case-insensitively. The plugin
resource strings provide English fallbacks in all locales. `PluginsTests.mc`
covers labels, repeated inert selections, Sensor Manager's default-off persisted
toggle, and mixed-case sorting alongside existing entries.

### Manual MOPP / PPE status

Open **Settings > Tool Preferences > Plugins > MOPP**, identified by an original
protective-mask glyph. **PPE Status** shows the saved manual value. Choose
**None** (unset, not MOPP 0) or **MOPP 0** through **MOPP 4**, then select
**Save PPE Status**. The selected marker is a draft until saved; Cancel or Back
discards unsaved choices. The saved value survives restarts.

This is explicitly **manual / local only**: no report is transmitted, no remote
acknowledgment is implied, and no commanded level, CBR detection, filter-life
timer, protection recommendation or compliance color is inferred. Garmin's
native Menu2 provides whole-row selection for both buttons and touch rather than
independently tappable trailing chips. Existing localized Selected/Cancel labels
are reused; new MOPP explanatory labels currently use English, like the existing
native preference labels, without exceeding older-device string-module limits.

DataSync now has an original synchronization glyph and a navigation chevron.
It retains its existing watch-side server/feed workflow and explicit unsupported
states described below. There is no global DataSync enable control or newly
claimed Companion support; subscriptions still require authoritative replies.

### Commands and Ditto feasibility

The Garmin application currently has no functional Commands plugin, Commands configuration
schema, Ditto SDK, Community identity, or custom PDL setting. Bloodhound's
`bloodhound_control` messages are a specific tracking protocol, not a general
Commands implementation. `TakClient.mc` does not dispatch Commands/Ditto
messages or negotiate their capabilities, and `StandaloneApp.mc` has no saved
preferences for either feature. Consequently, no functional Commands or Ditto
switch/configuration surface is advertised on Garmin; the Plugins entries are
explicitly unavailable placeholders only.

Native Ditto is blocked by the platform: the
[published Ditto SDK installation guides](https://docs.ditto.live/llms.txt)
do not provide a Connect IQ/Monkey C SDK. This watch app runs in Garmin's
Connect IQ runtime, not a supported native Ditto host. Garmin's
[BluetoothLowEnergy API](https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html)
provides central-role scanning and GATT client operations, not peripheral
advertising/GATT server support. Its
[Communications API](https://developer.garmin.com/connect-iq/api-docs/Toybox/Communications.html)
provides phone messaging and web requests, not the raw socket/discovery
interfaces required to substitute a native Ditto mesh transport. Adding a
toggle, an HTTPS call, or the BLE permission does not install a Ditto engine.

A viable architecture uses the supported Ditto SDK in the paired iOS companion
or Android/ATAK companion. That companion owns the Ditto database, identity,
licensing, credentials and mesh lifecycle. The Garmin app is a remote display
and control client over its existing `Communications.transmit` /
`registerForPhoneAppMessages` dictionary channel through Garmin Connect Mobile
and the Connect IQ Mobile SDK. The watch would not be a standalone Ditto peer;
loss of the phone link must be shown separately from the saved enablement choice.
This bridge is proposed, not implemented or verified in this repository.

Before exposing the requested controls, the companion and watch need an agreed,
versioned protocol for Commands configuration and Ditto settings/status, with
current-session capability negotiation, bounded payloads, correlated
acknowledgements, explicit rejection/timeouts and authoritative settings readback.
The protocol must define the actual Community identity and custom PDL format;
these must not be guessed from display labels or logged as credentials.
An SDK handoff must not be reported as successful configuration or active sync.

Once that bridge is supported, the UI requirements are a separate Commands
on/off switch and configuration row, and Ditto defaulting off only when no
choice is saved. Ditto's configuration subtitle must show `Community` or a
truncated custom PDL, with the full approved PDL Help text accessible by
scrolling. Saved intent must remain distinct from confirmed runtime state.
All plugin rows must use the shared case-insensitive sorter; Everywhere Comms
and Somewear Labs must remain inert, off, and labelled `Unfunded Request`.
These are acceptance requirements for the bridge, not current capabilities.

### DataSync watch-side preparation

Open **Settings > Tool Preferences > Plugins > DataSync**, choose a TAK server,
then select a feed to subscribe or unsubscribe, matching the iOS preferences
workflow. Feeds are TAK Data Sync missions. Subscription labels change only
after the companion returns a matching, authoritative response, never after a
successful phone handoff. Refresh retries discovery or reloads the selected
server. Password-protected feeds cannot be newly subscribed from the watch.

This is watch-side preparation, **not operational DataSync**: the ATAK companion
is unchanged and must implement the contract below. Unsupported versions,
malformed responses, relay failures and a 65-second response timeout (checked
by the existing five-second relay timer) display
explicit errors. Requests are not placed in the offline outbox. Mission map
items, persistent subscription caching, automatic mission refresh and mission
item editing/deletion are not implemented in this phase. Ordinary received
entities still use the existing map limits and are not persistent mission items.

Messages use the existing `{msgType, payload}` envelope:

| Watch request | Payload |
| --- | --- |
| `missions_servers_request` | `requestId`, `dataSyncVersion: 1`, `serverID: null`, `limit: 4` |
| `missions_request` | `requestId`, `dataSyncVersion: 1`, stable `serverID`, `limit: 20` |
| `mission_update` | The same fields plus `missionName` and Boolean `missionSubscribe` |

The companion must echo the exact `requestId` and `dataSyncVersion: 1`.
Discovery replies use `missions_servers_response` with `servers`; feed and
subscription replies use `missions_response` with the exact `serverID` and
`missions`. An error uses `missions_error` with `requestId` and a nonempty
`error` string. Server IDs must remain stable across discovery/reconnections,
not positional channel server indexes.

Server rows contain only `id`, `name`, optional `state`, optional `error`.
Feed rows contain only `name`, Boolean `subscribed`, Boolean
`passwordProtected`, optional nonnegative integer `itemCount`, optional
`error`. Names/IDs/state are bounded to 128 string units and errors to 256;
IDs/feed names must be unique within a response. No credentials, certificates
or map items belong in these snapshots. The watch rejects oversized lists and
unknown row fields to bound retained data on low-memory devices. The companion
must report an explicit error when a complete list exceeds four servers or
20 feeds; it must not silently omit entries or claim a complete snapshot.
Subscription responses must include the requested feed with the confirmed
state; otherwise the watch retains the old state and reports an error.

The new DataSync resource file provides English fallbacks in all locales
pending translation. Simulator checks are included in the existing test build
alongside point workflow/outbox checks.


## Platform limits

Connect IQ is not Wear OS. This application cannot use Android foreground
services, Compose, Tiles, MDM managed configuration, Android plugins, Samsung
Health APIs, or APK tooling. The ATAK companion relay still uses dictionary
messages through Garmin Connect. The Sit(x) Device API uses HTTPS requests through
Connect IQ networking. Account authorization, group discovery, and group-token
provisioning do not establish a TAK data connection: Connect IQ exposes no
authenticated WebSocket or raw socket API, so this watch build cannot send or
receive Sit(x) CoT. The current direct Sit(x) status is therefore explicitly
not connected to a TAK data stream.

Connect IQ exposes no UDP socket or multicast group membership. The Garmin app
does not implement TAK SA Multicast. Map user filters can use `callSign`,
`team`, and `role` only when those fields arrive in phone-relayed entity
messages. The relay parser accepts direct `callSign`/`team`/`role` fields and
nested `contact.callsign`/`__group.name`/`__group.role` dictionaries. The current
Garmin Connect IQ companion integration does not guarantee forwarding those
fields or provide an end-to-end delivery acknowledgement.

Connect IQ storage is not an OS Keychain; credentials persisted by this app are
not protected by an equivalent secure-token store.

The manifest currently targets Fenix 6 Pro, 7X, and 8 products and requires Connect
IQ 3.3.0; Fenix 3 HD is not supported by this build.

Garmin localized resources are selected automatically by the watch's system
locale via Connect IQ's built-in `Rez.Strings` mechanism; there is no in-app
language override.

### Supported languages

The app text is localized into the languages declared in `manifest.xml`:

Arabic, Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish,
French, German, Greek, Hebrew, Hungarian, Indonesian, Italian, Japanese,
Korean, Latvian, Lithuanian, Malay, Norwegian Bokmal, Polish, Portuguese,
Romanian, Russian, Simplified Chinese, Slovak, Slovenian, Spanish, Swedish,
Thai, Traditional Chinese, Turkish, Ukrainian, and Vietnamese.

### Maintaining translations

The English resource file at `resources/resources.xml` is the canonical string
key set. Each `resources-*/resources.xml` file should contain the same string
IDs. Run the localization check from the project root after adding or changing
resource keys:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Validate-Localization.ps1
```

The check reports missing or unexpected IDs and returns a non-zero exit code
until every locale has complete key coverage. A missing translation should be
replaced in the locale file rather than removing the key from the English
source. To add missing keys as temporary English fallbacks, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Sync-LocalizationFallbacks.ps1
```

Review and translate those fallback values before release.

Treat location and saved waypoints as sensitive data. Configure ATAK's TAK
connection according to the deployment's operational policy.

### Remote emergency alerts

Received ATAK and WearTAK emergencies share one alert list between the map and
the Bloodhound picker. Alerts are deduplicated by their CoT UID while retaining
the ingress sources that supplied them. A yellow warning triangle identifies an
alert independently of ordinary contact and point visibility filters.

The CoT `stale` deadline describes location freshness, not whether the emergency
has ended. After that deadline the alert remains visible and its coordinates are
identified as a stale, last-known location. An alert without usable coordinates
remains readable but cannot be shown on the map or selected for navigation. A
later location-less refresh may retain that source's previous valid location.

Only an explicit, ordered sender cancellation ends an emergency. If a
cancellation is missed, the last-known alert can remain visible indefinitely
until it is dismissed locally or its source is removed. **Dismiss locally**
hides an ongoing alert on this watch without sending a cancellation,
acknowledgement, or chat message. Dismissals and cancellation ordering survive
an app restart so delayed packets cannot reveal or resurrect an older alert.

## Implementation roadmap

This project is intentionally scoped to the currently working features above.
Everything else is planned work and should be considered future capability,
not a present guarantee.

1. **Map + point editing** - implemented: open the map, drop points, rename
	them, change point type, and delete them.
2. **ATAK relay plumbing** - planned: expand the watch-to-phone integration
	beyond the current local point workflow.
3. **Chat and messaging** - implemented: view received messages, send broadcast
	chat, and reply to received messages with quick replies.
4. **SOS and emergency actions** - planned: full confirmed emergency flows.
5. **Operational overlays and entity sync** - planned: broader map data,
	mission-aware entity integration, and multi-user workflow support.
6. **Automated alert relay** - watch-side implemented: resting heart rate while
	stationary and exertion while moving use the configured warning/alert hold
	durations; atmospheric-pressure alerts require the five-sample mean to stay
	across an enabled threshold for 10 seconds. Suspected immersion requires an
	opt-in 5 hPa rise above a barometric baseline held for 60 seconds.
	The watch sends `emergency` envelopes with distinct UIDs, `catg`/`desc`, and
	`ALERT`/`CANCEL` states; the existing Garmin companion handler places them at
	ATAK's phone location as emergency CoT. Alerts refresh during sustained
	conditions. This works only while the watch app is running and sensor events
	are available. Movement is inferred from recent steps or valid GPS speed;
	immersion requires available pressure readings. Physical watch-to-ATAK
	validation, including cancellations and false-positive checks, is pending.

## Development

Build the project with the Garmin Connect IQ SDK for the configured product.
Use the simulator for UI and payload checks, then validate relay behavior on a
physical watch with Garmin Connect and the ATAK plugin. Do not commit generated
build output or the private `developer_key.der`; both are ignored by Git.

Use size optimization and release mode (`-O 3z -r`) for distributable builds,
particularly on the memory-constrained Fenix 6 Pro family. To compile and run the
focused point workflow tests with the Connect IQ simulator already running:

```powershell
& "$env:CONNECTIQ_SDK\bin\monkeyc.bat" -f monkey.jungle -d fenix7x -y developer_key.der -o bin\point-workflow-tests.prg -O 3z -l 1 -t
if ($LASTEXITCODE -eq 0) {
    & "$env:CONNECTIQ_SDK\bin\monkeydo.bat" bin\point-workflow-tests.prg fenix7x /t
}
```

Menu construction is shared across devices, and localized labels use resource
IDs directly rather than an eagerly initialized symbol-to-resource dictionary.
These optimizations preserve the same features and translations for every target.
The non-Pro Fenix 6 and 6S are not supported: they exceed the 128 KiB watch-app
memory limit, and Garmin's native `WatchUi.MapView` is unavailable on both.

## Continuous integration and signed builds

The automation follows the Tracker split:

- [GitHub Actions](.github/workflows/garmin.yml) validates localization on pull
  requests and pushes to `main`. Trusted pushes to that branch (or a
  manual run on it) also run the entire Monkey C simulator test suite
  on `fenix7x` and export an optimized `.iq` bundle. The bundle uses a disposable
  key, **not the production signing identity**. Download it and test logs from
  workflow artifacts; CI bundles are not official releases.
- [Government GitLab CI](.gitlab-ci.yml) runs network-free tooling regression
  tests and exports a production-key-signed `.iq` bundle on shared Linux
  Java 17 runners on protected
  default-branch pushes (30-day artifacts) and protected version tags such as
  `v5.8.3` or `v5.8.0.8` (non-expiring artifacts). Distribution packages are
  exposed only after export and inventory validation succeed. Linux does
  **not** run the simulator suite; provenance and release notes say so explicitly.
  The optional manual `windows_simulator` job runs that suite on an interactive
  Windows runner and is not a prerequisite for headless export.
  Neither pipeline publishes a store release. The disabled-by-default GitLab
  publisher below can publish verified production-key default-branch builds as
  the rolling GitHub main-channel release after explicit activation.

### Shared Linux release runner

`main_release` and `official_release` are untagged container jobs using the
same shared Linux pool as WearOS, with
`eclipse-temurin:17-jdk-jammy`.
The image must allow installing Python 3, venv, CA certificates and git through
apt. No Docker daemon, persistent SDK installation, desktop or new credential
is required. The publisher and its network-free tests use a PowerShell 7 Linux
container. The Python regressions run in the exact Java 17 build image with the
same bootstrap as signed exports. Bootstrap refreshes Ubuntu indexes over HTTPS
without cached responses and fails on index-update errors, avoiding stale HTTP
indexes baked into the base image. WearOS's existing
`gradle-build-launcher:17-2.6.2` image uses Debian 11, whose LTS ended in August
2026; actual runner attempts could no longer fetch its security packages.
Garmin uses a maintained Java 17 base rather than an archived OS repository.

`tools/garmin_ci.py provision` downloads the official Linux **9.2.0** SDK from
Garmin's [SDK catalog](https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json),
using the exact archive `connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip`
and SHA-256 `4907d8455b651c5a00a865e364cc4f1921c055b9279c7c8634c7a7a6773b5593`.
The device/font ZIP comes from canonical project 6783's **members-only** Generic
Package `garmin-device-cache/9.2.0-1/devices-fonts.zip`, authenticated with the
existing ephemeral `CI_JOB_TOKEN`. Its SHA-256 is pinned in `.gitlab-ci.yml`;
an unset, malformed or mismatched pin fails closed. Authenticated package
downloads never follow redirects.

The package contains only `Devices/<manifest-product>/...` for the seven current
devices and `Fonts/<referenced-file>` with optional MD5 sidecars. It has 873 files
(350 font files including sidecars), 150,298,074 compressed bytes, and SHA-256
`4677eb4603cb0d19a475b87da63c45257e3de4cf380ee67d2c0c4c302693dcfb`.
TrueType and bitmap font references come from those devices' `simulator.json`;
Garmin's built-in legacy `bitstreamVeraSans` fonts are not cache files.
The SDK, cache and signing keys must never be committed or included in artifacts.

To prepare a replacement archive locally after a manifest/device update:

```powershell
python -m pip install -r tools\requirements-ci.txt
python tools\garmin_ci.py package --cache "$env:APPDATA\Garmin\ConnectIQ" --output C:\Temp\devices-fonts.zip
```

This command does **not** upload anything. Verify registry privacy before an
authorized upload; use a new package version, then update the URL and reviewed
SHA-256 pin together. Do not package the entire installed Fonts cache.
Provisioning installs an isolated SDK and Linux cache under `.garmin/`; it
does not modify an existing user's Garmin installation.

### Optional Windows simulator runner

For local simulator checks or the optional manual job, provision:

1. Connect IQ SDK **9.2.0**, all current product definitions listed in `manifest.xml`, and the
   `fenix7x` simulator device installed for the runner account. Set
   `CONNECTIQ_SDK` to the SDK directory containing `bin\monkeyc.bat`.
2. Java 17 on `PATH`, Windows PowerShell 5.1+, and OpenSSL on `PATH` (or the
   standard Git for Windows installation at
   `C:\Program Files\Git\usr\bin\openssl.exe`).
3. An interactive Windows desktop session for that account: do not run the GUI
   simulator as a headless Windows service. Run only one Garmin job at a time,
   with no pre-existing simulator session.
4. For GitHub, runner labels `self-hosted`, `Windows`, `X64`, `garmin-ci`.
   Use an isolated/disposable runner; only trusted `main` code is
   allowed to execute there. Pull requests run localization on GitHub-hosted
   Windows runners, **not** the simulator or self-hosted build. A successful
   PR localization check alone is not a successful build/test run.
5. For GitLab's optional simulator job only, a Windows shell runner with tags
   `windows`, `garmin-ci`, restricted to protected refs. The shared Linux release
   path does not depend on this runner. Protect `main` and the release-tag pattern
   before enabling signed jobs, and restrict who can modify protected code.

Configure these **protected** GitLab CI/CD variables, without committing keys:

- `GARMIN_DEVELOPER_KEY_B64`: base64 of the existing production DER developer
  key; masked/hidden.
- `GARMIN_DEVELOPER_KEY_SHA256`: SHA-256 fingerprint of that exact DER file,
  obtained with `Get-FileHash -Algorithm SHA256`. The build refuses a mismatched
  key, preserving the watch application's signing identity.

No production key is needed by GitHub. Keys are written to a private temporary
directory and deleted in `finally`; they are never included in artifacts.
Disposable runners are still required to handle externally cancelled jobs.
Both pipelines emit `SHA256SUMS.txt` for their distribution packages.

### Running the same checks locally

Use [Invoke-CI.ps1](tools/Invoke-CI.ps1):

```powershell
.\tools\Invoke-CI.ps1
.\tools\Invoke-CI.ps1 -Mode Release
```

Release mode requires the two signing variables above. The default output is
`bin\ci`, which must be empty at startup so stale builds cannot be uploaded.
Choose a new `-OutputDirectory` for another local run. `-TestNames` accepts
specific simulator tests for local diagnosis; pipelines omit it to run all
tests. A missing SDK, signing variable, simulator result, or failed test/build
fails the job. SDK 9.2's Java test launcher can return exit code 1 after a
passing run; the script requires a complete zero-failure summary whose count
matches `Ran N tests`, with empty stderr, rather than trusting that exit code.
Runner registration and GitLab signing variables must be
configured before remote build jobs can run.

The signed job intentionally enforces each device's memory limit; exporting an
`.iq` alone does not prove every device-specific `.prg` fits. The non-Pro
`fenix6` and `fenix6s` were removed from the manifest on 2026-10-20: their
128 KiB watch-app limit was already exceeded by the current release (`main`
needs 187,380 bytes; whole-route Bloodhound needs 199,900 versus 131,072), and
neither model supports Garmin's native map API. Optimized device builds pass for
all seven remaining manifest devices. The full fenix7x simulator suite passes
**120/120** tests; these are not hardware results.

## Git workflow

The government repository (`origin`) is the canonical repository. New work starts
on a `feature` branch, is validated there, and is merged into government
`main` when ready. After the government merge is complete, mirror the same
merged commit to the personal GitHub repo (`github`) so both repositories stay
aligned.

```text
origin  https://git.tak.gov/core/weartak-core/weartak-garmin  (canonical)
github  https://github.com/aegorsuch/weartak-garmin           (mirror)
```

Recommended flow:

```text
feature -> origin/main -> github/main
```

```bash
git switch feature
git push origin feature
git switch main
git pull origin main
git merge feature
git push origin main
git push github main
```

This keeps the government repo as the source of truth and the personal
repository as a synchronized mirror. Keep branch names consistent across both
repos and avoid maintaining separate histories for the same work. Never commit
the private `developer_key.der` file.

## Releasing

Official release publication remains manual. The opt-in automated development
channel below is separate. Build device-specific `.prg` files for every product
declared in the manifest for a manual release.
The maintainer's `fenix7x` direct-install build is also written to the Desktop,
replacing the superseded Fenix 7X release. Publish the device-specific PRGs;
do not publish debug files or the `.iq` bundle.

Version `5.8.3-9f1ec78` publishes seven device builds: Fenix 6 Pro,
6S Pro, 6X Pro, 7X, 8 (47 mm), 8 Solar (47 mm), and 8 Solar (51 mm).
The non-Pro Fenix 6 and Fenix 6S are not included: although the optimized app
compiles, loading still exceeds runtime memory on Fenix 6, and neither model
supports Garmin's native map API.

1. Bump `APP_VERSION` in `source/StandaloneApp.mc` to the new version, including
	the short source commit hash (for example, `5.8.0.3-0c54201`), and
   commit it (consistent with the government repo being canonical, merge this
   into `main` first as described above).
2. Build every supported product with the Garmin Connect IQ SDK and name each
	output `WearTAK-Garmin-{DEVICE}-{APP_VERSION}.prg`. Save the `fenix7x`
	release build on the Desktop; remove superseded Garmin release binaries.
3. Tag the release commit `v{APP_VERSION}`, matching `APP_VERSION` exactly.
4. Push the tag and create a release from it on `origin`
	(git.tak.gov/core/weartak-core/weartak-garmin), attaching the device-specific
	`.prg` files.
5. Mirror the same release to `github`
	(https://github.com/aegorsuch/weartak-garmin): push the tag there and
	create a release attaching the same device-specific `.prg` files.

### Release presentation

Use the title **WearTAK Garmin {APP_VERSION}**. Begin the description with a short
statement identifying the channel (official release or CI test build), Garmin
Connect IQ artifacts, and their intended use. Device-specific `.prg` files are
direct-install applications; an `.iq` is a distribution bundle, not a file to
copy to a watch. Do not describe Garmin artifacts as APKs or give them Android
`versionCode` values. The manual publication procedure above remains PRG-only;
this presentation standard does not authorize publishing additional artifacts.

Include the exact full source commit SHA recorded at build time, linked to that
commit in the canonical repository. A short hash in `APP_VERSION` or an asset
filename is not sufficient proof of the build source. Record the release tag's
resolved commit separately if it differs; do not silently substitute the current
branch head or tag target for unverified binary provenance.

For a CI-produced build, include the pipeline/run ID and link, and the build job
ID and link when available. Identify the actual build channel and signing status:
GitHub CI uses a disposable key, not the production signing identity. For a
manual build, say **Built manually; no CI run** rather than inventing a pipeline
ID. If historical build provenance cannot be verified, mark it **Unverified**
and retain the existing release assets and manual notes.

List available artifacts with readable labels, for example **Fenix 7X
direct-install app (.prg)**, linking to each existing exact download URL. Keep
checksums separate from the artifact list: link `SHA256SUMS.txt` when it was
generated from those exact release bytes, or provide a clearly labeled SHA-256
section only after verifying the bytes. CI's checksum file covers its own
artifacts, not independently built historical release files.

Presentation-only maintenance must preserve tags, download URLs, artifact
filenames/bytes, maintainer notes, publisher ownership and existing cleanup
gates. Do not create a publisher, replace assets, or infer missing source/build
metadata merely to make an older release match this format.

### Automated rolling GitHub release (activation required)

The canonical GitLab `main_release` job verifies the decoded production key's
SHA-256 fingerprint and exports with `monkeyc -e -r -O 3z`. It validates the
actual 7z IQ container, generated manifest, signing material and all hardware
variants from the selected devices' compiler definitions (currently 21 variants
across seven devices), not just the filename extension. It does **not** run
simulator tests. Only after these gates succeed does it emit schema-2
`release-build.json`, binding the exact full source SHA, version, project,
pipeline ID, pipeline IID and build job ID to the IQ and `SHA256SUMS.txt`.
The record explicitly says `tests: not-run-headless-linux`; schema-1 Windows
records claiming full-suite success are not accepted by the Linux publisher.
Disposable-key GitHub CI artifacts never emit that production record and are
not eligible for publication.

`publish_default_branch` consumes artifacts from that successful job in the
same pipeline. It is serialized, defaults off, and runs only on a protected
default-branch **push** with `GARMIN_PUBLISH_ENABLED` exactly `true`. Merge
requests, schedules, tag jobs and manual pipelines do not publish. The source
commit must already exist in the GitHub mirror and GitHub `main` must equal
that exact canonical SHA; the publisher does not push source commits or alter
the mirroring process. Merge canonical-first, mirror that exact merged SHA
non-force before its publisher starts.

After activation, the destination is **GitHub `aegorsuch/weartak-garmin`**, not a
GitLab Release or Package Registry. One rolling release uses the fixed tag
`TAK.gov-Forge-CI-CD-Pipeline-Release` and title
`TAK.gov Forge CI/CD Pipeline Release (<version>-p<IID>)`.
The anchor is created at the first published source SHA and never moved; GitHub
source archives therefore describe that anchor, not subsequent builds.
Initial publication creates a draft, uploads and verifies the IQ, then exposes
a stable release. Later builds update that same release. The final inventory
has exactly **one** current asset, whose filename and
label both equal `WearTAK-Garmin-<version>-p<IID>.iq`.
It downloads that asset and verifies SHA-256 before publishing without marking
it latest. Checksums remain in the notes and CI artifacts, not extra GitHub
assets. Notes match the shared release-page structure: an intro, exactly five
bullets (IQ version, pipeline IDs, canonical pipeline URL, source SHA and SHA-256),
and a fixed Garmin-specific distribution/source sentence. Simulator-not-run
evidence and device coverage remain in `release-build.json` and CI logs, not
additional release-page sections. The version is the literal `APP_VERSION`;
its intentional historical `-9f1ec78` suffix is not the current build's source
identity. The full source SHA in provenance and release notes is authoritative.

The publisher rejects mismatched provenance, unknown notes/assets, pre-existing
unmanaged anchors/drafts, replayed or newer pipelines, and concurrent changes.
Before any mutation it saves release/tag metadata and downloads and hash-verifies
the previous owned asset into `bin/ci/publication-backup/`, retained as a
non-expiring publisher artifact even on failure. The managed marker binds the
previous asset ID, filename, SHA-256 and pipeline to the exact expected full body.
Unknown or manually edited content is never claimed or overwritten.

For rolling updates, the prior download remains available while the new IQ is
uploaded and verified. Only after the new title/body is published and its bytes
are verified again may the exact previous managed, backed-up, hash-verified
asset ID be deleted. The final inventory must contain only the new IQ. A partial
attempt fails closed (possibly leaving a draft or both assets); a maintainer
must inspect the backup and live state before recovery. No automatic retry
claims a partial inventory.

Canonical and mirror heads, exact release notes/title and asset inventories are
rechecked before mutations. The GitLab resource group serializes CI publishers;
API rechecks are not an atomic lock against external edits between a check and
write. Historical releases, per-build tags, official `v...` releases, unknown
assets and manual notes are never deleted.

Activation is a separate maintainer-approved operation; this implementation
does not create credentials, change access or run a publisher:

- Configure the existing production `GARMIN_DEVELOPER_KEY_B64` and
  `GARMIN_DEVELOPER_KEY_SHA256` as protected secrets for the signed build.
- Supply a protected, masked `GARMIN_GITHUB_RELEASE_TOKEN` authorized for
  **Contents: write on only `aegorsuch/weartak-garmin`**. An authorized GitHub
  credential is required; no token is embedded or generated here. GitLab's
  ephemeral `CI_JOB_TOKEN` is used only for the canonical branch-head read.
- Keep `GARMIN_PUBLISH_ENABLED` unset until publication is approved and the
  shared Linux signed export, token authorization, canonical-to-GitHub source
  mirroring and production signing configuration have been verified. API
  authorization failures fail the job; they do not fall back to a disposable
  key, another repository or a different destination.

The existing signing identity variables and `GARMIN_GITHUB_RELEASE_TOKEN` are
protected and masked. They are reused, not replaced. The registry-only setting
was explicitly approved as members-only; project visibility remains internal.
Publication is controlled by the protected `GARMIN_PUBLISH_ENABLED` variable:
set it to exactly `true` only after approval to publish on subsequent protected
`main` pushes. Unset it or set it to `false` to disable publication for new
pipelines; this does not cancel an already-running publisher or remove existing
releases. The gate does not add a publisher retroactively to an existing pipeline.
Mirror the exact merged canonical SHA to GitHub before its publisher starts.
Enabling publication does not imply Linux simulator coverage.

Run the network-free publisher regression checks locally with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-GarminRelease.ps1
python -m unittest discover -s tools -p "test_*.py"
```

These tests use synthetic artifacts and mocked API calls; they do not sign
production builds or contact GitHub/GitLab. GitHub's hosted localization job
also runs them without credentials or release permissions.
