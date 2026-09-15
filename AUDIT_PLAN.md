# Warehouse audit + sales KPI layer — working plan

> **What this file is.** The live task board for the audit that started 2026-09-07 and
> the sales KPI layer that came out of it. It is updated in the same commit as the work
> it describes, so it is always the current picture.
>
> **How it relates to the other docs.** [`IMPLEMENTATION_STATUS.md`](IMPLEMENTATION_STATUS.md)
> remains the plan of record for the project as a whole; this file is one workstream
> inside it, at task granularity. [`crm_sync_contract.md`](crm_sync_contract.md) still
> outranks both on cadence, quota and mechanism. Nothing here restates a number that
> belongs to the contract.
>
> **Status vocabulary:** ✅ done and verified · 🔄 in progress · ⏳ not started ·
> ⛔ blocked (says on what).

**Last updated:** 2026-09-08 08:20 PT.

---

## Why this work exists

A full review of the repository and the live warehouse was asked for: faults, gaps,
badly-generated views, inconsistencies, duplicates and redundant tables — and on top of
that, a sales KPI layer complete enough to retire external applications.

The structural health turned out to be good: zero grain violations, zero duplicate
business keys, zero orphan jobs, every view building. What the audit found instead was
a dated time bomb, a stalled ingestion flow, a month-old piece of pipeline state that
had already destroyed data once, and two fully-built seeds that nothing read — which
turned out to be exactly what the chosen KPIs needed.

**Agreed scope:** the Data Warehouse only (`raw_smartmoving` / `staging` / `core` /
`marts` / `serving`). Three other applications share this database and are reported as
findings in section D, but are neither modified nor depended on.

**Agreed KPIs:** per-agent sales dashboards · pipeline and forecast · lead sources and
quality. Phone activity is out of scope (it needs RingCentral).

---

## Progress at a glance

| | Done | In progress | Pending | Blocked |
|---|---:|---:|---:|---:|
| A — critical defects | 7 | 0 | 0 | 0 |
| B — KPI layer | 5 | 0 | 1 | 0 |
| C — modelling defects | 7 | 0 | 1 | 0 |
| D — redundancy cleanup | 1 | 0 | 0 | 0 |

`dbt build`: **PASS=311, ERROR=0** (222 when the audit started).
Both marts reconcile exactly against `core`: 53,910 = 53,910.
Warehouse: 58,573 opportunities · 63,440 jobs · 36,847 leads · 2,133 MB · disk 42%.
Committed on branch `warehouse-audit-and-sales-kpis` (commit `cfae435`).

---

## A. Critical defects

### ✅ A1 — Retention would have deleted the 2023-2025 history on 2026-09-17
`sql/34_report_retention.sql` keeps one generation per instance per calendar day for
anything older than 10 days. The historical backfill landed 15 generations on a single
Pacific day holding **different years** of data, so the pass would have kept one of each
group and silently destroyed 2023 and 2024. Row counts would have looked healthy.

**Done:** `_is_historical_backfill` on the four pruned tables
(`sql/36_historical_backfill_marker.sql`), 15 generations and 133,381 rows flagged,
`sql/34` skips them in both the ranking and the delete.
**Verified:** zero generations are both flagged and unflagged — the only failure mode.

### ✅ A2 — `report_ingest` stalled, then crash-looped on out-of-memory for 24 h
From 2026-09-07 18:10 PT nothing was collected: all 39 SmartMoving emails sat unread and
the 21:00 batch had still not landed at 21:34, while n8n itself was demonstrably alive
(webhooks arriving, dlt running on schedule). The 31 pending reports were loaded by hand
and the 34 processed emails marked read.

**Resolved, but not by a fix.** The n8n containers restarted around 03:00 PT on 09-08 and
ingestion resumed on its own: the 03:03 generations landed normally at 03:13, with zero
ingest errors. Verified afterwards - payments did **not** duplicate (162,660 rows =
162,660 distinct keys, so marking the processed emails read did its job), and the 15
protected historical generations are intact.

**Root cause found on 2026-09-09, after it recurred and did not recover.** From 09-08
11:10 PT every execution died for 24 hours. n8n named it itself on the crashed runs:
*"Node crashed, possible out-of-memory issue"* at `Build Landing Rows`.

Three compounding causes, in order of importance:

1. **The batch was unbounded.** The Gmail sweep took every report email in the inbox -
   `newer_than:2d`, ~60 emails, ~200,000 rows - and processed them in ONE execution.
