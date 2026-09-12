from app.quota import choose_credit


def choice(**overrides):
    values = {
        "is_pro": False,
        "ai_used": 0,
        "signup_bonus_remaining": 0,
        "registered_period": "2026-08",
        "current_period": "2026-09",
        "pro_fair_use_monthly": 500,
    }
    values.update(overrides)
    return choose_credit(**values)


def test_signup_gets_exactly_two_bonus_credits_before_monthly_allowance():
    assert choice(signup_bonus_remaining=2, registered_period="2026-09") == "signup"
    assert choice(signup_bonus_remaining=1, registered_period="2026-09") == "signup"
    assert choice(signup_bonus_remaining=0, registered_period="2026-09") is None


def test_later_month_has_two_free_ai_credits():
    assert choice(ai_used=0) == "monthly"
    assert choice(ai_used=1) == "monthly"
    assert choice(ai_used=2) is None


def test_pro_is_unlimited_in_ui_but_has_abuse_guardrail():
    assert choice(is_pro=True, ai_used=499) == "pro"
    assert choice(is_pro=True, ai_used=500) is None

