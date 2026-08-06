FROM python:3.12-slim
 
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv
 
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl libpq5 && rm -rf /var/lib/apt/lists/*
 
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
 
COPY . .
RUN chmod +x /srv/start.sh
 
EXPOSE 8000
 
# $PORT is honoured by start.sh; the healthcheck follows it so the check still
# passes on platforms that assign a port at runtime.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://localhost:${PORT:-8000}/health" || exit 1
 
CMD ["/srv/start.sh"]

