#!/usr/bin/env python3
from __future__ import annotations
import os, sys, time, json, argparse, requests
from typing import Any, Dict, List

# Defaults (override via env or CLI)
BASE_URL = os.getenv("OPENAI_BASE_URL", "http://127.0.0.1:8000/v1")
API_KEY  = os.getenv("OPENAI_API_KEY", "dummy")

# Handy aliases -> full model ids (override with --model-id)
MODEL_ALIASES = {
    "gpt-oss":  "openai/gpt-oss-20b",
    "llama8b":  "meta-llama/Meta-Llama-3.1-8B-Instruct",
}

def _h() -> Dict[str, str]:
    return {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}

def _get(path: str) -> Dict[str, Any]:
    r = requests.get(f"{BASE_URL}{path}", headers=_h(), timeout=60)
    r.raise_for_status()
    return r.json()

def _post(path: str, payload: Dict[str, Any]) -> Dict[str, Any]:
    r = requests.post(f"{BASE_URL}{path}", headers=_h(), json=payload, timeout=180)
    r.raise_for_status()
    return r.json()

def resolve_model_id(model_id: str | None, alias: str | None) -> str:
    if model_id: return model_id
    if alias:    return MODEL_ALIASES.get(alias, alias)
    return MODEL_ALIASES["gpt-oss"]

def cmd_health(_: argparse.Namespace) -> None:
    try:
        print(json.dumps(_get("/health"), indent=2))
    except Exception as e:
        print(f"health check failed: {e}", file=sys.stderr); sys.exit(2)

def cmd_models(_: argparse.Namespace) -> None:
    print(json.dumps(_get("/models"), indent=2))

def cmd_chat(a: argparse.Namespace) -> None:
    model = resolve_model_id(a.model_id, a.alias)
    data = _post("/chat/completions", {
        "model": model,
        "messages": [{"role": "user", "content": a.prompt}],
        "max_tokens": a.max_tokens,
        "temperature": a.temp,
    })
    print(data["choices"][0]["message"]["content"].strip())

def tools_schema() -> List[Dict[str, Any]]:
    return [{
        "type": "function",
        "function": {
            "name": "get_time",
            "description": "Return the current unix timestamp.",
            "parameters": {"type": "object", "properties": {}}
        }
    }]

def cmd_tools_probe(a: argparse.Namespace) -> None:
    model = resolve_model_id(a.model_id, a.alias)
    data = _post("/chat/completions", {
        "model": model,
        "messages": [{"role": "user", "content": a.prompt}],
        "tools": tools_schema(),
        "tool_choice": "auto",
        "temperature": 0.0,
        "max_tokens": 64,
    })
    print(json.dumps(data["choices"][0]["message"].get("tool_calls", []), indent=2))

def cmd_tools_roundtrip(a: argparse.Namespace) -> None:
    model = resolve_model_id(a.model_id, a.alias)
    msgs: List[Dict[str, Any]] = [{"role": "user", "content": a.prompt}]
    first = _post("/chat/completions", {
        "model": model, "messages": msgs,
        "tools": tools_schema(), "tool_choice": "auto",
        "temperature": 0.0, "max_tokens": 64,
    })
    m = first["choices"][0]["message"]
    calls = m.get("tool_calls", [])
    if not calls:
        print("no tool_calls"); sys.exit(3)
    tool_msgs = []
    for tc in calls:
        if tc.get("type") == "function" and tc["function"]["name"] == "get_time":
            tool_msgs.append({
                "role": "tool",
                "tool_call_id": tc["id"],
                "name": "get_time",
                "content": json.dumps({"timestamp": int(time.time())}),
            })
    follow = _post("/chat/completions", {
        "model": model,
        "messages": msgs + [m] + tool_msgs,
        "temperature": 0.0, "max_tokens": 128,
    })
    print(follow["choices"][0]["message"]["content"].strip())

def main() -> None:
    p = argparse.ArgumentParser(prog="test_models")
    p.add_argument("--base-url", default=BASE_URL)
    p.add_argument("--api-key", default=API_KEY)
    p.add_argument("--alias", choices=list(MODEL_ALIASES.keys()))
    p.add_argument("--model-id", help="Full HF repo id (overrides --alias)")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("health").set_defaults(func=cmd_health)
    sub.add_parser("models").set_defaults(func=cmd_models)

    c = sub.add_parser("chat"); c.add_argument("--prompt", default="Say hello in 5 words.")
    c.add_argument("--max-tokens", type=int, default=32); c.add_argument("--temp", type=float, default=0.2)
    c.set_defaults(func=cmd_chat)

    t = sub.add_parser("tools"); t.add_argument("--prompt", default="What time is it? Use the tool.")
    t.set_defaults(func=cmd_tools_probe)

    r = sub.add_parser("roundtrip"); r.add_argument("--prompt", default="What time is it? Use the tool.")
    r.set_defaults(func=cmd_tools_roundtrip)

    a = p.parse_args()
    # allow per-invocation overrides of env-style defaults
    globals()["BASE_URL"] = a.base_url
    globals()["API_KEY"]  = a.api_key
    a.func(a)

if __name__ == "__main__":
    main()
