#!/usr/bin/env python3
"""Private local report from public GitHub counters. No analytics identity is published."""
import argparse
import csv
import html
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

REPOSITORY = 'ai798-Lab/TokenMini'


def summarize(releases):
    assets = []
    for release in releases:
        if release.get('draft'):
            continue
        for asset in release.get('assets', []):
            if not re.fullmatch(r'(TokenMini|MacPulse)-\d+\.\d+\.\d+\.dmg', asset['name']):
                continue
            assets.append({'release': release['tag_name'], 'asset_id': asset['id'],
                           'asset': asset['name'], 'downloads': asset['download_count'],
                           'product': 'tokenmini' if asset['name'].startswith('TokenMini') else 'macpulse-legacy'})
    return {'schema_version': 1, 'repository': REPOSITORY,
            'observed_at': datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
            'metric': 'github_release_installer_downloads',
            'total_downloads': sum(a['downloads'] for a in assets),
            'tokenmini_downloads': sum(a['downloads'] for a in assets if a['product'] == 'tokenmini'),
            'legacy_downloads': sum(a['downloads'] for a in assets if a['product'] == 'macpulse-legacy'),
            'assets': assets,
            'active_devices': {'status': 'not_connected', 'dau': None, 'wau': None}}


def render(report):
    rows = ''.join(f'<tr><td>{html.escape(a["release"])}</td><td>{html.escape(a["asset"])}</td><td>{a["downloads"]}</td></tr>' for a in report['assets'])
    return f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TokenMini 下载统计</title><style>body{{font:16px/1.7 system-ui;margin:48px auto;padding:0 24px;max-width:960px;color:#172235;background:#f5f7fb}}h1{{margin-bottom:0}}.cards{{display:flex;gap:16px;flex-wrap:wrap;margin:28px 0}}.card{{padding:20px;background:white;border-radius:16px;flex:1;min-width:150px}}strong{{font-size:36px;display:block}}small,p{{color:#526078}}table{{width:100%;border-collapse:collapse;background:white}}td,th{{padding:12px;text-align:left;border-bottom:1px solid #eee}}.notice{{padding:20px;background:#fff5da;border-radius:12px}}</style>
<h1>TokenMini 下载统计</h1><p>采集时间：{html.escape(report['observed_at'])} · 来源：GitHub Releases</p>
<div class="cards"><div class="card">TokenMini 下载次数<strong>{report['tokenmini_downloads']}</strong></div><div class="card">旧版 MacPulse<strong>{report['legacy_downloads']}</strong></div><div class="card">全部安装包<strong>{report['total_downloads']}</strong></div></div>
<p>这些是累计下载次数，包含重复下载、升级及发布验收下载；不代表人数、安装数或活跃用户。校验文件和调试文件不计入。</p>
<table><thead><tr><th>版本</th><th>安装包</th><th>下载次数</th></tr></thead><tbody>{rows}</tbody></table>
<h2>日活 / 周活</h2><div class="notice">尚未接通正式活跃统计服务。这里不以 0 代替未知数据，也不从下载量估算活跃人数。接通后仅统计主动同意的匿名设备：日活按北京时间当天去重，周活按含当天的最近 7 天去重。</div>
<p>重新运行“查看下载统计.command”可获取最新数值。旁边的 JSON / CSV 为可迁移的数据快照；此页面保存在本机。</p></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(Path(__file__).resolve().parents[1] / 'dist/metrics'))
    args = parser.parse_args()
    result = subprocess.run(['gh', 'api', '--paginate', '--slurp', f'repos/{REPOSITORY}/releases?per_page=100'], capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise SystemExit('无法获取 GitHub 下载量；保留旧报表。请检查 gh 登录和网络。')
    report = summarize([release for page in json.loads(result.stdout) for release in page])
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'downloads.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    (output / 'index.html').write_text(render(report))
    with (output / 'downloads.csv').open('w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['release', 'asset_id', 'asset', 'downloads', 'product'])
        writer.writeheader()
        writer.writerows(report['assets'])
    snapshot = output / 'snapshots' / (datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d-%H%M%S') + '.json')
    snapshot.parent.mkdir(exist_ok=True)
    snapshot.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f"TokenMini {report['tokenmini_downloads']} 次；旧版 {report['legacy_downloads']} 次；合计 {report['total_downloads']} 次。")
    print(output / 'index.html')


if __name__ == '__main__':
    main()
