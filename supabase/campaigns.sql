-- 施策ごとの成果を横断集計するための共通スキーマ
-- 「リプ→DM→販売」とは別に、キャンペーン単位のファネルを記録する
-- psql "$SUPABASE_DB_URL" -f supabase/campaigns.sql

create table if not exists campaigns (
  id text primary key,
  -- 'a_rt_lottery_20260501' のように人間が読める ID
  category text not null check (category in ('A','B','C','D')),
  type text not null,
  -- A: follow_rt | lottery | pinned | quote_rt | comment
  -- B: thread | lead_magnet | knowledge | before_after
  -- C: reply_to_dm | auto_dm | limited_offer | line
  -- D: poll | opinion | edgy | trend
  title text,
  target_tweet_id text,
  starts_at timestamptz,
  ends_at timestamptz,
  config jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  -- active | paused | ended
  created_at timestamptz not null default now()
);

create index if not exists idx_campaigns_status_category
  on campaigns (status, category);

-- 参加者の重複排除用（RT参加者・引用RT参加者・コメント参加者など）
create table if not exists campaign_entries (
  id bigserial primary key,
  campaign_id text not null references campaigns (id) on delete cascade,
  author_id text not null,
  username text,
  source_type text not null,
  -- rt | quote | reply | follow | dm_keyword
  source_tweet_id text,
  entered_at timestamptz not null default now(),
  unique (campaign_id, author_id, source_type)
);

create index if not exists idx_entries_campaign
  on campaign_entries (campaign_id);

-- KPI計測イベント（impressions, saves, clicks, dm_sent, conversion など何でも）
create table if not exists campaign_events (
  id bigserial primary key,
  campaign_id text not null references campaigns (id) on delete cascade,
  event text not null,
  -- impression | profile_click | link_click | save | reply | rt | quote |
  -- follow | dm_sent | dm_opened | cv | revenue
  actor_id text,
  value numeric default 1,
  meta jsonb default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_events_campaign_event
  on campaign_events (campaign_id, event, occurred_at desc);

-- 成約記録（販売・LINE追加・メルマガ登録など）
create table if not exists campaign_conversions (
  id bigserial primary key,
  campaign_id text not null references campaigns (id) on delete cascade,
  author_id text,
  cv_type text not null,
  -- purchase | line_add | email_opt_in | lead_magnet_dl
  amount numeric,
  external_id text,
  -- Stripe session id, LINE user id, etc
  occurred_at timestamptz not null default now()
);

create index if not exists idx_cv_campaign_type
  on campaign_conversions (campaign_id, cv_type);
