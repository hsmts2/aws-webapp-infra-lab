# deployment.md

CloudFormation でインフラを作成し、アプリを導入して、最後に削除するまでの一連の手順をまとめます。
構成の説明は [architecture.md](architecture.md) を参照してください。

<br>

## 目次

1. デプロイ手順
2. SSH 設定
3. SES（メール）手順メモ
4. トラブルシューティング
5. コスト管理と削除

---

<br>
# 1. デプロイ手順

## 1.0 事前準備

| 項目 | 内容 |
|---|---|
| AWS CLI | インストール済み（`aws --version`） |
| 認証情報 | `aws configure` 済み（`aws sts get-caller-identity` で確認） |
| EC2キーペア | 作成済み（既定名 `sample-key`） |
| グローバルIP | 踏み台SSH許可元。`YourIpCidr` に /32 で設定推奨 |
| ドメイン（任意） | 使う場合のみ Route 53 パブリックHostedZoneを用意 |

<br>
## 1.1 パラメータ準備

```bash
cp parameters/study.example.env parameters/study.env
vi parameters/study.env     # YourIpCidr などを実値に
```

ドメインを使わない場合は `DomainName` と `PublicHostedZoneId` を空のままにします
（ACM・HTTPS・公開Route53は作られません）。

<br>
## 1.2 テンプレート検証

```bash
aws cloudformation validate-template \
  --template-body file://templates/aws-webapp-infra-lab.yaml
```
<br>
## 1.3 スタック作成

```bash
aws cloudformation deploy \
  --template-file templates/aws-webapp-infra-lab.yaml \
  --stack-name aws-webapp-infra-lab \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides $(cat parameters/study.env)
```

> `CAPABILITY_NAMED_IAM` は、名前付きIAMロール（sample-role-web）を作るために必要です。

<br>
## 1.4 出力値の確認

```bash
aws cloudformation describe-stacks \
  --stack-name aws-webapp-infra-lab \
  --query "Stacks[0].Outputs" --output table
```

<br>
## 1.5 アプリ導入に必要な値をSSMから取得

```bash
PROJECT=sample

aws ssm get-parameter --name /$PROJECT/rds/endpoint --query Parameter.Value --output text
aws ssm get-parameter --name /$PROJECT/s3/image-bucket --query Parameter.Value --output text
aws ssm get-parameter --name /$PROJECT/elasticache/endpoint --query Parameter.Value --output text

# RDSマスターパスワード（Secrets Manager管理）
SECRET_ARN=$(aws ssm get-parameter --name /$PROJECT/rds/master-secret-arn --query Parameter.Value --output text)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text
# → JSONの "password" がマスター(admin)のパスワード
```

<br>
## 1.6 RDSにアプリ用DB/ユーザーを作成（1回だけ）

踏み台にSSHして、マスターユーザーで `sample_app` DBと専用ユーザーを作成します。
RDSは共有のため、この作業は **1回だけ**でよく、web01/web02の両方で行う必要はありません。

```bash
ssh -i path/to/sample-key.pem ec2-user@<BastionPublicIp>
# 踏み台からRDSへ（SQLは scripts/05-create-sample-app-db.sql を用意して流す）
mysql -u admin -p -h db.home < 05-create-sample-app-db.sql
```

<br>
## 1.7 Webサーバーへアプリ導入（web01 → web02）

各Webで scripts/ を順に実行します。SSH接続は本書「2. SSH設定」を参照してください。

