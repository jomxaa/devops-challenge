FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

WORKDIR /app

RUN useradd --system --uid 10001 --no-create-home appuser

COPY --chown=appuser:appuser app/app.py ./app.py

USER 10001:10001

EXPOSE 5000

CMD ["python", "app.py"]
