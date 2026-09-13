from app.quota import choose_credit


def choice(**overrides):
    values = {
        "is_pro": False,
        "ai_used": 0,
        "pro_fair_use_monthly": 500,
    }
    values.update(overrides)
    return choose_credit(**values)


def test_authenticated_free_account_gets_two_ai_credits_per_month():
    assert choice(ai_used=0) == "monthly"
    assert choice(ai_used=1) == "monthly"
    assert choice(ai_used=2) is None


def test_pro_has_a_server_side_abuse_guardrail():
    assert choice(is_pro=True, ai_used=499) == "pro"
    assert choice(is_pro=True, ai_used=500) is None