2. **Cleanup sat at the end of the graph**, behind the dbt rebuild, so a crash left
   every email in the inbox and the next sweep re-collected the same batch plus new
   arrivals. That is what turned one bad run into a 24-hour outage.
3. **Landing was per row.** One INSERT per row, ~5,000 round trips per report, and n8n
   retains each node's input and output for the whole execution, so every report was
   held in memory five or six times over. Executions ran 20-30 minutes.

**Fixed:** one report per execution (Gmail `limit: 1`, sweep `*/5 * * * *`); a single
set-based INSERT via `jsonb_to_recordset`; cleanup moved to immediately after the
row-count check, the point at which the email is provably consumed; the IMAP trigger
disabled, having fired zero executions in weeks while being the unbounded entry point.
Verified: the 18:09 payments report landed 524/524 rows in **154 ms** and its email was
trashed - the whole graph ran in under two seconds.

The *"Paired item data for item from node 'Download Report File' is unavailable"* error
was a symptom, not the cause: n8n replaces a crashed run's node output with stubs that
carry no `pairedItem`, so retrying one fails on the first `$('...').item`. Those are now
`.first()`, unambiguous because there is exactly one report per execution.

⚠️ **A4 is still the right thing to build.** Nothing alerted for 24 hours, because a
process killed for memory throws no error for `errorWorkflow` to catch. Also worth
doing: the droplet has 8 GB of RAM and **zero swap**, so Node dies outright instead of
degrading.

### ✅ A3 — A month-old presence proof was still deciding what counted as deleted
`_dlt_pipeline_state` held `{at: 2026-08-08, from: 20250204, to: 20270204}`, written by
a `--sweep-only` backfill that recorded no sightings at all. Five days later the
deletion pass marked **550 `ld` opportunities as vanished**; four were re-checked
against the API a month on and all four were alive, two of them Booked with a future
service date. 203 were still flagged.

**Done:** the 203 were re-verified against the API (204 calls, **all HTTP 200, zero
404s**) and cleared — `core` now has zero rows flagged deleted. `sweep_only` no longer
writes the presence note, and — the general fix — the deletion pass now **refuses any
presence proof older than two days** (`SWEEP_PROOF_MAX_AGE`). A stale sweep proves
nothing about absence, so the safe failure mode is to do nothing; real deletions still
come through the `opportunity-deleted` webhook's 404 path, which is direct evidence
rather than inference.





### ✅ Fase B — `serving.opportunities_v1` publicado (2026-09-14)

68.231 filas, 39 de las 60 columnas de `core`. Estrecho a proposito: un contrato
publico es barato de ampliar y caro de recortar. Excluye borradas y `is_in_scope=false`
(datos de otra empresa no pueden aparecer en un contrato publico). Catalogado.

### 🔵 Fase C — marketing: mart de campanas listo, falta el gasto (2026-09-14)

`marts.fct_campaign_daily` en dos niveles (campana individual y familia), con
`campaign_day_leads_total` y `line_share_pct` en cada fila para que la atribucion de
coste por lead sea una multiplicacion. Reconcilia exacto con `fct_lead_source_daily`
(67.677 = 67.677). Lo que queda - `dim_ad_campaign_map` (Nicolas), tablas raw de Ads,
CPL/CPA/CER - esta detallado en `IMPLEMENTATION_STATUS.md`.

### ✅ Fase C — CPL/CPA/CER publicados (2026-09-14, noche)

`dim_ad_campaign_map` (1 fila, el resto es de Nicolas), `int_ad_spend_daily`,
`fct_campaign_spend_daily` con el reparto por lead, `mart_unmapped_ad_spend` como cola,
y un test que exige atribuido + sin mapear = raw. Reconcilia: $9.025,74 + $30.155,33 =
$39.181,07 sobre $39.181,12 (redondeo, dentro de tolerancia). Hallazgos en
`IMPLEMENTATION_STATUS.md` §2 punto 3: el 63% del gasto atribuido cae en dias sin lead
(agregar por mes, no por dia) y el CPL de PNW Google Ads en 2026 es ~10x el de 2025.

### ✅ Fase C — Google Ads en produccion (2026-09-14, mismo dia)

Explorer access concedido al proyecto de Cloud al final del dia; primera corrida real,
un bug de libreria (enums como int en protobuf puro) corregido, prueba de un dia y
doble corrida superadas, backfill completo (413 campaign-days, $39.181, agosto 2024 →
hoy), workflow publicado, heartbeat ampliado. Queda para Nicolas: cuadrar $37.01 del
2026-09-13 contra la UI, anadir las tres child accounts, y `dim_ad_campaign_map`.

