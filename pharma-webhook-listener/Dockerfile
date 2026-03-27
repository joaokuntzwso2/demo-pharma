FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1

WORKDIR /app
COPY server.py /app/server.py

EXPOSE 8099

CMD ["python", "/app/server.py"]