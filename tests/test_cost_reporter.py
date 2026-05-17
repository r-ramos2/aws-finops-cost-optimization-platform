import importlib.util
import json
import os
from pathlib import Path


class FakeCEClient:
    def get_cost_and_usage(self, **kwargs):
        if kwargs["Granularity"] == "DAILY":
            return {
                "ResultsByTime": [
                    {
                        "Groups": [
                            {
                                "Keys": ["AmazonEC2"],
                                "Metrics": {"UnblendedCost": {"Amount": "25.00"}},
                            },
                            {
                                "Keys": ["AmazonS3"],
                                "Metrics": {"UnblendedCost": {"Amount": "5.00"}},
                            },
                        ]
                    }
                ]
            }
        return {"ResultsByTime": [{"Total": {"UnblendedCost": {"Amount": "100.00"}}}]}


class FakeCEClientEmpty:
    """Simulates a day with no billable usage."""

    def get_cost_and_usage(self, **kwargs):
        if kwargs["Granularity"] == "DAILY":
            return {"ResultsByTime": [{"Groups": []}]}
        return {"ResultsByTime": [{"Total": {"UnblendedCost": {"Amount": "0.00"}}}]}


def load_module():
    module_path = Path("lambda/cost_reporter/lambda_function.py")
    spec = importlib.util.spec_from_file_location("cost_reporter_lambda", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_cost_reporter_returns_budget_percent(monkeypatch, fake_sns):
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:test"
    os.environ["MONTHLY_BUDGET"] = "200"

    module = load_module()
    monkeypatch.setattr(module, "ce_client", FakeCEClient())
    monkeypatch.setattr(module, "sns_client", fake_sns)

    result = module.lambda_handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["daily_cost"] == 30.0
    assert body["mtd_cost"] == 100.0
    assert body["budget_percent"] == 50.0
    assert len(fake_sns.published) == 1


def test_cost_reporter_zero_usage_day(monkeypatch, fake_sns):
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:test"
    os.environ["MONTHLY_BUDGET"] = "1000"

    module = load_module()
    monkeypatch.setattr(module, "ce_client", FakeCEClientEmpty())
    monkeypatch.setattr(module, "sns_client", fake_sns)

    result = module.lambda_handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["daily_cost"] == 0.0
    assert body["budget_percent"] == 0.0
    # Report is still sent even on zero-cost days
    assert len(fake_sns.published) == 1
