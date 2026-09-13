import base64
import hashlib
import json
import secrets
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool

from .auth import Account
from .config import Settings
from .models import AuthSessionResponse, CreditState
from .quota import choose_credit


class CreditUnavailable(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Reservation:
    id: UUID
    replay: bool = False


class CreditStore:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.pool = AsyncConnectionPool(
            conninfo=settings.database_url,
            min_size=0,
            max_size=8,
            open=False,
            kwargs={"row_factory": dict_row},
        )

    async def open(self) -> None:
        await self.pool.open(wait=True)

    async def close(self) -> None:
        await self.pool.close()

    async def ready(self) -> bool:
        try:
            async with self.pool.connection() as connection:
                row = await (await connection.execute("SELECT 1 AS ready")).fetchone()
                return bool(row and row["ready"] == 1)
        except Exception:
            return False

    @staticmethod
    def period() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m")

    @staticmethod
    def _hash(value: str) -> str:
        return hashlib.sha256(value.encode()).hexdigest()

    def installation_hash(self, installation_id: str) -> str:
        value = f"{self.settings.installation_pepper}:{installation_id}"
        return self._hash(value)

    @asynccontextmanager
    async def transaction(self):
        async with self.pool.connection() as connection:
            async with connection.transaction():
                yield connection

    async def _ensure_account(self, connection, account: Account) -> None:
        await connection.execute(
            """INSERT INTO app_accounts (user_id, email)
               VALUES (%s, %s)
               ON CONFLICT (user_id) DO UPDATE
               SET email=excluded.email, updated_at=now()""",
            (account.user_id, account.email),
        )

    async def reserve(
        self,
        *,
        account: Account | None,
        installation_hash: str,
        idempotency_key: UUID,
        request_hash: str,
        model: str | None = None,
    ) -> Reservation:
        period = self.period()
        reservation_id = uuid4()
        stale_before = datetime.now(timezone.utc) - timedelta(minutes=2)
        async with self.transaction() as connection:
            existing = await (
                await connection.execute(
                    """SELECT id, status, request_hash, created_at
                       FROM ai_usage WHERE idempotency_key=%s FOR UPDATE""",
                    (idempotency_key,),
                )
            ).fetchone()
            if existing:
                if existing["request_hash"] != request_hash:
                    raise CreditUnavailable("IDEMPOTENCY_REUSED")
                if existing["status"] == "succeeded":
                    return Reservation(existing["id"], replay=True)
                if existing["status"] == "pending":
                    if existing["created_at"] > stale_before:
                        raise CreditUnavailable("REQUEST_IN_PROGRESS")
                    await connection.execute(
                        "UPDATE ai_usage SET created_at=now() WHERE id=%s",
                        (existing["id"],),
                    )
                    return Reservation(existing["id"])
                reservation_id = existing["id"]

            credit_kind = "guest"
            if account is None:
                guest = await (
                    await connection.execute(
                        """INSERT INTO guest_installations (installation_hash, ai_uses)
                           VALUES (%s, 1)
                           ON CONFLICT (installation_hash)
                           DO UPDATE SET ai_uses=guest_installations.ai_uses+1, updated_at=now()
                           WHERE guest_installations.ai_uses < 1
                           RETURNING ai_uses""",
                        (installation_hash,),
                    )
                ).fetchone()
                if guest is None:
                    raise CreditUnavailable("EMAIL_REQUIRED")
            else:
                await self._ensure_account(connection, account)
                entitlement = await (
                    await connection.execute(
                        """SELECT is_pro, pro_until FROM entitlements
                           WHERE user_id=%s FOR UPDATE""",
                        (account.user_id,),
                    )
                ).fetchone()
                is_pro = bool(
                    entitlement
                    and entitlement["is_pro"]
                    and (
                        entitlement["pro_until"] is None
                        or entitlement["pro_until"] > datetime.now(timezone.utc)
                    )
                )
                quota = await (
                    await connection.execute(
                        """INSERT INTO monthly_quotas (user_id, period)
                           VALUES (%s, %s)
                           ON CONFLICT (user_id, period)
                           DO UPDATE SET updated_at=now()
                           RETURNING ai_used""",
                        (account.user_id, period),
                    )
                ).fetchone()
                chosen = choose_credit(
                    is_pro=is_pro,
                    ai_used=quota["ai_used"],
                    pro_fair_use_monthly=self.settings.pro_fair_use_monthly,
                )
                if chosen is None:
                    raise CreditUnavailable(
                        "FAIR_USE_REVIEW" if is_pro else "AI_LIMIT_REACHED"
                    )
                credit_kind = chosen
                await connection.execute(
                    """UPDATE monthly_quotas SET ai_used=ai_used+1, updated_at=now()
                       WHERE user_id=%s AND period=%s""",
                    (account.user_id, period),
                )

            await connection.execute(
                """INSERT INTO ai_usage
                   (id, user_id, installation_hash, period, idempotency_key,
                    request_hash, model, credit_kind, status)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending')
                   ON CONFLICT (idempotency_key) DO UPDATE SET
                     user_id=excluded.user_id,
                     installation_hash=excluded.installation_hash,
                     period=excluded.period,
                     model=excluded.model,
                     credit_kind=excluded.credit_kind,
                     status='pending',
                     created_at=now(),
                     finished_at=NULL""",
                (
                    reservation_id,
                    account.user_id if account else None,
                    installation_hash,
                    period,
                    idempotency_key,
                    request_hash,
                    model or self.settings.openai_model,
                    credit_kind,
                ),
            )
        return Reservation(reservation_id)

    async def finish(
        self,
        reservation: Reservation,
        *,
        input_tokens: int,
        output_tokens: int,
    ) -> None:
        async with self.transaction() as connection:
            await connection.execute(
                """UPDATE ai_usage SET status='succeeded', input_tokens=%s,
                   output_tokens=%s, finished_at=now()
                   WHERE id=%s AND status='pending'""",
                (input_tokens, output_tokens, reservation.id),
            )

    async def cancel(self, reservation: Reservation) -> None:
        async with self.transaction() as connection:
            usage = await (
                await connection.execute(
                    "SELECT * FROM ai_usage WHERE id=%s AND status='pending' FOR UPDATE",
                    (reservation.id,),
                )
            ).fetchone()
            if not usage:
                return
            if usage["user_id"]:
                await connection.execute(
                    """UPDATE monthly_quotas
                       SET ai_used=greatest(0, ai_used-1), updated_at=now()
                       WHERE user_id=%s AND period=%s""",
                    (usage["user_id"], usage["period"]),
                )
            else:
                await connection.execute(
                    """UPDATE guest_installations
                       SET ai_uses=greatest(0, ai_uses-1), updated_at=now()
                       WHERE installation_hash=%s""",
                    (usage["installation_hash"],),
                )
            await connection.execute(
                "UPDATE ai_usage SET status='failed', finished_at=now() WHERE id=%s",
                (reservation.id,),
            )

    async def state(
        self, account: Account | None, installation_hash: str
    ) -> CreditState:
        period = self.period()
        async with self.transaction() as connection:
            if account is None:
                row = await (
                    await connection.execute(
                        "SELECT ai_uses FROM guest_installations WHERE installation_hash=%s",
                        (installation_hash,),
                    )
                ).fetchone()
                return CreditState(
                    authenticated=False,
                    is_pro=False,
                    ai_remaining=max(0, 1 - (row["ai_uses"] if row else 0)),
                    period=period,
                )
            await self._ensure_account(connection, account)
            quota = await (
                await connection.execute(
                    "SELECT ai_used FROM monthly_quotas WHERE user_id=%s AND period=%s",
                    (account.user_id, period),
                )
            ).fetchone()
            entitlement = await (
                await connection.execute(
                    "SELECT is_pro, pro_until FROM entitlements WHERE user_id=%s",
                    (account.user_id,),
                )
            ).fetchone()
            is_pro = bool(
                entitlement
                and entitlement["is_pro"]
                and (
                    entitlement["pro_until"] is None
                    or entitlement["pro_until"] > datetime.now(timezone.utc)
                )
            )
            used = quota["ai_used"] if quota else 0
            return CreditState(
                authenticated=True,
                is_pro=is_pro,
                ai_remaining=None if is_pro else max(0, 2 - used),
                period=period,
            )

    async def issue_auth_code(
        self,
        *,
        account: Account,
        code_challenge: str,
        redirect_uri: str,
    ) -> str:
        code = secrets.token_urlsafe(48)
        async with self.transaction() as connection:
            await self._ensure_account(connection, account)
            await connection.execute(
                """INSERT INTO auth_exchange_codes
                   (code_hash, user_id, code_challenge, redirect_uri, expires_at)
                   VALUES (%s, %s, %s, %s, now() + interval '5 minutes')""",
                (self._hash(code), account.user_id, code_challenge, redirect_uri),
            )
        return code

    @staticmethod
    def _pkce_challenge(verifier: str) -> str:
        digest = hashlib.sha256(verifier.encode()).digest()
        return base64.urlsafe_b64encode(digest).decode().rstrip("=")

    async def exchange_auth_code(
        self, *, code: str, verifier: str, redirect_uri: str
    ) -> AuthSessionResponse | None:
        async with self.transaction() as connection:
            row = await (
                await connection.execute(
                    """SELECT c.*, a.email FROM auth_exchange_codes c
                       JOIN app_accounts a ON a.user_id=c.user_id
                       WHERE c.code_hash=%s FOR UPDATE""",
                    (self._hash(code),),
                )
            ).fetchone()
            if (
                not row
                or row["consumed_at"] is not None
                or row["expires_at"] <= datetime.now(timezone.utc)
                or row["redirect_uri"] != redirect_uri
                or not secrets.compare_digest(
                    row["code_challenge"], self._pkce_challenge(verifier)
                )
            ):
                return None
            await connection.execute(
                "UPDATE auth_exchange_codes SET consumed_at=now() WHERE code_hash=%s",
                (self._hash(code),),
            )
            return await self._new_session(connection, row["user_id"], row["email"])

    async def _new_session(
        self, connection, user_id: str, email: str
    ) -> AuthSessionResponse:
        access = secrets.token_urlsafe(48)
        refresh = secrets.token_urlsafe(64)
        await connection.execute(
            """INSERT INTO mobile_sessions
               (id, user_id, access_token_hash, refresh_token_hash,
                access_expires_at, refresh_expires_at)
               VALUES (%s, %s, %s, %s, now() + interval '15 minutes',
                       now() + interval '30 days')""",
            (uuid4(), user_id, self._hash(access), self._hash(refresh)),
        )
        return AuthSessionResponse(
            access_token=access,
            refresh_token=refresh,
            user_id=user_id,
            email=email,
        )

    async def refresh_session(self, refresh_token: str) -> AuthSessionResponse | None:
        access = secrets.token_urlsafe(48)
        refreshed = secrets.token_urlsafe(64)
        async with self.transaction() as connection:
            row = await (
                await connection.execute(
                    """SELECT s.id, s.user_id, a.email FROM mobile_sessions s
                       JOIN app_accounts a ON a.user_id=s.user_id
                       WHERE s.refresh_token_hash=%s AND s.revoked_at IS NULL
                         AND s.refresh_expires_at > now()
                       FOR UPDATE""",
                    (self._hash(refresh_token),),
                )
            ).fetchone()
            if not row:
                return None
            await connection.execute(
                """UPDATE mobile_sessions SET access_token_hash=%s,
                   refresh_token_hash=%s, access_expires_at=now() + interval '15 minutes',
                   refresh_expires_at=now() + interval '30 days', rotated_at=now()
                   WHERE id=%s""",
                (self._hash(access), self._hash(refreshed), row["id"]),
            )
            return AuthSessionResponse(
                access_token=access,
                refresh_token=refreshed,
                user_id=row["user_id"],
                email=row["email"],
            )

    async def account_for_access_token(self, token: str) -> Account | None:
        async with self.pool.connection() as connection:
            row = await (
                await connection.execute(
                    """SELECT s.user_id, a.email FROM mobile_sessions s
                       JOIN app_accounts a ON a.user_id=s.user_id
                       WHERE s.access_token_hash=%s AND s.revoked_at IS NULL
                         AND s.access_expires_at > now()""",
                    (self._hash(token),),
                )
            ).fetchone()
            return Account(row["user_id"], row["email"]) if row else None

    async def revoke_session(self, refresh_token: str) -> None:
        async with self.transaction() as connection:
            await connection.execute(
                """UPDATE mobile_sessions SET revoked_at=now()
                   WHERE refresh_token_hash=%s AND revoked_at IS NULL""",
                (self._hash(refresh_token),),
            )

    async def stripe_customer_for(self, account: Account) -> str | None:
        async with self.transaction() as connection:
            await self._ensure_account(connection, account)
            row = await (
                await connection.execute(
                    "SELECT stripe_customer_id FROM app_accounts WHERE user_id=%s",
                    (account.user_id,),
                )
            ).fetchone()
            return row["stripe_customer_id"]

    async def bind_stripe_customer(self, account: Account, customer_id: str) -> None:
        async with self.transaction() as connection:
            await self._ensure_account(connection, account)
            await connection.execute(
                """UPDATE app_accounts SET stripe_customer_id=%s, updated_at=now()
                   WHERE user_id=%s""",
                (customer_id, account.user_id),
            )

    async def apply_stripe_event(
        self,
        *,
        event_id: str,
        event_type: str,
        payload: dict,
        customer_id: str | None,
        subscription_id: str | None,
        active: bool | None,
        pro_until: datetime | None,
    ) -> bool:
        async with self.transaction() as connection:
            inserted = await (
                await connection.execute(
                    """INSERT INTO billing_events (event_id, event_type, payload)
                       VALUES (%s, %s, %s::jsonb)
                       ON CONFLICT (event_id) DO NOTHING RETURNING event_id""",
                    (event_id, event_type, json.dumps(payload)),
                )
            ).fetchone()
            if not inserted:
                return False
            if customer_id and active is not None:
                account = await (
                    await connection.execute(
                        "SELECT user_id FROM app_accounts WHERE stripe_customer_id=%s",
                        (customer_id,),
                    )
                ).fetchone()
                if account:
                    await connection.execute(
                        """INSERT INTO entitlements
                           (user_id, is_pro, stripe_subscription_id, pro_until,
                            verified_at, updated_at)
                           VALUES (%s, %s, %s, %s, now(), now())
                           ON CONFLICT (user_id) DO UPDATE SET
                             is_pro=excluded.is_pro,
                             stripe_subscription_id=excluded.stripe_subscription_id,
                             pro_until=excluded.pro_until,
                             verified_at=now(), updated_at=now()""",
                        (
                            account["user_id"],
                            active,
                            subscription_id,
                            pro_until,
                        ),
                    )
                    await connection.execute(
                        "UPDATE billing_events SET user_id=%s WHERE event_id=%s",
                        (account["user_id"], event_id),
                    )
            return True
