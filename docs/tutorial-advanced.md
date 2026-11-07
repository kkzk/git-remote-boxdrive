# チュートリアル 2: 複数の Box フォルダを submodule で束ね、AI に資料を更新させる

複数の Box フォルダを 1 つの作業場にまとめ、

- 参照用のフォルダ（仕様書・議事録など）は **読むだけ**
- 更新対象のフォルダ（提案書など）は **AI（Claude Code）が編集・コミットまで行い、Box への反映（push）だけは人間が承認する**

という運用を組み立てます。[チュートリアル 1](tutorial-basic.md) の内容（clone / pull / push の基本）を理解している前提です。

---

## 全体像

```text
C:\Users\you\work\A社案件\          ← 親リポジトリ（作業場。必ず Box の外に作る）
├── CLAUDE.md                        ← AI への作業ルール
├── .claude\settings.json            ← AI の権限設定（push は人間の承認が必要）
├── ref\                             ← 参照専用（AI も人間も編集しない）
│   ├── 仕様書\   ⇔ boxdrive::C:/Users/you/Box/A社/仕様書
│   └── 議事録\   ⇔ boxdrive::C:/Users/you/Box/A社/議事録
└── out\                             ← 更新対象
    └── 提案書\   ⇔ boxdrive::C:/Users/you/Box/営業資料/A社提案書
```

`ref\` `out\` の下はそれぞれ独立した git リポジトリ（submodule）で、各 Box フォルダとつながっています。親リポジトリは「どの版の参照資料をもとに、どの版の提案書を作ったか」の組み合わせを記録します。

1 回の更新サイクルと、各ステップの担当は次のとおりです。

| # | ステップ | 担当 | 承認 |
|---|---|---|---|
| 1 | 全 Box フォルダの最新を取り込む | AI | 不要 |
| 2 | 参照資料を読み、提案書を編集してコミット | AI | 不要 |
| 3 | 変更内容をレビュー | **人間** | — |
| 4 | Box へ push | AI が実行を提案 | **人間が承認** |
| 5 | 親リポジトリに組み合わせを記録 | AI | 不要 |

Box に書き込まれるのはステップ 4 だけなので、そこを人間の承認制にすれば「AI が勝手に共有資料を書き換える」ことは起きません。また git-remote-boxdrive の性質上、Box 側が誰かに更新されていれば push は失敗するので、AI が他人の更新を上書きすることもありません。

---

## 1. 準備: submodule で boxdrive を使えるようにする

git は安全のため、submodule 経由では未知の通信方式を使わせません。そのままだと次のエラーになります。

```
fatal: transport 'boxdrive' not allowed
```

一度だけ、次の設定をしてください。

```bash
git config --global protocol.boxdrive.allow always
```

## 2. 作業場（親リポジトリ）を作る

```bash
mkdir -p ~/work/A社案件 && cd ~/work/A社案件
git init

# 参照用
git submodule add -b main "boxdrive::C:/Users/you/Box/A社/仕様書" ref/仕様書
git submodule add -b main "boxdrive::C:/Users/you/Box/A社/議事録" ref/議事録
# 更新対象
git submodule add -b main "boxdrive::C:/Users/you/Box/営業資料/A社提案書" out/提案書

