# cost-cleanup.md — コスト管理と削除手順

学習用スタックは課金が続くリソース（NAT Gateway、ElastiCache、RDS、EIP等）を含む。
使い終えたら確実に削除する。

## スタック削除

```bash
aws cloudformation delete-stack --stack-name aws-webapp-infra-lab

# 削除完了の確認（DELETE_COMPLETE になるまで待つ）
aws cloudformation describe-stacks --stack-name aws-webapp-infra-lab
```

## 削除後に残りやすいリソース（手動確認）

| リソース | 注意点 | 対処 |
|---|---|---|
| RDSスナップショット | `DeletionPolicy: Snapshot` で自動スナップショットが残る | 不要ならRDSコンソールで削除 |
| S3バケット | `DeletionPolicy: Retain` で残る。中身があると削除不可 | 中身を空にしてから手動削除 |
| NAT Gateway | 削除漏れがあると時間課金が続く（要注意） | EC2→NATゲートウェイで残存確認 |
| EIP | NAT用2つ＋踏み台用1つ。未関連付けのEIPは課金 | EC2→Elastic IPで残存確認・解放 |
| ElastiCache | ノード数が多い（2シャード×レプリカ） | 削除完了を確認 |
| Route 53 ホストゾーン | privateゾーン `home` はスタックで消えるが、手動作成のpublicゾーンは残る | 必要に応じ手動削除 |
| CloudWatch Logs | ロググループが残る場合 | 不要なら削除 |
| Secrets Manager | RDSパスワードのSecretは削除保留期間（既定7日）がある | 即時削除したい場合はコンソールで強制削除 |

## 課金が大きいものの優先確認

学習で放置すると効きやすいのはこの3つ。

1. NAT Gateway ×2（時間課金＋データ処理課金）
2. ElastiCache（ノード数ぶん）
3. RDS（インスタンス稼働時間）

削除後、これらが消えているかを最優先で確認する。

## セキュリティ後始末（重要）

- SES SMTP用IAMユーザーのアクセスキーを無効化・削除する。
- 作業ログ・スクショに残った認証情報（SES SMTPのUsername/Password、
  SECRET_KEY_BASE）が公開リポジトリに含まれていないか確認する。
