#!/usr/bin/env python3
"""Автоматический прогон бенчмарка: 16 инцидентов на одну связку MCP.

Связки (спека, раздел «Прогоны»):
  1. Radar MCP                                   (VM нет)
  2. Radar MCP + VictoriaMetrics (traffic.prometheusUrl)
  3. Radar MCP + GitHub MCP                      (VM нет)
  4. Radar MCP + VictoriaMetrics + GitHub MCP
  5. Radar MCP + VictoriaMetrics + VictoriaLogs MCP   (GitHub выключен)
  6. Radar MCP + VictoriaMetrics + VictoriaLogs MCP + GitHub MCP

Скрипт переключает стенд в нужную связку (helm upgrade Radar и Holmes),
прогоняет 16 симптомов («приложение <name> недоступно») через HTTP API HolmesGPT
и складывает ответы и расход токенов в /tmp/holmesgpt-bench/<bundle>/.

Источник цифр — ответ /api/chat: analysis (ответ слабой модели) и
metadata.usage (токены). Вердикт «верно/неверно» не ставится — это дело судьи.
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

NS = "holmes"
RADAR_NS = "radar"
APPS = [
    "go-1", "go-2", "go-3", "go-4",
    "nuxt-1", "nuxt-2", "nuxt-3", "nuxt-4",
    "java-1", "java-2", "java-3", "java-4",
    "python-1", "python-2", "python-3", "python-4",
]

RADAR_VM_URL = "http://vmsingle-vmks-victoria-metrics-k8s-stack.vmks.svc:8428"
VLOGS_MCP_URL = "http://vlogs-mcp-victoria-logs-mcp.vmks.svc:8080/mcp"
HOLMES_VALUES = "values/holmes-values.yaml"

# Какие MCP включены в каждой связке.
BUNDLES = {
    1: {"vm": False, "github": False, "vlogs": False},
    2: {"vm": True, "github": False, "vlogs": False},
    3: {"vm": False, "github": True, "vlogs": False},
    4: {"vm": True, "github": True, "vlogs": False},
    5: {"vm": True, "github": False, "vlogs": True},
    6: {"vm": True, "github": True, "vlogs": True},
}


def run(cmd, **kw):
    print("+", " ".join(cmd), flush=True)
    return subprocess.run(cmd, check=True, text=True, **kw)


def configure_radar(vm):
    url = RADAR_VM_URL if vm else ""
    run([
        "helm", "upgrade", "--install", "radar",
        "oci://ghcr.io/skyhook-io/charts/radar",
        "--namespace", RADAR_NS, "--version", "1.15.0", "--wait", "--timeout", "5m",
        "--set", "mcp.enabled=true",
        "--set", f"traffic.prometheusUrl={url}",
    ])


def configure_holmes(bundle):
    cfg = BUNDLES[bundle]
    base = [
        "helm", "upgrade", "--install", "holmes", "robusta/holmes",
        "--namespace", NS, "--version", "0.42.0", "--wait", "--timeout", "8m",
        "-f", HOLMES_VALUES,
        "--set", "extraEnvVarsSecrets[0]=holmes-llm-credentials",
        "--set", "modelList.weak.model=openai/qwen/qwen3.6-27b",
        "--set", "modelList.weak.api_key=envRef:OPENAI_API_KEY",
        "--set", "modelList.weak.api_base=envRef:OPENAI_API_BASE",
    ]
    if cfg["vlogs"]:
        base += [
            "--set", f"mcp_servers.vlogs.config.url={VLOGS_MCP_URL}",
            "--set", "mcp_servers.vlogs.config.mode=streamable-http",
        ]
    if cfg["github"]:
        base += [
            "--set", "mcpAddons.github.enabled=true",
            "--set", "mcpAddons.github.auth.secretName=github-mcp-token",
        ]
    run(base)


def holmes_pod():
    data = json.loads(subprocess.check_output([
        "kubectl", "get", "pod", "-n", NS,
        "-l", "app=holmes", "-o", "json",
    ], text=True))
    for item in data["items"]:
        if item.get("metadata", {}).get("deletionTimestamp"):
            continue
        if item.get("status", {}).get("phase") != "Running":
            continue
        for cs in item["status"].get("containerStatuses", []):
            if cs.get("ready"):
                return item["metadata"]["name"]
    raise RuntimeError("готовый под Holmes не найден")


def wait_ready(pod, timeout=300):
    for _ in range(timeout // 5):
        ready = subprocess.run(
            ["kubectl", "get", "pod", "-n", NS, pod,
             "-o", "jsonpath={.status.containerStatuses[0].ready}"],
            capture_output=True, text=True).stdout.strip()
        if ready == "true":
            return
        time.sleep(5)
    raise RuntimeError(f"под {pod} не стал Ready за {timeout}s")


def api_chat(ask, timeout=900):
    pod = holmes_pod()
    payload = json.dumps({"ask": ask, "model": "weak", "stream": False}).encode()
    proc = subprocess.run([
        "kubectl", "exec", "-i", "-n", NS, pod, "--",
        "python3", "-c",
        (
            "import sys,urllib.request;"
            "req=urllib.request.Request('http://localhost:5050/api/chat',"
            "data=sys.stdin.buffer.read(),"
            "headers={'Content-Type':'application/json'});"
            "sys.stdout.buffer.write(urllib.request.urlopen(req,timeout=%d).read())"
        ) % timeout,
    ], input=payload, capture_output=True)
    if proc.returncode != 0:
        return {"error": proc.stderr.decode()[:2000]}
    return json.loads(proc.stdout.decode())


def run_bundle(bundle, outdir, apps=None):
    cfg = BUNDLES[bundle]
    apps = apps or APPS
    print(f"=== Связка {bundle}: {cfg} ===", flush=True)
    configure_radar(cfg["vm"])
    configure_holmes(bundle)
    pod = holmes_pod()
    wait_ready(pod)

    os.makedirs(outdir, exist_ok=True)
    results = []
    for app in apps:
        symptom = f"приложение {app} недоступно"
        print(f"--- {bundle}: {symptom}", flush=True)
        resp = api_chat(symptom)
        usage = (resp.get("metadata") or {}).get("usage", {}) if "error" not in resp else {}
        entry = {
            "app": app,
            "symptom": symptom,
            "analysis": resp.get("analysis"),
            "error": resp.get("error"),
            "usage": usage,
            "tool_calls": [t.get("tool_name") for t in (resp.get("tool_calls") or [])],
        }
        results.append(entry)
        with open(os.path.join(outdir, f"{app}.json"), "w") as fh:
            json.dump(entry, fh, ensure_ascii=False, indent=2)

    summary = {
        "bundle": bundle,
        "config": cfg,
        "incidents": len(results),
        "errors": sum(1 for r in results if r["error"]),
        "total_tokens": sum((r["usage"] or {}).get("total_tokens", 0) for r in results),
        "prompt_tokens": sum((r["usage"] or {}).get("prompt_tokens", 0) for r in results),
        "completion_tokens": sum((r["usage"] or {}).get("completion_tokens", 0) for r in results),
    }
    with open(os.path.join(outdir, "summary.json"), "w") as fh:
        json.dump(summary, fh, ensure_ascii=False, indent=2)
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)
    return summary


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bundle", type=int, choices=sorted(BUNDLES))
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--apps", default="",
                    help="Запятыми: список приложений (по умолчанию все 16)")
    args = ap.parse_args()
    outdir = args.outdir or f"/tmp/holmesgpt-bench/bundle-{args.bundle}"
    apps = [a for a in args.apps.split(",") if a] or None
    run_bundle(args.bundle, outdir, apps)


if __name__ == "__main__":
    sys.exit(main())
