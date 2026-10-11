-- =====================================================================
-- 2026年分县区人才队伍月报 · 逐月填报系统（v2）数据库初始化脚本
-- 在 Supabase Dashboard → SQL Editor → New query 整段执行
--
-- 版本说明（v2 新增）：
--   · 逐月填报：monthly_reports 每县区每月一行，成员填「当月新增数」
--   · 系统累计：目标值只存一份于 regions 表，累计=1~某月之和由前端/SQL计算
--   · 修改审计：fill_logs 由触发器自动记录每次字段改动（谁/何时/旧值→新值）
--   · 账号预置：由管理员在 Dashboard 建 12 个虚拟邮箱账号并在 profiles 绑定县区，
--     应用不再提供自助注册
-- =====================================================================

-- 删除旧结构（仅演示/初始化时使用；正式请确认无重要数据）
drop table if exists public.fill_logs cascade;
drop table if exists public.monthly_reports cascade;
drop table if exists public.profiles cascade;
drop table if exists public.regions cascade;

-- ========== 1. regions：县区目标值（唯一一份，全年不变） ==========
create table public.regions (
  region         text primary key,
  peixun_target  int not null default 0,   -- 全年培训目标任务
  jineng_target  int not null default 0,   -- 全年技能人才目标任务
  gjg_target     int not null default 0    -- 全年高级工以上目标任务
);

-- ========== 2. monthly_reports：每县区每月一条，存当月新增 ==========
create table public.monthly_reports (
  id             uuid primary key default gen_random_uuid(),
  report_month   text not null,            -- 'YYYY-MM'，如 '2026-09'
  region         text not null references public.regions(region),
  peixun_c       int not null default 0,   -- 当月新增·职业技能培训
  jineng_sheng_c int not null default 0,   -- 当月新增·技能人才省级
  jineng_shi_c   int not null default 0,   -- 当月新增·技能人才市级
  gjg_sheng_c    int not null default 0,   -- 当月新增·高级工省级
  gjg_shi_c      int not null default 0,   -- 当月新增·高级工市级
  updated_by     uuid references auth.users(id),
  updated_at     timestamptz default now(),
  unique (region, report_month)
);

-- ========== 3. fill_logs：修改审计表 ==========
create table public.fill_logs (
  id           bigint generated always as identity primary key,
  report_month text not null,
  region       text not null,
  field        text not null,              -- 被改字段名，如 peixun_c
  old_value    int,
  new_value    int,
  filled_by    uuid references auth.users(id),
  filled_at    timestamptz default now()
);
create index if not exists idx_fill_logs_region_month on public.fill_logs(region, report_month);

-- ========== 4. profiles：账号 → 县区 / 管理员 ==========
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  region     text,                         -- 所属县区名；管理员为 NULL
  is_admin   boolean not null default false,
  created_at timestamptz default now()
);

-- ========== 5. 行级安全策略（RLS） ==========
alter table public.regions         enable row level security;
alter table public.monthly_reports enable row level security;
alter table public.fill_logs       enable row level security;
alter table public.profiles        enable row level security;

-- ---- regions：所有登录用户可读（目标列由触发器保护） ----
create policy "regions_select_auth" on public.regions
  for select to authenticated using (true);

-- ---- monthly_reports：普通用户只管自己县区；管理员全部 ----
create policy "monthly_select_own_or_admin" on public.monthly_reports
  for select to authenticated
  using (
    (select is_admin from public.profiles where id = auth.uid()) = true
    or region = (select region from public.profiles where id = auth.uid())
  );

create policy "monthly_insert_own" on public.monthly_reports
  for insert to authenticated
  with check ( region = (select region from public.profiles where id = auth.uid()) );

create policy "monthly_update_own_or_admin" on public.monthly_reports
  for update to authenticated
  using (
    (select is_admin from public.profiles where id = auth.uid()) = true
    or region = (select region from public.profiles where id = auth.uid())
  )
  with check (
    (select is_admin from public.profiles where id = auth.uid()) = true
    or region = (select region from public.profiles where id = auth.uid())
  );

-- 普通用户不可删行（不授 delete 策略）

-- ---- fill_logs：审计由触发器(security definer)写入；查询限制同月度数据 ----
create policy "fill_logs_select_own_or_admin" on public.fill_logs
  for select to authenticated
  using (
    (select is_admin from public.profiles where id = auth.uid()) = true
    or region = (select region from public.profiles where id = auth.uid())
  );

