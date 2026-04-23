-- n8n自動化フロー用のSupabaseスキーマ
-- 「リプライ → DM → 販売」を支えるテーブル群

create table if not exists processed_replies (
  id bigserial primary key,
  tweet_id text not null unique,
  processed_at timestamptz not null default now(),
  skipped_reason text
);

create index if not exists idx_processed_replies_tweet_id
  on processed_replies (tweet_id);

create table if not exists leads (
  id bigserial primary key,
  author_id text not null,
  tweet_id text not null,
  lead_score int not null default 0,
  intent text,
  stage text not null default 'dm_sent',
  -- dm_sent | purchased | churned
  source_text text,
  amount numeric(10, 2),
  followup_count int not null default 0,
  last_followup_at timestamptz,
  purchased_at timestamptz,
  created_at timestamptz not null default now(),
  unique (author_id, tweet_id)
);

create index if not exists idx_leads_author_id on leads (author_id);
create index if not exists idx_leads_stage_created on leads (stage, created_at);

create table if not exists error_log (
  id bigserial primary key,
  workflow_name text,
  node_name text,
  message text,
  stack text,
  execution_url text,
  created_at timestamptz not null default now()
);

create index if not exists idx_error_log_created on error_log (created_at desc);

create table if not exists known_followers (
  id bigserial primary key,
  follower_id text not null unique,
  username text,
  name text,
  description text,
  followers_count int,
  verified boolean default false,
  dm_sent boolean not null default false,
  skipped_reason text,
  first_seen_at timestamptz not null default now()
);

create index if not exists idx_known_followers_follower_id on known_followers (follower_id);
create index if not exists idx_known_followers_first_seen on known_followers (first_seen_at desc);
