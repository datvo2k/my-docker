#!/bin/bash
set -e

function setup_signals {
    echo "[entrypoint.sh] Setup shutdown signals"
    cid="$1"
    shift
    handler="$1"
    shift
    for sig; do
        trap "$handler '$cid' '$sig'" "$sig"
    done
}

function handle_signal {
    case "$2" in
    SIGINT)
        stop_mongod
        ;;
    SIGTERM)
        stop_mongod
        ;;
    SIGHUP)
        stop_mongod
        ;;
    esac
}

setup_signals "$1" "handle_signal" SIGINT SIGTERM SIGHUP

create_data_dir() {
    echo "[entrypoint.sh] Create Mongo Data Dir <${MONGO_DATA_DIR}>"
    mkdir -p ${MONGO_DATA_DIR}
    chmod -R 0755 ${MONGO_DATA_DIR}
}

stop_mongod() {
    echo "[entrypoint.sh] Stop MongoDb"
    PID=$(pgrep mongod)
    if [[ ${MONGO_REPLICA_SET_NAME} != 'NONE' && ${MONGO_REPLICA_SET_NAME} != '' ]]; then
        mongosh --quiet admin --port ${MONGO_PORT} --eval 'db.adminCommand( { replSetStepDown: 120, secondaryCatchUpPeriodSecs: 0, force: true } );' | true
    fi
    mongosh --quiet admin --port ${MONGO_PORT} --eval 'db.shutdownServer();' | true
    while ps -p $PID &>/dev/null; do
        sleep 1
    done
    echo "[entrypoint.sh] MongoDB stopped"
}

create_data_dir

if [[ ${1:0:1} = '-' ]]; then
    EXTRA_ARGS="$@"
    set --
elif [[ ${1} == mongod || ${1} == $(which mongod) ]]; then
    EXTRA_ARGS="${@:2}"
    set --
fi

if [[ ${MONGO_WIREDTIGER_CACHE_SIZE_GB} != 'NONE' ]]; then
    echo "[entrypoint.sh] Added wiredTigerMaxMemory to ${MONGO_WIREDTIGER_CACHE_SIZE_GB}"
    MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --wiredTigerCacheSizeGB ${MONGO_WIREDTIGER_CACHE_SIZE_GB}"
fi

echo "[entrypoint.sh] Set StorageEngine to <${MONGO_STORAGEENGINE}>"
MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --storageEngine ${MONGO_STORAGEENGINE}"

echo "[entrypoint.sh] Set IpBinding to <${MONGO_BINDING}>"
MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} ${MONGO_BINDING}"

if [[ ${MONGO_MAX_CONNECTIONS} != 'NONE' ]]; then
    echo "[entrypoint.sh] Set Max Connections to <${MONGO_MAX_CONNECTIONS}>"
    MONGO_MAX_CONNECTIONS="${MONGO_EXTRA_ARGS} --maxConns ${MONGO_MAX_CONNECTIONS}"
fi

echo "[entrypoint.sh] Upgrade MongoDb stored files if needed"
mongod --port ${MONGO_PORT} --upgrade --dbpath ${MONGO_DATA_DIR} ${MONGO_EXTRA_ARGS}

echo "[entrypoint.sh] Starting MongoDb for upgrade Information"
mongod --port ${MONGO_PORT} --fork --syslog --dbpath ${MONGO_DATA_DIR} 2>&1

MONGODB_SHORT=$(cat mongoshort.txt)

echo "[entrypoint.sh] Set Version to ${MONGODB_SHORT}"
mongosh --quiet admin --port ${MONGO_PORT} --eval "db.adminCommand( { setFeatureCompatibilityVersion: '"${MONGODB_SHORT}"', confirm: true } );"
mongosh --quiet admin --port ${MONGO_PORT} --eval "db.adminCommand( { getParameter: 1, featureCompatibilityVersion: 1 } );"

if [[ ${MONGO_ROOT_PWD} != 'NONE' && ${MONGO_ROOT_PWD} != '' ]]; then
    echo "[entrypoint.sh] Admin User to Database"
    mongosh --quiet admin --port ${MONGO_PORT} --eval "db.dropUser('${MONGO_ROOT_USERNAME}');" | true
    mongosh --quiet admin --port ${MONGO_PORT} --eval "db.createUser({'user': '${MONGO_ROOT_USERNAME}','pwd': '${MONGO_ROOT_PWD}','roles': [ 'root' ]});"