### 🔵 (historico) Fase C — extraccion construida, bloqueada por Google (2026-09-14, tarde)

Cliente, recurso dlt, CLI, esquema raw, staging con tests y workflow n8n (inactivo) -
todo desplegado en el droplet. La cuenta de servicio autentica y ve el Manager
`2797921560`; **cada lectura devuelve `CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION`**
hasta que Nicolas solicite Explorer/Basic access en el API Center. Nada mas por hacer
de nuestro lado hasta entonces. Decision clave: `account_id` (la child) forma parte de
la PK de `raw_google_ads.campaign_daily`, y las children se descubren en cada corrida,
asi que las tres cuentas que faltan no requieren cambios. Detalle en
`IMPLEMENTATION_STATUS.md` §2 y `marketing_ads_integration_guide.md` §2.

### ✅ Seeds de agentes, borrador completo (2026-09-14)

`dim_agent` 31 -> 65 (los 34 nombres que faltaban: vendedores historicos 2023-2025,
un alias y dos cuentas compartidas). `dim_agent_assignment` 34 -> 75, con 11 ventanas
confirmadas extendidas hacia atras y 41 nuevas. **`is_within_assignment` pasa del 58% al
99,3%.** Todo lo derivado lleva la marca DRAFT y la evidencia; Nicolas lo corrige.

### ✅ Fase A — Cancellations y Payments conectados (2026-09-10)

Los dos reportes aterrizaban y estaban tipados en `staging` desde 2026-08, y **ningun
modelo aguas abajo los leia**: 240.793 filas en `raw` sin consumidor. Cerrado.

**Cancellations.** `int_report_cancellation_latest` (patron `int_report_*_latest`, no
brazo de observacion: una sola fuente, nada que reconciliar) y `core.opportunities`
gana `cancelled_date_local` y `cancelled_amount`. El motivo de cancelacion pasa de
**219 a 1.476** registros (3,5% -> 23,3%) en siete categorias limpias, y **$2.793.977**
de ingreso cancelado se vuelve medible por primera vez.

**Dos vistas, dos preguntas distintas.** Es el error mas facil de cometer aqui:

| Vista | Grano | Responde |
|---|---|---|
| `sales_agent_daily_v1.cancellation_pct` | dia en que **llego el lead** (cohorte) | "de lo que gano este dia, cuanto se cayo" |
| `serving.cancellations_daily_v1` | dia en que **se cancelo** (periodo) | "cuanto perdimos en julio" |

La misma cancelacion aparece en ambas, en fechas distintas. **Sumarlas duplica.**

La formula de la tasa es `cancelaciones / (reservados + cancelaciones)`, no sobre
reservados solos: una cancelacion REEMPLAZA el estado booked (el status 20 pone
`is_cancelled` y quita `is_booked`), asi que devolver las cancelaciones al denominador
es lo que reconstruye "todo lo que alguna vez se gano". La vista de periodo
deliberadamente **no publica tasa**: en un grano de calendario el denominador no es
conocible, porque lo cancelado hoy se reservo a lo largo de meses anteriores.

⚠️ Cobertura desde 2026-01-02 (ventana del reporte): 1.476 de las 6.331 canceladas de
`core` tienen fecha. La vista de cohorte cuenta las 6.331 porque el flag viene del
entero de estado. Que los totales no coincidan es esto, no un fallo.

**Payments.** `int_report_payments_latest` + `core.payments`: 3.021 pagos, **$5,05M**,
ventana 2026-06-12 -> 2026-09-09. El 100% de los 2.695 pagos de oportunidad enlazan a su
GUID, y aparecen **326 pagos contra cuentas de almacenaje** que no tenian ninguna
representacion en el almacen.

No se fusiona con `core.opportunity_payments` (1.973 filas, via API) y es deliberado: no
existe un identificador de pago compartido sobre el que unir - la API no emite id de pago
y el reporte no trae GUID - asi que cualquier union duplicaria o inventaria una
correspondencia. Dos tablas con alcances claramente distintos son mejores que una con una
llave fabricada. La del reporte cubre todo a coste cero de cuota y trae fecha, metodo,
codigo de confirmacion y pagos contra job o almacenaje; la de la API trae GUID y ordinal.

`dbt build`: PASS=347, ERROR=0.

### ⏳ Siguiente fase — reportes de cancelaciones por area y por motivo

Pedidos explicitamente y **deliberadamente no implementados todavia**. Los datos ya
estan en su sitio; falta el modelado.

