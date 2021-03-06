#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# Need to create the TIBCO EMS image using https://github.com/mikeschippers/docker-tibco

if [ ! -f ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip ]
then
     echo -e "\033[0;33mERROR: ${DIR}/docker-tibco/ does not contain TIBCO EMS zip file TIB_ems-ce_8.5.1_linux_x86_64.zip\033[0m"
     exit 1
fi

if [ ! -f ${DIR}/tibjms.jar ]
then
     echo -e "\033[0;33m${DIR}/tibjms.jar missing, will get it from ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip\033[0m"
     rm -rf /tmp/TIB_ems-ce_8.5.1
     unzip ${DIR}/docker-tibco/TIB_ems-ce_8.5.1_linux_x86_64.zip -d /tmp/
     tar xvfz /tmp/TIB_ems-ce_8.5.1/tar/TIB_ems-ce_8.5.1_linux_x86_64-java_client.tar.gz opt/tibco/ems/8.5/lib/tibjms.jar
     cp ${DIR}/opt/tibco/ems/8.5/lib/tibjms.jar ${DIR}/
     rm -rf ${DIR}/opt
fi

if test -z "$(docker images -q tibems:latest)"
then
     echo -e "\033[0;33mBuilding TIBCO EMS docker image..it can take a while...\033[0m"
     OLDDIR=$PWD
     cd ${DIR}/docker-tibco
     docker build -t tibbase:1.0.0 ./tibbase
     docker build -t tibems:latest . -f ./tibems/Dockerfile
     cd ${OLDDIR}
fi

${DIR}/../../environment/plaintext/start.sh "${PWD}/docker-compose.plaintext.yml"


echo -e "\033[0;33mSending messages to topic sink-messages\033[0m"
seq 10 | docker exec -i broker kafka-console-producer --broker-list broker:9092 --topic sink-messages

echo -e "\033[0;33mCreating TIBCO EMS sink connector\033[0m"
docker exec connect \
     curl -X PUT \
     -H "Content-Type: application/json" \
     --data '{
               "connector.class": "io.confluent.connect.jms.TibcoSinkConnector",
                    "tasks.max": "1",
                    "topics": "sink-messages",
                    "tibco.url": "tcp://tibco-ems:7222",
                    "tibco.username": "admin",
                    "tibco.password": "",
                    "jms.destination.type": "queue",
                    "jms.destination.name": "connector-quickstart",
                    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "value.converter": "org.apache.kafka.connect.storage.StringConverter",
                    "confluent.topic.bootstrap.servers": "broker:9092",
                    "confluent.topic.replication.factor": "1"
          }' \
     http://localhost:8083/connectors/tibco-ems-sink/config | jq .

sleep 5


echo -e "\033[0;33mVerify we have received the data in connector-quickstart EMS queue\033[0m"
docker exec tibco-ems bash -c '
cd /opt/tibco/ems/8.5/samples/java
export TIBEMS_JAVA=/opt/tibco/ems/8.5/lib
CLASSPATH=${TIBEMS_JAVA}/jms-2.0.jar:${CLASSPATH}
CLASSPATH=.:${TIBEMS_JAVA}/tibjms.jar:${TIBEMS_JAVA}/tibjmsadmin.jar:${CLASSPATH}
export CLASSPATH
javac *.java
java tibjmsMsgConsumer -user admin -queue connector-quickstart'