git commit -m "作業場を作成"
```

`-b main` を付けると、各 submodule が `main` ブランチの状態で取り出されます（付けないと「ブランチ無し（detached HEAD）」になり、コミットしても push しにくくなります）。

### 参照用フォルダを誤って push できないようにする

参照用の submodule は、push 先を存在しない値にしておきます。誤って push しても失敗するだけになります。

```bash
git -C ref/仕様書 remote set-url --push origin 参照専用-push禁止
git -C ref/議事録 remote set-url --push origin 参照専用-push禁止
```

```bash
git -C ref/仕様書 remote -v
# origin  boxdrive::C:/Users/you/Box/A社/仕様書 (fetch)
# origin  参照専用-push禁止 (push)
```

> この設定は各 submodule の手元設定（`.git/modules/...`）に保存され、親リポジトリには記録されません。別の PC で作業場を作ったときは再設定が必要です（[8.](#8-別の-pc-やほかのメンバーが作業場を作るとき) 参照）。

## 3. AI への作業ルールを書く（CLAUDE.md）

作業場の直下に `CLAUDE.md` を作ります。Claude Code は起動時にこれを読み、ルールに従って作業します。

````markdown
# A社案件 作業ルール

## フォルダの役割
- `ref/` 以下は参照専用。読むだけで、編集・コミット・push は絶対にしない
- `out/提案書/` が更新対象。ここだけを編集する
- 各フォルダは Box Drive と git-remote-boxdrive でつながった submodule である
- Box Drive のフォルダ（`C:/Users/you/Box/` 以下）を直接読み書きしない。必ず git を経由する

## 作業の手順
1. 作業前に `git submodule update --remote --merge` で全フォルダを最新にする
2. `out/提案書/` を編集したら、そのフォルダでコミットする
   （`git -C out/提案書 add -A && git -C out/提案書 commit -m "..."`）
   コミットメッセージは日本語で、何をなぜ変えたかを書く。根拠にした参照資料のファイル名も書く
3. コミットしたら、push する前に必ず作業を止めて、次をまとめて報告する
   - 変更したファイルと変更の要約
   - `git -C out/提案書 diff --stat origin/main` の結果
   - 根拠にした参照資料
4. 人間が承認したら `git -C out/提案書 push origin main` で反映する
5. push が `fetch first` / `non-fast-forward` で拒否されたら、
   `git -C out/提案書 pull origin main` で取り込み、競合があれば解決してから、
   **もう一度 3. の報告からやり直す**（取り込んだ内容も含めて再承認が必要）
6. push に成功したら、親リポジトリで `git add ref out && git commit -m "..."` を行い、
   どの版の参照資料をもとに更新したかを記録する

## 禁止事項
- 強制 push（`-f`, `--force`, `+main`）
- `ref/` 以下の変更
- 人間の承認なしの push
````

## 4. AI の権限を設定する（.claude/settings.json）

CLAUDE.md は「お願い」なので、守られない可能性をゼロにはできません。Claude Code の権限設定で、仕組みとしても縛っておきます。

作業場の直下に `.claude/settings.json` を作ります（`you` は自分のユーザー名に置き換え）。

```json
{
  "permissions": {
    "allow": [
      "Bash(git submodule update --remote --merge)",
      "Bash(git submodule status)",
      "Bash(git status *)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git -C out/提案書 status *)",
      "Bash(git -C out/提案書 diff *)",
      "Bash(git -C out/提案書 log *)",
      "Bash(git -C out/提案書 add *)",
      "Bash(git -C out/提案書 commit *)",
      "Bash(git -C out/提案書 pull origin main)",
      "Edit(/out/提案書/**)"
    ],
    "ask": [
      "Bash(git push)",
      "Bash(git push *)",
      "Bash(git -C * push)",
      "Bash(git -C * push *)",
      "Bash(git submodule foreach *)"
    ],
    "deny": [
      "Bash(git push -f*)",
      "Bash(git push --force*)",
      "Bash(git -C * push -f*)",
      "Bash(git -C * push --force*)",
      "Edit(/ref/**)",
      "Edit(//c/Users/you/Box/**)"
    ]
  }
}
```

ポイント:

- **`ask`** に入れたコマンド（push 系）は、AI が実行しようとするたびに承認ダイアログが出ます。`ask` は `allow` より優先されるので、ダイアログで「今後は確認しない」系を選んでも、このファイルの `ask` がある限り毎回確認されます
- **`deny`** で、強制 push・参照フォルダの編集・Box フォルダの直接編集を禁止します。`Edit(...)` のルールはファイルを書き換えるツール全般に効きます
- Windows のパスは `C:\Users\you\Box` → `//c/Users/you/Box` のように書きます（先頭の `//` は「ドライブからの絶対パス」の意味）
- Windows 版 Claude Code で PowerShell ツールも使われる環境では、同じルールを `PowerShell(...)` でも追加してください
- 設定後、Claude Code の中で `/permissions` を実行すると、ルールが読み込まれているか確認できます

