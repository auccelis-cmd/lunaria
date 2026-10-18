# 月汐 Lunaria · 同步與伴侶連動版

資料放在「插單」的 Supabase 專案裡。所有資料表都以 `lunaria_` 開頭，不會動到插單原本的資料。

## 一、Supabase（約 10 分鐘）

1. **先做安全檢查**：SQL Editor → New query → 貼上 `supabase-check-capture-pad.sql` → Run
   - 第一個結果「沒開 RLS 的表」必須是空的。
   - 第二個結果裡，插單每張表的 `qual` 應該是 `(auth.uid() = user_id)` 這類條件。如果看到 `true`，先截圖給阿佩，處理好再往下做。
   - 原因：伴侶會在同一個專案註冊帳號，插單的表一定要「只有本人讀得到」。
2. **建立月汐的表**：New query → 貼上 `supabase-setup.sql` → Run（重複執行也沒關係）
3. **登入網址**：Authentication → URL Configuration → Redirect URLs → Add URL
   填 `https://auccelis-cmd.github.io/lunaria/**`（repo 名稱不同就換掉 `lunaria`）。
   不加的話，註冊確認信的連結會跳回插單。
4. **複製金鑰**：Project Settings → API，複製 Project URL 和 anon public key。

## 二、App 檔案

1. （已完成）`index.html` 已填好插單專案的網址和 publishable key。
2. 把整個資料夾的檔案上傳到 GitHub 的 `lunaria` repo → Settings → Pages 開啟。
3. iPhone 用 Safari 開網址 → 分享 → 加入主畫面。

## 三、連動伴侶

1. 你：設定 → 註冊／登入 → 填「伴侶看到的名字」→ 勾選要分享的項目 → 產生邀請碼。
2. 伴侶：用自己的手機開同一個網址、加入主畫面 → 自己註冊帳號 → 設定 → 輸入邀請碼 → 連動。
3. 伴侶的 App 會多一個「伴侶」分頁，看得到你的週期狀態和你開放的項目。

分享的項目隨時可以在設定裡改，改完伴侶重新整理就會生效。解除連動後，對方立刻看不到任何東西。

## 更新 App

改了檔案後，把 `sw.js` 第 2 行的 `lunaria-v2` 改成 v3、v4……，手機下次開啟才會換新版。
