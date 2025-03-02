from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ..databases.database import get_db
from ..models.task import Task
from ..models.user import User
from ..schemas.task import TaskCreate, TaskUpdate, Task
from ..utils.dependencies import get_current_user

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.post("/", response_model=Task)
def create_task(
        task: TaskCreate,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user)
):
    new_task = Task(
        title=task.title,
        description=task.description,
        completed=task.completed,
        user_id=user.id
    )
    db.add(new_task)
    db.commit()
    db.refresh(new_task)
    return new_task


@router.get("/", response_model=list[Task])
def get_all_tasks(
        skip: int = 0,
        limit: int = 100,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user)
):
    return db.query(Task) \
        .filter(Task.user_id == user.id) \
        .offset(skip).limit(limit).all()


@router.get("/{task_id}", response_model=Task)
def get_task(
        task_id: int,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user)
):
    task = db.query(Task) \
        .filter(Task.id == task_id, Task.user_id == user.id) \
        .first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@router.put("/{task_id}", response_model=Task)
def update_task(
        task_id: int,
        task_data: TaskUpdate,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user)
):
    task = db.query(Task) \
        .filter(Task.id == task_id, Task.user_id == user.id) \
        .first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    for key, value in task_data.dict().items():
        setattr(task, key, value)

    db.commit()
    db.refresh(task)
    return task


@router.delete("/{task_id}")
def delete_task(
        task_id: int,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user)
):
    task = db.query(Task) \
        .filter(Task.id == task_id, Task.user_id == user.id) \
        .first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    db.delete(task)
    db.commit()
    return {"message": "Task deleted"}