1. **Cancelaciones por ZIP de origen.** Donde se generan las cancelaciones. El ZIP vive
   hoy en `core.jobs.origin_zip` y en `core.leads.origin_zip`, no en
   `core.opportunities`, asi que el mart tendra que resolver cual usar cuando una
   oportunidad tiene varios jobs. Grano propuesto:
   `(entity_id, origin_zip, line_of_business, cancelled_date)`. Ojo con el denominador:
   una tasa por ZIP necesita tambien los reservados de ese ZIP, no solo las
   cancelaciones - si no, un ZIP con 2 cancelaciones de 2 trabajos se vera igual que uno
   con 2 de 200.
2. **Subdivision por motivo.** Siete motivos limpios, ya en `core.opportunities`
   .`cancellation_reason`. Grano `(entity_id, cancellation_reason, line_of_business,
   cancelled_date)` con su porcentaje sobre el total del periodo. Barato: no necesita
   ninguna fuente nueva.

### ✅ A8 — `report_bot` lost the `ld` All Jobs report on a blank sign-in page

Found 2026-09-14 while checking the 1 PM burst: eleven reports landed, the twelfth —
All Jobs for `ld` — never arrived, because `report_bot_all_jobs` had failed for `ld` at
10:00 and 13:00 PT (and on 09-12 and 09-13 at the same hours) with *"waiting for
locator('#emailAddress')"*. The failure screenshot is a blank white page: the Angular
app never painted on that cold load. `local`, tried seconds later in a fresh context,
signed in normally, and the 02:50 PT full-year run of the same day succeeded — so this
is a stalled first load, not credentials or a moved selector.

`login()` did one `goto` and one 30-second wait; `open_report()` already retried three
times, `login()` did not. **Fixed:** the sign-in navigation now reloads up to three
times before failing (`pipeline/report_bot/smartmoving.py`). Deployed to the droplet
and the `ld` request re-run by hand at 13:37 PT — signed in on the first attempt,
report queued.

⚠️ The `report_bot_all_jobs` alert fired each time and was correct. The gap is that
nothing re-requests a report whose *request* failed: the next scheduled run does, three
hours later, so a single failed run costs one All Jobs window for that instance.

### ✅ A7 — A repeated Quote # inside one Lead Status file blocked the queue for two days

Found 2026-09-14. From 2026-09-12 22:00 UTC every sweep of `report_ingest` failed on the
same email — a `local` Lead Status generated 2026-09-12 20:04 UTC — with *"SmartMoving
reported 4499 records, 4498 landed"*: **1,262 consecutive error executions**, one Slack
alert each. Two rows in that export carried the same `Quote #` (134862, a Closed
opportunity the CRM listed twice), so the second one collided on the landing PK and
`ON CONFLICT DO NOTHING` dropped it.

What it did and did not break, measured against `raw`:

- **Landing kept working.** The sweep takes the newest inbox email first, so every
  report that arrived after the stuck one was ingested on its next sweep and trashed.
  All 09-13 and 09-14 generations are in `raw` with the right counts.
- **No dbt rebuild came out of this flow for two days.** `Inbox Drained?` was never
  true while the stuck email sat there, so `core` and `serving` were refreshed only by
  the 03:30 nightly build. Intraday freshness was lost, not data.
- **The quote drain stopped for the same reason** — it hangs off the same branch.

**Fixed** in `Build Landing Rows`: a natural key that repeats inside one file is suffixed
with its position (`134862#000600`), so every row lands and the count matches.
Position is stable across re-ingests, so idempotency holds. dbt joins on the `Quote #`
inside `row_data`, never on `row_key`, so nothing downstream sees the suffix. Published
in n8n at 20:05 UTC; the stuck email passed on the next sweep (4,499 = 4,499), the
queue drained, and the drain + rebuild ran once at the end of the burst.

⚠️ **This is the third time the same failure shape has occurred** (A2, A6, A7): one email
that cannot pass `Assert Row Count Matches` re-fails every two minutes, floods Slack
with identical alerts, and holds back every rebuild behind it. The individual causes
were all different; the mechanism that turns one bad file into a two-day outage is the
same. It is documented as an open item in `deploy/n8n_report_ingest_setup.md` under
*Known limitations* — a persistent mismatch should be quarantined (logged to
`report_ingest_errors`, archived out of the inbox) after a bounded number of attempts,
so the rest of the queue and the rebuild proceed while someone looks at the one file.

**What now detects it:** `scripts/pipeline_heartbeat.py` gained an `ingest_to_build`
check (threshold 3 h) — reports landing while `core.opportunities.synced_at` stays
older than the newest landing. The two existing checks could not see this stall:
`reports` watches `_ingested_at`, which kept advancing, and `dbt_build` allows 30 h,
which the nightly build satisfied. Deployed to the droplet 2026-09-14.

