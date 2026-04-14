---
description: セキュリティアドバイザリのトリアージ（run_cmd用）
model: sonnet
---

**実行環境**: `claude --print` で呼び出されている。標準出力がそのまま呼び出し元スクリプトの戻り値になる。
**使用可能なツール**: Read のみ
**出力形式**: 標準出力に以下のJSON配列のみを出力する。説明文・前置き・コードフェンス不要。
**必ず [ で始まるJSON配列で返すこと。{ で始まるオブジェクトは不可。**

---

# セキュリティトリアージ

`~/.claude/reports/security-advisories-pending.json` を読み、各脆弱性が **クラウド環境（AWS/ECS/EKS/Terraform）を利用する顧客** に影響する可能性があるかトリアージする。

## スコア閾値（即時性に基づく）

このスクリプトは5分ごとに実行される。スコア閾値は即時性に応じて設定する。

- **CVSS 7.0未満**: 即時通知不要。`relevant: false` とする（fetch段階でも除外済み）
- **CVSS 7.0〜8.9（high）**: 当日中対応 → urgency: `"medium"`
- **CVSS 9.0以上（critical）**: 即時対応 → urgency: `"high"`
- CVSSスコアが未記録（0）の場合: 下記の関連性判断を適用し urgency は `"medium"` とする

## 関連性判断基準

以下のいずれかに該当すれば `relevant: true`:

1. **広く使われているパッケージ**: npm/pip/Go の主要パッケージや、有名フレームワーク（Express, Django, Flask, React, Next.js 等）の依存ツリーに含まれる可能性が高いもの
2. **インフラ・クラウドツール**: Terraform, AWS SDK, kubectl, Docker, Helm 等に関連するもの
3. **サプライチェーンリスク**: パッケージ乗っ取り・悪意あるコード注入など、バージョンアップだけで被害を受けるもの
4. **CVSS 9.5以上**: スコアが極めて高く、エコシステムを問わず注意が必要なもの

以下は `relevant: false`:
- ニッチなアプリケーション固有の脆弱性（特定CMS、特定学術ツール等）
- デスクトップアプリのみに影響し、サーバ/コンテナ環境に無関係なもの

## 出力形式

```json
[
  {
    "ghsa_id": "GHSA-xxxx-xxxx-xxxx",
    "relevant": true,
    "urgency": "high",
    "cvss_score": 9.8,
    "title_ja": "axios のリダイレクト時の認証情報漏洩",
    "summary_ja": "axios がリダイレクト先にも Authorization ヘッダをそのまま転送してしまう。外部サーバへ意図せず認証情報が漏れる。",
    "impact_ja": "axios を使っている Node.js アプリ全般。API キーや Bearer トークンを送るサービス間通信が特に危険。npm 週1億 DL のため被害範囲は非常に広い。",
    "mitigation_temp_ja": "axios の maxRedirects: 0 を設定してリダイレクトを無効化するか、リダイレクト先を手動で検証する。",
    "mitigation_perm_ja": "axios を修正済みバージョンにアップデートし、package-lock.json で影響バージョンが残っていないか確認する。",
    "reason": "axios は npm 週1億DL。ほぼ全ての Node.js プロジェクトの transitive dependency"
  }
]
```

- `title_ja`: 原文タイトルの日本語訳（50字以内）
- `summary_ja`: 「バカでもわかる」説明。エンジニアでない人でも何が起きているか理解できるレベルで書く
- `impact_ja`: 「誰が・何を使っていると危険か」を具体的に記述
- `mitigation_temp_ja` / `mitigation_perm_ja`: 具体的なコマンドやバージョン番号を含む実践的な内容
- `relevant: false` の項目も配列に含める（reason のみ1行、他フィールドは省略可）
- 脆弱性が0件の場合は空配列 `[]` を返す
