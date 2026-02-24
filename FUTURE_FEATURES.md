# Future Features Roadmap

## Premium Cloud Sync
- Position cloud sync as a premium-only feature.
- Free users keep local-only storage on a single device.
- Premium users unlock cross-device sync and backup/restore.

## Proposed Cloud Schema
- `users`: canonical user profile and auth metadata.
- `onboarding_profiles`: selected skin types, goal, routine, completion timestamp.
- `analyses`: historical analysis snapshots, score payload, and timestamps.
- `sync_events`: append-only event stream for conflict detection and debugging.

## Local-to-Cloud Migration Strategy
- Run one-time backfill when premium cloud sync is enabled for a local user.
- Map local user id to remote user id; preserve local ids as migration references.
- Upload onboarding profile first, then analyses in chronological order.
- Mark migrated records with a sync version to avoid duplicate uploads.

## Premium Gating Rules
- Cloud sync toggle is visible to all users, but activation requires premium entitlement.
- If premium expires, keep local read access and pause cloud writes.
- Re-activation resumes incremental sync from last known sync version.

## Rollout Phases
1. Add remote API contracts and background sync worker.
2. Release internal alpha with migration telemetry.
3. Release staged beta (10% users) with sync health dashboards.
4. Roll out broadly after conflict/error rates stabilize.

## Telemetry Checkpoints
- Migration success rate.
- Sync latency (p50/p95).
- Conflict incidence rate.
- Retry rate and terminal failure rate.
- Premium conversion rate from cloud-sync paywall entry points.
