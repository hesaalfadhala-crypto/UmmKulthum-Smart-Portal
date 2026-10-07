-- Internal trigger lookup is deliberately outside the exposed public schema.
create schema school_documentation_internal;
revoke all on schema school_documentation_internal from public, anon, authenticated;
alter function public.validate_documentation_photos() set schema school_documentation_internal;

create or replace function school_documentation_internal.validate_documentation_photos()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare photo jsonb; expected_prefix text;
begin
  if auth.uid() is not null and new.created_by is distinct from auth.uid() then
    raise exception 'Creator does not match the signed-in user' using errcode = '42501';
  end if;
  if auth.uid() is null and current_setting('role', true) in ('anon', 'authenticated') then
    raise exception 'A signed-in creator is required' using errcode = '42501';
  end if;
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
revoke all on function school_documentation_internal.validate_documentation_photos() from public, anon, authenticated;
