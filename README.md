# git-remote-boxdrive

Box Drive（などの同期フォルダ）を **ただのファイルツリー** として git のリモートにする remote helper。
依存は Git for Windows（git + 同梱 bash）のみ。Box CLI・API トークン・追加インストールは不要。

- Box 側には普通のファイルだけが置かれる（`.git` もバンドルも無い）→ Box（Web）しか見ない管理者にもそのまま見える
- 履歴は手元の git だけが持つ
- **Box 側が、手元の基準（最後に pull/push した状態）より更新されていたら push を失敗させる**

## チュートリアル

- [チュートリアル 1: Box Drive の資料を git で更新する（日常の使い方）](docs/tutorial-basic.md)
  — 1 つの Box フォルダを相手に、取り込み・編集・反映・競合解決・過去の版への復元を行う流れ
- [チュートリアル 2: 複数の Box フォルダを submodule で束ね、AI に資料を更新させる](docs/tutorial-advanced.md)
  — 参照用／更新対象の Box フォルダを submodule で管理し、AI（Claude Code）が編集、Box への反映だけ人間が承認する運用

## 導入

### かんたんな方法（おすすめ）

1. [Git for Windows](https://gitforwindows.org/) をインストールしておく（インストール済みなら不要）
2. このフォルダ（ZIP の場合はすべて展開したもの）の **`install.cmd` をダブルクリック**
   - 「Windows によって PC が保護されました」と出たら「詳細情報」→「実行」
   - 管理者権限は不要。最後に「動作確認 OK」と出れば完了
3. 開いていた Git を使うアプリ（コマンドプロンプト、VS Code など）を開き直す

新しい版に更新するときも、同じく `install.cmd` をダブルクリックするだけ。
やめるときは `uninstall.cmd` をダブルクリック。

`install.cmd` は `%LOCALAPPDATA%\Programs\git-remote-boxdrive` にファイルをコピーし、そのフォルダをユーザー環境変数 `Path` に1行追加する（既存の内容は変えない）。

会社の PC などで、バッチファイルや PowerShell の実行が禁止されていると、`install.cmd` は途中で失敗する。その場合は下の「手動で入れる場合」の手順で入れるか、PC の管理者に相談する。

### 手動で入れる場合

コマンドを使わず、エクスプローラーと Windows の設定画面だけで入れられる。

1. エクスプローラーのアドレスバーに `%LOCALAPPDATA%\Programs` と入力して Enter し、`git-remote-boxdrive` というフォルダを作る
2. そのフォルダに `git-remote-boxdrive` ファイルをコピーする（改行コードは LF のまま！）
3. スタートメニューで「環境変数」と検索し、「環境変数を編集」を開く
4. 上側の「ユーザー環境変数」の `Path` を選んで「編集」→「新規」で次を入力し、すべて「OK」で閉じる
   ```text
   %LOCALAPPDATA%\Programs\git-remote-boxdrive
   ```
   （既存の行は消さない。`Path` が無い場合は「新規」で変数名 `Path` として作る）
5. Git を使うアプリを開き直す

Git Bash に慣れていれば、`~/bin` などに置いて PATH に追加してもよい（`~/bin` は既定では PATH に入っていない）。

### リモートを追加する

Box Drive のフォルダを指すリモートを追加する。

```bash
git remote add box boxdrive::/c/Users/me/Box/project     # Git Bash 形式
git remote add box boxdrive::C:/Users/me/Box/project     # Windows 形式でも可
# 既存の Box フォルダから始めるなら
git clone boxdrive::/c/Users/me/Box/project work
```

## 使い方

```bash
git pull box main        # Box の変更を取り込む（3-way マージされる）
git push box main        # 手元の変更を Box に反映
git push box HEAD:main   # ローカルブランチ名が main 以外のとき
```

Box 上の「ブランチ」は `main` ひとつだけ（`BOX_BRANCH` 環境変数で名前変更可）。
強制 push による上書きはできない。Git が更新不要と判断した場合や、`--force-with-lease` を指定しても通常の更新として扱う場合は、エラーにならないことがある。なお、通常の push でも、コミット済みの削除は Box 側に反映される。

### push が失敗するとき

```
! [remote rejected] main -> main (fetch first: Box 側が更新されています。git pull してから再度 push してください)
```

`git pull box main` → 競合を解決 → もう一度 `git push box main`。

### すでに手元にあるリポジトリに Box の既存ファイルがある場合

最初の pull だけ履歴が無関係と判定されるため `git pull box main --allow-unrelated-histories` が必要。

## 複数の Box フォルダをサブモジュールとして参照する

作業用のフォルダをローカルの git リポジトリにして、参照したい Box フォルダをそれぞれサブモジュールとして取り込める。親リポジトリの履歴に「いつ、どの Box の状態を見ていたか」が残る。

```bash
# 最初に一度だけ（git はサブモジュールで未知のプロトコルを既定で拒否する）
git config --global protocol.boxdrive.allow always

git init work && cd work
git submodule add -b main boxdrive::C:/Users/me/Box/仕様書 ref/spec
git submodule add -b main boxdrive::C:/Users/me/Box/議事録 ref/minutes
git commit -m "参照する Box フォルダを追加"
```

`protocol.boxdrive.allow` を設定していないと `fatal: transport 'boxdrive' not allowed` で失敗する。

### Box の最新を取り込む

```bash
git submodule update --remote          # すべての Box を最新に
git commit -am "参照中の Box を更新"     # 取り込んだ状態を親に記録（任意）
```

### サブモジュールで編集して Box に書き戻す

`git submodule update` の後のサブモジュールは、どのブランチにもいない状態（detached HEAD）になっている。編集する前に `main` に切り替える。

```bash
cd ref/spec
git switch main
git pull
# 編集して commit
git push origin main
cd ../.. && git commit -am "ref/spec を更新"
```

### 注意点

- **親を別の場所に clone したら、必ず `--remote` を付ける。** Box 側には履歴が無く、Box の状態を表す合成コミットは clone ごとに作られる。そのため、親に記録されたコミットは他の clone からは取得できない。
  ```bash
  git clone <親リポジトリ> work2 && cd work2
  git submodule update --init --remote
  ```
  `--remote` なしで実行すると `did not contain <sha>` で失敗する。その場合は `git submodule update --init --remote --force` で復旧できる。
- **親リポジトリ自体は boxdrive で Box に push できない。** サブモジュールはファイルとして表現できないため。親を共有・バックアップするなら、通常の git リモートを使う。
- `.gitmodules` には自分の Box Drive のパス（ユーザー名を含む）がそのまま入る。他の人と親を共有する場合は、各自 `git config submodule.<名前>.url boxdrive::<自分のパス>` で上書きしてもらう。
- サブモジュールごとに list のたびに Box フォルダ全体を読むため、大きなフォルダを多数つなぐと `update --remote` が遅くなる。

## 関連する先行事例

[git-annex の Box.com 向けガイド](https://git-annex.branchable.com/tips/using_box.com_as_a_special_remote/)には、Box を WebDAV 経由の special remote として使う例がある。また、[git-remote-annex](https://git-annex.branchable.com/git-remote-annex/)を使うと、git-annex の special remote に保存した Git リポジトリを `annex::` URL で clone/pull/push できる。

ただし、これは git-annex が管理するデータ／リポジトリを Box に保存する方式で、Box Drive の同期フォルダを直接ファイルツリーとして使う本ツールとは仕組みが異なる。Box.com 向けガイドは WebDAV を使う古い手順なので、現行環境で利用できるかは Box の対応状況を確認すること。

## 仕組み（要点）

| 操作 | 内容 |
|---|---|
| list/fetch | Box フォルダ全体を tree 化し、前回把握した状態と比較。違えば「Box の変更を表す合成コミット（親＝前回状態）」を作ってリモート先頭として返す。`.git/refs/box-state/*` に保存 |
| push | ① Box の現在状態が前回状態と一致するか → 不一致なら失敗 ② 通常の non-fast-forward 判定 ③ 差分ファイルのみ書き込み（一時ファイル→rename） ④ 書き込み後に再スナップショットして検証 |

比較は更新日時ではなく **内容ハッシュ** なので、Box Drive の同期で日時がずれても誤判定しない。

## 既知の制限

- **排他制御なし**: Box には CAS が無いので、ほぼ同時の push は競合しうる（push 後の検証で検知を試みる）。少人数の共有・引き継ぎ向け。
- **ブランチ・タグは Box 側に無い**（`main` 1本のみ）。ブランチ削除も非対応。
- **改行コード**: ファイルは無変換のバイト列で比較・保存する。Windows の `core.autocrlf=true` でも動くが、Box 側を CRLF のエディタで編集されると全行差分になることがある。チームで `.gitattributes`（`* text=auto eol=lf` など）を揃えるのを推奨。
- **無視されるファイル**: `.DS_Store` `desktop.ini` `Thumbs.db` `~$*` `*.boxgit-tmp.*` `.git/`
- 実行権限・シンボリックリンク・空フォルダは保持しない。ファイル名に改行を含むものは無視。
- Box Drive の未ダウンロード（オンデマンド）ファイルは読み込みが遅い／失敗することがある。その場合は少し待って再実行。
- 大規模リポジトリ（数万ファイル）では list のたびに全走査するため遅い。

## テスト

```bash
bash test.sh    # Box の代わりにローカルフォルダで検証
```
