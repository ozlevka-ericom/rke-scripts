#!/usr/bin/python

from elasticsearch import Elasticsearch
from elasticsearch.client import IngestClient
import os
import json

hosts = ["localhost:9200"]
pipelines_dir = "./"
max_attempts_waiting = 100

if "ELASTICSEARCH_HOST" in os.environ:
    hosts = [os.environ["ELASTICSEARCH_HOST"]]

if "PIPELINE_DIR" in os.environ:
    pipelines_dir = os.environ["PIPELINE_DIR"]

if "MAX_WAITING_ATTEMPTS" in os.environ:
    max_attempts_waiting = int(os.environ["MAX_WAITING_ATTEMPTS"])

client = Elasticsearch(hosts)

def wait_elasticsearch_beready():
    counter = 1
    es_ready = False
    while not es_ready:
        print("Start check elasticsearch ready attempt {}".format(counter))
        try:
            es_ready = client.ping()
        except Exception as ex:
            pass
        print("Wait to elasticsearch {} be ready".format(hosts))
        counter += 1
        if counter >= max_attempts_waiting:
            print("Maximum attempts exceeded {} stop execution".format(counter))
            exit(1)

def make_pipelines():
    with open(os.path.join(pipelines_dir, "pipelines.json")) as file:
        pipelines = json.load(file)
        ing_client = IngestClient(client)
        for key in pipelines.keys():
            print("Creating {0} created {1}".format(key,ing_client.put_pipeline(key, pipelines[key])))

def main():
    wait_elasticsearch_beready()
    make_pipelines()
    exit(0)


if __name__ == "__main__":
    main()