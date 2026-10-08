-- Additive migration for the inspected original project.
-- Keeps existing documentation/profile RLS policies and all existing records.
alter table public.documentations
  add column details jsonb not null default '{}'::jsonb,
  add column photo_files jsonb not null default '[]'::jsonb,
  add column request_id uuid;

alter table public.documentations
  add constraint documentation_details_object check (jsonb_typeof(details) = 'object'),
  add constraint documentation_photos_array check (
    case when jsonb_typeof(photo_files) = 'array' then jsonb_array_length(photo_files) <= 10 else false end
  ),
  add constraint documentation_submission_unique unique (created_by, request_id);

create index documentation_photo_refs on public.documentations using gin (photo_files jsonb_path_ops);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('school-documentation-images', 'school-documentation-images', false, 3145728, array['image/jpeg']);

create policy "School images upload in own folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'school-documentation-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()))
);

-- The nested SELECT uses existing documentations RLS, so a photo never grants
-- access to a record which the same user cannot read.
create policy "School images follow documentation visibility"
on storage.objects for select to authenticated
using (
  bucket_id = 'school-documentation-images'
  and exists (
    select 1 from public.documentations d
    where d.photo_files @> jsonb_build_array(jsonb_build_object(
      'bucket', 'school-documentation-images', 'path', storage.objects.name
    ))
  )
);

-- Uploaded files are not SELECT-visible until the row is committed. This trigger
-- uses fixed-schema access to check their existence and owner without granting
-- clients a new read policy on staging files.
create function public.validate_documentation_photos()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare photo jsonb; expected_prefix text;
begin
  if jsonb_typeof(new.photo_files) <> 'array' or jsonb_array_length(new.photo_files) > 10 then
    raise exception 'A documentation must contain at most ten photo references' using errcode = '23514';
  end if;
  if jsonb_array_length(new.photo_files) = 0 then return new; end if;
  if new.request_id is null then
    raise exception 'Photo references require a submission identifier' using errcode = '23514';
  end if;
  expected_prefix := new.created_by::text || '/' || new.request_id::text || '/';
  for photo in select value from jsonb_array_elements(new.photo_files) loop
    if jsonb_typeof(photo) <> 'object'
       or photo->>'bucket' is distinct from 'school-documentation-images'
       or coalesce(photo->>'path', '') !~ ('^' || expected_prefix || '[0-9a-f-]{36}\.jpg$') then
      raise exception 'Invalid documentation photo reference' using errcode = '23514';
    end if;
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'school-documentation-images' and o.name = photo->>'path'
        and coalesce(o.owner_id, o.owner::text) = new.created_by::text
    ) then
      raise exception 'Photo upload is missing or belongs to another user' using errcode = '23514';
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function public.validate_documentation_photos() from public, anon, authenticated;
create trigger validate_documentation_photo_refs
before insert or update of created_by, request_id, photo_files on public.documentations
for each row execute function public.validate_documentation_photos();

comment on column public.documentations.details is 'Complete documentation fields including checkbox groups; server archive authority';
comment on column public.documentations.photo_files is 'Private storage references only; never temporary or public URLs';
comment on column public.documentations.request_id is 'Stable client submission id; unique per creator, nullable for legacy rows';