Also seen while draining, harmless but worth knowing: the All Jobs email generated
2026-09-14 20:02:27 UTC was picked up twice, fifteen minutes apart, and the second pass
was a full no-op (4,998 = 4,998, one `_source_email`). Two deliveries of the same report
share a `Date` header, so the landing PK absorbs them.

### ✅ A6 — The keyless report's row key was not stable, and it silently sextupled payments

Found 2026-09-09, minutes after the quote drain went live: `report_ingest` began failing
every two minutes with *"Row count mismatch for payments / local: SmartMoving reported
2518 records, 5036 landed"*, which blocked the queue behind it exactly the way A2 did.

`report_payments` is the one report with no natural key, so its `row_key` was the row's
position plus a hash of the row's contents. The comment in the node asserted that
re-ingesting the same email yields the same rows in the same order and therefore the
same keys. **The position was stable; the hash was not.** A re-ingest produced different
keys, `ON CONFLICT DO NOTHING` never matched, and the whole generation was inserted
again. Thirteen generations had landed between two and **six** times over — 72,297
duplicate rows — and none of it raised anything, because the assertion only fires on the
generation currently being ingested.

**Fixed:** the key is now the position alone. The hash was not just unstable, it was
unnecessary — `report_generated_at` is already part of the primary key, so rows are
never compared across generations.

**Cleaned:** 72,297 duplicate rows removed, keeping the earliest landing of each
generation; then 2,518 legacy-keyed rows removed from the one generation that had since
re-landed under the new scheme. Every payments generation now matches the count
SmartMoving stated. `sql/38_dedupe_payments_row_keys.sql` holds the re-runnable form.

A transitional node, **Purge Legacy Row Keys**, sits between landing and verification: a
generation that landed under the old scheme and re-lands under the new one would carry
both and double, so it drops the legacy copy wherever the position-keyed copy exists. It
never removes a generation's only rows, and it retires when
`row_key ~ '^__row[0-9]{6}__'` returns zero.

⚠️ **The lesson is about the assertion, not the key.** The row-count check compares one
generation at a time, so it cannot see a generation that was duplicated on a previous
run — it only failed once the *same* generation was re-ingested. Six-fold duplication sat
in `raw` for two days in silence.

### ✅ A5 — 13,196 opportunities were missing from `core`, and they were the ones that never converted

Found 2026-09-09 chasing a single lead: Ana Vasquez showed 13 leads for 09-07 in
`serving.sales_agent_daily_v1` and 14 in the CRM. The missing one, quote 138511, was in
`raw` with the right date and the right agent, and had a row in `core.opportunities`
that was **empty** - no quote, no agent, no lead date, only a status. The mart filters
on `created_date_local`, so it vanished.

**Root cause, measured.** `core.opportunities` is keyed on the SmartMoving GUID, and the
report arm inner-joins the quote crosswalk to get one. The crosswalk is built from the
API only, and every API opportunity path reaches an opportunity **through its jobs** -
the sweep window is a service-date window and service dates live on jobs. So a lead that
never converted was invisible to all of them: 98.4% of opportunities present in core have
a job, against 5.5% of the absent ones. By status: **88% of bad leads, 72% of in-progress
leads and 39% of lost leads were missing**, against 0% of closed, completed and cancelled.

That is the worst possible shape for the error. The absent rows were almost entirely
leads that did NOT convert, so they were missing from the conversion denominator and
every rate in the sales layer read high.

**The fix cost zero API calls.** The premise the architecture rested on - *"/api/leads
does not return an opportunityId"*, written into `core/opportunities.sql` and the sync
strategy - is false. **The lead's `id` IS the opportunity GUID:** 23,717 of 36,895 lead
ids are byte-identical to an existing `external_opportunity_id`, GUIDs do not collide by
accident, and six lead ids absent from core were put to `GET /api/opportunities/{id}` -
all six returned 200, echoed the same id, and carried a quoteNumber. The rows were
already extracted and already carried the real identifier; nothing was joining them.

`/api/leads` is now an arm of `int_opportunity_observations` like any other source.

| | Before | After |
|---|---:|---:|
| `core.opportunities` | 58,678 | **71,874** |
| Leads in the sales mart | 53,910 | 66,929 |
| Booked | 26,644 | 26,639 |

Booked did not move, which is the point: the correction is entirely in the denominator.
Ana on 2026-09-07 now reads 10 local + 4 long distance = **14**, matching the CRM.

