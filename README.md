# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently supporting the fenix 6, fenix 6S, fenix 6X
Pro, fenix 7X, fenix 8 47 mm, and fenix 8 51 mm variants.

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
	7X running version `5.8.0.3-c545fb2`, use
	`WearTAK-Garmin-fenix7x-5.8.0.3-c545fb2.prg`.
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

The app is currently focused on a lightweight, local map-and-point workflow.
The Garmin-to-ATAK relay is being integrated in the companion's
`garmin-connect-iq-integration` branch. These are the watch features working
right now:

- Open and navigate the map.
- Drop a 2525D point from the main menu or map; new point titles use the
	configured callsign and UTC time in `CALLSIGN_HHMMSSZ` format.
- Clear all 2525D points from the main menu.
- Rename a point.
- Change a point's type.
- Delete a point.
- View point details with marker type/drop time, bearing arrow, distance,
	latitude/longitude, MGRS, and Bloodhound, title, remark, marker-type, move,
	delete, and back actions.
- View self coordinates in latitude/longitude and MGRS.
- Pan, zoom, and recenter the map.
- Track a selected point with Bloodhound range, true bearing, proximity radius,
	vibration, and cancel controls.
- Send and clear categorized manual alerts through the Garmin relay when the
	relay is active. The companion's Garmin Connect IQ integration uses the
	phone's ATAK location to create the alert, so the watch does not need a GPS fix.
- Show sensor readings for environment and physiology.
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
	from Network Preferences. Pairing, token refresh, and an authenticated profile
	request are implemented using the shared WearTAK public OAuth client; mission,
	GeoChat, SOS, and other resource operations are not yet connected.

The following are still planned capabilities and are not the current scope of
this build:

- full ATAK chat integration and quick replies
- completing and validating the WearTAK ATAK plugin connection and relay integration
- SOS and emergency alert workflows
- incoming entity or entities syncing beyond the current local map groundwork
- full shared TAK mission/overlay behaviors
- broader map-layer, team, or operational features beyond point creation and
	editing
- end-to-end acknowledgement, delivery retries, and validation of automated
	alert/cancellation behavior on physical devices
- Sit(x) Device API integration for missions, GeoChat, SOS, and other resources

## Using the app

1. In the ATAK companion, enable **Garmin Connect IQ**. On the watch, select
	**Settings**, select **Network Preferences**, then toggle **ATAK Relay** on.
	Toggle it off there to stop the watch-side relay. Garmin Connect Mobile must
	be paired with the watch; ATAK manages the TAK server connection.
2. Open **Device Preferences** to maintain user metrics. App text follows the
	watch's system language.
3. Open **Alerting Preferences** to opt in to alerts. Warnings remain local to
	the watch; qualifying automated alerts use the same companion emergency CoT
	path as Samsung/Wear OS and require an active ATAK relay and a valid phone fix.
4. Use **Drop 2525D Point** to add an Unknown point at the current location,
	then open **Map** to edit points, view coordinates, or start Bloodhound.
5. Select **Manual Alert** from the main menu and choose an alert type to send
	it through the active Garmin relay. Select **Clear Manual Alert** to send a
	cancellation.
6. To pair Sit(x), open **Settings** > **Network Preferences** > **Sit(x) Device
	API**, enter the organization's host (for example, `weartak.sitx.io`), then
	select **Auth Code** to request a code. Open Sit(x)'s device authorization page
	on your phone or computer and enter the displayed code. Select **Auth Code**
	again to request a fresh code. A paired phone or watch-supported internet
	connection is required; pairing does not yet enable Sit(x) mission, chat, or
	SOS actions. Select **Clear Sit(x)** to remove saved authorization.

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
Connect IQ networking and is currently limited to account pairing and token
refresh plus an authenticated `/myinfo` check. It does not provide raw CoT
streaming. The manifest currently targets
Fenix 6, 7, and 8 products and requires Connect IQ 3.3.0; Fenix 3 HD is not
supported by this build.

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
   the short source commit hash (for example, `5.8.0.3-c545fb2`), and
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

