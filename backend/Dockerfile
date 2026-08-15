FROM python:3.12-slim

WORKDIR /app

# install deps first for layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

ENV CAREER_AI_ENV=production \
    CAREER_AI_DB=/data/career_ai.db \
    PORT=8077
VOLUME ["/data"]
EXPOSE 8077

# Run as non-root
RUN useradd -m appuser && mkdir -p /data && chown appuser /data
USER appuser

# --proxy-headers: the host terminates TLS, so without it every request looks
# like plain HTTP coming from the proxy's own address.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
