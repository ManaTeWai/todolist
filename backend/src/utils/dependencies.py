from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from jose import JWTError
from ..databases.database import get_db
from ..models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid credentials"
    )
    try:
        # Здесь должна быть ваша логика декодирования токена
        # Например: payload = jwt.decode(token, SECRET_KEY)
        # user = db.query(User).filter(User.id == payload["sub"]).first()
        user = db.query(User).first()  # Заглушка для примера
    except JWTError:
        raise credentials_exception
    return user