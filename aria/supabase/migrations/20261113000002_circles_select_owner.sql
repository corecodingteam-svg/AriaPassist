-- Owners can always read their circle. Needed for INSERT … RETURNING:
-- the owner's membership is created by an AFTER trigger, so the
-- membership-based check alone rejects the freshly inserted row.
drop policy circles_select on public.circles;
create policy circles_select on public.circles for select to authenticated
  using (owner_id = (select auth.uid()) or public.is_circle_member(id));
