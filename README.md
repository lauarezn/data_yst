# data_yst

2026 年分县区人才队伍月报 · 逐月填报系统（Supabase 版）

面向「报规统处」的逐月数据填报应用：各区县填报员按月录入「开展补贴性职业技能培训人数」「新增技能人才人数」「新增取得高级工以上证书人数」等指标，系统自动累计并生成分县区汇总表，管理员可查看当月新增表、累计表及填写审计记录。

## 文件说明

| 文件 | 说明 |
| --- | --- |
| `index.html` | 前端单页应用（纯前端 + Supabase JS SDK，无构建步骤），包含登录、填报员填报、管理员汇总三套视图 |
| `supabase_setup.sql` | Supabase 数据库初始化脚本：建表（regions / monthly_reports / fill_logs / profiles）、行级安全策略（RLS）、审计触发器、12 个县区全年目标预置 |

## 技术栈与结构

- 前端：HTML + JavaScript + Supabase JS SDK（v2）
- 后端数据库：Supabase (PostgreSQL)
- 认证：Supabase Auth，账号由管理员预设并分发给各区县，无自助注册

### 数据表

- `regions`：县区全年目标（培训 / 技能人才 / 高级工以上）
- `monthly_reports`：每县区每月一条，存当月新增的 5 个指标
- `fill_logs`：修改审计记录（每次填报/修改自动留痕）
- `profiles`：账号 ↔ 县区 / 管理员标记

### 覆盖县区（12 个 + 太原市汇总）

市本级、小店区、迎泽区、杏花岭区、尖草坪区、万柏林区、晋源区、清徐县、阳曲县、娄烦县、古交市、综改区。

## 部署步骤

1. 在 Supabase 创建项目，打开 **SQL Editor** 整段执行 `supabase_setup.sql`。
2. 在 `index.html` 顶部把 `SUPABASE_URL` 和 `SUPABASE_ANON_KEY` 替换为你的项目值：
   - Supabase 项目 → Project Settings → API → Project URL、anon public key
3. 在 Supabase Dashboard 建立 12 个账号（虚拟邮箱）并写入 `profiles`，将其绑定到各区县；管理员账号将 `is_admin` 置为 `true`。
4. 打开 `index.html` 即可使用（账号由管理员分发，无需注册）。

## 权限与审计

- 普通填报员只能填报和维护自己所在县区的数据；管理员可查看和汇总全部县区。
- 普通用户不可删除数据行。
- `regions` 的全年目标列仅管理员可修改。
- 每次数据修改均自动写入 `fill_logs` 审计表（字段、旧值 → 新值、操作人、时间）。
