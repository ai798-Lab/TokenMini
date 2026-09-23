#!/usr/bin/env python3
"""Sign a model catalog locally. Requires Python cryptography; never uploads anything.
Keep .local-secrets/model-catalog.key securely backed up outside version control.
"""
import argparse
import base64
import json
import os
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument("payload", type=Path)
parser.add_argument("--initialize", action="store_true", help="Generate a signing key only for the first setup")
args = parser.parse_args()
key_path = ROOT / ".local-secrets/model-catalog.key"
if args.initialize and not key_path.exists():
    key_path.parent.mkdir(mode=0o700, exist_ok=True)
    key = Ed25519PrivateKey.generate()
    fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()))
key = Ed25519PrivateKey.from_private_bytes(key_path.read_bytes())
public = base64.b64encode(key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
source = ROOT / "Sources/MacPulse/AIUsage/CatalogPublicKey.swift"
expected = '// Public verification key. Private signing material is never bundled.\nenum CatalogPublicKey { static let value = "' + public + '" }\n'
if source.exists() and source.read_text() != expected:
    raise SystemExit("Signing key does not match the client verification key; refusing key rotation.")
payload_obj = json.loads(args.payload.read_text())
assert payload_obj["schema"] == 1 and payload_obj["revision"] > 0
assert payload_obj["models"]
raw = json.dumps(payload_obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()
out = ROOT / "site/models/catalog.json"
if out.exists():
    old = json.loads(base64.b64decode(json.loads(out.read_text())["payload"]))
    if payload_obj["revision"] <= old["revision"]:
        raise SystemExit("New catalog revision must increase.")
envelope = {"payload": base64.b64encode(raw).decode(), "signature": base64.b64encode(key.sign(raw)).decode()}
source.write_text(expected)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(envelope, indent=2) + "\n")
print(f"Signed local catalog revision {payload_obj['revision']} ({len(payload_obj['models'])} models). No upload performed.")
