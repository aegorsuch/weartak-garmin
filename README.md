# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently targeting the fenix 7X, Tactix 8 class,
fēnix 8 class, and fenix 6X Pro / Tactix Delta class devices.

## Project links

- Personal GitHub: https://github.com/aegorsuch/weartak-garmin
- Government repo: https://git.tak.gov/core/weartak-core/weartak-garmin

## Installation

1. Download the `.prg` matching your watch from the latest GitHub release.
2. Connect the watch to your computer with its USB cable and wait for it to
	appear as a removable drive.
3. Open the watch drive and navigate to `GARMIN/Apps`.
4. Drag only the matching `.prg` into the `GARMIN/Apps` folder. For a fēnix
	7X, use `WearTAK-Garmin-fenix7x.prg`.
5. Safely eject the watch, disconnect the USB cable, and launch WearTAK from
	the watch's app list.

Do not copy the `.prg.debug.xml`, other device builds, or the `.iq` package to
the watch. The `.iq` package is the release bundle for Garmin's supported
distribution workflow; direct USB sideloading uses the device-specific `.prg`.
Garmin uses the watch's system language for localized app text.

The app uses Garmin Connect IQ phone messages to relay watch input to the
WearTAK ATAK companion. ATAK owns TAK server connectivity, mTLS credentials,
identity, and the authoritative phone location for PLI; the watch provides a
secondary display and input surface.

> Important: there is no live ATAK connection yet. The ATAK plugin connection is
> not integrated in this build. This build is currently a local map-and-point
> editing workflow; it does not yet establish a connected, operational TAK/ATAK
> session with a remote server.

## Current capabilities

The app is currently focused on a lightweight, local map-and-point workflow.
There is no live ATAK connection yet, and these are the features working right
now:

- Open and navigate the map.
- Drop an Unknown 2525D point from the main menu or map.
- Clear all 2525D points from the main menu.
- Rename a point.
- Change a point's type.
- Delete a point.
- View point and self coordinates in latitude/longitude and MGRS.
- Pan, zoom, and recenter the map.
- Track a selected point with Bloodhound range, true bearing, proximity radius,
	vibration, and cancel controls.
- Show sensor readings for environment and physiology.
- Show the current watch position internally for mapping, coordinates, and
	Bloodhound calculations.
- Configure physiological, exertion, environmental, pressure, and battery alerts
	plus a BATDOK medical profile. Alert families default to off until the user
	enables them.
- Use localized app text based on the watch's system language. The manifest
	declares the supported languages for Garmin store/device metadata.
- Configure Chat and Navigation tools, including proximity vibration, radius,
	and intensity preferences.

The following are still planned capabilities and are not the current scope of
this build:

- full ATAK chat integration and quick replies
- WearTAK ATAK plugin connection and relay integration
- SOS and emergency alert workflows
- incoming entity or entities syncing beyond the current local map groundwork
- full shared TAK mission/overlay behaviors
- broader map-layer, team, or operational features beyond point creation and
	editing

## Using the app

1. Open **Device Preferences** to maintain user metrics. App text follows the
	watch's system language.
2. Open **Alerting Preferences** to opt in to local watch alerts. Warning
	settings notify the watch user locally; full alert routing across TAK is held
	for the future ATAK-device connection.
3. Use **Drop 2525D Point** to add an Unknown point at the current location,
	then open **Map** to edit points, view coordinates, or start Bloodhound.
4. Select **SOS** from the main menu for a confirmed emergency action, or
	select **Clear SOS** after an alert is active.

ATAK companion message envelopes are reserved for the planned plugin connection;
they are not an integrated operational workflow in this build. **Send SOS**
opens a separate confirmation before transmitting through the currently available
relay plumbing; full ATAK integration remains future work.

Marker create and update operations use the `marker` envelope when relay plumbing
is available. Deletion uses a `marker_delete` envelope with the Garmin marker UID,
for example `garmin-marker-point-1`; full ATAK handling remains future work.


## Platform limits

Connect IQ is not Wear OS. This application cannot use Android foreground
services, Compose, Tiles, MDM managed configuration, Android plugins, Samsung
Health APIs, or APK tooling. It sends only dictionary messages through Garmin
Connect; all TAK network transport and mTLS remain on ATAK.

Garmin localized resources are selected automatically by the watch's system
locale via Connect IQ's built-in `Rez.Strings` mechanism; there is no in-app
language override.

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

1. **Map + point editing** - active: open the map, drop points, rename them,
	change point type, and delete them.
2. **ATAK relay plumbing** - planned: expand the watch-to-phone integration
	beyond the current local point workflow.
3. **Chat and messaging** - planned: support incoming and outgoing ATAK chat
	messaging.
4. **SOS and emergency actions** - planned: full confirmed emergency flows.
5. **Operational overlays and entity sync** - planned: broader map data,
	mission-aware entity integration, and multi-user workflow support.

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

Releases are built and published manually; there is no CI automation. The
`.iq` bundle covers all five supported products (fenix7x, fenix847mm,
fenix8solar47mm, fenix8solar51mm, fenix6xpro) in a single file, so it is the
only artifact attached to a release.

1. Bump `APP_VERSION` in `source/StandaloneApp.mc` to the new version and
   commit it (consistent with the government repo being canonical, merge this
   into `develop` first as described above).
2. Build `WearTAK-Garmin.iq` locally with the Garmin Connect IQ SDK (the VS
   Code Monkey C extension's build/export flow uses `monkey.jungle` and the
   local `developer_key.der` already configured in `.vscode/settings.json`).
3. Tag the release commit `vX.Y.Z.Z.Z`, matching `APP_VERSION` exactly.
4. Push the tag and create a release from it on `origin`
   (git.tak.gov/core/weartak-core/weartak-garmin), attaching the built `.iq`.
5. Mirror the same release to `github`
   (https://github.com/aegorsuch/weartak-garmin): push the tag there and
   create a release attaching the same `.iq` file.

