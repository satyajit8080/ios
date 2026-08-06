"""Bootstrap: create tables, seed badges, challenges, a food library and an admin account.
 
Usage: python -m app.seed [admin_email] [admin_password]
"""
import os
import sys
from datetime import date
 
from sqlalchemy import select
 
from app.api.v1.challenges import seed_challenges
from app.core.security import hash_password
from app.db.session import SessionLocal, engine
from app.models import Base, Food, ReminderSetting, User
from app.services.gamification import seed_badges
 
FOODS = [
    ("Chicken breast, grilled", None, "100 g", 100, 165, 31.0, 0.0, 3.6, 0.0, 0.0),
    ("Salmon fillet, baked", None, "100 g", 100, 208, 20.4, 0.0, 13.4, 0.0, 0.0),
    ("Whole egg, large", None, "1 egg", 50, 72, 6.3, 0.4, 4.8, 0.0, 0.2),
    ("Greek yoghurt, 2%", None, "170 g pot", 170, 146, 20.0, 8.0, 4.0, 0.0, 7.0),
    ("Rolled oats, dry", None, "40 g", 40, 152, 5.3, 27.0, 2.6, 4.0, 0.4),
    ("Brown rice, cooked", None, "150 g", 150, 165, 3.8, 34.0, 1.3, 2.7, 0.5),
    ("Sweet potato, roasted", None, "150 g", 150, 135, 2.4, 31.0, 0.2, 4.5, 9.5),
    ("Broccoli, steamed", None, "100 g", 100, 35, 2.4, 7.2, 0.4, 3.3, 1.4),
    ("Avocado", None, "half", 100, 160, 2.0, 8.5, 14.7, 6.7, 0.7),
    ("Banana, medium", None, "1 banana", 118, 105, 1.3, 27.0, 0.4, 3.1, 14.4),
    ("Apple, medium", None, "1 apple", 182, 95, 0.5, 25.0, 0.3, 4.4, 19.0),
    ("Blueberries", None, "100 g", 100, 57, 0.7, 14.5, 0.3, 2.4, 10.0),
    ("Almonds", None, "28 g", 28, 164, 6.0, 6.1, 14.2, 3.5, 1.2),
    ("Olive oil", None, "1 tbsp", 14, 119, 0.0, 0.0, 13.5, 0.0, 0.0),
    ("Whole wheat bread", None, "1 slice", 43, 110, 5.0, 20.0, 1.5, 3.0, 2.0),
    ("Lentils, cooked", None, "150 g", 150, 176, 13.5, 30.0, 0.6, 11.7, 2.7),
    ("Tofu, firm", None, "100 g", 100, 144, 17.3, 2.8, 8.7, 2.3, 0.6),
    ("Cottage cheese, low fat", None, "150 g", 150, 122, 20.0, 5.0, 2.0, 0.0, 5.0),
    ("Beef mince, 5% fat", None, "100 g", 100, 137, 21.0, 0.0, 5.0, 0.0, 0.0),
    ("Whey protein powder", None, "1 scoop", 30, 120, 24.0, 3.0, 1.5, 0.5, 2.0),
    ("Peanut butter", None, "1 tbsp", 16, 94, 4.0, 3.2, 8.0, 1.0, 1.5),
    ("Pasta, cooked", None, "150 g", 150, 221, 8.1, 43.0, 1.3, 2.5, 1.5),
    ("Chickpeas, cooked", None, "150 g", 150, 246, 13.0, 41.0, 4.0, 11.5, 7.0),
    ("Spinach, raw", None, "50 g", 50, 12, 1.5, 1.8, 0.2, 1.1, 0.2),
    ("Milk, semi-skimmed", None, "250 ml", 250, 122, 8.5, 12.0, 4.3, 0.0, 12.0),
    ("Cheddar cheese", None, "30 g", 30, 120, 7.0, 0.4, 10.0, 0.0, 0.1),
    ("Tuna, canned in water", None, "100 g", 100, 116, 26.0, 0.0, 0.8, 0.0, 0.0),
    ("Potato, boiled", None, "150 g", 150, 130, 2.9, 30.0, 0.2, 3.2, 1.3),
    ("Quinoa, cooked", None, "150 g", 150, 180, 6.6, 31.5, 2.9, 3.9, 1.3),
    ("Dark chocolate 85%", None, "20 g", 20, 120, 2.0, 6.0, 10.0, 2.4, 3.0),
]
 
 
def main() -> None:
    # Precedence: command-line args, then environment, then a safe default.
    # Hosted platforms run this with no arguments, so ADMIN_EMAIL and
    # ADMIN_PASSWORD are the path that actually matters in production.
    email = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("ADMIN_EMAIL", "admin@awlc.app")
    password = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("ADMIN_PASSWORD", "ChangeMe123!")
 
    # Alembic owns the schema. This is a safety net for a fresh database where
    # migrations have not been applied yet; it never drops or alters anything.
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        seed_badges(db)
        seed_challenges(db)
 
        existing = {f.name for f in db.scalars(select(Food)).all()}
        for name, brand, label, grams, kcal, protein, carbs, fat, fiber, sugar in FOODS:
            if name in existing:
                continue
            db.add(
                Food(
                    name=name, brand=brand, serving_label=label, serving_grams=grams,
                    calories=kcal, protein_g=protein, carbs_g=carbs, fat_g=fat,
                    fiber_g=fiber, sugar_g=sugar, is_public=True,
                )
            )
        db.commit()
 
        admin = db.scalar(select(User).where(User.email == email))
        if admin is None:
            admin = User(
                email=email,
                hashed_password=hash_password(password),
                full_name="Admin",
                is_admin=True,
                onboarded=True,
                height_cm=175,
                gender="unspecified",
                birth_date=date(1990, 1, 1),
                start_weight_kg=85,
                goal_weight_kg=78,
            )
            db.add(admin)
            db.commit()
            db.refresh(admin)
            db.add(ReminderSetting(user_id=admin.id))
            db.commit()
            print(f"admin created: {email}")
        else:
            admin.is_admin = True
            db.add(admin)
            db.commit()
            print(f"admin ensured: {email}")
 
        print(f"foods: {db.scalar(select(__import__('sqlalchemy').func.count(Food.id)))}")
    finally:
        db.close()
 
 
if __name__ == "__main__":
    main()