> **注意:** 権限ルールはコマンドの文字列で判定するため、完全なサンドボックスではありません（たとえば別の書き方のコマンドで Box フォルダに書き込むことは理論上可能です）。また、`--dangerously-skip-permissions`（全許可モード）で起動すると承認ダイアログが出なくなるので、この運用では **使わないでください**。

### より厳しくしたい場合: push を人間が自分で打つ

AI に push を一切させたくない場合は、push 系を `ask` から `deny` に移します。

```json
    "deny": [
      "Bash(git push)",
      "Bash(git push *)",
      "Bash(git -C * push)",
      "Bash(git -C * push *)",
      ...
    ]
```

この場合、レビュー後に人間が Claude Code のプロンプトで先頭に `!` を付けて実行します（`!` で始めた行は AI を介さずにそのまま実行されます）。

```text
! git -C out/提案書 push origin main
```

## 5. 運用サイクル

Claude Code を作業場で起動します。

```bash
cd ~/work/A社案件
claude
```

### ステップ 1〜2: AI に依頼する

依頼例:

```text
議事録の最新回（11/5 定例）で決まった仕様変更を、提案書の「3. システム構成」と
「5. 見積」に反映してください。仕様の根拠は ref/仕様書 を見てください。
```

AI は CLAUDE.md に従って、

1. `git submodule update --remote --merge` で全フォルダを最新化
2. `ref/議事録` `ref/仕様書` を読み、`out/提案書` を編集
3. `out/提案書` でコミット

まで進め、push の前に止まって変更内容を報告します。

### ステップ 3: 人間がレビューする

AI の報告を読んだうえで、必要なら自分でも差分を確認します。Claude Code のプロンプトから `!` 付きで実行するか、別の Git Bash で実行します。

```bash
git -C out/提案書 log --oneline origin/main..HEAD   # まだ Box に出していないコミット
git -C out/提案書 diff origin/main                  # Box の現状との差分（テキストファイル）
git -C out/提案書 diff --stat origin/main           # 変更ファイルの一覧
```

Word ファイル（`.docx`）の場合、`git diff` では中身が読めません。Box 上の現状を別名で取り出し、Word の「校閲 → 比較」で見比べるとレビューしやすくなります。

```bash
git -C out/提案書 show origin/main:提案書.docx > ~/Desktop/提案書_Box現状.docx
```

> AI に編集させる資料は、できれば Markdown（`.md`）などのテキスト形式にしておくと、AI の編集精度が上がり、`git diff` でのレビューも格段に楽になります。

修正してほしい点があれば、そのまま AI に伝えて追加のコミットをさせます。
今回の変更自体を取りやめる場合は、Box の現状に戻します（未 push のコミットは消えます）。

```bash
git -C out/提案書 reset --hard origin/main
```

### ステップ 4: 承認して push

問題なければ AI に「承認します。push してください」と伝えます。AI が `git -C out/提案書 push origin main` を実行しようとすると、Claude Code の承認ダイアログが出るので、コマンドが想定どおり（対象が `out/提案書`、強制 push でない）であることを確認して許可します。

```
git-remote-boxdrive: 反映完了: 書き込み 2 / 削除 0
To boxdrive::C:/Users/you/Box/営業資料/A社提案書
   0c5e64d..42f98a2  main -> main
```

**レビュー中に同僚が Box の提案書を更新していた場合**、push は `fetch first` または `non-fast-forward` で失敗し、Box は変更されません。AI は CLAUDE.md に従って取り込み・競合解決を行い、改めて報告してくるので、取り込んだ内容も含めてもう一度レビュー・承認します。

### ステップ 5: 組み合わせを記録する

push が終わると、親リポジトリでは submodule の版が進んだことが変更として見えます。

```bash
git diff --submodule=log
# Submodule out/提案書 0c5e64d..42f98a2:
#   > 11/5 定例の仕様変更を構成図・見積に反映
# Submodule ref/議事録 7a8b9c0..1d2e3f4:
#   > Box snapshot: /c/Users/you/Box/A社/議事録
```

