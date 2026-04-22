#!/usr/bin/env python3
"""fetch-tech-feeds.py — RSS/Atom フィードを取得して JSON 出力（L1 Infrastructure）

購読フィードは ~/.claude/config/tech-feeds.json で管理。
weekly-review.sh から呼ばれ、L3 が分析する材料を準備する。

使い方:
  python3 fetch-tech-feeds.py                    # stdout に JSON 出力
  python3 fetch-tech-feeds.py --output FILE      # ファイルに出力
  python3 fetch-tech-feeds.py --days 14          # 過去14日分（デフォルト: 7）
  python3 fetch-tech-feeds.py --dry-run          # フィード一覧を表示するだけ
"""

import argparse
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from html import unescape
from pathlib import Path

CONFIG_PATH = Path.home() / ".claude" / "config" / "tech-feeds.json"
SEEN_URLS_PATH = Path.home() / ".claude" / "data" / "tech-feeds-seen-urls.json"
SEEN_URLS_EXPIRE_DAYS = 30
ATOM_NS = "http://www.w3.org/2005/Atom"


def load_seen_urls() -> dict[str, str]:
    """過去に表示済みのURL辞書を読み込む {url: "YYYY-MM-DD"}"""
    if not SEEN_URLS_PATH.exists():
        print("INFO: seen-urls.json 未存在（初回実行）", file=sys.stderr)
        return {}
    with open(SEEN_URLS_PATH, encoding="utf-8") as f:
        data = json.load(f)
    print(f"INFO: seen-urls 読み込み: {len(data)}件", file=sys.stderr)
    return data


