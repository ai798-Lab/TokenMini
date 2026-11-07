import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

source = Path(__file__).resolve().parents[1] / "Resources/Integrations/tokenmini_deepseek.py"
spec = importlib.util.spec_from_file_location("tokenmini_deepseek", source)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeTests(unittest.TestCase):
    def test_counts_and_privacy(self):
        with tempfile.TemporaryDirectory() as directory:
            response = dict(id="fixture-request", model="deepseek-flash", created=1793152800,
                            usage=dict(prompt_tokens=100, completion_tokens=20,
                                       prompt_cache_hit_tokens=40, reasoning_tokens=10),
                            choices=[dict(message=dict(content="private fixture response"))])
            path = bridge.record_response(response, directory=directory)
            text = path.read_text()
            row = json.loads(text)
            self.assertEqual(row["input"] + row["cacheRead"] + row["output"], 120)
            self.assertNotIn("private fixture response", text)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(row["id"], "fixture-request")

    def test_missing_usage_is_not_recorded_as_zero(self):
        with self.assertRaises(ValueError):
            bridge.record_response(dict(id="fixture-request", model="deepseek-flash"))

    def test_cache_subset_is_required(self):
        with self.assertRaises(ValueError):
            bridge.record_response(dict(id="fixture-request", model="deepseek-flash",
                                       usage=dict(prompt_tokens=10, completion_tokens=2, prompt_cache_hit_tokens=20)))


if __name__ == "__main__":
    unittest.main()