AI がこれをコミットします（手動なら `git add ref out && git commit -m "..."`）。
これで「11/5 版の議事録をもとに、提案書のこの版を作った」という対応が親リポジトリの履歴に残ります。

## 6. 状況をまとめて確認するコマンド

```bash
# 各フォルダの「まだ Box に出していないコミット」の数
git submodule foreach -q 'printf "%s: 未反映 %s 件\n" "$sm_path" "$(git rev-list --count origin/main..HEAD)"'

# 各フォルダの現在の版
git submodule status
```

よく使うものは alias にしておくと便利です。

```bash
git config alias.box-sync '!git submodule update --remote --merge'
git box-sync     # 全フォルダを最新化
```

## 7. 参照フォルダ・更新対象を増やす

更新対象を増やす場合は、`git submodule add -b main ... out/<名前>` で追加し、CLAUDE.md と `.claude/settings.json` の `out/提案書` に関する記述を追加・一般化してください（例: `Edit(/out/**)`）。

参照フォルダを増やす場合は `ref/<名前>` に追加し、[2.](#参照用フォルダを誤って-push-できないようにする) の push 禁止設定も忘れずに行います。

## 8. 別の PC やほかのメンバーが作業場を作るとき

Box 上には履歴が無いため、Box の変更を表す「Box snapshot」コミットは **各 PC で別々に作られます**（同じ内容でもコミット ID が一致しません）。そのため、親リポジトリを別の PC にコピーして普通に `git submodule update --init` すると、記録された版が見つからず失敗します。

```
fatal: Fetched in submodule path 'ref/仕様書', but it did not contain 250f919....
```

別の PC では、記録された版ではなく **Box の最新** を取り出すようにします。

```bash
git clone <親リポジトリの置き場所> A社案件 && cd A社案件
git config --global protocol.boxdrive.allow always

# Box Drive のパスが自分の PC と違う（ユーザー名が違う）場合は、先に URL を書き換える
git submodule init
git config submodule.ref/仕様書.url   "boxdrive::C:/Users/<自分>/Box/A社/仕様書"
git config submodule.ref/議事録.url   "boxdrive::C:/Users/<自分>/Box/A社/議事録"
git config submodule.out/提案書.url   "boxdrive::C:/Users/<自分>/Box/営業資料/A社提案書"

git submodule update --init --remote             # Box の最新を取り出す
git submodule foreach -q 'git switch -q main'    # ブランチ無しの状態を main に切り替える

git -C ref/仕様書 remote set-url --push origin 参照専用-push禁止
git -C ref/議事録 remote set-url --push origin 参照専用-push禁止
```

`.claude/settings.json` の Box パス（`//c/Users/you/Box/**`）も、自分のユーザー名に合わせて書き換えてください。個人ごとに違う設定は `.claude/settings.local.json` に書くと、親リポジトリで共有する設定と分けられます。

> 親リポジトリの履歴に残る submodule の版（コミット ID）は、**その PC の中でだけ意味を持つ** 記録です。複数人で親リポジトリを共有する場合、共有されるのは CLAUDE.md・権限設定・フォルダ構成（`.gitmodules`）だと考えてください。資料そのものの正本は常に Box 側です。

## 9. 注意点のまとめ

- 作業場（親リポジトリ）は **Box の外** に作る。Box の中に作ると `.git` が同期されてしまう
- submodule で使うには `protocol.boxdrive.allow always` が必要
- 承認ダイアログはコマンドをよく見てから許可する。全許可モードでは起動しない
- `git submodule update --remote --merge` は、submodule に未コミットの変更があると失敗することがある。先にコミットするか、取り消してから実行する
- Box への反映は push した時点で即座に行われ、Box Drive を通じてすぐに共有される。取り消したい場合は「元に戻すコミット」を作って再度 push する（[チュートリアル 1 の 5.](tutorial-basic.md#5-過去の版を見る戻す)）
- そのほかの制限（同時 push の競合、無視されるファイル、改行コードなど）は [README の「既知の制限」](../README.md#既知の制限) を参照
