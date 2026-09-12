def choose_credit(
    *,
    is_pro: bool,
    ai_used: int,
    signup_bonus_remaining: int,
    registered_period: str,
    current_period: str,
    pro_fair_use_monthly: int,
) -> str | None:
    if is_pro:
        return "pro" if ai_used < pro_fair_use_monthly else None
    if signup_bonus_remaining > 0:
        return "signup"
    if registered_period == current_period:
        return None
    return "monthly" if ai_used < 2 else None

