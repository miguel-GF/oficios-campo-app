from dataclasses import dataclass

from fastapi import HTTPException


@dataclass(frozen=True)
class Account:
    user_id: str
    email: str


def bearer_value(authorization: str | None) -> str | None:
    if authorization is None:
        return None
    prefix = "Bearer "
    if not authorization.startswith(prefix) or len(authorization) <= len(prefix):
        raise HTTPException(status_code=401, detail="AUTH_INVALID")
    return authorization[len(prefix) :]
