#!/usr/bin/env python3
"""cost-report.py — トークン経済学の可視化基盤（L1 Infrastructure）

cost.log を集計し、日次/週次/月次/リポ別/コマンド別のコストレポートを出力する。
予算サーキットブレーカー機能付き。

使い方:
  python3 cost-report.py                          # 今月のサマリ（テキスト）
  python3 cost-report.py --format json             # JSON出力（L5 Meta向け）
  python3 cost-report.py --date 2026-03-31         # 指定日のレポート
  python3 cost-report.py --range 2026-03-01:2026-03-31  # 期間指定
  python3 cost-report.py --budget-check 50.00      # 月額上限チェック（超過で exit 1）
  python3 cost-report.py --top-commands 5          # コスト上位コマンド
"""

import argparse
import csv
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

COST_LOG = Path.home() / ".claude" / "cost.log"
HEADER = ["date", "time", "repo", "command", "usage_usd", "duration_ms",
          "input_tokens", "output_tokens", "exit_code"]


def parse_log(path: Path) -> list[dict]:
    """cost.log をパースしてレコードのリストを返す。"""
    if not path.exists():
        return []
    records = []
    with open(path, "r") as f:
        reader = csv.DictReader(f, delimiter="\t", fieldnames=HEADER)
        for row in reader:
            # ヘッダー行をスキップ
            if row["date"] == "date":
                continue
            try:
                row["usage_usd"] = float(row["usage_usd"] or 0)
                row["duration_ms"] = int(float(row["duration_ms"] or 0))
                row["input_tokens"] = int(float(row["input_tokens"] or 0))
                row["output_tokens"] = int(float(row["output_tokens"] or 0))
                row["exit_code"] = int(row["exit_code"] or 0)
                records.append(row)
            except (ValueError, TypeError):
                continue
    return records


def filter_by_date(records: list[dict], start: str, end: str) -> list[dict]:
    """日付範囲でフィルタ。"""
    return [r for r in records if start <= r["date"] <= end]


def aggregate(records: list[dict]) -> dict:
    """レコードリストを集計してサマリ辞書を返す。"""
    if not records:
        return {"total_usd": 0, "total_calls": 0, "total_input_tokens": 0,
                "total_output_tokens": 0, "total_duration_ms": 0,
                "errors": 0, "by_repo": {}, "by_command": {}, "by_date": {}}

    by_repo = defaultdict(lambda: {"usd": 0, "calls": 0, "input_tokens": 0, "output_tokens": 0})
    by_command = defaultdict(lambda: {"usd": 0, "calls": 0, "input_tokens": 0, "output_tokens": 0})
    by_date = defaultdict(lambda: {"usd": 0, "calls": 0})

    total_usd = 0
    total_input = 0
    total_output = 0
    total_duration = 0
    errors = 0

    for r in records:
        usd = r["usage_usd"]
        total_usd += usd
        total_input += r["input_tokens"]
        total_output += r["output_tokens"]
        total_duration += r["duration_ms"]
        if r["exit_code"] != 0:
            errors += 1

        repo = r["repo"]
        by_repo[repo]["usd"] += usd
        by_repo[repo]["calls"] += 1
        by_repo[repo]["input_tokens"] += r["input_tokens"]
        by_repo[repo]["output_tokens"] += r["output_tokens"]

        cmd = f"{repo}/{r['command']}"
        by_command[cmd]["usd"] += usd
        by_command[cmd]["calls"] += 1
        by_command[cmd]["input_tokens"] += r["input_tokens"]
        by_command[cmd]["output_tokens"] += r["output_tokens"]

        by_date[r["date"]]["usd"] += usd
        by_date[r["date"]]["calls"] += 1

    return {
        "total_usd": round(total_usd, 6),
        "total_calls": len(records),
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_duration_ms": total_duration,
        "errors": errors,
        "by_repo": {k: {kk: round(vv, 6) if isinstance(vv, float) else vv
                        for kk, vv in v.items()} for k, v in sorted(by_repo.items())},
        "by_command": {k: {kk: round(vv, 6) if isinstance(vv, float) else vv
                           for kk, vv in v.items()}
                       for k, v in sorted(by_command.items(), key=lambda x: -x[1]["usd"])},
        "by_date": dict(sorted(by_date.items())),
    }


