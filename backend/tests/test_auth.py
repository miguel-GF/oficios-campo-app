from app.auth import registration_period


def test_registration_period_uses_supabase_creation_month():
    assert registration_period("2026-09-03T12:30:00Z") == "2026-09"


def test_registration_period_handles_missing_or_invalid_values():
    assert registration_period(None) is None
    assert registration_period("not-a-date") is None
