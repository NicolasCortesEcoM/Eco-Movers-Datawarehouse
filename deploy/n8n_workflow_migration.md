# Migrating the existing n8n workflows

Two things changed on 2026-08-08 and every workflow that SSHes into the droplet is
affected by both.

## Change 1 - the host path moved

| Old | New |
|---|---|
| `/opt/datawarehouse` | `/home/datawarehouse_user/datawarehouse` |

`/opt` on this droplet is mode 700 owned by another application's service user.
Claiming space there would have meant loosening permissions on a directory that is
not ours, so the deployment lives in the service account's home instead.

**Any node still pointing at `/opt/datawarehouse` fails with "Permission denied".**

## Change 2 - piping the output hides failures

This is the one that matters. Every command of this shape is broken:

```bash
cd /opt/datawarehouse/pipeline && ../venv/bin/python run.py ... 2>&1 | tail -25
```

A shell pipeline returns the exit code of its **last** stage - `tail` - which always
succeeds. So the node reports success no matter how badly `run.py` failed, the
schedule stays green, and the only symptom is data that quietly stops moving.

This is not hypothetical. Extraction had been failing at the load step since
2026-07-22 and reporting exit 0 the whole time. Seventeen days, no alert.

**Correct shape - capture, print, re-raise:**

```bash
out=$(cd /home/datawarehouse_user/datawarehouse/pipeline && \
      set -a && . ../.env && set +a && \
      ../venv/bin/python run.py <ARGS> 2>&1); rc=$?; echo "$out" | tail -25; exit $rc
```

The `set -a; . ../.env; set +a` is required: the SSH node opens a non-login shell,
so nothing in the host `.env` is exported unless the command does it.

---

## Per-workflow changes

Apply Change 1 and Change 2 to every SSH node below. `<ARGS>` is all that differs.

| Workflow | `<ARGS>` | Schedule change |
|---|---|---|
| `Enrichment_worker` | `--ids <ids> --instance <inst> --dest postgres --budget 200 --pace 0.6` | keep 5 min |
| `leads_poll` | `--job leads --instance <inst> --dest postgres --budget 60` | 30 min -> **5x/day**, aligned with the sweep |
| `opps_sweep` | `--job opps-window --instance <inst> --dest postgres --budget 200` | hourly -> **06:30, 10:30, 13:30, 16:30, 20:30 PT** |
| `nightly_reconciliation` | `--job enrich --instance <inst> --dest postgres --budget 400 --refresh-stale-hours 336` | keep 02:00 |
| `weekly_dims` | `--job dims --instance <inst> --dest postgres --budget 60` | unchanged |
| `Reporting_datawarehouse` | no SSH node - webhook only | unchanged |

### Also add to every one of them

1. **`errorWorkflow` = `datawarehouse_error_handler`** (id `J1y2uCUFvCcNkZjZ`) in
   Workflow Settings, so a failure actually reaches Slack.
2. **A `Assert Exit Code` Code node** after the SSH node. The SSH node reports the
   remote status in `code` but does **not** fail the workflow on it, so without this
   the `exit $rc` above still goes unnoticed:

```javascript
const r = $input.first().json;
const code = Number(r.code ?? r.exitCode ?? 0);
const out = String(r.stdout || '') + '\n' + String(r.stderr || '');

// The SSH node surfaces the remote exit status but treats any completed command as
// a success. Throwing here is what routes a failed extraction to the error workflow
// instead of letting the schedule stay green over a pipeline that stopped running.
if (code !== 0) {
  throw new Error('Extraction FAILED (exit ' + code + ').\n\n' + out.slice(-3000));
}

// dlt reports a failed load as a normal log line, not a non-zero exit, whenever the
// failure happens inside a load package. API quota is spent before this point, so a
// silent partial load is expensive as well as wrong.
if (/PipelineStepFailed|contains failed jobs|LoadClientJobFailed/i.test(out)) {
  throw new Error('dlt reported a failed load package.\n\n' + out.slice(-3000));
}

return [{ json: { ok: true, tail: out.slice(-1500) } }];
```

### Finally

Wrap any node that runs **dbt** (not `run.py`) in `flock`, exactly as
`n8n_dbt_build_reports.json` does. Two overlapping dbt builds drop and recreate the
same tables, and the loser writes into objects the winner already replaced.

## After migrating

Run one manual `--job enrich` per instance. The API side is stale to 2026-07-22, so
`core.opportunities` is carrying July values for every field the reports do not cover
until a full enrichment pass catches up.
