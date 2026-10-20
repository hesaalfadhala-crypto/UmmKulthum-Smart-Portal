-- Hidden legacy audience selections must not block the dedicated form. Preserve their values.
create or replace function documentation_private.resolve_other_choices() returns trigger
language plpgsql set search_path='' as $$
declare k text; selected boolean; label text; vals jsonb; rendered text;
begin
 if new.details is null then return new;end if;
 if new.details ? 'otherDetails' and jsonb_typeof(new.details->'otherDetails')<>'object' then raise exception 'تفاصيل أخرى غير صالحة.';end if;
 foreach k in array array['type','department','projects','committees','targets','docCompetitionResult'] loop
  if k='docCompetitionResult' and coalesce(new.details->>'type',new.activity_type)<>'مسابقة وإنجاز طلابي' then continue;end if;
  if k='targets' and new.details->'recognition'->>'schemaVersion'='2' and coalesce(new.details->'projects' @> '["أنتِ تستحقين الشكر"]'::jsonb,false) then continue;end if;
  vals:=new.details->k;
  if k in('projects','committees','targets') then
   selected:=coalesce(vals @> '["أخرى"]'::jsonb,false);
  else selected:=coalesce(new.details->>k,'')='أخرى';end if;
  if not selected then continue;end if;
  if jsonb_typeof(new.details->'otherDetails'->k) is distinct from 'string' then raise exception 'يرجى التحديد: %',k;end if;
  label:=btrim(new.details->'otherDetails'->>k);
  if length(label) not between 1 and 300 then raise exception 'يرجى التحديد: % (حتى 300 حرف).',k;end if;
  if k in('projects','committees','targets') then
   select string_agg(case when v='أخرى' then label else v end,' • ' order by ordinal)
    into rendered from jsonb_array_elements_text(vals) with ordinality a(v,ordinal);
   if k='projects' then new.projects:=rendered;
   elsif k='committees' then new.committees:=rendered;
   else new.target_categories:=rendered;end if;
  elsif k='department' then new.department:=label;
  elsif k='type' then new.activity_type:=label;
  else new.competition_result:=label;end if;
 end loop;
 return new;
end $$;
