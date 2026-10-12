create or replace function support_private.resubmit_booking(request_uuid uuid,starts_at timestamptz,ends_at timestamptz,location text,expected_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.support_requests;
begin
 if not support_private.member() then raise exception 'يلزم حساب المدرسة.' using errcode='42501';end if;
 select * into r from public.support_requests where id=request_uuid for update;
 if not found or r.created_by<>auth.uid() or r.kind<>'booking' or r.status<>'needs_revision' then raise exception 'طلب التعديل غير متاح.' using errcode='42501';end if;
 if r.version is distinct from expected_version then raise exception 'حدّثي الطلب أولًا.' using errcode='40001';end if;
 if starts_at is null or ends_at is null or location is null or starts_at<now() or ends_at<=starts_at or length(btrim(location)) not between 1 and 300 then raise exception 'راجعي المكان والموعد الجديد.';end if;
 update public.support_requests set requested_start=starts_at,requested_end=ends_at,location=btrim(resubmit_booking.location),status='pending',version=version+1,updated_at=now() where id=request_uuid;
 return jsonb_build_object('id',request_uuid,'status','pending','version',r.version+1);
end $$;
