# チュートリアル 1: Box Drive の資料を git で更新する（日常の使い方）

Box Drive 上のひとつのフォルダ（例: 営業部の提案書フォルダ）を、git で履歴を取りながら更新する流れを、最初の準備から順に説明します。

想定する状況:

- Box 上に `営業資料/提案書` フォルダがあり、チームで共有している
- 自分は git で編集履歴を残したい。ほかのメンバーや管理者は git を使わず、Box（Web やエクスプローラー）で直接ファイルを触ることもある

以下のコマンドはすべて **Git Bash** で実行します（スタートメニューの「Git Bash」）。

---

## 0. 準備

1. [README の「導入」](../README.md#導入) に従って `git-remote-boxdrive` をインストールしておく
2. Box Drive が起動していて、エクスプローラーで Box のフォルダが見えることを確認する
3. git を初めて使う場合は、名前とメールアドレスを登録する（コミットの作者として記録されます）

   ```bash
   git config --global user.name  "山田 太郎"
   git config --global user.email "taro.yamada@example.com"
   ```

Box フォルダの場所は、エクスプローラーで対象フォルダを開き、アドレスバーをクリックすると確認できます。
以降の例では `C:\Users\you\Box\営業資料\提案書` とします。git では `\` を `/` に置き換えて `C:/Users/you/Box/営業資料/提案書` と書きます。

## 1. 作業用フォルダを作る（最初の 1 回だけ）

> **重要:** 作業用フォルダは **Box の外** に作ってください（例: `C:\Users\you\work`）。
> Box の中に作ると、`.git` フォルダまで Box に同期されてしまい、本ツールを使う意味がなくなります。

```bash
mkdir -p ~/work && cd ~/work
git clone "boxdrive::C:/Users/you/Box/営業資料/提案書" 提案書
cd 提案書
```

これで `~/work/提案書`（= `C:\Users\you\work\提案書`）に Box と同じファイルが取り出され、git の管理下になります。
`clone` で作ったリポジトリでは、Box は `origin` という名前で登録されているので、以降は `git pull` / `git push` だけで操作できます。

```bash
git log --oneline
# a1b2c3d Box snapshot: /c/Users/you/Box/営業資料/提案書
```

最初の履歴は「Box snapshot」という名前のコミットです。これは「clone した時点の Box の中身」を表します（作者は `box`）。

### （おすすめ）改行コードをそろえる

テキストファイル（`.md` `.txt` `.csv` など）を扱う場合は、改行コードの違いで全行が変更扱いになるのを防ぐため、`.gitattributes` を置いておくと安全です。

```bash
echo '* text=auto eol=lf' > .gitattributes
git add .gitattributes
git commit -m "改行コードの設定を追加"
git push
```

> `.gitattributes` も普通のファイルとして Box に置かれます。Box に余計なファイルを置きたくない場合は、代わりに `.git/info/attributes` に同じ内容を書いてください（手元だけの設定になります）。

Word / Excel / PowerPoint などのファイルしか扱わない場合、この設定は不要です。

## 2. 毎日の流れ

基本は「**取り込む → 編集する → 記録する → 反映する**」の 4 ステップです。

```bash
cd ~/work/提案書

# ① 取り込む: Box 側で誰かが更新していれば、その内容を手元に取り込む
git pull

# ② 編集する: エクスプローラーで ~/work/提案書 を開き、普段どおり Word や Excel で編集・保存する
#    （Box フォルダ側ではなく、作業用フォルダのファイルを編集すること）

# ③ 記録する: 何を変えたかを確認して、コミットする
git status                      # 変更されたファイルの一覧
git diff                        # テキストファイルなら変更行も見られる
git add -A
git commit -m "A社提案書: 見積金額を改訂"

# ④ 反映する: Box に書き込む
git push
```

`git push` が成功すると、変更したファイルだけが Box フォルダに書き込まれ、Box Drive が自動でクラウドに同期します。

```
git-remote-boxdrive: 反映完了: 書き込み 1 / 削除 0
To boxdrive::C:/Users/you/Box/営業資料/提案書
   1a2b3c4..5d6e7f8  main -> main
```

- ファイルを削除・名前変更した場合も、コミットしてから push すれば Box 側に反映されます
- 1 回の push に複数のコミットをまとめてもかまいません。Box には最後の状態だけが書き込まれ、途中の履歴は手元の git にだけ残ります

## 3. ほかの人が Box を直接更新していたとき

同僚が Box の Web 画面からファイルを差し替えた後に、自分が push しようとすると、**push は失敗します**。これは「他人の更新を知らずに上書きしてしまう」のを防ぐための動作です。

```
 ! [rejected]        main -> main (non-fast-forward)
```

または

```
 ! [remote rejected] main -> main (fetch first: Box 側が更新されています。git pull してから再度 push してください)
```

このときは、メッセージどおり取り込んでから push し直します。

```bash
git pull          # Box の変更を取り込み、自分の変更と合わせる（マージ）
git push          # もう一度反映
```

`git log` を見ると、同僚の更新は「Box snapshot」（作者 `box`）として記録されています。

```bash
git log --oneline --format='%h %an %s'
# 9f8e7d6 山田 太郎 Merge branch 'main' of boxdrive::...
# 3c4d5e6 box Box snapshot: /c/Users/you/Box/営業資料/提案書   ← 同僚が Box で直接更新した分
# 1a2b3c4 山田 太郎 A社提案書: 見積金額を改訂
```

> git は「誰が Box 上で変更したか」までは分かりません。誰の変更かを知りたいときは、Box の Web 画面のバージョン履歴を確認してください。

## 4. 競合（コンフリクト）したとき

自分と同僚が **同じファイル** を変更していると、`git pull` で競合が起きることがあります。

```
CONFLICT (content): Merge conflict in 見積書.xlsx
Automatic merge failed; fix conflicts and then commit the result.
```

### Word / Excel などのファイルの場合

Office ファイルは git が自動で混ぜ合わせることができないので、どちらを残すかを選びます。

```bash
git checkout --theirs 見積書.xlsx   # Box 側（同僚）の版を採用する場合
# git checkout --ours 見積書.xlsx   # 自分の版を採用する場合
```

両方の内容を手で統合したい場合は、それぞれの版を別名で取り出して見比べ、統合した版を `見積書.xlsx` として保存します。

```bash
git show :2:見積書.xlsx > 見積書_自分.xlsx    # 自分の版
git show :3:見積書.xlsx > 見積書_Box.xlsx     # Box 側の版
# ...Excel で見比べて 見積書.xlsx を作り直す。作業後、別名ファイルは削除する
rm 見積書_自分.xlsx 見積書_Box.xlsx
```

### テキストファイルの場合

ファイルの中に次のような印が入るので、エディタで正しい内容に直し、印の行を消します。

```text
<<<<<<< HEAD
納期: 12月10日
=======
納期: 12月15日
>>>>>>> 3c4d5e6...
```

### 解決したら

```bash
git add -A
git commit --no-edit     # マージを完了する
git push
```

途中でやめたくなったら `git merge --abort` で pull 前の状態に戻せます。

## 5. 過去の版を見る・戻す

git の履歴は手元にあるので、Box の状態に関係なく過去の版を取り出せます。

```bash
git log --oneline -- 見積書.xlsx              # このファイルの変更履歴
git show 1a2b3c4:見積書.xlsx > 見積書_旧.xlsx  # 過去の版を別名で取り出して見る
```

ファイルを過去の版に戻して Box にも反映する場合:

```bash
git restore --source=1a2b3c4 見積書.xlsx
git commit -am "見積書を 1a2b3c4 の版に戻す"
git push
```

> 強制 push（`git push -f`）は使えません。過去に戻すときも「過去の内容で上書きする新しいコミット」を作って push します。Box 側の他人の更新を誤って消さないための仕様です。

## 6. よくあるつまずき

| 症状 | 対処 |
|---|---|
| `fatal: ... フォルダが見つかりません` | Box Drive が起動しているか、パスが正しいか確認する。パスに空白がある場合は全体を `"` で囲む |
| `ファイルの読み取りに失敗しました` | Box Drive がファイルをダウンロード中・同期中の可能性。少し待って再実行する。頻繁に起きる場合は、Box Drive でフォルダを「オフラインで使用可能にする」に設定する |
| `書き込みに失敗: ...（ロック中/同期中の可能性）` | Box 側のファイルを誰か（または自分）が Office で開いている。閉じてから再実行する |
| `反映後の検証に失敗` | 書き込み中に誰かが Box を更新した可能性がある。`git pull` してから状態を確認し、必要なら再度 push する |
| `~$見積書.xlsx` などが気になる | Office の一時ファイルは自動で無視されるので、気にしなくてよい |
| 毎回 `LF will be replaced by CRLF` と警告が出る | 動作に問題はない。気になる場合は 1. の `.gitattributes` を設定する |

## 7. すでに手元にあるフォルダから始める場合

手元のフォルダを git 管理していて、それを（空の、または既存の）Box フォルダとつなぎたい場合は `clone` の代わりに次のようにします。

```bash
cd ~/work/既存フォルダ
git remote add box "boxdrive::C:/Users/you/Box/営業資料/提案書"
git pull box main --allow-unrelated-histories   # Box にすでにファイルがある場合（初回のみ）
git push box main
```

この場合、リモート名は `box` なので、以降も `git pull box main` / `git push box main` と指定します（`git push -u box main` としておくと、以降は `git pull` / `git push` だけで済みます）。

---

次のステップ: 複数の Box フォルダを束ねて、AI に資料を更新させる運用は [チュートリアル 2](tutorial-advanced.md) を参照してください。