**The alternative was rejected on the numbers.** Matching report quotes to leads on
timestamp + salesperson measured 99.58% precise against known GUIDs - which sounds fine
and means roughly 40 opportunities silently attached to the wrong customer across the
backlog. Adding service date and referral source reached 100% on 1,330 ground-truth cases
but both fields are mutable in the CRM, so the match would not be reproducible between
builds. Rule 7 exists to prevent exactly this class of guess, and no guess was needed.

### ✅ A4 — Nothing detected an n8n execution that *dies*
Every alerting mechanism in the project lives *inside* an execution: a node throws and
`errorWorkflow` catches it. An execution killed by the OOM reaper, a container restart
mid-run, or a schedule trigger that never fires produce **no signal at all** — which is
exactly how A2 went unnoticed. The one liveness check (`Assert Serving Is Fresh`) is
evaluated only inside the 03:30 build, so if that execution is the one that dies,
nothing evaluates it.

**Done.** `scripts/pipeline_heartbeat.py` + `monitoring.pipeline_heartbeat`
(`sql/37_pipeline_heartbeat.sql`), on cron at :05/:35 — outside n8n on purpose. It
checks four mechanisms (reports, webhooks, dlt extraction, dbt build) and asks when each
last *succeeded*, not whether anything threw.

**✅ Proven by a real incident, 2026-09-09.** During the `report_ingest` out-of-memory
outage it did exactly its job: `reports` flipped to `is_silent` at **06:05 PT** — the
first check after the 8 h threshold elapsed — and posted the Slack alert on all 14
subsequent runs until ingestion recovered at 12:35 PT. Nothing else in the project
noticed, because a process killed for memory throws no error for `errorWorkflow` to
catch. That is precisely the failure class this was built for, and the only alerting
path that saw it.

Two residual weaknesses, both worth a follow-up rather than a rewrite:

- **8 hours is the floor for the reports threshold, not a choice.** SmartMoving sends at
  03, 11, 13, 15, 18 and 21 PT, so the widest legitimate gap is the 03:00→11:00 overnight
  window. Detecting faster requires a schedule-aware threshold (tight by day, loose
  overnight) instead of one constant.
- **It repeats rather than escalates.** 14 identical Slack messages in 6.5 hours is how
  an alert channel gets muted. It needs to alert on the transition, then remind at a
  decreasing rate.

**Also done 2026-09-09: 4 GB of swap on the droplet** (`/swapfile`, in `/etc/fstab`,
`vm.swappiness=10`). The box has 8 GB of RAM and had none, which is why Node was killed
outright instead of degrading. Swap is a shock absorber, not a fix — the real fix was
bounding the batch — but with zero swap there is no margin at all.

**Verified both ways**, because a silence detector that has never fired is not a
detector: with real thresholds all four report alive; with thresholds forced to four
minutes all four flag `SILENT`, the alert message formats, exit code is 1, and the rows
land in the table. Test rows were then deleted so the table does not lie.

Every run is recorded, not just the bad ones — a heartbeat table with no recent
heartbeat is the only way to notice that the monitor itself stopped.

⚠️ **One value still needed from you:** set `HEARTBEAT_SLACK_WEBHOOK` in the droplet
`.env` to a Slack incoming-webhook URL. Until then the check runs, records and exits
non-zero, but the finding only reaches cron's local mail — which nobody reads.

---

## B. The sales KPI layer

### ✅ B0 — Wire the two orphaned seeds
Both were seeded, tested and documented from the start, and read by nothing.

- **`dim_status_map`** — three separate comments in the repo asserted a join to it that
  **was never written**. Now joined in `core.opportunities` via `norm_text`, contributing
  `status_subcategory` and `status_category_reported`. Three missing rows added from
  measured unmatched values.
  **Lost-reason coverage: 56.6% → 95.6%.** Overall subcategory coverage 97.4%.
- **`dim_referral_source`** — now gives `referral_channel_group`, `referral_platform`,
  `referral_is_paid`, `referral_source_clean`. **Channel on 90%** of in-scope
  opportunities, paid/unpaid on 99%.

Both joins are guarded against fan-out by singular tests, because `norm_text` can
collapse distinct seed keys into one — and in `dim_referral_source` it already does, for
two pairs of spelling variants.

### ✅ B1 — Per-agent sales mart
`marts.fct_agent_leads_daily` extended, not duplicated: loss breakdown
(`lost_to_competitor`, `lost_on_price`, `lost_no_contact`, `lost_to_diy`,
`lost_reason_unknown`), realised deal size, and the prior-tenant filter.

