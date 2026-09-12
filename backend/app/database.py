import hashlib
from contextlib import contextmanager
from datetime import datetime, timezone
from uuid import UUID, uuid4

from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from .auth import Account
from .config import Settings
from .models import CreditState
from .quota import choose_credit


class CreditUnavailable(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class CreditStore:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.pool = ConnectionPool(
            conninfo=settings.database_url,
            min_size=0,
            max_size=5,
            open=False,
            kwargs={"row_factory": dict_row},
        )

    def open(self) -> None:
        self.pool.open(wait=True)

    def close(self) -> None:
        self.pool.close()

    @staticmethod
    def period() -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m")

    def installation_hash(self, installation_id: str) -> str:
        # Quotas follow the installation across Wi-Fi/mobile networks. The
        # edge rate limiter separately includes IP to absorb request floods.
        value = f"{self.settings.installation_pepper}:{installation_id}"
        return hashlib.sha256(value.encode()).hexdigest()

    @contextmanager
    def transaction(self):
        with self.pool.connection() as connection:
            with connection.transaction():
                yield connection

    def reserve(
        self,
        *,
        account: Account | None,
        installation_hash: str,
        idempotency_key: UUID,
        request_hash: str,
        model: str | None = None,
    ) -> UUID:
        period = self.period()
        reservation_id = uuid4()
        with self.transaction() as connection:
            credit_kind = "guest"
            existing = connection.execute(
                "SELECT id, status, request_hash FROM ai_usage WHERE idempotency_key=%s FOR UPDATE",
                (idempotency_key,),
            ).fetchone()
            if existing:
                if existing["request_hash"] != request_hash:
                    raise CreditUnavailable("IDEMPOTENCY_REUSED")
                if existing["status"] == "succeeded":
                    raise CreditUnavailable("REQUEST_ALREADY_COMPLETED")
                raise CreditUnavailable("REQUEST_IN_PROGRESS")

            if account is None:
                guest = connection.execute(
                    """INSERT INTO guest_installations (installation_hash, ai_uses)
                       VALUES (%s, 1)
                       ON CONFLICT (installation_hash)
                       DO UPDATE SET ai_uses=guest_installations.ai_uses+1, updated_at=now()
                       WHERE guest_installations.ai_uses < 1
                       RETURNING ai_uses""",
                    (installation_hash,),
                ).fetchone()
                if guest is None:
                    raise CreditUnavailable("EMAIL_REQUIRED")
            else:
                connection.execute(
                    """INSERT INTO app_accounts (user_id, email, registered_period)
                       VALUES (%s, %s, %s)
                       ON CONFLICT (user_id) DO UPDATE SET email=excluded.email, updated_at=now()""",
                    (account.user_id, account.email, account.registered_period or period),
                )
                account_row = connection.execute(
                    """SELECT signup_bonus_remaining, registered_period
                       FROM app_accounts WHERE user_id=%s FOR UPDATE""",
                    (account.user_id,),
                ).fetchone()
                signup_bonus = account_row["signup_bonus_remaining"]
                if signup_bonus > 0:
                    # Claim the welcome pool for the first account seen on an
                    # installation, even before its first AI request. This
                    # prevents creating several accounts to multiply credits.
                    claim = connection.execute(
                        "SELECT user_id FROM signup_credit_claims WHERE installation_hash=%s",
                        (installation_hash,),
                    ).fetchone()
                    if claim is None:
                        connection.execute(
                            """INSERT INTO signup_credit_claims (installation_hash, user_id)
                               VALUES (%s, %s) ON CONFLICT (installation_hash) DO NOTHING""",
                            (installation_hash, account.user_id),
                        )
                        claim = connection.execute(
                            "SELECT user_id FROM signup_credit_claims WHERE installation_hash=%s",
                            (installation_hash,),
                        ).fetchone()
                    if claim["user_id"] != account.user_id:
                        signup_bonus = 0
                entitlement = connection.execute(
                    "SELECT is_pro, pro_until FROM entitlements WHERE user_id=%s FOR UPDATE",
                    (account.user_id,),
                ).fetchone()
                is_pro = bool(
                    entitlement
                    and entitlement["is_pro"]
                    and (
                        entitlement["pro_until"] is None
                        or entitlement["pro_until"] > datetime.now(timezone.utc)
                    )
                )
                quota = connection.execute(
                    """INSERT INTO monthly_quotas (user_id, period)
                       VALUES (%s, %s)
                       ON CONFLICT (user_id, period) DO UPDATE SET updated_at=now()
                       RETURNING ai_used""",
                    (account.user_id, period),
                ).fetchone()
                chosen = choose_credit(
                    is_pro=is_pro,
                    ai_used=quota["ai_used"],
                    signup_bonus_remaining=signup_bonus,
                    registered_period=account_row["registered_period"],
                    current_period=period,
                    pro_fair_use_monthly=self.settings.pro_fair_use_monthly,
                )
                if chosen is None:
                    code = "FAIR_USE_REVIEW" if is_pro else "AI_LIMIT_REACHED"
                    raise CreditUnavailable(code)
                credit_kind = chosen
                if credit_kind == "signup":
                    connection.execute(
                        """UPDATE app_accounts
                           SET signup_bonus_remaining=signup_bonus_remaining-1, updated_at=now()
                           WHERE user_id=%s""",
                        (account.user_id,),
                    )
                connection.execute(
                    """UPDATE monthly_quotas SET ai_used=ai_used+1, updated_at=now()
                       WHERE user_id=%s AND period=%s""",
                    (account.user_id, period),
                )

            connection.execute(
                """INSERT INTO ai_usage
                   (id, user_id, installation_hash, period, idempotency_key, request_hash, model, credit_kind, status)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending')""",
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
        return reservation_id

    def finish(self, reservation_id: UUID, *, input_tokens: int, output_tokens: int) -> None:
        with self.transaction() as connection:
            connection.execute(
                """UPDATE ai_usage SET status='succeeded', input_tokens=%s,
                   output_tokens=%s, finished_at=now()
                   WHERE id=%s AND status='pending'""",
                (input_tokens, output_tokens, reservation_id),
            )

    def cancel(self, reservation_id: UUID) -> None:
        with self.transaction() as connection:
            usage = connection.execute(
                "SELECT * FROM ai_usage WHERE id=%s AND status='pending' FOR UPDATE",
                (reservation_id,),
            ).fetchone()
            if not usage:
                return
            if usage["user_id"]:
                connection.execute(
                    """UPDATE monthly_quotas SET ai_used=greatest(0, ai_used-1), updated_at=now()
                       WHERE user_id=%s AND period=%s""",
                    (usage["user_id"], usage["period"]),
                )
                if usage["credit_kind"] == "signup":
                    connection.execute(
                        """UPDATE app_accounts
                           SET signup_bonus_remaining=least(2, signup_bonus_remaining+1), updated_at=now()
                           WHERE user_id=%s""",
                        (usage["user_id"],),
                    )
            else:
                connection.execute(
                    """UPDATE guest_installations SET ai_uses=greatest(0, ai_uses-1), updated_at=now()
                       WHERE installation_hash=%s""",
                    (usage["installation_hash"],),
                )
            connection.execute(
                "UPDATE ai_usage SET status='failed', finished_at=now() WHERE id=%s",
                (reservation_id,),
            )

    def state(self, account: Account | None, installation_hash: str) -> CreditState:
        period = self.period()
        with self.transaction() as connection:
            if account is None:
                row = connection.execute(
                    "SELECT ai_uses FROM guest_installations WHERE installation_hash=%s",
                    (installation_hash,),
                ).fetchone()
                return CreditState(
                    authenticated=False,
                    is_pro=False,
                    ai_remaining=max(0, 1 - (row["ai_uses"] if row else 0)),
                    manual_remaining=3,
                    signup_bonus_remaining=2,
                    period=period,
                )
            connection.execute(
                """INSERT INTO app_accounts (user_id, email, registered_period)
                   VALUES (%s, %s, %s)
                   ON CONFLICT (user_id) DO UPDATE SET email=excluded.email, updated_at=now()""",
                (account.user_id, account.email, account.registered_period or period),
            )
            quota = connection.execute(
                "SELECT ai_used, manual_used FROM monthly_quotas WHERE user_id=%s AND period=%s",
                (account.user_id, period),
            ).fetchone()
            entitlement = connection.execute(
                "SELECT is_pro, pro_until FROM entitlements WHERE user_id=%s",
                (account.user_id,),
            ).fetchone()
            account_row = connection.execute(
                "SELECT signup_bonus_remaining, registered_period FROM app_accounts WHERE user_id=%s",
                (account.user_id,),
            ).fetchone()
            is_pro = bool(
                entitlement
                and entitlement["is_pro"]
                and (
                    entitlement["pro_until"] is None
                    or entitlement["pro_until"] > datetime.now(timezone.utc)
                )
            )
            ai_used = quota["ai_used"] if quota else 0
            bonus = account_row["signup_bonus_remaining"] if account_row else 2
            signup_period = account_row["registered_period"] if account_row else period
            claim = None
            if bonus > 0:
                claim = connection.execute(
                    "SELECT user_id FROM signup_credit_claims WHERE installation_hash=%s",
                    (installation_hash,),
                ).fetchone()
                if claim is None:
                    connection.execute(
                        """INSERT INTO signup_credit_claims (installation_hash, user_id)
                           VALUES (%s, %s) ON CONFLICT (installation_hash) DO NOTHING""",
                        (installation_hash, account.user_id),
                    )
                    claim = connection.execute(
                        "SELECT user_id FROM signup_credit_claims WHERE installation_hash=%s",
                        (installation_hash,),
                    ).fetchone()
                if claim and claim["user_id"] != account.user_id:
                    bonus = 0
            free_remaining = bonus if signup_period == period else max(0, 2 - ai_used)
            return CreditState(
                authenticated=True,
                is_pro=is_pro,
                ai_remaining=None if is_pro else free_remaining,
                manual_remaining=max(
                    0,
                    (3 if signup_period == period else 4)
                    - (quota["manual_used"] if quota else 0),
                ),
                signup_bonus_remaining=bonus,
                period=period,
            )

    def save_entitlement(
        self,
        *,
        account: Account,
        token_hash: str,
        active: bool,
        expires_at,
        base_plan_id: str | None,
        audit: dict,
    ) -> None:
        import json

        with self.transaction() as connection:
            connection.execute(
                """INSERT INTO app_accounts (user_id, email, registered_period)
                   VALUES (%s, %s, %s)
                   ON CONFLICT (user_id) DO UPDATE SET email=excluded.email, updated_at=now()""",
                (
                    account.user_id,
                    account.email,
                    account.registered_period or self.period(),
                ),
            )
            connection.execute(
                """INSERT INTO entitlements
                   (user_id, is_pro, product_id, purchase_token_hash, pro_until, verified_at, updated_at)
                   VALUES (%s, %s, %s, %s, %s, now(), now())
                   ON CONFLICT (user_id) DO UPDATE SET
                     is_pro=excluded.is_pro, product_id=excluded.product_id,
                     purchase_token_hash=excluded.purchase_token_hash,
                     pro_until=excluded.pro_until, verified_at=now(), updated_at=now()""",
                (
                    account.user_id,
                    active,
                    self.settings.play_product_id,
                    token_hash,
                    expires_at,
                ),
            )
            connection.execute(
                """INSERT INTO billing_events
                   (event_id, user_id, event_type, purchase_token_hash, payload)
                   VALUES (%s, %s, 'client_verification', %s, %s::jsonb)
                   ON CONFLICT (event_id) DO NOTHING""",
                (
                    f"verify:{token_hash}:{int(datetime.now(timezone.utc).timestamp() // 3600)}",
                    account.user_id,
                    token_hash,
                    json.dumps({**audit, "base_plan_id": base_plan_id}),
                ),
            )
