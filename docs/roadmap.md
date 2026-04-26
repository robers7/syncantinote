# Delivery Roadmap

## Milestone A - Bootstrap

- Monorepo layout and TypeScript configuration.
- Server migration and route scaffolding.
- Helper migration and sync loop scaffolding.
- VPS deployment scripts and templates.

## Milestone B - Upload channel

- Read Antinote snapshot.
- Detect changed rows with hash + updated timestamp.
- Push changes to VPS API.

## Milestone C - Pull channel

- Pull changes since revision watermark.
- Queue or apply based on Antinote process state.

## Milestone D - Conflicts and deletes

- Return and store conflict details.
- Keep-both conflict copy strategy.
- Soft delete propagation (`deleted_at`).

## Milestone E - Ops hardening

- Health and status endpoints.
- Retry/backoff and dead-letter queue file for failed applies.
- Backup and restore scripts for canonical DB.
