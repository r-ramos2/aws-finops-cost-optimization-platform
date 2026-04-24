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


class FakeSNSClient:
    def __init__(self):
        self.published = []

    def publish(self, **kwargs):
        self.published.append(kwargs)
        return {"MessageId": "msg-1"}


def load_module():
    module_path = Path("lambda/cost_reporter/lambda_function.py")
    spec = importlib.util.spec_from_file_location("cost_reporter_lambda", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_cost_reporter_returns_budget_percent(monkeypatch):
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:test"
    os.environ["MONTHLY_BUDGET"] = "200"

    module = load_module()
    fake_sns = FakeSNSClient()
    monkeypatch.setattr(module, "ce_client", FakeCEClient())
    monkeypatch.setattr(module, "sns_client", fake_sns)

    result = module.lambda_handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["daily_cost"] == 30.0
    assert body["mtd_cost"] == 100.0
    assert body["budget_percent"] == 50.0
    assert len(fake_sns.published) == 1
