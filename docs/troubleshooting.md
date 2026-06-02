# troubleshooting.md — つまずきと解決

サンプルアプリ（第13章）構築で実際に踏んだ問題と解決策。書籍は2022年末時点のため、
OS（glibc）とRuby/Gemの経年差分で多くつまずく。

## つまずき早見表

| # | 症状 | 原因 | 解決 |
|---|---|---|---|
| 1 | bundler/nokogiriが `Ruby >= 3.2` で弾かれる | Ruby 2.6.6が古い | Ruby 2.7.8にする |
| 2 | `Could not find bundler (1.17.3)` | bundlerバージョン不一致 | `gem install bundler -v 1.17.3`、以後 `bundle _1.17.3_` |
| 3 | nokogiri `conflicting types for canonicalize` | 新glibcとの関数名衝突 | nokogiri 1.11.7プリコンパイル版＋`bundle update nokogiri` |
| 4 | `The "libcurl" package isn't available` | fogがovirt-engine-sdkを引き込む | `sudo yum install -y libcurl-devel` |
| 5 | `using password: NO` / `bundle: command not found` | ec2-userで作業していた | deployユーザーで環境変数・コマンド実行 |
| 6 | `Could not locate Gemfile` | ホームで実行 | `cd /var/www/aws-intro-sample-2nd` |
| 7 | `Yarn executable was not detected` | Yarn未導入 | 無視可（assetsは書き出される） |
| 8 | CSSが404/502になったり消えたり | Pumaを停止/再起動していた | `nohup ... &` で常駐起動 |
| 9 | CSSが404（最後の難関） | ALBがPuma直結なのに `RAILS_SERVE_STATIC_FILES` 未設定 | `RAILS_SERVE_STATIC_FILES=1` を効かせてPuma再起動 |
| 10 | `RAILS_SERVE_STATIC_FILES` がsourceしても空 | `.bash_profile` の行が読まれない | 末尾に再追記 or 起動コマンドに直接付与 |
| 11 | 登録は成功するが有効化メールが飛ばない | `AWS_INTRO_SAMPLE_HOST` 未設定で本文URL生成が `Missing host to link to!` で落ちる | `.bash_profile` に `export AWS_INTRO_SAMPLE_HOST='www.zexample.com'` を追加してPuma再起動 |
| 12 | 登録時 `Email has already been taken` | 同じメールで既に登録済み（エラーではなく正常なバリデーション） | 別アドレスで登録 |
| 13 | `Account not activated` 表示 | 有効化リンク未クリック（正常な状態） | メールのリンクを踏む、または `activated=1` に手動更新 |

## nokogiri ビルド失敗（#3）の詳細

書籍指定の nokogiri 1.10.10 をソースビルドすると、新しいglibcの `canonicalize`
関数と名前衝突してコンパイルに失敗する。

```
error: conflicting types for 'canonicalize'
```

解決は、プリコンパイル版を入れてから bundle update する。

```bash
gem install nokogiri -v 1.11.7        # x86_64-linux のプリコンパイル版が入る
bundle _1.17.3_ update nokogiri        # Gemfile.lockが1.15.7等に解決され全Gemが入る
```

やってはいけない回避策（記録）。`--platform x86_64-linux`（結局ソースに落ちる）、
`CFLAGS="-Dcanonicalize=..."`（glibc側まで巻き込んで逆効果）。どちらも無駄。

## CSSが404（#9）の詳細 — 今回最大の難関

ALBがPuma(3000)に直結している構成のため、Nginxは静的配信の経路に入らない。
Rails自身がCSSを配信する必要があり、それには `RAILS_SERVE_STATIC_FILES=1` が必須。

経路を1段ずつ切り分けると原因が分かる。

```bash
# ① Puma直（3000）でCSSが返るか ← ここが本命
curl -I http://localhost:3000/assets/application-xxxx.css
# ② Puma直でトップHTMLが返るか
curl -I http://localhost:3000/
# ③ ALB経由（ドメイン）で返るか
curl -I https://www.zexample.com/
```

| ①の結果 | 意味 | 対処 |
|---|---|---|
| `Couldn't connect` | Pumaが止まっている | nohupで起動 |
| `404` | Pumaは生きてるが静的配信OFF | `RAILS_SERVE_STATIC_FILES=1` を効かせて再起動 |
| `200 OK text/css` | 正常 | ALB登録とブラウザキャッシュを確認 |

## メールが飛ばない（#11）の詳細

ユーザー登録は成功してDBにユーザーが入る（`Email has already been taken` が出るのが証拠）
のに、有効化メールだけ届かない。原因は `AWS_INTRO_SAMPLE_HOST` 未設定で、メール本文の
有効化リンクURL生成時に `Missing host to link to!` で落ち、SES到達前に失敗していること。

```bash
# .bash_profile に追加（Markdownリンク記法など混ぜないこと。プレーンな文字列で）
export AWS_INTRO_SAMPLE_HOST='www.zexample.com'
```

確認は `tail -f log/puma.log` しながら新規アドレスで登録し、`Sent mail to ...` が出るか見る。
出るのに届かない場合はGmail等のスパム判定（迷惑メールフォルダ）を確認。

学習を止めずに進めたい場合は、DBで手動有効化できる。

```sql
UPDATE users SET activated = 1, activated_at = NOW() WHERE email = '（登録メール）';
```

## Pumaの停止・再起動メモ

```bash
# 停止
kill $(cat /var/www/aws-intro-sample-2nd/tmp/pids/server.pid)
# 確認
ps aux | grep puma | grep -v grep
# 起動（バックグラウンド。フォアグラウンド起動はCtrl+Cで死ぬので厳禁）
cd /var/www/aws-intro-sample-2nd
nohup bundle _1.17.3_ exec rails server -e production -b 0.0.0.0 -p 3000 > log/puma.log 2>&1 &
```

`A server is already running` は二重起動防止メッセージ（エラーではない）。
先に kill するか、既に動いているなら起動不要。
