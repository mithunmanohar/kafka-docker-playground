#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mSending messages to topic http-messages\033[0m"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic http-messages

echo -e "\033[0;33m-------------------------------------\033[0m"
echo -e "\033[0;33mRunning Basic Authentication Example\033[0m"
echo -e "\033[0;33m-------------------------------------\033[0m"

echo -e "\033[0;33mCreating HttpSinkBasicAuth connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
          "topics": "http-messages",
               "tasks.max": "1",
               "connector.class": "io.confluent.connect.http.HttpSinkConnector",
               "key.converter": "org.apache.kafka.connect.storage.StringConverter",
               "value.converter": "org.apache.kafka.connect.storage.StringConverter",
               "confluent.topic.bootstrap.servers": "broker:9092",
               "confluent.topic.replication.factor": "1",
               "http.api.url": "http://http-service-basic-auth:8080/api/messages",
               "auth.type": "BASIC",
               "connection.user": "admin",
               "connection.password": "password"
          }' \
     http://localhost:8083/connectors/HttpSinkBasicAuth/config | jq .


sleep 10

echo -e "\033[0;33mConfirm that the data was sent to the HTTP endpoint.\033[0m"
curl admin:password@localhost:9080/api/messages | jq .
