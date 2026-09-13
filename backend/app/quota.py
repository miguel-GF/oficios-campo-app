def choose_credit(*, is_pro: bool, ai_used: int, pro_fair_use_monthly: int) -> str | None:
    if is_pro:
        return "pro" if ai_used < pro_fair_use_monthly else None
    return "monthly" if ai_used < 2 else None