-- ---- profiles：用户可看自己 ----
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid());

-- ========== 6. 目标列保护（regions 的 target 只有管理员可改） ==========
create or replace function public.protect_region_target()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if coalesce((select is_admin from public.profiles where id = auth.uid()), false) = false then
    if new.peixun_target is distinct from old.peixun_target
       or new.jineng_target is distinct from old.jineng_target
       or new.gjg_target  is distinct from old.gjg_target then
      raise exception '非管理员不可修改目标任务';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists trg_protect_region_target on public.regions;
create trigger trg_protect_region_target before update on public.regions
  for each row execute function public.protect_region_target();

-- ========== 7. 修改审计触发器（自动写入 fill_logs） ==========
create or replace function public.record_fill_log()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  if new.peixun_c is distinct from old.peixun_c then
    insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at)
    values (new.report_month, new.region, 'peixun_c', old.peixun_c, new.peixun_c, new.updated_by, new.updated_at);
  end if;
  if new.jineng_sheng_c is distinct from old.jineng_sheng_c then
    insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at)
    values (new.report_month, new.region, 'jineng_sheng_c', old.jineng_sheng_c, new.jineng_sheng_c, new.updated_by, new.updated_at);
  end if;
  if new.jineng_shi_c is distinct from old.jineng_shi_c then
    insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at)
    values (new.report_month, new.region, 'jineng_shi_c', old.jineng_shi_c, new.jineng_shi_c, new.updated_by, new.updated_at);
  end if;
  if new.gjg_sheng_c is distinct from old.gjg_sheng_c then
    insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at)
    values (new.report_month, new.region, 'gjg_sheng_c', old.gjg_sheng_c, new.gjg_sheng_c, new.updated_by, new.updated_at);
  end if;
  if new.gjg_shi_c is distinct from old.gjg_shi_c then
    insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at)
    values (new.report_month, new.region, 'gjg_shi_c', old.gjg_shi_c, new.gjg_shi_c, new.updated_by, new.updated_at);
  end if;
  return new;
end; $$;
drop trigger if exists trg_fill_log on public.monthly_reports;
create trigger trg_fill_log after update on public.monthly_reports
  for each row execute function public.record_fill_log();

-- 首次填报某月（insert）也写入审计（old 视为 0）
create or replace function public.record_fill_log_insert()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  insert into public.fill_logs(report_month, region, field, old_value, new_value, filled_by, filled_at) values
    (new.report_month, new.region, 'peixun_c',       0, new.peixun_c,       new.updated_by, new.updated_at),
    (new.report_month, new.region, 'jineng_sheng_c', 0, new.jineng_sheng_c, new.updated_by, new.updated_at),
    (new.report_month, new.region, 'jineng_shi_c',   0, new.jineng_shi_c,   new.updated_by, new.updated_at),
    (new.report_month, new.region, 'gjg_sheng_c',    0, new.gjg_sheng_c,    new.updated_by, new.updated_at),
    (new.report_month, new.region, 'gjg_shi_c',      0, new.gjg_shi_c,      new.updated_by, new.updated_at);
  return new;
end; $$;
drop trigger if exists trg_fill_log_insert on public.monthly_reports;
create trigger trg_fill_log_insert after insert on public.monthly_reports
  for each row execute function public.record_fill_log_insert();

-- ========== 8. 预置 12 个填报单位目标（太原市为汇总，不计入） ==========
insert into public.regions (region, peixun_target, jineng_target, gjg_target) values
  ('市本级',    500,   0,   0),
  ('小店区',   2000, 1200, 600),
  ('迎泽区',   2000, 1200, 600),
  ('杏花岭区', 2000, 1500, 800),
  ('尖草坪区', 2000, 1500, 500),
  ('万柏林区', 2000, 1500, 900),
  ('晋源区',   1700, 1200, 500),
  ('清徐县',   1000,  400, 100),
  ('阳曲县',    600,  400, 100),
  ('娄烦县',    300,  200, 100),
  ('古交市',    600,  400, 100),
  ('综改区',   5300,  500, 500)
on conflict (region) do nothing;

-- ========== 9. 注册兜底建档（如仍使用注册可保留） ==========
create or replace function public.handle_new_user()
returns trigger language plpgsql
security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 完成。见 README：管理员在 Dashboard 建 12 个账号并绑定县区。
