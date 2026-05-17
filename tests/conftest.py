import pytest


class FakeSNSClient:
    def __init__(self):
        self.published = []

    def publish(self, **kwargs):
        self.published.append(kwargs)
        return {"MessageId": "test-msg-id"}


@pytest.fixture
def fake_sns():
    return FakeSNSClient()