```bash
ssh web01

# ---- web01 上 ----
# 01-02 は ec2-user（sudo）
bash 01-install-middleware.sh
bash 02-create-deploy-user.sh

# 03 以降は deploy
sudo su - deploy
bash 03-install-ruby.sh
source ~/.bash_profile

# 06（環境変数）を先に：exampleをコピーして実値を埋めて実行
cp 06-configure-env.sh.example 06-configure-env.sh
vi 06-configure-env.sh        # SSM/Secrets Managerから取得した値を埋める
bash 06-configure-env.sh
source ~/.bash_profile

# 04（アプリ取得・bundle・precompile）
bash 04-deploy-sample-app.sh

# DBマイグレーション（初回のみ。RDS共有なのでweb01で1回でよい）
cd /var/www/aws-intro-sample-2nd
bundle _1.17.3_ exec rails db:migrate RAILS_ENV=production

# 07（Puma起動）
bash 07-start-puma.sh
```

web02 でも同じ手順を実行します。ただし **DB作成（1.6）と db:migrate は不要**です（RDS共有のため）。
`SECRET_KEY_BASE` は web01 と同じ値にしてください。

<br>
## 1.8 ALBに登録して動作確認

`07-start-puma.sh` の最後で `curl -I http://localhost:3000/assets/...css` が
**200 OK** になっていることを確認してから、ALBターゲットグループのhealthyを確認します。
`AlbDnsName`（またはドメイン）にブラウザでアクセスして、CSSが当たった画面を確認します。

---

<br>
# 2. SSH 設定

手元PCの `~/.ssh/config`（Windowsは `C:\Users\<user>\.ssh\config`）に設定すると、
`ssh web01` だけで踏み台経由の接続ができます。

```
Host bastion
    HostName <BastionPublicIp>           # Outputs の BastionPublicIp
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem

Host web01
    HostName web01.home                  # プライベートDNS（VPC内で解決）
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem
    ProxyJump bastion

Host web02
    HostName web02.home
    User ec2-user
    IdentityFile ~/.ssh/sample-key.pem
    ProxyJump bastion
```

> `web01.home` / `web02.home` はVPC内のプライベートDNSです。踏み台を経由（ProxyJump）
> することでプライベートサブネットのWebに到達できます。

---

<br>
# 3. SES（メール）手順メモ

SESはCloudFormationでは作りません（本番アクセス申請やSMTP認証情報の発行がUI/申請ベースのため）。

1. SESでドメイン（例: zexample.com）を検証（DNSにDKIM/検証レコードを登録）
2. 検証済みメールアドレス、または本番アクセスを申請（サンドボックス解除）
3. SMTP認証情報を作成。SMTP Username（AKIA...）と SMTP Password が発行される
   - **発行時に安全な場所へ保存。平文で扱わない**
4. アプリの `.bash_profile`（06-configure-env）に以下を設定
   - `AWS_INTRO_SAMPLE_SMTP_DOMAIN`（例: zexample.com）
   - `AWS_INTRO_SAMPLE_SMTP_ADDRESS`（例: email-smtp.ap-northeast-1.amazonaws.com）
   - `AWS_INTRO_SAMPLE_SMTP_USERNAME` / `AWS_INTRO_SAMPLE_SMTP_PASSWORD`
   - `AWS_INTRO_SAMPLE_HOST`（メール本文のリンク生成に必須。例: www.zexample.com）

> 注意: Secrets Manager にあるのは RDSマスターユーザー(admin)のパスワードです。
> アプリが使う `sample_app` ユーザーのパスワードは、DB初期化SQLで自分が決めた値であり、両者は別物です。

---

<br>
# 4. トラブルシューティング

サンプルアプリ（第13章）構築で実際に踏んだ問題と解決策です。書籍は2022年末時点のため、
OS（glibc）とRuby/Gemの経年差分で多くつまずきます。

<br>
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

<br>
## nokogiri ビルド失敗（#3）の詳細

書籍指定の nokogiri 1.10.10 をソースビルドすると、新しいglibcの `canonicalize`
関数と名前衝突してコンパイルに失敗します（`error: conflicting types for 'canonicalize'`）。
プリコンパイル版を入れてから bundle update します。

```bash
gem install nokogiri -v 1.11.7        # x86_64-linux のプリコンパイル版
bundle _1.17.3_ update nokogiri        # Gemfile.lockが1.15.7等に解決され全Gemが入る
```

