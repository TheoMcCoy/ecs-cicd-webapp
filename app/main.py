import os
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.responses import HTMLResponse


APP_NAME = os.getenv("APP_NAME", "Containerized Web App")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

app = FastAPI(title=APP_NAME, version=APP_VERSION)


@app.get("/", response_class=HTMLResponse)
def home():
    response_time = datetime.now(timezone.utc).isoformat()
    return f"""
    <html>
      <head>
        <title>{APP_NAME}</title>
        <style>
          body {{
            font-family: Arial, sans-serif;
            margin: 48px;
            background: #f6f8fb;
            color: #102033;
          }}
          .card {{
            background: white;
            border: 1px solid #d8dee9;
            border-radius: 8px;
            padding: 28px;
            max-width: 760px;
          }}
          .version {{
            color: #2563eb;
            font-weight: 700;
          }}
        </style>
      </head>
      <body>
        <main class="card">
          <h1>{APP_NAME}</h1>
          <p>This application is deployed through an AWS ECS Fargate CI/CD pipeline.</p>
          <p>Current version: <span class="version">{APP_VERSION}</span></p>
          <p>Container response time: {response_time}</p>
        </main>
      </body>
    </html>
    """


@app.get("/health")
def health():
    return {"status": "healthy", "version": APP_VERSION}


@app.get("/version")
def version():
    return {"app": APP_NAME, "version": APP_VERSION}
