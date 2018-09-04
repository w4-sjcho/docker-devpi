#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

function generate_password() {
    # We disable exit on error because we close the pipe
    # when we have enough characters, which results in a
    # non-zero exit status
    set +e
    tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1 | tr -cd '[:alnum:]'
    set -e
}


function kill_devpi() {
    _PID=$(cat "$DEVPI_SERVER_ROOT/.xproc/devpi-server/xprocess.PID")
    echo "ENTRYPOINT: Sending SIGTERM to PID $_PID"
    kill -SIGTERM "$_PID"
}

if [ "${1:-}" == "bash" ]; then
    exec "$@"
fi

DEVPI_ROOT_PASSWORD_FILE="${DEVPI_ROOT_PASSWORD_FILE:-$DEVPI_SERVER_ROOT/.root_password}"
DEVPI_ROOT_PASSWORD="${DEVPI_ROOT_PASSWORD:-}"
if [ -f "$DEVPI_ROOT_PASSWORD_FILE" ]; then
    DEVPI_ROOT_PASSWORD=$(cat "$DEVPI_ROOT_PASSWORD_FILE")
elif [ -z "$DEVPI_ROOT_PASSWORD" ]; then
    DEVPI_ROOT_PASSWORD=$(generate_password)
fi

if [ ! -d "$DEVPI_SERVER_ROOT" ]; then
    echo "ENTRYPOINT: Creating devpi-server root"
    mkdir -p "$DEVPI_SERVER_ROOT"
fi

initialize=no
if [ ! -f "$DEVPI_SERVER_ROOT/.serverversion" ]; then
    initialize=yes
    echo "ENTRYPOINT: Initializing server root $DEVPI_SERVER_ROOT"
    devpi-server --init --serverdir "$DEVPI_SERVER_ROOT"
fi

echo "ENTRYPOINT: Starting devpi-server"
devpi-server --start --host 0.0.0.0 --port 3141 --serverdir "$DEVPI_SERVER_ROOT" --theme semantic-ui "$@"

echo "ENTRYPOINT: Installing signal traps"
trap kill_devpi SIGINT SIGTERM

if [ "$initialize" == "yes" ]; then
    echo "ENTRYPOINT: Initializing devpi-server"
    devpi use http://localhost:3141
    devpi login root --password=''
    if [ -f "$DEVPI_ROOT_PASSWORD_FILE" ]; then
      echo "ENTRYPOINT: Setting root password from file $DEVPI_ROOT_PASSWORD_FILE"
    else
      echo "ENTRYPOINT: Setting root password to $DEVPI_ROOT_PASSWORD"
      echo -n "$DEVPI_ROOT_PASSWORD" > "$DEVPI_ROOT_PASSWORD_FILE"
    fi
    devpi user -m root "password=$DEVPI_ROOT_PASSWORD"
    devpi logoff
fi

echo "ENTRYPOINT: Tailing log"
tail -f "$DEVPI_SERVER_ROOT/.xproc/devpi-server/xprocess.log" &

echo "ENTRYPOINT: Watching devpi-server"
PID=$(cat "$DEVPI_SERVER_ROOT/.xproc/devpi-server/xprocess.PID")

if [ -z "$PID" ]; then
    echo "ENTRYPOINT: Could not determine PID of devpi-server!"
    exit 1
fi

set +e

while : ; do
    kill -0 "$PID" > /dev/null 2>&1 || break
    sleep 2s
done

echo "ENTRYPOINT: devpi-server died, exiting..."