やってはいけない回避策（記録）。`--platform x86_64-linux`（結局ソースに落ちる）、
`CFLAGS="-Dcanonicalize=..."`（glibc側まで巻き込んで逆効果）。

<br>
## CSSが404（#9）— 今回最大の難関

ALBがPuma(3000)に直結しているため、Nginxは静的配信の経路に入りません。
Rails自身がCSSを配信する必要があり、`RAILS_SERVE_STATIC_FILES=1` が必須です。
経路を1段ずつ確認すると原因が分かります。

```bash
# ① Puma直（3000）でCSSが返るか ← 本命
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

<br>
## メールが飛ばない（#11）の詳細

ユーザー登録は成功してDBにユーザーが入る（`Email has already been taken` が証拠）
のに有効化メールだけ届きません。原因は `AWS_INTRO_SAMPLE_HOST` 未設定で、本文の
有効化リンクURL生成時に `Missing host to link to!` で落ち、SES到達前に失敗していることです。

```bash
export AWS_INTRO_SAMPLE_HOST='www.zexample.com'   # プレーンな文字列で
```

確認は `tail -f log/puma.log` しながら新規アドレスで登録し、`Sent mail to ...` が出るか見ます。
出るのに届かない場合はGmail等のスパム判定（迷惑メールフォルダ）を確認します。
学習を止めずに進めたい場合はDBで手動有効化できます。

```sql
UPDATE users SET activated = 1, activated_at = NOW() WHERE email = '（登録メール）';
```

<br>
## Pumaの停止・再起動メモ

```bash
kill $(cat /var/www/aws-intro-sample-2nd/tmp/pids/server.pid)   # 停止
ps aux | grep puma | grep -v grep                                # 確認
cd /var/www/aws-intro-sample-2nd
nohup bundle _1.17.3_ exec rails server -e production -b 0.0.0.0 -p 3000 > log/puma.log 2>&1 &  # 起動
```

`A server is already running` は二重起動防止メッセージです（エラーではありません）。
フォアグラウンド起動はCtrl+Cで死ぬので厳禁です。必ず `nohup ... &` で起動します。

---

<br>
# 5. コスト管理と削除

学習用スタックは課金が続くリソース（NAT Gateway、ElastiCache、RDS、EIP等）を含みます。
使い終えたら確実に削除します。

<br>
## スタック削除

```bash
aws cloudformation delete-stack --stack-name aws-webapp-infra-lab
aws cloudformation describe-stacks --stack-name aws-webapp-infra-lab   # 完了確認
```

## 削除後に残りやすいリソース（手動確認）

| リソース | 注意点 |
|---|---|
| RDSスナップショット | `DeletionPolicy: Snapshot` で残る。不要ならコンソールで削除 |
| S3バケット | `DeletionPolicy: Retain` で残る。中身を空にして手動削除 |
| NAT Gateway | 削除漏れで時間課金が続く（最優先確認） |
| EIP | NAT用2＋踏み台用1。未関連付けは課金。解放確認 |
| ElastiCache | ノード数が多い。削除完了を確認 |
| Route 53 ホストゾーン | privateゾーンはスタックで消える。手動作成のpublicは残る |
| Secrets Manager | 削除保留期間（既定7日）がある |
| CloudWatch Logs | ロググループが残る場合 |

<br>
## 課金が大きいものの優先確認

1. NAT Gateway ×2（時間課金＋データ処理課金）
2. ElastiCache（ノード数ぶん）
3. RDS（稼働時間）

<br>
## セキュリティ後始末

- SES SMTP用IAMユーザーのアクセスキーを無効化・削除します。
- 作業ログ・スクショに残った認証情報（SES SMTP、SECRET_KEY_BASE）が
  公開リポジトリに含まれていないか確認します。

  <br>
