-- Remove legacy content-hash row_keys from any payments generation that has since
-- been re-landed with the deterministic position-only key. The two are the same rows
-- under two key schemes; keeping dup_gens doubles the generation and makes the row-count
-- assertion fail forever, which blocks the ingest queue behind it.
-- Safe to re-run: it only ever deletes where the position-keyed copy already exists.
with dup_gens as (
  select source_instance_id si, report_generated_at g
  from raw_smartmoving.report_payments
  group by 1,2
  having count(*) filter (where row_key ~ '^__row[0-9]{6}__') > 0
     and count(*) filter (where row_key ~ '^__row[0-9]{6}$')  > 0
)
delete from raw_smartmoving.report_payments p
using dup_gens b
where p.source_instance_id = b.si
  and p.report_generated_at = b.g
  and p.row_key ~ '^__row[0-9]{6}__';