def save_seen_urls(seen: dict[str, str]) -> None:
    """seen URLsを保存。30日以上前のエントリは削除"""
    cutoff = (datetime.now() - timedelta(days=SEEN_URLS_EXPIRE_DAYS)).strftime("%Y-%m-%d")
    pruned = {url: date for url, date in seen.items() if date >= cutoff}
    SEEN_URLS_PATH.parent.mkdir(parents=True, exist_ok=True)
    SEEN_URLS_PATH.write_text(
        json.dumps(pruned, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"INFO: seen-urls 書き込み: {len(pruned)}件（pruned前: {len(seen)}件）", file=sys.stderr)


def load_config() -> dict:
    with open(CONFIG_PATH, encoding="utf-8") as f:
        return json.load(f)


def parse_date(date_str: str) -> datetime | None:
    """RSS/Atom の日付文字列をパース"""
    formats = [
        "%a, %d %b %Y %H:%M:%S %z",   # RSS: Mon, 01 Jan 2026 00:00:00 +0000
        "%a, %d %b %Y %H:%M:%S %Z",   # RSS with timezone name
        "%Y-%m-%dT%H:%M:%S%z",         # Atom: 2026-01-01T00:00:00+00:00
        "%Y-%m-%dT%H:%M:%SZ",          # Atom: 2026-01-01T00:00:00Z
        "%Y-%m-%dT%H:%M:%S.%f%z",      # Atom with microseconds
        "%b %d, %Y",                   # Scrape: Apr 7, 2026
    ]
    for fmt in formats:
        try:
            dt = datetime.strptime(date_str.strip(), fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt
        except ValueError:
            continue
    return None


def fetch_feed(url: str, timeout: int = 15) -> ET.Element:
    """URL からフィードを取得してパース"""
    req = urllib.request.Request(url, headers={"User-Agent": "fetch-tech-feeds/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return ET.fromstring(resp.read())


def parse_entries(root: ET.Element, source_name: str, cutoff: datetime) -> list[dict]:
    """RSS/Atom のエントリをパースしてフィルタ"""
    entries = []

    # Atom format
    atom_entries = root.findall(f"{{{ATOM_NS}}}entry")
    if atom_entries:
        for entry in atom_entries:
            title = entry.findtext(f"{{{ATOM_NS}}}title", "")
            link_el = entry.find(f"{{{ATOM_NS}}}link")
            link = link_el.get("href", "") if link_el is not None else ""
            updated = entry.findtext(f"{{{ATOM_NS}}}updated", "")
            summary = entry.findtext(f"{{{ATOM_NS}}}summary", "")
            if not summary:
                summary = entry.findtext(f"{{{ATOM_NS}}}content", "")

            pub_date = parse_date(updated) if updated else None
            if pub_date and pub_date >= cutoff:
                entries.append({
                    "source": source_name,
                    "title": title.strip(),
                    "url": link,
                    "published": pub_date.strftime("%Y-%m-%d"),
                    "summary": summary.strip()[:300],
                })
        return entries

    # RSS format
    for item in root.iter("item"):
        title = item.findtext("title", "")
        link = item.findtext("link", "")
        pub_date_str = item.findtext("pubDate", "")
        description = item.findtext("description", "")

        pub_date = parse_date(pub_date_str) if pub_date_str else None
        if pub_date and pub_date >= cutoff:
            entries.append({
                "source": source_name,
                "title": title.strip(),
                "url": link.strip(),
                "published": pub_date.strftime("%Y-%m-%d"),
                "summary": description.strip()[:300],
            })

    return entries


def scrape_page(url: str, source_name: str, cutoff: datetime) -> list[dict]:
    """HTML ページをスクレイピングして記事一覧を抽出"""
    req = urllib.request.Request(url, headers={"User-Agent": "fetch-tech-feeds/1.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        html = resp.read().decode("utf-8", errors="ignore")

    entries = []
    seen_paths = set()

    # 各 <a href="/news/slug">...</a> ブロックを抽出
    for m in re.finditer(
        r'<a\s[^>]*href="(/news/[^"]+)"[^>]*>(.*?)</a>', html, re.DOTALL
    ):
        path, block = m.group(1), m.group(2)

        if path in seen_paths:
            continue

        # ブロック内から日付を取得
        time_m = re.search(r'<time[^>]*>([^<]+)</time>', block)
        if not time_m:
            continue
        date_str = time_m.group(1).strip()

        # ブロック内からタイトルを取得
        # Featured grid: <h4>title</h4>
        # Publication list: <span class="...title...">title</span>
        title = ""
        h_m = re.search(r'<h\d[^>]*>([^<]+)</h\d>', block)
        if h_m:
            title = h_m.group(1).strip()
        else:
            span_m = re.search(r'<span[^>]*title[^>]*>([^<]+)</span>', block)
            if span_m:
                title = span_m.group(1).strip()

        if not title:
            continue

        pub_date = parse_date(date_str)
        if pub_date and pub_date >= cutoff:
            seen_paths.add(path)
            entries.append({
                "source": source_name,
                "title": unescape(title),
                "url": f"https://www.anthropic.com{path}",
                "published": pub_date.strftime("%Y-%m-%d"),
                "summary": "",
            })

    return entries


def fetch_github_advisories(source_name: str, cutoff: datetime,
                             severity: str = "critical") -> list[dict]:
    """GitHub Advisory Database から脆弱性情報を取得"""
    url = (
        f"https://api.github.com/advisories"
        f"?severity={severity}&type=reviewed&per_page=100"
        f"&sort=published&direction=desc"
    )
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "fetch-tech-feeds/1.0",
    })
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())

    entries = []
    cutoff_str = cutoff.strftime("%Y-%m-%d")

    for adv in data:
        published = adv.get("published_at", "")[:10]
        if published < cutoff_str:
            continue

        # 影響パッケージ情報を収集
        packages = []
        for vuln in adv.get("vulnerabilities", []):
            pkg = vuln.get("package", {})
            ecosystem = pkg.get("ecosystem", "")
            name = pkg.get("name", "")
            if ecosystem and name:
                packages.append(f"{ecosystem}/{name}")

        cvss = adv.get("cvss", {}).get("score", 0)
        summary = adv.get("summary", "")

        entries.append({
            "source": source_name,
            "title": summary[:120],
            "url": adv.get("html_url", ""),
            "published": published,
            "summary": summary[:300],
            "ghsa_id": adv.get("ghsa_id", ""),
            "cvss": cvss,
            "packages": packages,
            "cve_id": adv.get("cve_id", ""),
        })

    return entries


def main():
    parser = argparse.ArgumentParser(description="RSS/Atom フィード取得")
    parser.add_argument("--output", metavar="FILE", help="JSON出力先")
    parser.add_argument("--days", type=int, default=7,
                        help="過去N日分を取得（デフォルト: 7）")
    parser.add_argument("--dry-run", action="store_true", dest="dry_run",
                        help="フィード一覧を表示するだけ")
    parser.add_argument("--config-override", metavar="JSON",
                        help="設定ファイルの代わりに使うJSON文字列")
    args = parser.parse_args()

    if args.config_override:
        config = json.loads(args.config_override)
    else:
        config = load_config()
    feeds = config.get("feeds", [])

    if args.dry_run:
        src = "コマンドライン" if args.config_override else str(CONFIG_PATH)
        print(f"設定: {src}")
        print(f"フィード数: {len(feeds)}")
        for f in feeds:
            feed_type = f.get("type", "rss")
            print(f"  - [{feed_type}] {f['name']}: {f['url']}")
        return

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    all_entries = []
    errors = []

    for feed in feeds:
        try:
            feed_type = feed.get("type", "rss")
            if feed_type == "scrape":
                entries = scrape_page(feed["url"], feed["name"], cutoff)
            elif feed_type == "github_advisories":
                severity = feed.get("severity", "critical")
                entries = fetch_github_advisories(feed["name"], cutoff, severity)
            else:
                root = fetch_feed(feed["url"])
                entries = parse_entries(root, feed["name"], cutoff)
            all_entries.extend(entries)
        except Exception as e:
            errors.append({"source": feed["name"], "error": str(e)})

    # URL 重複除去（同一URLが複数フィードに現れる場合、先に取得した方を残す）
    seen_urls: set[str] = set()
    unique_entries = []
    for entry in all_entries:
        url = entry.get("url", "")
        if url and url in seen_urls:
            continue
        seen_urls.add(url)
        unique_entries.append(entry)

    # 跨ぎ重複除去（過去30日以内に表示済みのURLをスキップ）
    seen_urls_history = load_seen_urls()
    today = datetime.now().strftime("%Y-%m-%d")
    deduped_entries = []
    for entry in unique_entries:
        url = entry.get("url", "")
        if url and url in seen_urls_history:
            continue
        deduped_entries.append(entry)
        if url:
            seen_urls_history[url] = today
    save_seen_urls(seen_urls_history)
    skipped = len(unique_entries) - len(deduped_entries)
    print(f"INFO: 跨ぎ重複除去: {skipped}件スキップ, {len(deduped_entries)}件通過", file=sys.stderr)
    unique_entries = deduped_entries

    result = {
        "fetched_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "days": args.days,
        "total_entries": len(unique_entries),
        "errors": errors,
        "entries": sorted(unique_entries, key=lambda x: x["published"], reverse=True),
    }

    output = json.dumps(result, ensure_ascii=False, indent=2)

    if args.output:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(output + "\n", encoding="utf-8")
        print(f"出力: {args.output}（{len(all_entries)}件, エラー: {len(errors)}件）")
    else:
        print(output)


if __name__ == "__main__":
    main()
