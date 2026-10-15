-- app.severity_for returned labels the enum does not have.
--
-- `gap_severity` is (strong, minor, medium, critical). The function emitted
-- 'none' for the top band and 'moderate' for the third, so any evaluation
-- landing in either range failed the whole insert with
-- `invalid input value for enum public.gap_severity`.
--
-- It stayed hidden because the first answers in testing all scored low enough
-- to fall through to 'critical', which is a real label. The bug needed a
-- mid-range mastery to fire — exactly the range a student reaches once they
-- start improving, so it would have surfaced on the first encouraging result
-- rather than the first bad one.
--
-- Written as a lookup against the enum's own labels rather than free strings,
-- so a future rename fails loudly at migration time instead of silently at
-- the first evaluation that reaches that band.

create or replace function app.severity_for(p_mastery numeric)
returns public.gap_severity
language sql
immutable
as $$
  select case
    when p_mastery >= 75 then 'strong'
    when p_mastery >= 55 then 'minor'
    when p_mastery >= 35 then 'medium'
    else 'critical'
  end::public.gap_severity;
$$;

comment on function app.severity_for is
  'Maps a mastery percentage onto gap_severity. Bands match VxSeverity in the client: 75+ strong, 55+ minor, 35+ medium, below that critical.';

-- Prove every band round-trips now, at migration time rather than at the
-- first evaluation that happens to reach one.
do $$
declare
  v record;
begin
  for v in
    select * from (values (95.0, 'strong'), (60.0, 'minor'),
                          (40.0, 'medium'), (10.0, 'critical')) as t(pct, expected)
  loop
    if app.severity_for(v.pct) <> v.expected::public.gap_severity then
      raise exception 'severity_for(%) gave %, expected %',
        v.pct, app.severity_for(v.pct), v.expected;
    end if;
  end loop;
end $$;

-- Rows written before the fix could only be 'critical' (the other paths
-- raised), but a stale severity is a wrong colour on the concept list, so
-- recompute them all from the mastery that is actually stored.
update public.concept_mastery
   set gap_severity = app.severity_for(mastery_pct)
 where gap_severity is distinct from app.severity_for(mastery_pct);
