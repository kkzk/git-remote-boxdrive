#!/bin/bash
# git-remote-boxdrive の動作テスト。Box の代わりにローカルフォルダを使う。
#   使い方: bash test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
export PATH="$HERE:$PATH"
chmod +x "$HERE/git-remote-boxdrive" "$HERE/git-remote-box"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
BOX="$T/fakebox/proj"; mkdir -p "$BOX"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL="$T/gitconfig"; : > "$GIT_CONFIG_GLOBAL"
git config --global init.defaultBranch main
git config --global core.autocrlf false
git config --global pull.rebase false

pass=0; fail=0
ok()  { echo "  PASS: $1"; pass=$((pass+1)); }
ng()  { echo "  FAIL: $1"; fail=$((fail+1)); }
expect_ok()   { local d="$1"; shift; if "$@" >"$T/out" 2>&1; then ok "$d"; else ng "$d"; sed 's/^/      /' "$T/out"; fi; }
expect_fail() { local d="$1"; shift; if "$@" >"$T/out" 2>&1; then ng "$d (成功してしまった)"; else ok "$d"; fi; }
expect_msg()  { grep -q -- "$2" "$T/out" && ok "$1" || { ng "$1"; sed 's/^/      /' "$T/out"; }; }

echo "== 1. 空の Box へ最初の push"
git init -q "$T/A"; cd "$T/A"
echo "hello" > a.txt; mkdir sub; echo "sub file" > "sub/b.txt"; echo "日本語" > "日本語 ファイル.txt"
git add -A; git commit -qm init
git remote add box "boxdrive::$BOX"
expect_ok "push main" git push box main
git remote add legacy "box::$BOX"
expect_ok "旧形式 box:: も利用できる" git fetch legacy
git remote remove legacy
[[ "$(cat "$BOX/a.txt")" == hello && -f "$BOX/sub/b.txt" && -f "$BOX/日本語 ファイル.txt" ]] && ok "Box にファイルが平文で存在" || ng "Box のファイル"
[[ -z "$(cd "$BOX" && find . -name '*boxgit-tmp*')" ]] && ok "一時ファイルが残っていない" || ng "一時ファイル残存"
[[ ! -e "$BOX/.git" ]] && ok "Box に .git が無い" || ng ".git が Box にある"

echo "== 2. 別の人が clone"
cd "$T"; expect_ok "clone" git clone -q "boxdrive::$BOX" B
cd "$T/B"
[[ "$(cat a.txt)" == hello ]] && ok "clone 内容一致" || ng "clone 内容"
git config user.name B; git config user.email b@b

echo "== 3. 通常の更新 (B が push)"
echo "from B" >> a.txt; git commit -qam "B edit"
expect_ok "B push" git push origin main
grep -q "from B" "$BOX/a.txt" && ok "Box に反映" || ng "Box に反映されていない"

echo "== 4. A は古い基準 → Box が更新済みなので push 失敗"
cd "$T/A"; echo "from A" > c.txt; git add c.txt; git commit -qm "A add c"
expect_fail "A push が拒否される" git push box main
expect_msg "拒否理由が出る" "non-fast-forward\|fetch first"
[[ ! -e "$BOX/c.txt" ]] && ok "Box は変更されていない" || ng "拒否されたのに Box が変わった"

echo "== 5. A が pull してマージ → push 成功"
expect_ok "A pull (3-way merge)" git pull -q box main --no-edit
expect_ok "A push (再)" git push box main
[[ -f "$BOX/c.txt" ]] && grep -q "from B" "$BOX/a.txt" && ok "Box に両方の変更" || ng "Box の内容"

echo "== 6. 管理者が Box を直接編集 (git を使わない人)"
echo "admin edit" >> "$BOX/sub/b.txt"
echo "new by admin" > "$BOX/admin.txt"
cd "$T/A"; echo "x" >> c.txt; git commit -qam "A edit c"
expect_fail "A push が拒否される (Box 側が新しい)" git push box main
expect_ok "A pull" git pull -q box main --no-edit
grep -q "admin edit" sub/b.txt && [[ -f admin.txt ]] && ok "管理者の変更が手元に来た" || ng "管理者の変更が取り込めていない"
expect_ok "A push" git push box main

echo "== 7. 削除の反映"
cd "$T/A"; git rm -q c.txt; git commit -qm "rm c"
expect_ok "削除 push" git push box main
[[ ! -e "$BOX/c.txt" ]] && ok "Box から削除された" || ng "Box に残っている"
echo "管理者がファイルを消した:"; rm "$BOX/admin.txt"
cd "$T/B"; expect_ok "B pull" git pull -q origin main --no-edit
[[ ! -e admin.txt ]] && ok "管理者の削除が手元にも反映" || ng "削除が反映されない"

echo "== 8. 変更なしの再 push / fetch"
cd "$T/A"; expect_fail "A は管理者の削除を未取得なので push 拒否" git push box main
expect_ok "A pull" git pull -q box main --no-edit
expect_ok "pull 後の push" git push box main
expect_ok "変更なしの再 push" git push box main
expect_ok "fetch" git fetch box

echo "== 9. 除外ファイル"
touch "$BOX/.DS_Store" "$BOX/Thumbs.db" "$BOX/~\$tmp.docx"
cd "$T/A"; expect_ok "fetch" git fetch box
git ls-tree -r --name-only box/main 2>/dev/null | grep -q 'DS_Store\|Thumbs\|~\$' && ng "除外ファイルが取り込まれた" || ok "除外ファイルは無視"

echo "== 10. 強制 push は Box の変更を上書きできない"
echo "admin2" > "$BOX/admin2.txt"
cd "$T/A"; echo y >> a.txt; git commit -qam "A edit a"
expect_fail "通常 push は拒否" git push box main
expect_fail "force push は拒否" git push -f box main
expect_msg "強制 push の拒否理由が出る" "強制 push"
expect_fail "明示的な強制 refspec は拒否" git push box +main:main
[[ "$(cat "$BOX/admin2.txt")" == admin2 ]] && ok "Box のファイルが残っている" || ng "Box のファイルが変更された"
expect_ok "Box の状態を fetch" git fetch -q box
expect_fail "履歴を上書きする force-with-lease は拒否" git push --force-with-lease box main
expect_msg "force-with-lease の拒否理由が出る" "non-fast-forward\|強制 push"
[[ "$(cat "$BOX/admin2.txt")" == admin2 ]] && ok "force-with-lease でもファイルを保持" || ng "Box のファイルが変更された"
expect_ok "A pull" git pull -q box main --no-edit
expect_fail "pull 後も force push は拒否" git push -f box main
expect_msg "pull 後も強制 push の拒否理由が出る" "強制 push"
expect_ok "pull 後の通常 push" git push box main
[[ "$(cat "$BOX/admin2.txt")" == admin2 ]] && ok "管理者のファイルを保持" || ng "管理者のファイルが失われた"

echo "== 11. 空フォルダ・main 以外の push 先"
cd "$T/A"; git checkout -qb feat; echo f > f.txt; git add f.txt; git commit -qm f
expect_fail "feat ブランチ push は拒否" git push box feat
expect_ok "feat:main は OK (pull 済みなら)" bash -c "git fetch -q box && git merge -q --no-edit box/main; git push box feat:main"

echo
echo "結果: PASS=$pass FAIL=$fail"
[[ $fail -eq 0 ]]
