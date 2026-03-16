## Frontend Backup Snapshot (2026-03-16)

This repository was snapshotted to preserve a known-working autonomous live chat state.

### Included state
- Prominent recording banner with live stop button.
- Replay button reliability improvements via pending audio-to-message attachment in controller.
- Existing autonomous chat flow, tool prompts, and video-context controls retained.

### Related backend deployment at snapshot time
- Service: `locateassist-backend`
- Region: `us-central1`
- Active revision: `locateassist-backend-00075-vr2`
- Image: `gcr.io/locateassist/locateassist-backend:20260316-144902`
- Digest: `sha256:aaf5b43c865fe9e3667e0c353ba511520f579fa8f3065d902f21fc5801f41dd1`

### Restore note
Use this commit hash in this repo to restore this exact frontend state.
