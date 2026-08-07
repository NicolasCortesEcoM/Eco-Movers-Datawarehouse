# How status works in this warehouse

If you are new here, read this before writing any query that counts leads, booked
jobs, or conversion. Status is the single most confusing part of the SmartMoving
data, and getting it wrong produces numbers that look plausible and are wrong.

---

## The short version

**Count on `status_code` (and the `is_*` flags derived from it). Ignore `pipeline_status`.**

```sql
-- how many booked?
select count(*) from core.jobs where is_booked;

-- conversion rate, excluding junk leads
select round(100.0 * count(*) filter (where is_booked)
           / nullif(count(*) filter (where not is_bad_lead), 0), 1) as booked_pct
from core.jobs;
```

That is the whole answer for most questions. The rest of this page explains why
there is more than one status field and when the others matter.

---

## There are three status fields. Only one is authoritative.

### 1. `status` — the integer. **This is the real one.**

SmartMoving's API returns an integer that is the actual state of the lead or
opportunity. It has exactly nine values:

| Code | Name           | Category    | Meaning |
|-----:|----------------|-------------|---------|
| 0    | NewLead        | `open`      | Just received, nobody has worked it |
| 1    | LeadInProgress | `open`      | Sales is working it |
| 3    | Opportunity    | `open`      | Qualified and quoted, still winnable |
| 4    | Booked         | `booked`    | Customer committed — the revenue milestone |
| 10   | Completed      | `completed` | Move performed |
| 11   | Closed         | `closed`    | Job finished and closed out |
| 20   | Cancelled      | `cancelled` | Was booked, then cancelled |
| 30   | Lost           | `lost`      | Real lead that went elsewhere or stopped moving |
| 50   | BadLead        | `bad_lead`  | Not a real lead (spam, duplicate, wrong service) |

This lives in the seed **`dim_opportunity_status`**, which also carries the boolean
flags. Both leads and opportunities use this same enum, so "booked" means the same
thing everywhere.

**Two rules that are easy to get wrong:**

- **Completed (10) and Closed (11) both count as booked.** A job that finished
  necessarily passed through booking. If you filter `status_code = 4` instead of
  `is_booked`, you will under-count revenue by every job that has since completed.
- **BadLead (50) is the only status with `is_valid_lead = false`.** It is what you
  exclude from a conversion-rate denominator. Lost and Cancelled are real leads
  that did not convert — they belong in the denominator.

### 2. `pipeline_status` — the CRM label. **Context only, never a metric.**

This is SmartMoving's `leadStatus` field: a free-text pipeline label a rep sets by
dragging a card — `CMET`, `Follow Up`, `Tentative Booking`, `Lead Reservoir`,
`Wellness Check`.

It is genuinely useful for understanding what a rep is doing. It is **not** an
outcome, and it does not agree with the real status. Measured in our own data: a
`status_code = 30` (Lost) opportunity can still read `pipeline_status = 'Booked'`.

It also arrives dirty — both `'Booked'` and `'Booked '` (with a trailing space)
occur in the same column. We trim it once at the staging boundary, because
untrimmed it splits into two values and booked counts run about 15% low.

**Never write `where pipeline_status = 'Booked'`.**

### 3. The report `Status` string — authoritative, and adds the *reason*.

The scheduled reports emit status as a string that is the enum name **plus a
subcategory**:

```
Lost price too high
Lost already booked with another mover
Cancelled no availability
Bad lead duplicate lead
```

This is the same outcome as the integer, with the "why" attached. It maps through
the seed **`dim_status_map`**, which resolves 99% of observed values to the same
`status_category` vocabulary as the integer enum — so counts agree whichever side
you come from.

Use this when you want to know *why* something was lost or cancelled. Use the
integer when you just want the outcome.

---

## Which seed do I join to?

| I have… | Join to | Get |
|---|---|---|
| the integer `status_code` | `dim_opportunity_status` | name, category, `is_*` flags |
| a report status string | `dim_status_map` | category, **subcategory**, `is_*` flags |
| `pipeline_status` | nothing | it is context, not a classification |

Both seeds share one `status_category` vocabulary:
`open`, `booked`, `completed`, `closed`, `cancelled`, `lost`, `bad_lead`.

Join report strings with the **`norm_text`** macro on both sides — report casing
and punctuation drift, and `norm_text` collapses that.

---

## Where the numbers come from

`core.jobs` and `core.leads` already carry the resolved label, category and flags,
so most questions never need a seed join at all:

```
opportunity_status_code      the integer
opportunity_status_label     'Booked', 'Lost', 'Cancelled', ...
opportunity_status_category  'booked', 'lost', ...
is_booked, is_lost, is_cancelled, is_completed, is_bad_lead, is_open
```

The flags are real booleans, so `where is_booked` works directly — no `= 1`.

---

## The one report that makes conversion possible

`report_lead_status` (the **Lead Status** scheduled report) is keyed on lead
**received date**, so a single export returns *every* lead and opportunity received
in a period, whatever happened to it afterwards.

That matters because every other report is one slice — only booked, only lost. This
one is the **denominator**. Without it you can count what you won, but you cannot
compute a conversion rate, because you do not know what came in.

It costs zero API quota.

---

## Common mistakes

| Mistake | What happens |
|---|---|
| `where pipeline_status = 'Booked'` | Wrong number. That field is not an outcome. |
| `where status_code = 4` | Under-counts: misses Completed (10) and Closed (11). Use `is_booked`. |
| Excluding Lost/Cancelled from the denominator | Inflates conversion rate. Only BadLead should be excluded. |
| Joining report status strings without `norm_text` | Silent misses from casing/punctuation drift. |
| Trusting `Lead Status` in a report | Same trap as `pipeline_status` — it is the CRM label, not the outcome. |