### ✅ B2 — Pipeline and forecast
`marts.fct_pipeline_current` and `serving.pipeline_current_v1` are published. They are
a current snapshot, not a time series, and deliberately separate committed (booked)
from speculative (open) work. There is no probability-weighted forecast column. The
measured horizon is short; the useful signal is revenue already committed, not an
inflated combined funnel value.

### ✅ B3 — Lead source / quality mart
`marts.fct_lead_source_daily`, 10,756 rows, 2023-01-01 → 2026-09-07, cohort grain
`(entity_id, channel_group, line_of_business, lead_received_date)`. This is where
marketing spend attaches later: cost per lead, CAC and ROAS become joins at
`(date, channel)`, not new models.

### ✅ B4 — Publish to `serving` (partial)
`serving.sales_agent_daily_v1` (12,643 rows) and `serving.lead_source_daily_v1`
(10,756 rows), both catalogued in `serving_catalog.md`, both RLS-enabled, both verified
queryable by `app_read`. Also added the `relationships` tests back to `core` that the
original two operational serving views never had. `serving.pipeline_current_v1` is also
published, catalogued and related back to `marts.fct_pipeline_current`.

**Still pending:** `serving.opportunities_v1`, the view the project has declared its
number-one priority since the beginning.

### Added outside the original plan — prior-tenant isolation
The sweep back to 2023 pulled in the business that used the `ld` SmartMoving account
before 2025: **3,170 opportunities and 3,283 jobs**. Pre-2025 `ld` rows carry no branch,
no sales agent and no lead date where 2025+ carries all three on 100% of rows, and the
customer bases are disjoint — 50 shared names out of 2,892 and 2,381. Quote numbers run
*continuously* across the handover, so the split can only be a date.

`dim_instance.data_valid_from` (`ld` 2025-01-01, `local` 2023-01-01) drives `is_in_scope`
on `core.opportunities` and `core.jobs`. Rows are **flagged, never deleted** — raw keeps
what the API returned and the exclusion stays visible and reversible. The KPI marts
filter on it.

---

## C. Modelling and consistency defects

| # | Finding | Status |
|---|---|---|
| C1 | `core.lines_of_business` had **no YAML entry and zero tests** while feeding a mart | ✅ documented and tested |
| C2 | `_core.yml` defined `opportunity_charges` **twice** with contradictory grain descriptions. It does **not** break the build — verified — the second block silently wins | ✅ stale block removed |
| C3 | `core.agents` tested `unique` on the name when the grain is `(entity_id, source_agent_name)`; passes only while there is one entity | ✅ singular test on the pair |
| C4 | `report_cancellations` and `report_payments` were **not even declared as sources** and had no staging model | ✅ both declared and modelled — see below |
| C5 | The Booked-report join is duplicated between `int_opportunity_observations` and the `bkd_extra` CTE in `core/opportunities.sql` — the one report that never got its own `int_report_*_latest` | ⏳ the last one left |
| C6 | `--max-pages` was **not propagated** to `--job jobs` or the dims pulls, which truncated silently at 50 pages | ✅ every paginated pull now honours it |
| C7 | `--ids` with `--quotes` yielded two resources with the same name; nothing rejected it | ✅ rejected up front with an explanation |
| C8 | The contract said `dbt_build_reports` runs the retention prune; **the workflow only ever ran `dbt seed && dbt build`**, so pruning happened only on manual deploys. The cron was documented four different ways | ✅ retention now runs from cron at 04:10 PT and is proven to execute; the contract, `sql/README.md` and the workflow's own sticky note now agree |

Also fixed along the way: `_marts.yml` used the deprecated `tests:` key throughout — 15
occurrences migrated to `data_tests:`.

### C4 in detail — the two reports nothing read

Both were landing and row-count verified since 2026-08 and had **no source declaration
at all**, let alone a model.

- **`stg_smartmoving__report_cancellations`** — 33,725 rows, 2026-01-02 → 2026-09-07.
  `cancelled_date_local` exists in no other source: "cancelled" without a date cannot be
  trended, or compared against the booking it undid.
- **`stg_smartmoving__report_payments`** — 162,660 rows, the only per-payment record
  anywhere. `invoiced_amount` is one total per opportunity; this is the transactions
  behind it.

The payments model carries a hard three-way discriminator, and measuring it corrected
the assumption the contract has carried for months:

| | rows |
|---|---:|
| Quote only → opportunity | 130,171 |
| Quote **and** Job → opportunity | 13,988 |
| Storage Account, no quote or job → storage | 18,501 |
| **Job without a Quote** | **0** |
| None of the three | 0 |

