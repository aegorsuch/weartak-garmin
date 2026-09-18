# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently targeting the fenix 7X.

## Project links

- Personal GitHub: https://github.com/aegorsuch/weartak-garmin
- Government repo: https://git.tak.gov/core/weartak-core/weartak-garmin

The app uses Garmin Connect IQ phone messages to relay watch input to the
WearTAK ATAK companion. ATAK owns TAK server connectivity, mTLS credentials,
identity, and the authoritative phone location for PLI; the watch provides a
secondary display and input surface.

> Important: there is no live ATAK connection yet. This build is currently a
> local map-and-point editing workflow; it does not yet establish a connected,
> operational TAK/ATAK session with a remote server.

## Current capabilities

The app is currently focused on a lightweight, local map-and-point workflow.
There is no live ATAK connection yet, and these are the features working right
now:

- Open and navigate the map.
- Drop a point on the map.
- Rename a point.
- Change a point's type.
- Delete a point.
- Pan, zoom, and recenter the map.
- Show the current watch position on the map.
- Configure physiological and exertion alerts plus a BATDOK medical profile.
- Publish local point changes as marker operations to the ATAK companion.

The following are still planned capabilities and are not the current scope of
this build:

- full ATAK chat integration and quick replies
- SOS and emergency alert workflows
- incoming entity or entities syncing beyond the current local map groundwork
- full shared TAK mission/overlay behaviors
- broader map-layer, team, or operational features beyond point creation and
	editing

## Using the app

1. Install and start the WearTAK ATAK plugin on the paired Android phone.
2. Select **Start relay**. The watch waits for Garmin Connect to acknowledge
	its relay handshake and requests an initial map entity sync from the ATAK
	companion.
3. Open **Map** to browse the map, center on the current position, and add
	local points.
4. Select **SOS** from the main menu for a confirmed emergency action, or
	select **Clear SOS** after an alert is active.

The ATAK companion may send incoming entities to the watch using `entity` or
`entities` envelopes. It may send chat using a `chat` envelope with `sender`,
`text`, and optional `uid` fields. **Send SOS** opens a separate confirmation before
transmitting; selecting it again clears alerting.

Marker create and update operations use the `marker` envelope. Deletion uses a
`marker_delete` envelope with the Garmin marker UID, for example
`garmin-marker-point-1`. The ATAK companion should remove that UID from its
authoritative map state when it receives the deletion envelope.


## Platform limits

Connect IQ is not Wear OS. This application cannot use Android foreground
services, Compose, Tiles, MDM managed configuration, Android plugins, Samsung
Health APIs, or APK tooling. It sends only dictionary messages through Garmin
Connect; all TAK network transport and mTLS remain on ATAK.

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
