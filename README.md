# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently supporting the fenix 6 family, fenix 7X,
and fenix 8 (47 mm and 51 mm variants).

## Project links

- Personal GitHub: https://github.com/aegorsuch/weartak-garmin
- Government repo: https://git.tak.gov/core/weartak-core/weartak-garmin

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
	7X running version `5.8.0.3-835d7a9`, use
	`WearTAK-Garmin-fenix7x-5.8.0.3-835d7a9.prg`.
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
messages. That transport is being implemented in the ATAK companion's
`garmin-connect-iq-integration` branch (a separate repository).

> Important: the watch-side relay and the ATAK companion's Garmin Connect IQ
> integration are still under development. Using both builds is required for
> Garmin messages to reach ATAK; a watch-side relay toggle alone does not
> establish a TAK server connection.

## Current capabilities

The app opens to a native, scrollable Connect IQ menu. The Garmin-to-ATAK phone
relay depends on the companion's Garmin Connect IQ receiver. These are the watch
features currently available:

- The alphabetical main menu contains Chat (when enabled), Clear 2525D,
	Drop 2525D, Manual Alert, Map, and Settings.
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
- Configure Dynamic or Constant Reporting intervals, Wi-Fi battery-saving
	preferences, and Physiological Monitoring under Reporting Strategy. These
	settings are intended for standalone Sit(x) use when no phone is connected.
	Physiological Monitoring controls heart-rate sampling; reporting intervals
	and Wi-Fi preferences are currently stored only and do not change transmitted
	PLI because direct Sit(x) PLI transport and active Wi-Fi SSID detection are
	not implemented on Garmin.
- View point details as native scrollable rows for marker type/drop time,
	distance, bearing, latitude/longitude, and MGRS, followed by Bloodhound,
	title, remark, marker-type, move, delete, and back actions.
- View self coordinates in latitude/longitude and MGRS.
- Tap the self marker to view separate latitude and longitude rows and MGRS.
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
4. Open **Alerting Preferences** to opt in to alerts. Warnings remain local to
	the watch; qualifying automated alerts use the same companion emergency CoT
	path as Samsung/Wear OS and require an active ATAK relay and a valid phone fix.
5. Select **Drop 2525D** from the main menu to choose a marker type and
	add it at the current location. **Clear 2525D** opens the saved
	marker list or Clear Last Marker. Open **Map** to edit points, view coordinates,
	or start Bloodhound. Long-press the map to place the current default marker.
6. Select **Manual Alert** from the main menu and choose an alert type. It is
	sent through an active Garmin relay; without one, its active state remains
	local. Select **Manual Alert (Active)** to clear it.
7. To configure Sit(x), open **Network Preferences** > **Sit(x) TAK**, turn on
	TAK, enter the organization under **Address**, authorize with the displayed
	code, and select a permitted **Group**. **Sit(x) State** will say that the
	group is ready but a WebSocket is unavailable on Connect IQ; this is not a live
	TAK data connection. **Re-auth** starts a new device authorization. A paired
	phone or watch-supported internet connection is required.

Manual alerts use the `emergency` message envelope with an `ALERT` or `CANCEL`
state and the selected alert type. The companion's Garmin Connect IQ integration
uses ATAK's phone location for both alert and cancellation, so the watch does
not need its own GPS fix. The watch still requires the relay to be active and
the phone must have a valid location fix. A successful watch-side transmit is
not an end-to-end delivery acknowledgement; validate alert and cancellation
handling with the companion integration on physical devices.

Marker create and update operations use the `marker` envelope when relay plumbing
is available. Deletion uses a `marker_delete` envelope with the Garmin marker UID,
for example `garmin-marker-point-1`; full ATAK handling remains future work.


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

The manifest currently targets Fenix 6, 7, and 8 products and requires Connect
IQ 3.3.0; Fenix 3 HD is not supported by this build.

Garmin localized resources are selected automatically by the watch's system
locale via Connect IQ's built-in `Rez.Strings` mechanism; there is no in-app
language override.

### Supported languages

The app text is localized into the languages declared in `manifest.xml`:

Arabic, Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish,
French, German, Greek, Hebrew, Hungarian, Indonesian, Italian, Japanese,
Korean, Latvian, Lithuanian, Norwegian Bokmal, Polish, Portuguese, Romanian,
Russian, Slovak, Slovenian, Spanish, Swedish, Thai, Turkish, Ukrainian, and
Vietnamese.

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

## Implementation roadmap

This project is intentionally scoped to the currently working features above.
Everything else is planned work and should be considered future capability,
not a present guarantee.

1. **Map + point editing** - implemented: open the map, drop points, rename
	them, change point type, and delete them.
2. **ATAK relay plumbing** - planned: expand the watch-to-phone integration
	beyond the current local point workflow.
3. **Chat and messaging** - planned: support incoming and outgoing ATAK chat
	messaging.
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

## Git workflow

The government repository (`origin`) is the canonical repository. New work starts
on a `feature` branch, is validated there, and is merged into government
`develop` when ready. After the government merge is complete, mirror the same
merged commit to the personal GitHub repo (`github`) so both repositories stay
aligned.

```text
origin  https://git.tak.gov/core/weartak-core/weartak-garmin  (canonical)
github  https://github.com/aegorsuch/weartak-garmin           (mirror)
```

Recommended flow:

```text
feature -> origin/develop -> github/develop
```

```bash
git switch feature
git push origin feature
git switch develop
git pull origin develop
git merge feature
git push origin develop
git push github develop
```

This keeps the government repo as the source of truth and the personal
repository as a synchronized mirror. Keep branch names consistent across both
repos and avoid maintaining separate histories for the same work. Never commit
the private `developer_key.der` file.

## Releasing

Releases are built and published manually; there is no CI automation. Publish
the nine device-specific `.prg` files for direct USB installation. The `.iq`
bundle covers all nine supported products (fenix6, fenix6pro, fenix6s,
fenix6spro, fenix6xpro, fenix7x, fenix847mm, fenix8solar47mm, and
fenix8solar51mm) for Garmin's distribution workflow.

1. Bump `APP_VERSION` in `source/StandaloneApp.mc` to the new version, including
	the short source commit hash (for example, `5.8.0.3-0c54201`), and
   commit it (consistent with the government repo being canonical, merge this
   into `develop` first as described above).
2. Build each device-specific `.prg` with the Garmin Connect IQ SDK, selecting
	its product with `-d` (for example, `-d fenix6`) and name the output
	`WearTAK-Garmin-{product}-{APP_VERSION}.prg`. Build
	`WearTAK-Garmin.iq` as well when preparing the Garmin distribution package.
3. Tag the release commit `v{APP_VERSION}`, matching `APP_VERSION` exactly.
4. Push the tag and create a release from it on `origin`
	(git.tak.gov/core/weartak-core/weartak-garmin), attaching the nine `.prg`
	files and the `.iq` package when needed.
5. Mirror the same release to `github`
	(https://github.com/aegorsuch/weartak-garmin): push the tag there and
	create a release attaching the same build artifacts.