**There is no such thing as a job-only payment in this data.** `Job` refines a payment
that already belongs to an opportunity; it is not an alternative target. The `job` arm
is kept as a defensive branch that has never fired.

What does matter is the storage third: forcing every payment under an opportunity id —
the obvious shortcut — would silently drop 18,501 payments, **$8.9M and 11% of the
cash**, and the remaining total would still look entirely plausible.

`payment_target` is tested with **warn** severity, not error: an unattached payment is a
real finding and must be loud, but payments are not yet promoted into `core`, and a
changed vendor export should not take down the nightly build of the whole warehouse over
a report nothing depends on yet. Promote to error when a core model starts reading it.

---

## D. Redundancy and cleanup — ✅ done (warehouse side)

**Done inside the warehouse:** the 8 source declarations nothing read are gone; the
stale "deliberately not modelled" description of `report_lost_leads` is corrected;
`jobs.json` and `OLD_TABLES/SCRDLA - dim_lob_map.csv` are deleted; `CLAUDE.md` rule 2
now names the client the code actually imports rather than a shim nothing does; and
`smartmoving_sync_strategy.md` carries a header listing its known drift instead of
quietly misleading whoever opens it first.

**Deliberately left alone:** `.notes.json` and the empty `.agents/` (harmless, and not
mine to decide), and the 9 weekly `dim_*` pulls that nothing reads — they cost ~100 API
calls a month and are the reference lists a future model will want.

**Outside the agreed scope — reported only.** This database is shared by at least three
other applications:

- **`qc`** (25 tables) — includes `qc.smartmoving_jobs`, 1,859 rows of quote, status,
  amounts, salesperson and dates: **duplicate extraction from SmartMoving**, precisely
  what the warehouse exists to prevent under priority #1 of `CLAUDE.md`. Also
  `qc.agents` (101 rows with `extension_number`) and 17,226 call recordings with
  transcripts. `qc.call_scores` and `qc.qc_metrics` are empty.
- **`workspace` / `ecoworkspace`** — exact duplicates of each other (13,217 tasks and
  60 projects each). Looks like a half-finished rename.
- **`raw_ringcentral.calls`** — 17,226 calls, 2026-04-09 → today, live. Carries a
  datable defect: `call_direction` switched from lower-case to capitalised on
  **2026-09-04**, which splits any grouping by direction. For when it enters scope:
  **92.4% of dialled numbers (3,840 of 4,154) match a customer phone** in `core`, so
  call-to-opportunity attribution is very achievable.

---

## Corrections made during execution

Recorded because each was a wrong turn caught by measurement, and the reasoning is worth
keeping:

- The first backfill marker used a correlated `NOT EXISTS` and ran **over ten minutes**
  on one table before being killed. Rewritten set-based: **7.2 seconds**.
- The obvious content rule ("protect a generation whose data predates its generation
  year") **over-fires** — it also protects ten routine `ld` Booked generations, because
  Long Distance has no 2026 booked date at all. Pinned to the actual load window instead.
- `dbt_utils` **is not installed** in this project and there is no `packages.yml`; a
  composite-uniqueness test using it would have broken the build. Replaced with singular
  tests, which the project already has a path for.
- `dim_referral_source.is_paid` is loaded as a **boolean**, not text.
- **`quoted_leads` was removed rather than shipped.** The estimate is never null, and
  `> 0` does not indicate a quote: opportunities with a zero estimate convert at 50.0%
  and those with a positive one at 48.9%. A metric that looks like a funnel step and
  is not one does more harm than its absence.
- **Deal size moved off the estimate.** `estimated_final_total` is zero on 45% of booked
  opportunities and would have reported **$1,151 against a true $2,085**. Now computed
  from `invoiced_amount`, present on 96% of booked deals. 2025 average: **$1,914**.

---

## Two caveats that ship with the KPI views

Both are written into `serving_catalog.md` as well, because a consumer who ignores them
gets wrong answers with no error.

1. **Recent cohorts are not comparable to old ones.** A lead from last week has not had
   time to be lost, so its cohort looks inflated — August 2026 read 71% against a 45-50%
   baseline. Exclude the last ~60 days, or show `open_leads` beside the rate.
2. **Do not slice by `is_within_assignment` yet.** It reads `false` for 42% of leads
   because `dim_agent_assignment` was built for 2026 and the 2023-2025 history falls
   outside its validity windows. Seed work, not code. Related: 34 of the 65 salesperson
   names in the data are not in `dim_agent` at all.
