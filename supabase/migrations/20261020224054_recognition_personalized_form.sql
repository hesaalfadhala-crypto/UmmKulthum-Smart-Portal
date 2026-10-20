-- Versioned recognition payload; existing records and RLS grants remain unchanged.
create or replace function documentation_private.validate_execution_recognition() returns trigger language plpgsql security definer set search_path='' as $$
declare d jsonb:=coalesce(new.details,'{}');r jsonb;ids jsonb;recipients jsonb;awards jsonb;hours numeric;kind text;item jsonb;person record;personal_hours numeric;seen integer;typ text:=coalesce(new.activity_type,d->>'type');
begin
 if coalesce(d->'recognition'->>'schemaVersion','')='2' and documentation_private.is_recognition(d,new.projects) then null;
 elsif typ in('فعالية','ورشة تدريبية','مبادرة','ملتقى') then
  new.execution_scope:=coalesce(new.execution_scope,nullif(d->>'executionScope',''),case when typ='ورشة تدريبية' then new.workshop_type end);
  if new.execution_scope is null or new.execution_scope not in('internal','external') then raise exception 'نطاق التنفيذ مطلوب: داخلية أو خارجية.';end if;
  new.organizing_entity:=nullif(btrim(coalesce(new.organizing_entity,d->>'organizingEntity')),'');new.hosting_entity:=nullif(btrim(coalesce(new.hosting_entity,d->>'hostingEntity')),'');
  if new.execution_scope='external' and (coalesce(length(new.organizing_entity),0) not between 1 and 300 or coalesce(length(new.hosting_entity),0) not between 1 and 300) then raise exception 'الجهة المنظمة والجهة المستضيفة مطلوبتان للنشاط الخارجي.';end if;
  if new.execution_scope='internal' then new.organizing_entity:=null;new.hosting_entity:=null;end if;
  d:=d||jsonb_build_object('executionScope',new.execution_scope,'organizingEntity',new.organizing_entity,'hostingEntity',new.hosting_entity);
  if typ='ورشة تدريبية' then
   new.workshop_type:=new.execution_scope;new.executing_agency:=new.organizing_entity;
   d:=d||jsonb_build_object('workshopType',new.execution_scope,'executingAgency',new.organizing_entity);
  end if;
 else new.execution_scope:=null;new.organizing_entity:=null;new.hosting_entity:=null;d:=d-array['executionScope','organizingEntity','hostingEntity'];end if;
 if documentation_private.is_recognition(d,new.projects) then
  if not documentation_private.recognition_allowed(true) then raise exception 'إضافة التكريم متاحة للمخولات فقط.' using errcode='42501';end if;
  if not coalesce(d->'projects' @> '["أنتِ تستحقين الشكر"]'::jsonb,false) then raise exception 'اختاري مشروع أنتِ تستحقين الشكر.';end if;
  r:=d->'recognition';
  if jsonb_typeof(r) is distinct from 'object' then raise exception 'بيانات التكريم مطلوبة.';end if;
  if r->>'schemaVersion'='2' then
   if coalesce(length(btrim(r->>'title')),0) not between 1 and 300 then raise exception 'عنوان التكريم مطلوب.';end if;
   if coalesce(r->>'date','') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'تاريخ التكريم مطلوب.';end if;
   new.activity:=btrim(r->>'title');new.activity_date:=(r->>'date')::date;
   ids:=r->'recipientIds';
   if jsonb_typeof(ids) is distinct from 'array' then raise exception 'اختاري المكرمات.';end if;
   if jsonb_array_length(ids) not between 1 and 150 or (select count(distinct value) from jsonb_array_elements_text(ids))<>jsonb_array_length(ids) then raise exception 'اختاري المكرمات دون تكرار.';end if;
   if jsonb_typeof(r->'recipients') is distinct from 'array' then raise exception 'بيانات المكرمات مطلوبة.';end if;
   if jsonb_array_length(r->'recipients')<>jsonb_array_length(ids) then raise exception 'راجعي بيانات المكرمات.';end if;
   awards:=r->'awards';
   if jsonb_typeof(awards) is distinct from 'array' then raise exception 'اختاري نوع التكريم.';end if;
   if jsonb_array_length(awards) not between 1 and 7 or (select count(distinct value) from jsonb_array_elements_text(awards))<>jsonb_array_length(awards)
    or exists(select 1 from jsonb_array_elements_text(awards) a where a not in('شهادة شكر وتقدير','بطاقة شكر إلكترونية','ساعات سعادة','تكريم في الطابور الصباحي','تكريم في اجتماع أو فعالية','هدية رمزية','أخرى')) then raise exception 'نوع التكريم غير صالح.';end if;
   if awards @> '["أخرى"]' and coalesce(length(btrim(r->>'awardOther')),0) not between 1 and 500 then raise exception 'وضحي نوع التكريم الآخر.';end if;
   recipients:='[]'::jsonb;hours:=0;seen:=0;
   for person in select p.id,p.full_name,p.department from public.profiles p where p.id in(select value::uuid from jsonb_array_elements_text(ids)) order by p.full_name loop
    if (select count(*) from jsonb_array_elements(r->'recipients') x where x->>'id'=person.id::text)<>1 then raise exception 'بيانات المكرمة مكررة أو ناقصة.';end if;
    select x into item from jsonb_array_elements(r->'recipients') x where x->>'id'=person.id::text;
    if coalesce(length(btrim(item->>'reason')),0) not between 1 and 6000 then raise exception 'سبب التكريم مطلوب لكل مكرمة.';end if;
    if awards @> '["ساعات سعادة"]' then
     personal_hours:=(item->>'hours')::numeric;
     if personal_hours is null or personal_hours<=0 or personal_hours>1000 or personal_hours<>round(personal_hours,2) then raise exception 'راجعي ساعات السعادة لكل مكرمة.';end if;
    else personal_hours:=0;end if;
    recipients:=recipients||jsonb_build_array(jsonb_build_object('id',person.id,'name',person.full_name,'department',coalesce(person.department,''),'reason',btrim(item->>'reason'),'hours',personal_hours));
    hours:=hours+personal_hours;seen:=seen+1;
   end loop;
   if seen<>jsonb_array_length(ids) then raise exception 'إحدى المكرمات غير موجودة في حسابات المدرسة.';end if;
   r:=jsonb_build_object('schemaVersion',2,'title',new.activity,'date',new.activity_date,'recipientIds',ids,'recipients',recipients,'kind',coalesce(nullif(r->>'kind',''),'جهود استثنائية'),'kindOther',left(coalesce(r->>'kindOther',''),500),'reason',left(coalesce(r->>'reason',''),6000),'awards',awards,'awardOther',case when awards @> '["أخرى"]' then btrim(r->>'awardOther') else null end,'hours',0,'totalHours',hours,'presenter',left(coalesce(r->>'presenter',''),300),'notes',left(coalesce(r->>'notes',''),6000));
   new.details:=d||jsonb_build_object('recognition',r,'activity',new.activity,'date',new.activity_date);
   return new;
  end if;
  if coalesce(length(btrim(r->>'title')),0) not between 1 and 300 or coalesce(length(btrim(r->>'reason')),0) not between 1 and 6000 or coalesce(length(btrim(r->>'presenter')),0) not between 1 and 300 then raise exception 'عنوان التكريم وسببه والجهة المقدمة مطلوبة.';end if;
  if coalesce(r->>'date','') !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'تاريخ التكريم مطلوب.';end if;
  new.activity:=btrim(r->>'title');new.activity_date:=(r->>'date')::date;
  ids:=r->'recipientIds';
  if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids) not between 1 and 150 then raise exception 'اختاري مكرمة واحدة على الأقل.';end if;
  if (select count(distinct value) from jsonb_array_elements_text(ids))<>jsonb_array_length(ids) then raise exception 'لا يجوز تكرار المكرمة في الفعالية نفسها.';end if;
  select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'department',coalesce(nullif(btrim(p.department),''),'الإدارة المدرسية')) order by p.full_name) into recipients from public.profiles p where p.id in(select value::uuid from jsonb_array_elements_text(ids));
  if coalesce(jsonb_array_length(recipients),0)<>jsonb_array_length(ids) then raise exception 'إحدى المكرمات غير موجودة في حسابات المدرسة.';end if;
  kind:=r->>'kind';
  if kind is null or kind not in('مبادرة متميزة','تميز في الأداء الوظيفي','جهود استثنائية','تفعيل الأنشطة والفعاليات','تعاون ومساندة الزميلات','تحقيق إنجاز أو مركز متقدم','أخرى') then raise exception 'نوع التكريم غير صالح.';end if;
  if kind='أخرى' and coalesce(length(btrim(r->>'kindOther')),0) not between 1 and 500 then raise exception 'وضحي نوع التكريم الآخر.';end if;
  awards:=r->'awards';
  if jsonb_typeof(awards) is distinct from 'array' or jsonb_array_length(awards) not between 1 and 7 or exists(select 1 from jsonb_array_elements_text(awards) a where a not in('شهادة شكر وتقدير','بطاقة شكر إلكترونية','ساعات سعادة','تكريم في الطابور الصباحي','تكريم في اجتماع أو فعالية','هدية رمزية','أخرى')) then raise exception 'اختاري نوع التقدير المقدم.';end if;
  if awards @> '["أخرى"]' and coalesce(length(btrim(r->>'awardOther')),0) not between 1 and 500 then raise exception 'وضحي نوع التقدير الآخر.';end if;
  if awards @> '["ساعات سعادة"]' then
   hours:=(r->>'hours')::numeric;
   if hours is null or hours<=0 or hours>1000 or hours<>round(hours,2) then raise exception 'أدخلي ساعات السعادة لكل مكرمة أكبر من صفر وحتى 1000 بمنزلتين عشريتين.';end if;
  else hours:=0;end if;
  r:=jsonb_build_object('title',new.activity,'date',new.activity_date,'recipientIds',ids,'recipients',recipients,'kind',kind,'kindOther',case when kind='أخرى' then btrim(r->>'kindOther') else null end,'reason',btrim(r->>'reason'),'awards',awards,'awardOther',case when awards @> '["أخرى"]' then btrim(r->>'awardOther') else null end,'hours',hours,'presenter',btrim(r->>'presenter'),'notes',left(coalesce(r->>'notes',''),6000));
  d:=d||jsonb_build_object('recognition',r,'activity',new.activity,'date',new.activity_date);
 end if;
 new.details:=d;return new;
end$$;

-- Directory data comes from profiles; blank departments remain blank. Access checks stay unchanged.
create or replace function documentation_private.recognition_staff() returns table(id uuid,full_name text,department text) language plpgsql stable security definer set search_path='' as $$
begin
 if not documentation_private.recognition_allowed(true) then raise exception 'ليست لديكِ صلاحية إدخال التكريم.' using errcode='42501';end if;
 return query select p.id,p.full_name,coalesce(p.department,'') from public.profiles p where nullif(btrim(p.full_name),'') is not null order by p.full_name;
end$$;
