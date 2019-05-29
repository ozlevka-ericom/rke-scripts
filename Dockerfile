FROM python:3.6-alpine3.7


RUN pip install elasticsearch

WORKDIR /app

ENV PIPELINE_DIR="/app"
ENV MAX_WAITING_ATTEMPTS=20

COPY install.py pipelines.json /app/


ENTRYPOINT ["python", "install.py"]
