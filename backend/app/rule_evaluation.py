"""Deterministic side-by-side comparison of stored rule versions on identical OHLCV."""
from __future__ import annotations

from typing import Any

from .analysis_report import build_analysis_report


def _signature(report: dict[str, Any]) -> dict[str, Any]:
    trend = report.get("trend_and_price_action", {})
    breakout = trend.get("breakout", {})
    trend_data = trend.get("trend", {})
    fibonacci = report.get("fibonacci", {})
    elliott = report.get("elliott", {})
    flow = report.get("volume_flow", {})
    return {
        "rule_version": report["analysis_rules_version"],
        "config_sha256": report.get("analysis_rule_config_sha256"),
        "as_of": report["as_of"],
        "bars_available": report["bars_available"],
        "data_sources": report.get("data_quality", {}).get("sources", []),
        "trend": trend_data.get("classification", trend_data.get("status", "unknown")),
        "trend_ema_parameters": {
            "fast_period": trend_data.get("ema_fast_period"),
            "slow_period": trend_data.get("ema_slow_period"),
        },
        "breakout": breakout.get("state", "unknown"),
        "price_action_parameters": {
            "pivot_lookback_bars": trend.get("price_zones", {}).get("lookback_bars"),
            "pivot_wing": trend.get("price_zones", {}).get("pivot_wing"),
            "range_lookback_bars": breakout.get("range_lookback_bars"),
            "volume_confirmation_threshold": breakout.get("volume_confirmation_threshold"),
            "price_buffer_atr": breakout.get("price_buffer_atr"),
        },
        "fibonacci_status": fibonacci.get("status", "unknown"),
        "fibonacci_direction": fibonacci.get("direction"),
        "elliott_status": elliott.get("status", "unknown"),
        "elliott_rule_score": elliott.get("rule_score"),
        "volume_flow_window": flow.get("window", report.get("analysis_rule_parameters", {}).get("volume_flow", {}).get("window", 20)),
        "indicator_parameters": report.get("indicators", {}),
        "volume_flow_classification": flow.get("classification", flow.get("status", "unknown")),
        "scenario_statuses": {
            item["name"]: item["status"] for item in report.get("scenarios", [])
        },
    }


def compare_rule_versions(candles: list[dict], rule_versions: list[dict]) -> dict[str, Any]:
    """Compare rule outputs on the exact same candles; never infer trading returns."""
    if not candles:
        raise ValueError("At least one stored OHLCV candle is required")
    if not isinstance(rule_versions, list) or not 2 <= len(rule_versions) <= 5:
        raise ValueError("Provide between 2 and 5 rule versions")
    versions = [item.get("version") for item in rule_versions]
    if any(not isinstance(version, str) or not version for version in versions):
        raise ValueError("Each rule version must have a version identifier")
    if len(set(versions)) != len(versions):
        raise ValueError("Rule versions must be unique")

    signatures = {}
    for item in rule_versions:
        report = build_analysis_report(
            candles,
            rule_config=item.get("config", {}),
            rule_version=item["version"],
            rule_config_sha256=item.get("config_sha256"),
        )
        signatures[item["version"]] = _signature(report)

    keys = list(next(iter(signatures.values())).keys())
    differences = {}
    for key in keys:
        values = {version: signature[key] for version, signature in signatures.items()}
        if any(value != next(iter(values.values())) for value in values.values()):
            differences[key] = values

    first = next(iter(signatures.values()))
    return {
        "status": "ok",
        "comparison_method": "same_ohlcv_deterministic_rule_output",
        "input": {
            "as_of": first["as_of"],
            "bars_available": first["bars_available"],
            "data_sources": first["data_sources"],
            "same_input_for_all_versions": True,
        },
        "versions_compared": list(signatures.keys()),
        "results": signatures,
        "differences": differences,
        "limitations": [
            "Đây là so sánh đầu ra quy tắc trên cùng một tập OHLCV, không phải backtest.",
            "Không tính lợi nhuận, tỷ lệ thắng hoặc xác suất dự báo.",
            "Khác biệt đầu ra không chứng minh phiên bản mới tốt hơn; cần bộ dữ liệu ngoài mẫu và tiêu chí đánh giá được xác định trước.",
            "Mọi kết quả vẫn phụ thuộc chất lượng, nguồn và trạng thái điều chỉnh của OHLCV đầu vào.",
        ],
    }
