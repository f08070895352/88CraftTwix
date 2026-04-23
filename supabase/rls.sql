-- Row Level Security と役割分離
-- 目的:
-- 1) Supabase Service Role Key が万一n8n外で漏れても、テーブル単位での被害を最小化する
-- 2) 書き込みはサーバサイド(n8n)のみ。人間向けの読み取りは Anon Key + ポリシー経由
--
-- 適用: psql "$SUPABASE_DB_URL" -f supabase/rls.sql
-- ※ schema.sql を流した後に実行してください

-- ==============================================================
-- n8n 専用ロール: anon と service_role の中間。書込み可・読取り可。
-- n8n の Supabase Credential にはこのロールの JWT を設定する。
-- ==============================================================
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'n8n_writer') then
    create role n8n_writer noinherit login password :'n8n_writer_password';
  end if;
end$$;

grant usage on schema public to n8n_writer;
grant select, insert, update on all tables in schema public to n8n_writer;
grant usage, select on all sequences in schema public to n8n_writer;
alter default privileges in schema public
  grant select, insert, update on tables to n8n_writer;

-- ==============================================================
-- RLS 有効化
-- ==============================================================
alter table processed_replies enable row level security;
alter table leads             enable row level security;
alter table error_log         enable row level security;
alter table known_followers   enable row level security;

-- ==============================================================
-- ポリシー
-- ==============================================================

-- n8n_writer はすべての行を読み書きできる
create policy n8n_writer_all_processed on processed_replies
  for all to n8n_writer using (true) with check (true);

create policy n8n_writer_all_leads on leads
  for all to n8n_writer using (true) with check (true);

create policy n8n_writer_all_errors on error_log
  for all to n8n_writer using (true) with check (true);

create policy n8n_writer_all_followers on known_followers
  for all to n8n_writer using (true) with check (true);

-- anon は何も読めない（ダッシュボード等では authenticated を使う前提）
-- authenticated は読み取りのみ。書込みは n8n_writer 経由。
create policy authenticated_read_leads on leads
  for select to authenticated using (true);

create policy authenticated_read_errors on error_log
  for select to authenticated using (true);

create policy authenticated_read_followers on known_followers
  for select to authenticated using (true);

-- processed_replies は運用ログなので誰にも公開しない
-- (n8n_writer のみアクセス可)

-- service_role は RLS をバイパスするのでポリシー不要
-- → service_role key は Stripe Webhookの署名検証Code内など、
--   n8n_writer では権限不足になるバッチ処理にだけ使う。
