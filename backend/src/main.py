from fastapi import FastAPI
from databases.database import engine, Base
#from models.task import Task
#from models.user import User
#from routes import tasks
#from routes import auth

Base.metadata.create_all(bind=engine)

app = FastAPI()

#app.include_router(tasks.router)
#app.include_router(auth.router)

@app.get("/", summary='мое событие')
def read_root():
    return {"message": "Todo List API"}