# setup-notes.md — SSH設定・SES手順メモ

CloudFormation では作らない／自動化しない部分の手順メモ。

## SSH 設定（踏み台経由でWebに入る）

手元PCの `~/.ssh/config`（Windowsは `C:\Users\<user>\.ssh\config`）に設定すると、
`ssh web01` だけで踏み台経由の接続ができる。

```
Host bastion
    HostName <BastionPublicIp>           # CloudFormation Outputs の BastionPublicIp
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

> `web01.home` / `web02.home` はVPC内のプライベートDNS。踏み台を経由（ProxyJump）
> することでプライベートサブネットのWebに到達できる。
> ドメインを使う場合は bastion の HostName を `bastion.<domain>` にできる。

接続例。

```bash
ssh web01
ssh web02
```

## SES（メール）手順メモ

SESはCloudFormationでは作らない。本番アクセス申請やSMTP認証情報の発行がUI/申請
ベースのため。以下を手動で行う。

1. SESでドメイン（例: zexample.com）を検証（DNSにDKIM/検証レコードを登録）
2. 検証済みメールアドレス、または本番アクセスを申請（サンドボックス解除）
3. SMTP認証情報を作成（IAMユーザー `no-reply` 相当）。
   - SMTP Username（AKIA...）と SMTP Password が発行される
   - **この認証情報は平文で扱わない。発行時に安全な場所へ保存**
4. アプリの `.bash_profile`（05-configure-env）に以下を設定
   - `AWS_INTRO_SAMPLE_SMTP_DOMAIN`（例: zexample.com）
   - `AWS_INTRO_SAMPLE_SMTP_ADDRESS`（例: email-smtp.ap-northeast-1.amazonaws.com）
   - `AWS_INTRO_SAMPLE_SMTP_USERNAME` / `AWS_INTRO_SAMPLE_SMTP_PASSWORD`
   - `AWS_INTRO_SAMPLE_HOST`（メール本文のリンク生成に必須。例: www.zexample.com）

> メールが飛ばない場合は troubleshooting.md #11 を参照。
> 学習用スタックを使い終えたら、SES SMTP用IAMユーザーのアクセスキーを無効化・削除する。

## アプリの環境変数とSSMの対応

CloudFormationが保存するSSMパラメータと、アプリ環境変数の対応。

| アプリ環境変数 | 取得元 |
|---|---|
| AWS_INTRO_SAMPLE_DATABASE_PASSWORD | Secrets Manager（/<proj>/rds/master-secret-arn 経由）※sample_appユーザーのパスワードは別途自分で設定 |
| AWS_INTRO_SAMPLE_S3_BUCKET | /<proj>/s3/image-bucket |
| AWS_INTRO_SAMPLE_REDIS_ADDRESS | /<proj>/elasticache/endpoint を redis://...:6379/0 形式に |
| （DB接続先） | db.home（プライベートDNS） |

> 注意: Secrets Manager にあるのは RDSマスターユーザー(admin)のパスワード。
> アプリが使う `sample_app` ユーザーのパスワードは、DB初期化SQLで自分が決めた値。
> 両者は別物なので混同しないこと。
