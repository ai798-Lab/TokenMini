import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('metrics', Path(__file__).parents[1] / 'scripts/download-metrics.py')
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


class DownloadMetricsTests(unittest.TestCase):
    def test_only_public_installer_assets_count_and_products_stay_separate(self):
        releases = [
            {'tag_name': 'v0.14.0', 'draft': False, 'assets': [
                {'id': 1, 'name': 'TokenMini-0.14.0.dmg', 'download_count': 7},
                {'id': 2, 'name': 'TokenMini-0.14.0.dmg.sha256', 'download_count': 99},
                {'id': 3, 'name': 'TokenMini-0.14.0-dSYM.zip', 'download_count': 5}]},
            {'tag_name': 'v0.10.0', 'assets': [{'id': 4, 'name': 'MacPulse-0.10.0.dmg', 'download_count': 2}]},
            {'tag_name': 'draft', 'draft': True, 'assets': [{'id': 5, 'name': 'TokenMini-9.0.0.dmg', 'download_count': 10}]}]
        report = metrics.summarize(releases)
        self.assertEqual(report['total_downloads'], 9)
        self.assertEqual(report['tokenmini_downloads'], 7)
        self.assertEqual(report['legacy_downloads'], 2)
        self.assertIsNone(report['active_devices']['dau'])
        self.assertEqual(report['active_devices']['status'], 'not_connected')

    def test_html_escapes_external_labels_and_never_calls_downloads_users(self):
        report = metrics.summarize([{'tag_name': '<script>alert(1)</script>', 'assets': [
            {'id': 1, 'name': 'TokenMini-1.0.0.dmg', 'download_count': 3}]}])
        html = metrics.render(report)
        self.assertNotIn('<script>alert(1)</script>', html)
        self.assertIn('下载次数', html)
        self.assertIn('尚未接通', html)


if __name__ == '__main__':
    unittest.main()
