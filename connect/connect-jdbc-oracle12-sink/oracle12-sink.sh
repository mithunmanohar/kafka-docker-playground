#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ ! -f ${DIR}/ojdbc8.jar ]
then
     echo -e "\033[0;33mERROR: ${DIR}/ojdbc8.jar is missing. It must be downloaded manually in order to acknowledge user agreement\033[0m"
     exit 1
fi

if test -z "$(docker images -q oracle/database:12.2.0.1-ee)"
then
     if [ ! -f ${DIR}/linuxx64_12201_database.zip ]
     then
          echo -e "\033[0;33mERROR: ${DIR}/linuxx64_12201_database.zip is missing. It must be downloaded manually in order to acknowledge user agreement\033[0m"
          exit 1
     fi
     echo -e "\033[0;33mBuilding oracle/database:12.2.0.1-ee docker image..it can take a while...(more than 15 minutes!)\033[0m"
     OLDDIR=$PWD
     rm -rf ${DIR}/docker-images
     git clone https://github.com/oracle/docker-images.git

     cp ${DIR}/linuxx64_12201_database.zip ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles/12.2.0.1/linuxx64_12201_database.zip
     cd ${DIR}/docker-images/OracleDatabase/SingleInstance/dockerfiles
     ./buildDockerImage.sh -v 12.2.0.1 -e
     rm -rf ${DIR}/docker-images
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


# Verify Oracle DB has started within MAX_WAIT seconds
MAX_WAIT=900
CUR_WAIT=0
echo -e "\033[0;33mWaiting up to $MAX_WAIT seconds for Oracle DB to start\033[0m"
docker container logs oracle > /tmp/out.txt 2>&1
while [[ ! $(cat /tmp/out.txt) =~ "DONE: Executing user defined scripts" ]]; do
sleep 10
docker container logs oracle > /tmp/out.txt 2>&1
CUR_WAIT=$(( CUR_WAIT+10 ))
if [[ "$CUR_WAIT" -gt "$MAX_WAIT" ]]; then
     echo -e "\nERROR: The logs in oracle container do not show 'DONE: Executing user defined scripts' after $MAX_WAIT seconds. Please troubleshoot with 'docker container ps' and 'docker container logs'.\n"
     exit 1
fi
done
echo -e "\033[0;33mOracle DB has started!\033[0m"

echo -e "\033[0;33mCreating Oracle sink connector\033[0m"

docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
                    "tasks.max": "1",
                    "connection.user": "myuser",
                    "connection.password": "mypassword",
                    "connection.url": "jdbc:oracle:thin:@oracle:1521/ORCLPDB1",
                    "topics": "ORDERS",
                    "auto.create": "true",
                    "insert.mode":"insert",
                    "auto.evolve":"true"
          }' \
     http://localhost:8083/connectors/oracle-sink/config | jq .


echo -e "\033[0;33mSending messages to topic ORDERS\033[0m"
docker exec -i schema-registry kafka-avro-console-producer --broker-list broker:9092 --topic ORDERS --property value.schema='{"type":"record","name":"myrecord","fields":[{"name":"id","type":"int"},{"name":"product", "type": "string"}, {"name":"quantity", "type": "int"}, {"name":"price",
"type": "float"}]}' << EOF
{"id": 999, "product": "foo", "quantity": 100, "price": 50}
EOF

sleep 5


echo -e "\033[0;33mShow content of ORDERS table:\033[0m"
docker exec oracle bash -c "echo 'select * from ORDERS;' | sqlplus myuser/mypassword@//localhost:1521/ORCLPDB1"

