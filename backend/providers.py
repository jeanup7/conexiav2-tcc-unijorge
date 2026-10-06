"""Contracts for future verification providers. No facial data is accepted here."""
from dataclasses import dataclass
from typing import Protocol

@dataclass(frozen=True)
class VerificationResult:
    verified: bool
    reference: str | None = None

class GuardianProvider(Protocol):
    def begin(self, account_id: str) -> str: ...
    def verify_callback(self, payload: bytes, signature: str) -> VerificationResult: ...

class UnconfiguredGuardianProvider:
    def begin(self, account_id: str) -> str:
        raise RuntimeError('Guardian provider not configured')
    def verify_callback(self, payload: bytes, signature: str) -> VerificationResult:
        # Fail closed. Client booleans, terms acceptance and selfies are not proof.
        return VerificationResult(False)

class EmailDelivery(Protocol):
    def send_one_time_code(self, destination: str, purpose: str, code: str) -> None: ...
