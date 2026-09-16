# WearTAK-Garmin

WearTAK-Garmin is a standalone Garmin Connect IQ watch application for basic
Team Awareness Kit (TAK) operational awareness. It is designed for Garmin
watches with maps and GPS, currently targeting the fenix 7X.

The app uses Garmin Connect IQ phone messages to relay watch input to the
WearTAK ATAK companion. ATAK owns TAK server connectivity, mTLS credentials,
identity, and the authoritative phone location for PLI; the watch provides a
secondary display and input surface.

## Current capabilities

- Relays `marker` and `emergency` JSON envelopes to the ATAK phone
	companion through Garmin Connect IQ. No TAK endpoint or credentials are
	stored on the watch.
- Inherits callsign, team, role, reporting rate, and PLI ownership from ATAK;
	the watch is a secondary map, point-drop, chat, and SOS interface.
- Displays the watch's current position on a pan-and-zoom map.
- Drops app-owned 2525D-style friendly, hostile, unknown, and obstacle points
	without creating Garmin saved-location flags.
- Lets the user set a dropped point's title and remark after selecting it on
	the map, and relays those fields to ATAK.
- Supports long-press point placement, then lets you select a point to change
	its type, title, remark, or delete it.
- Supports swipe, flick, and drag map panning, plus recenter and zoom controls.
- Provides a confirmed cleanup action for legacy Garmin waypoints named
	`Unknown 2525D point`.
- Publishes map points as typed CoT marker events after their type is selected.
- Provides a confirmed SOS action that sends an emergency event through the
	ATAK companion.
- Displays phone-relayed `entity` or `entities` messages on the map.
- Displays phone-relayed chat messages and sends `Rgr`, `Neg`, `ObjS`, or
	`nPos` quick replies through the ATAK companion.

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

1. **Phone relay** - implemented: dictionary envelopes sent through Garmin
	Connect IQ to the ATAK companion, with delivery-confirmed startup and an
	initial entity-sync request.
2. **ATAK-owned PLI** - implemented: identity and reporting remain owned by
	the ATAK companion.
3. **Map input and incoming entities** - implemented: typed map points and
	phone-relayed entities share the existing on-watch map.
4. **SOS/manual alert** - implemented: confirmed alert and cancel envelopes.

## Development

Build the project with the Garmin Connect IQ SDK for the configured product.
Use the simulator for UI and payload checks, then validate relay behavior on a
physical watch with Garmin Connect and the ATAK plugin. Do not commit generated
build output or the private `developer_key.der`; both are ignored by Git.

## Git workflow

Make changes on `develop` and push them to the `tpc` remote. Merge tested
changes into `main` when they are ready for release.
