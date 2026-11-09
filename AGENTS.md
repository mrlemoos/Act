<!-- galicia:start -->
## Galicia

Read context.md first; load relevant domain context only. Domain terms: docs/Language.md. Decisions: docs/adr/. Specs/tickets: docs/specs/. Start new records from .galicia/templates/adr.md, spec.md, or ticket.md. Local Markdown only. No emojis. Preserve checks, exact contracts and uncertainty. Before consequential ADR work, recommend scoped small-model research/review; spawn only when authorised.

Startup review fallback: run `node .galicia/check.ts` once per session if no startup hook ran. Metadata flags are review candidates; never delete without explicit user approval. Follow relevant specs to compare implementation when needed; age alone proves nothing. Grilling cadence: read .galicia/config.json, ask user if unset.
<!-- galicia:end -->

## Git workflow

Use Conventional Commits for every commit, for example `feat: add shot planning` or `fix: preserve Fountain line endings`.

Always commit on `main`. Do not create feature branches. Preserve unrelated work when preparing commits.
