#!/bin/bash

verify_installed()
{
  local cmd="$1"
  if [[ $(type $cmd 2>&1) =~ "not found" ]]; then
    echo -e "\nERROR: This script requires '$cmd'. Please install '$cmd' and run again.\n"
    exit 1
  fi
}
verify_installed "docker-compose"

docker-compose down -v
docker-compose up -d

echo -e "\033[0;33mInvoke manual steps\033[0m"
docker exec -i ksql-cli bash -c 'echo -e "\n\n⏳ Waiting for KSQL to be available before launching CLI\n"; while [ $(curl -s -o /dev/null -w %{http_code} http://ksql-server:8088/) -eq 000 ] ; do echo -e $(date) "KSQL Server HTTP state: " $(curl -s -o /dev/null -w %{http_code} http:/ksql-server:8088/) " (waiting for 200)" ; sleep 10 ; done; ksql http://ksql-server:8088' << EOF

CREATE STREAM ratings (id INT, rating DOUBLE)
    WITH (kafka_topic='ratings',
          partitions=2,
          value_format='avro');

INSERT INTO ratings (id, rating) VALUES (294, 8.2);
INSERT INTO ratings (id, rating) VALUES (294, 8.5);
INSERT INTO ratings (id, rating) VALUES (354, 9.9);
INSERT INTO ratings (id, rating) VALUES (354, 9.7);
INSERT INTO ratings (id, rating) VALUES (782, 7.8);
INSERT INTO ratings (id, rating) VALUES (782, 7.7);
INSERT INTO ratings (id, rating) VALUES (128, 8.7);
INSERT INTO ratings (id, rating) VALUES (128, 8.4);
INSERT INTO ratings (id, rating) VALUES (780, 2.1);

SET 'auto.offset.reset' = 'earliest';

SELECT ROWKEY, ID, RATING
FROM RATINGS
LIMIT 9;

CREATE STREAM RATINGS_REKEYED
    WITH (KAFKA_TOPIC='ratings_keyed_by_id') AS
    SELECT *
    FROM RATINGS
    PARTITION BY ID;

SELECT ROWKEY, ID, RATING
FROM RATINGS_REKEYED
LIMIT 9;

PRINT 'ratings_keyed_by_id' FROM BEGINNING LIMIT 9;

EOF


echo -e "\033[0;33mInvoke the tests\033[0m"
docker exec ksql-cli ksql-test-runner -i /opt/app/test/input.json -s opt/app/src/statements.sql -o /opt/app/test/output.json