def format_text(summary: dict, title: str) -> str:
    """人間が読めるテキスト形式に変換。"""
    lines = [f"=== {title} ===", ""]

    lines.append(f"合計: ${summary['total_usd']:.4f}（{summary['total_calls']}回, "
                 f"エラー{summary['errors']}件）")
    lines.append(f"トークン: 入力{summary['total_input_tokens']:,} / "
                 f"出力{summary['total_output_tokens']:,}")
    lines.append("")

    if summary["by_repo"]:
        lines.append("--- リポジトリ別 ---")
        for repo, data in summary["by_repo"].items():
            lines.append(f"  {repo}: ${data['usd']:.4f}（{data['calls']}回, "
                         f"入力{data['input_tokens']:,} / 出力{data['output_tokens']:,}）")
        lines.append("")

    if summary["by_command"]:
        lines.append("--- コマンド別（コスト順） ---")
        for cmd, data in list(summary["by_command"].items())[:10]:
            lines.append(f"  {cmd}: ${data['usd']:.4f}（{data['calls']}回）")
        lines.append("")

    if summary["by_date"]:
        lines.append("--- 日別推移 ---")
        for date, data in summary["by_date"].items():
            lines.append(f"  {date}: ${data['usd']:.4f}（{data['calls']}回）")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="cost.log の集計・分析")
    parser.add_argument("--format", choices=["text", "json"], default="text")
    parser.add_argument("--date", help="指定日のレポート（YYYY-MM-DD）")
    parser.add_argument("--range", help="期間指定（YYYY-MM-DD:YYYY-MM-DD）")
    parser.add_argument("--budget-check", type=float,
                        help="月額上限チェック。超過で exit 1")
    parser.add_argument("--top-commands", type=int, default=10,
                        help="コスト上位N件のコマンドを表示")
    parser.add_argument("--log", default=str(COST_LOG),
                        help=f"cost.log のパス（デフォルト: {COST_LOG}）")
    args = parser.parse_args()

    records = parse_log(Path(args.log))
    if not records:
        if args.format == "json":
            print(json.dumps({"error": "cost.log が空、または存在しない"}))
        else:
            print("cost.log が空、または存在しません")
        sys.exit(0)

    # 日付範囲の決定
    today = datetime.now().strftime("%Y-%m-%d")
    month_start = datetime.now().strftime("%Y-%m-01")

    if args.date:
        start = end = args.date
        title = f"日次レポート: {args.date}"
    elif args.range:
        start, end = args.range.split(":")
        title = f"期間レポート: {start} 〜 {end}"
    else:
        start, end = month_start, today
        title = f"月次レポート: {start} 〜 {end}"

    filtered = filter_by_date(records, start, end)
    summary = aggregate(filtered)

    # 予算チェック
    if args.budget_check is not None:
        month_records = filter_by_date(records, month_start, today)
        month_summary = aggregate(month_records)
        month_cost = month_summary["total_usd"]

        if month_cost > args.budget_check:
            msg = (f"BUDGET EXCEEDED: ${month_cost:.4f} / "
                   f"${args.budget_check:.2f}（{month_cost/args.budget_check*100:.0f}%）")
            if args.format == "json":
                print(json.dumps({"budget_exceeded": True, "current": month_cost,
                                  "limit": args.budget_check, "message": msg}))
            else:
                print(f"🚨 {msg}")
            sys.exit(1)
        else:
            remaining = args.budget_check - month_cost
            msg = (f"BUDGET OK: ${month_cost:.4f} / "
                   f"${args.budget_check:.2f}（残り${remaining:.4f}）")
            if args.format == "json":
                print(json.dumps({"budget_exceeded": False, "current": month_cost,
                                  "limit": args.budget_check, "remaining": remaining}))
            else:
                print(f"✅ {msg}")
            sys.exit(0)

    # 通常レポート
    if args.format == "json":
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(format_text(summary, title))


if __name__ == "__main__":
    main()
