-- ============================================================
-- 先跑這個：檢查插單的資料表是否安全
-- 伴侶會在「同一個 Supabase 專案」註冊帳號，
-- 所以插單的表必須只讓本人讀得到，否則伴侶登入後也能讀插單資料。
-- ============================================================

-- A. 沒開 RLS 的表（應該要是空的；有出現的表 = 任何人都可能讀寫）
select tablename as "沒開 RLS 的表"
from pg_tables
where schemaname = 'public' and rowsecurity = false;

-- B. 插單現有的權限政策
--    qual / with_check 裡應該要看到 auth.uid() = user_id 之類的條件。
--    如果是 true，代表「所有登入的人都能讀」，要先改。
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename not like 'lunaria_%'
order by tablename;
