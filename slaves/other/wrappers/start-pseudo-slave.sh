#!/bin/bash

set -e
set -u

if [ "$#" != 1 ]; then
  echo >&2 "Usage: $0 <NODE_NAME>"
  exit 1
fi

MYLOGNAME="`basename "$0"`[$$]"
info() {
  logger -s -p user.info -t "$MYLOGNAME" "$1"
}
croak() {
  logger -s -p user.warn -t "$MYLOGNAME" "$1"
  exit 1
}


NODE_NAME=${1:-}
hostname=$(hostname -f)

pidnc1=""
pidnc2=""
pidjenkins=""

#set -x

case "$NODE_NAME" in
  build-arm-0[0-3].torproject.org)
    info "[$hostname] Updating jenkins-tools on $NODE_NAME:"
    ssh -o BatchMode=yes "$NODE_NAME" "(cd jenkins-tools && git pull)" < /dev/null

    # the lock is held by the liveness check child look until the loop is
    # established.
    # if the lock is released and the file still exists, things are ok.
    lock_flag=$(tempfile)
    exec 200< "$lock_flag"
    flock -x -w 0 200

    info "[$hostname] Starting liveness loop for $NODE_NAME"
    mainpid="$$"
    (
      portlistennc=$(($RANDOM % 60000 + 1500))
      portlistenssh=$(($RANDOM % 60000 + 1500))
      portpipessh=$(($RANDOM % 60000 + 1500))
      nc -l -p $portlistennc > /dev/null < /dev/null 200< /dev/null & pidnc1=$!
      ssh -o BatchMode=yes -o ExitOnForwardFailure=yes -L $portlistenssh:localhost:$portpipessh  -R $portpipessh:localhost:$portlistennc "$NODE_NAME" -f -n sleep 10 > /dev/null < /dev/null 200< /dev/null
      ( while : ; do echo . ; sleep 10; done | nc localhost $portlistenssh ) > /dev/null < /dev/null 200< /dev/null & pidnc2=$!

      if ! kill -0 $pidnc1 || ! kill -0 $pidnc2 ; then
        rm -f "$lock_flag"
        croak "Slave ssh not connected."
      fi

      # things are established
      flock -u 200

      info "[$hostname] In child, liveness loop for $NODE_NAME starting.  pidnc1=$pidnc1, pidnc2=$pidnc2"
      while : ; do
        if ! kill -0 $pidnc1 || ! kill -0 $pidnc2 ; then
          kill $mainpid $pidnc2 $pidnc1 || true
          croak "ssh pipe died"
        elif ! kill -0 $mainpid; then
          kill $pidnc2 $pidnc1 || true
          croak "jenkins slave terminated, killing liveness loop"
        fi
        sleep 30
      done
    ) & child=$!
    flock -u 200

    if ! flock -x -w 10 200; then
      kill $child
      rm -f "$lock_flag"
      croak "Could not acquire lock on flag file - probably slave ssh alive loop failed."
    fi
    if ! [ -e "$lock_flag" ]; then
      kill $child
      croak "Lock flag is gone - probably slave ssh alive loop failed."
    fi

    rm -f "$lock_flag"
    exec java -jar ~/slave.jar
    ;;
  *)
    croak "$0 Unknown node name $NODE_NAME"
    ;;
esac
