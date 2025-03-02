from sqlalchemy import Column, Integer, String, Boolean, ForeignKey
from ..databases.database import Base

# Модель задачи
class Task(Base):
    __tablename__ = "tasks"
    id = Column(Integer, primary_key=True)
    title = Column(String(50))
    description = Column(String(200))
    completed = Column(Boolean, default=False)
    user_id = Column(Integer, ForeignKey("users.id")) # Связь с пользователем
    
