import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
export const id=n=>'30000000-0000-4000-8000-'+String(n).padStart(12,'0');
export const migration='20261011201134_weekly_plans.sql';
export async function database(){
 const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema storage;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth,storage to authenticated;grant execute on function auth.uid() to authenticated;
 create table profiles(id uuid primary key references auth.users(id),full_name text,role text,department text,school_access text);
 alter table profiles enable row level security;grant select on profiles to authenticated;create policy own on profiles for select to authenticated using(id=auth.uid());
 create table observation_teachers(id uuid primary key,full_name text,department text,user_id uuid,active boolean default true,position text,academic_year text);
 create table observation_access(user_id uuid references profiles(id),department text,can_edit boolean,domain_ids integer[]);
 alter table observation_access enable row level security;grant select on observation_access to authenticated;create policy own_grants on observation_access for select to authenticated using(user_id=auth.uid());
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,owner uuid,owner_id text);
 alter table storage.objects enable row level security;grant select,insert,delete on storage.objects to authenticated;
 `);
 await db.exec(await fs.readFile(new URL('../../supabase/migrations/'+migration,import.meta.url),'utf8'));
 await db.exec("alter table profiles add column departments text[] not null default '{}';");await db.exec(await fs.readFile(new URL('../../supabase/migrations/20261019222107_weekly_shared_visibility.sql',import.meta.url),'utf8'));
 for(let n=1;n<=9;n++){await db.query('insert into auth.users values($1,$2,now())',[id(n),'qa'+n+'@school.invalid']);if(n<9)await db.query('insert into profiles(id,full_name,role,department,school_access) values($1,$2,$3,$4,$5)',[id(n),'مستخدمة اختبار '+n,n===1?'principal':n===2||n===3?'assistant_principal':n===4?'first_teacher':'teacher',n===3||n===4?'الرياضيات':'',n<3?'all':'own']);}
 await db.query("insert into observation_access values($1,'الرياضيات',true,'{}'),($2,'الرياضيات',true,'{}')",[id(3),id(4)]);
 for(const [n,dept,bound] of [[5,'الرياضيات',true],[6,'الرياضيات',true],[7,'اللغة العربية',true],[8,'الرياضيات',false]])await db.query('insert into weekly_staff(id,user_id,full_name,department,author_enabled,required_by_default) values($1,$2,$3,$4,true,true)',[id(100+n),bound?id(n):null,'معلمة اختبار '+n,dept]);
 await as(db,1);
 const period=await rpc(db,'configure_weekly_plans',{payload:{action:'period',academic_year:'2026-2027',semester:1,week_number:7,starts_on:'2026-10-11',due_at:'2026-10-12T12:00:00+03:00',staff_ids:[id(105),id(106),id(107),id(108)]}});
 return {db,period:period.id};
}
export async function as(db,n){await db.exec(`reset role;set request.jwt.claim.sub='${n?id(n):''}';set role ${n?'authenticated':'anon'}`);}
export async function admin(db){await db.exec('reset role');}
export async function rpc(db,name,args={}){return(await db.query('select public.'+name+'('+Object.keys(args).map((_,i)=>'$'+(i+1)).join(',')+') result',Object.values(args))).rows[0].result;}
export const body=(text='مهمة اختبار واضحة')=>({slots:[{day:0,period:'1',category:'meeting',text}],deliveries:[{task:'ملف اختبار',responsible:'معلمة اختبار',due:'2026-10-12'}],notes:'ملاحظات اختبار'});
export const saveArgs=(period,n=5,kind='staff',version=0,op=1000)=>({payload:{id:id(500+n),period_id:period,kind,staff_id:kind==='staff'?id(100+n):null,body:body(),file_id:null,submit:false},expected_version:version,operation_id:id(op)});
