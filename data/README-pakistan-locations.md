# Pakistan location import

Place the reviewed, authoritative dataset at `data/pakistan-locations.json`.
It must conform to `data/pakistan-locations.schema.json`. No unreviewed sample
or fabricated national dataset is included in the repository.

Validate without database writes:

```powershell
node scripts/import-pakistan-locations.mjs data/pakistan-locations.json --dry-run
```

After review, import from a trusted server/admin environment (never a browser):

```powershell
node --env-file=.env.local scripts/import-pakistan-locations.mjs data/pakistan-locations.json
```

The importer resolves parents independently of input ordering and reuses an
existing row with the same normalized name, type, and parent. Re-running the
same reviewed file is therefore idempotent.
