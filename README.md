# AReach — Smartphone AR for Social Discovery at Events

AReach is a smartphone-based augmented reality system for social discovery in closed professional events. It explores how concise attendee information can help people notice potentially relevant connections and possible conversation openings before face-to-face interaction.

This repository is a **source showcase**, prepared from private source commit `7da5d88a778017c1f14b925f6166a2c8b89be915`. It is not intended to be installed, built, or run. The six reviewed UI screenshots and app branding are retained. The event-preview screenshot was excluded because it showed an event join code; the camera screenshot with photorealistic people was excluded because its image provenance is unknown. This source snapshot is not packaged or verified as a runnable build.

The software was developed as part of a master's dissertation in Software Engineering at the Polytechnic University of Setúbal, submitted in November 2026. Research datasets, participant records, researcher mappings, signed consent forms, ethics and administrative documents, dissertation and article sources, and temporary research files are intentionally excluded.

## Features represented in the source

- Event creation, participation, and attendee-profile workflows.
- Camera and attendee-list discovery interfaces.
- Optional participant-authored “Ask me about…” topics.
- Nearby-device discovery and spatial association.
- Event-scoped authorisation and account-level discoverability.
- Reporting, blocking, and account-management flows.

AReach does not use facial recognition. Backend authorisation resolves whether attendee information may be accessed. The iPhone separately evaluates nearby-device and camera evidence for physical association and decides how to render available information. Internal association is not independent ground-truth verification, and the production camera interface does not explicitly label every uncertainty mode.

## Architecture and technology

1. **Mobile application:** Expo, React Native, and TypeScript provide event, profile, attendee-list, and camera workflows.
2. **Native iOS spatial subsystem:** Swift uses ARKit, Vision, Nearby Interaction, Bluetooth, and local-network discovery for on-device observations, ranging, association, and overlays.
3. **Backend API:** Hono on Cloudflare Workers handles authentication, events, profile access, and visibility enforcement; PostgreSQL stores application data.

Nearby devices communicate directly for local discovery and spatial measurements. Camera observations and physical association remain on the device. The Astro web workspace contains project information pages and UI source.

## Repository layout

```text
apps/
├── api/       API source, database schema, and migrations
├── mobile/    Expo app and native iOS spatial module
└── web/       Astro source
```

The workspace manifests and lockfile are retained to identify the project structure and dependencies. Local secrets, production resource identifiers, deployment workflows, store-review credentials, and study-specific infrastructure are omitted. Safe environment examples contain placeholders only.

## Research limits

The dissertation reports a five-participant exploratory activity using the combined camera and attendee-list experience. It did not independently measure automated spatial-association accuracy, establish improved networking outcomes, or isolate the effect of AR. The code and this source snapshot do not establish device compatibility, deployment, or operational reliability.

## Academic reference

Rosa, P. (2026). *AReach: A Smartphone-Based Augmented Reality System for Social Discovery at Events* [Master's dissertation, Polytechnic University of Setúbal, School of Technology of Setúbal]. Submitted November 2026.

## Rights and licensing

No project-wide licence is included. `apps/mobile/LICENSE` contains an Expo copyright notice and does not establish a licence for all AReach code. Confirm ownership and third-party rights before publication or reuse; choose a project-wide licence only after that review.
