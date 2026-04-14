---
model: claude-haiku-4-5-20251001
---

**実行環境**: `claude --print` で呼び出されている。標準出力がそのまま呼び出し元スクリプトの戻り値になる。
**使用可能なツール**: Read のみ
**出力形式**: 標準出力に以下のJSON配列のみを出力する。説明文・前置き・コードフェンス不要。**必ず [ で始まるJSON配列で返すこと。{ で始まるオブジェクトは不可。**

---

`~/.claude/reports/tech-feeds-latest.json` を読み、SREエンジニア視点でランク付けしてください。

## 手順

1. `~/.claude/reports/tech-feeds-latest.json` を読む
2. ソースごとに最も重要な記事を1件選ぶ
3. 全選出記事をSREとして重要度の高い順に並べ、上位5件に絞る
4. 1位の記事を `recommended: true` にする
5. 各記事の summary を日本語で50字以内に要約する

## 判断基準

以下を重要とみなす:
- AWS/ECS/EKS/Terraform/Kubernetes に関する新機能・変更
- セキュリティアップデート
- Claude Code / Anthropic の新リリース
- インフラ運用に直接影響する内容

## 出力形式

```json
[
  {
    "source": "AWS Containers",
    "title": "Deploying MCP servers on Amazon ECS",
    "url": "https://...",
    "summary_ja": "ECS上でMCPサーバーを3層構成でデプロイする実装例。",
    "recommended": true
  },
  {
    "source": "Claude Code Releases",
    "title": "v2.1.108",
    "url": "https://...",
    "summary_ja": "プロンプトキャッシュの1時間設定用環境変数を追加。",
    "recommended": false
  }
]
```
