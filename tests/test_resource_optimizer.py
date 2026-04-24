import importlib.util
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path


class FakePaginator:
    def __init__(self, pages):
        self.pages = pages

    def paginate(self, **kwargs):
        return self.pages


class FakeEC2Client:
    def get_paginator(self, name):
        if name == "describe_volumes":
            return FakePaginator([{"Volumes": [{"VolumeId": "vol-1", "Size": 100}]}])
        if name == "describe_instances":
            return FakePaginator(
                [
                    {
                        "Reservations": [
                            {
                                "Instances": [
                                    {
                                        "InstanceId": "i-1",
                                        "InstanceType": "t3.small",
                                        "BlockDeviceMappings": [{"Ebs": {"VolumeId": "vol-2"}}],
                                    }
                                ]
                            }
                        ]
                    }
                ]
            )
        if name == "describe_snapshots":
            return FakePaginator(
                [
                    {
                        "Snapshots": [
                            {
                                "SnapshotId": "snap-1",
                                "VolumeSize": 20,
                                "StartTime": datetime.now(timezone.utc) - timedelta(days=120),
                            }
                        ]
                    }
                ]
            )
        raise ValueError(name)

    def describe_volumes(self, VolumeIds):
        return {"Volumes": [{"Size": 50}]}


class FakeSNSClient:
    def __init__(self):
        self.published = []

    def publish(self, **kwargs):
        self.published.append(kwargs)
        return {"MessageId": "msg-3"}


def load_module():
    module_path = Path("lambda/resource_optimizer/lambda_function.py")
    spec = importlib.util.spec_from_file_location("resource_optimizer_lambda", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_resource_optimizer_reports_savings(monkeypatch):
    os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
    os.environ["SNS_TOPIC_ARN"] = "arn:aws:sns:us-east-1:123456789012:test"
    os.environ["MIN_SAVINGS_THRESHOLD"] = "1"

    module = load_module()
    fake_sns = FakeSNSClient()
    monkeypatch.setattr(module, "ec2_client", FakeEC2Client())
    monkeypatch.setattr(module, "sns_client", fake_sns)

    result = module.lambda_handler({}, {})
    body = json.loads(result["body"])

    assert result["statusCode"] == 200
    assert body["total_recommendations"] >= 1
    assert body["total_monthly_savings"] > 0
    assert len(fake_sns.published) == 1
