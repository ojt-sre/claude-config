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

`~/.claude/reports/security-advisories-latest.json` を読み、各脆弱性が **クラウド環境（AWS/ECS/EKS/Terraform）を利用する顧客** に影響する可能性があるかトリアージする。

## 判断基準

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
    "reason": "axios は npm 週1億DL。ほぼ全ての Node.js プロジェクトの transitive dependency",
    "action": "顧客の package-lock.json を確認し、影響バージョンを使っていないか検証"
  }
]
```

- `urgency`: `"high"` = 即対応推奨 / `"medium"` = 次回メンテで対応 / `"low"` = 認知のみ
- `relevant: false` の項目も配列に含めるが、`reason` は1行で簡潔に
- 脆弱性が0件の場合は空配列 `[]` を返す
