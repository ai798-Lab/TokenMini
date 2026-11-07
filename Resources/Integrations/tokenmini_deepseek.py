"""Record an existing DeepSeek Chat Completions response locally. No network or API key access.

    response = client.chat.completions.create(...)
    record_response(response, project="My project", session="job-123")

Streaming: pass the final chunk containing usage (stream_options.include_usage=True).
Only request id, time, model and numeric usage are written. Never prompts or outputs.
"""
import datetime
import fcntl
import json
import os
from pathlib import Path


def record_response(response, *, project="DeepSeek API", session="api", directory=None):
    if hasattr(response, "model_dump"):
        response = response.model_dump()
    if not isinstance(response, dict) or not isinstance(response.get("usage"), dict):
        raise ValueError("A response containing actual usage is required")
    usage = response["usage"]

    def count(value):
        if type(value) is not int or not 0 <= value <= 1_000_000_000:
            raise ValueError("Token counts must be nonnegative integers")
        return value

    prompt = count(usage.get("prompt_tokens"))
    output = count(usage.get("completion_tokens"))
    details = usage.get("prompt_tokens_details") or {}
    cached = count(usage.get("prompt_cache_hit_tokens", details.get("cached_tokens", 0)))
    if cached > prompt:
        raise ValueError("Cached tokens are a subset of prompt tokens")
    request_id, model = response.get("id"), response.get("model")
    if not isinstance(request_id, str) or not request_id or not isinstance(model, str) or not model:
        raise ValueError("A stable request id and model are required")
    created = response.get("created")
    when = datetime.datetime.fromtimestamp(created, datetime.timezone.utc) if isinstance(created, (int, float)) else datetime.datetime.now(datetime.timezone.utc)
    row = dict(id=request_id, timestamp=when.isoformat(), model=model,
               input=prompt-cached, cacheRead=cached, output=output,
               project=str(project)[:256], session=str(session)[:256])
    root = Path(directory) if directory is not None else Path.home() / "Library/Application Support/TokenMini/api-usage/deepseek"
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = root / (when.strftime("%Y-%m-%d") + ".jsonl")
    fd = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a", encoding="utf-8") as file:
        fcntl.flock(file.fileno(), fcntl.LOCK_EX)
        file.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        file.flush()
        os.fsync(file.fileno())
    return path


if __name__ == "__main__":
    import sys
    record_response(json.load(sys.stdin))
