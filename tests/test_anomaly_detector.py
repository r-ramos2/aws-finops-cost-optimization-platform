import importlib.util
import json
import os
from pathlib import Path


class FakeCEClient:
    def __init__(self):
        self.calls = 0

    def get_cost_and_usage(self, **kwargs):
        self.calls += 1
        if self.calls == 1:
            return {
                "ResultsByTime": [
                    {
                        "Groups": [
                            {
                                "Keys": ["AmazonEC2"],
                                "Metrics": {"UnblendedCost": {"Amount": "40.00"}},
                            }
                        ]
                    }
                ]
            }
        return {
            "ResultsByTime": [
                {
                    "Groups": [
                        {
                            "Keys": ["AmazonEC2"],
                            "Metrics": {"UnblendedCost": {"Amount": "20.00"}},
                        }
                    ]
                }
            ]
        }


class FakeSNSClient:
    def __init__(self):
        self.published = []

    def publish(self, **kwargs):
        self.published.append(kwargs)
        return {"MessageId": "msg-2"}


def load_module():
    module_path = Path("lambda/anomaly_detector/lambda_function.py")
    spec = importlib.util.spec_from_file_location("anomaly_detector_lambda", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_anomaly_detector_publishes_when_threshold_exceeded(monkeypatch):
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:test"
    os.environ["ANOMALY_THRESHOLD"] = "30"

    module = load_module()
    fake_sns = FakeSNSClient()
    monkeypatch.setattr(module, "ce_client", FakeCEClient())
    monkeypatch.setattr(module, "sns_client", fake_sns)

    result = module.lambda_handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["anomalies_found"] >= 1
    assert len(fake_sns.published) == 1