fi

if [[ ${MONGO_REPLICA_SET_NAME} == 'Standalone0' ]]; then
    echo "[entrypoint.sh] remove replicaSet definition for 'Standalone0' replicaSet"
    mongosh --quiet local --port ${MONGO_PORT} --eval "db.dropDatabase();"
fi

echo "[entrypoint.sh] Stop MongoDb for insert USER or Update Feature Version ..."
stop_mongod

if [[ ${MONGO_REPLICA_SET_NAME} != 'NONE' && ${MONGO_REPLICA_SET_NAME} != '' ]]; then
    echo "[entrypoint.sh] use ReplicaSet definition"
    MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --replSet ${MONGO_REPLICA_SET_NAME}"

    echo "[entrypoint.sh] Starting MongoDb for checking and initiate ReplicaSet"
    mongod --port ${MONGO_PORT} --fork --syslog --dbpath ${MONGO_DATA_DIR} ${MONGO_EXTRA_ARGS} 2>&1

    echo "[entrypoint.sh] initiate ReplicaSet"
    mongosh --quiet admin --port ${MONGO_PORT} --eval "rs.initiate()"
    echo "[entrypoint.sh] Stop mongodb for initiate ReplicaSet"
    stop_mongod
fi

if [[ ${MONGO_ROOT_PWD} != 'NONE' ]]; then
    if [[ ${MONGO_REPLICA_SET_NAME} != 'NONE' && ${MONGO_REPLICA_SET_NAME} != '' ]]; then
        if [[ ${MONGO_REPLICA_KEY} != 'RANDOM' && ${MONGO_REPLICA_KEY} != '' ]]; then
            echo "[entrypoint.sh] use given replica key"
            echo ${MONGO_REPLICA_KEY} >${MONGO_DATA_DIR}/replica.key
        else
            echo "[entrypoint.sh] generate random replica key"
            openssl rand -base64 741 >${MONGO_DATA_DIR}/replica.key
        fi
        echo "[entrypoint.sh] chmod replica.key"
        chmod 400 ${MONGO_DATA_DIR}/replica.key
        echo "[entrypoint.sh] chown replica.key"
        chown 999:999 ${MONGO_DATA_DIR}/replica.key
        MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --keyFile ${MONGO_DATA_DIR}/replica.key"
    fi
    MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --auth"
fi

if [[ ${MONGO_LOG} != 'NONE' && ${MONGO_LOG} != '' ]]; then
    echo "[entrypoint.sh] set logpath"
    if [[ ${MONGO_LOG} == 'stdout' || ${MONGO_LOG} == 'STDOUT' ]]; then
        echo "[entrypoint.sh] set logpath to stdout"
        MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --logpath /proc/$$/fd/1"

        chown --dereference mongodb "/proc/$$/fd/1" "/proc/$$/fd/2" || :
    else
        echo "[entrypoint.sh] set logpath to ${MONGO_LOG}"
        MONGO_EXTRA_ARGS="${MONGO_EXTRA_ARGS} --logpath ${MONGO_LOG}"
    fi
    echo "[entrypoint.sh] Starting mongod..."
    echo "[entrypoint.sh] Arguments on mongod startup $MONGO_EXTRA_ARGS"
    mongod --port ${MONGO_PORT} --dbpath ${MONGO_DATA_DIR} ${MONGO_EXTRA_ARGS} --fork 2>&1
    if [[ ${MONGO_LOG} != 'stdout' && ${MONGO_LOG} != 'STDOUT' ]]; then
        echo "[entrypoint.sh] Start following the mongodb log"
        tail -f "${MONGO_LOG}"
    else
        PID=$(pgrep mongod)
        while ps -p $PID &>/dev/null; do
            sleep 10
        done
    fi
else
    echo "[entrypoint.sh] Starting mongod..."
    echo "[entrypoint.sh] Arguments on mongod startup $MONGO_EXTRA_ARGS"
    mongod --port ${MONGO_PORT} --dbpath ${MONGO_DATA_DIR} ${MONGO_EXTRA_ARGS} --syslog --fork 2>&1
    PID=$(pgrep mongod)
    while ps -p $PID &>/dev/null; do
        sleep 10
    done
fi
