#!/usr/bin/env python3
"""Quality gate for a JMeter HTML report."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

P95_LIMIT_MS = 100.0
ERROR_LIMIT_PCT = 1.0


class GateInputError(Exception):
    """The report cannot be evaluated."""


def _number(row: dict[str, Any], field: str) -> float:
    value = row.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GateInputError(f"el campo '{field}' debe ser numérico")
    value = float(value)
    if not math.isfinite(value):
        raise GateInputError(f"el campo '{field}' no es finito")
    return value


def _find_total(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise GateInputError("statistics.json debe contener un objeto JSON")

    direct = data.get("Total")
    if isinstance(direct, dict):
        return direct

    matches: list[dict[str, Any]] = []
    for key, value in data.items():
        if isinstance(value, dict):
            key_is_total = str(key).strip().casefold() == "total"
            transaction = value.get("transaction")
            transaction_is_total = (
                isinstance(transaction, str)
                and transaction.strip().casefold() == "total"
            )
            if key_is_total or transaction_is_total:
                matches.append(value)

    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise GateInputError("no se encontró la fila TOTAL en statistics.json")
    raise GateInputError("se encontraron varias filas TOTAL ambiguas")


def read_metrics(report_dir: Path) -> dict[str, float]:
    statistics_path = report_dir / "statistics.json"
    if not report_dir.exists():
        raise GateInputError(f"la carpeta del reporte no existe: {report_dir}")
    if not report_dir.is_dir():
        raise GateInputError(f"la ruta no es una carpeta: {report_dir}")
    if not statistics_path.is_file():
        raise GateInputError(f"no existe: {statistics_path}")

    try:
        data = json.loads(statistics_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise GateInputError(f"no se pudo leer {statistics_path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise GateInputError(f"JSON inválido en {statistics_path}: {exc.msg}") from exc

    total = _find_total(data)
    return {
        "p95_ms": _number(total, "pct2ResTime"),
        "errors_pct": _number(total, "errorPct"),
    }


def evaluate(metrics: dict[str, float]) -> bool:
    return (
        metrics["p95_ms"] <= P95_LIMIT_MS
        and metrics["errors_pct"] <= ERROR_LIMIT_PCT
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Evalúa p95 y errores de statistics.json de un reporte HTML de JMeter."
    )
    parser.add_argument("report_dir", type=Path, help="carpeta que contiene statistics.json")
    args = parser.parse_args(argv)

    try:
        metrics = read_metrics(args.report_dir)
    except GateInputError as exc:
        print(f"GATE ERROR: {exc}", file=sys.stderr)
        return 2

    passed = evaluate(metrics)
    result = "PASS" if passed else "FAIL"
    print(f"p95: {metrics['p95_ms']:.2f} ms (límite <= {P95_LIMIT_MS:.2f} ms)")
    print(f"errores: {metrics['errors_pct']:.2f}% (límite <= {ERROR_LIMIT_PCT:.2f}%)")
    print(f"resultado: {result}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
