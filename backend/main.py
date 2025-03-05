from fastapi import FastAPI

app = FastAPI()

@app.get('/', summary='основная ручка', tags=['основная'] )
def root():
    return "Hello World"

