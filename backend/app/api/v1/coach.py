from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.deps import get_current_user, throttle
from app.db.session import get_db
from app.models import ChatMessage, User, UserMemory
from app.schemas.misc import ChatMessageOut, ChatRequest, ChatResponse, MemoryOut
from app.services import ai, coach

router = APIRouter(prefix="/coach", tags=["coach"])

SUPPORT_REPLY = (
    "I'm going to step out of coach mode for a second, because what you wrote matters more than any number.\n\n"
    "What you're describing sounds really hard, and it isn't something to push through alone. Please talk to your "
    "doctor or a mental-health professional about it — they can help in ways an app can't. If you're in the US you "
    "can call or text 988 any time; the National Alliance for Eating Disorders helpline is 1-866-662-1235 on weekdays. "
    "Outside the US, findahelpline.com lists local services.\n\n"
    "I'm still here for the everyday stuff whenever you want it, and I'd rather support you than set targets today."
)

FREE_DAILY_MESSAGES = 5


@router.post("", response_model=ChatResponse, dependencies=[Depends(throttle("coach", 60, 3600))])
async def send_message(
    payload: ChatRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not user.is_premium:
        from datetime import date, datetime, time, timezone

        start = datetime.combine(date.today(), time.min, tzinfo=timezone.utc)
        used = db.query(ChatMessage).filter(
            ChatMessage.user_id == user.id,
            ChatMessage.role == "user",
            ChatMessage.created_at >= start,
        ).count()
        if used >= FREE_DAILY_MESSAGES:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                f"You've used your {FREE_DAILY_MESSAGES} free coach messages today. Premium removes the limit.",
            )

    db.add(ChatMessage(user_id=user.id, role="user", content=payload.message))
    db.commit()

    if coach.has_risk_language(payload.message):
        reply = ChatMessage(user_id=user.id, role="assistant", content=SUPPORT_REPLY, provider="safety")
        db.add(reply)
        db.commit()
        db.refresh(reply)
        return ChatResponse(reply=ChatMessageOut.model_validate(reply), provider="safety")

    system = ai.COACH_SYSTEM + "\n\nLive data for this user:\n" + coach.build_context(db, user)
    transcript = coach.history(db, user, limit=20)
    try:
        text, provider = await ai.chat(transcript, system=system)
    except ai.AIUnavailable:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "The coach is unavailable right now.")

    reply = ChatMessage(user_id=user.id, role="assistant", content=text, provider=provider)
    db.add(reply)
    db.commit()
    db.refresh(reply)

    await coach.extract_memories(db, user, transcript + [{"role": "assistant", "content": text}])
    return ChatResponse(reply=ChatMessageOut.model_validate(reply), provider=provider)


@router.get("/history", response_model=List[ChatMessageOut])
def chat_history(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.user_id == user.id)
        .order_by(ChatMessage.created_at.desc())
        .limit(100)
    ).all()
    return [ChatMessageOut.model_validate(r) for r in reversed(rows)]


@router.delete("/history", status_code=204)
def clear_history(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.query(ChatMessage).filter(ChatMessage.user_id == user.id).delete()
    db.commit()


@router.get("/memory", response_model=List[MemoryOut])
def list_memory(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(UserMemory).where(UserMemory.user_id == user.id)).all()
    return [MemoryOut.model_validate(r) for r in rows]


@router.delete("/memory/{key}", status_code=204)
def forget(key: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.query(UserMemory).filter(UserMemory.user_id == user.id, UserMemory.key == key).delete()
    db.commit()
