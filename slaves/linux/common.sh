#bash

check_arg() {
	name="$1"; shift
	arg="$1"; shift

	if [ -z "${arg:-}" ]; then
		echo >&2 "No $name given."
		exit 1
	fi
	if [[ "$arg" =~ [^A-Za-z0-9.-] ]]; then
		echo >&2 "Invalid $name: $arg."
		exit 1
	fi
	if [[ "$arg" =~ \.\. ]]; then
		echo >&2 "Invalid $name: $arg."
		exit 1
	fi
}
cleanup() {
	if ! [ -z "{$chroot:-}" ]; then
		echo "Clean up build environment."
		schroot --end-session --chroot "$chroot"
	fi
}

init_args() {
	check_arg "node_name" "${NODE_NAME:-}"
	check_arg "suite" "${SUITE:-}"
	check_arg "architecture" "${ARCHITECTURE:-}"
	jobname=${JOB_NAME%%/*}
	check_arg "job's name" "${jobname:-}"
}

relay_to_remote() {
	local what
	what="$1"
	shift

	local sync_to_remote
	local sync_from_remote
	local fp
	local i

	if [ -n "${1:-}" ]; then
		sync_to_remote=("${!1}")
	else
		sync_to_remote=()
	fi
	if [ -n "${2:-}" ]; then
		sync_from_remote=("${!2}")
	else
		sync_from_remote=()
	fi

	hostname=$(hostname -f)
	if [ "$hostname" != $NODE_NAME ] ; then
		case $NODE_NAME in
			build-arm-0[0-3].torproject.org)
				for i in "${sync_from_remote[@]}"; do
					echo "[$hostname] Syncing $i to $NODE_NAME"
					fp=$(realpath --relative-to=/home/jenkins ./$i)
					ssh "$NODE_NAME" "mkdir -p $(dirname $fp)"
					rsync -ravz --delete "$i/." "$NODE_NAME:$fp"
				done
				echo "[$hostname] Forwarding build request to $NODE_NAME."
				set -x
				fp=$(realpath --relative-to=/home/jenkins .)
				ssh -o BatchMode=yes -tt "$NODE_NAME" "(cd jenkins-tools && git pull) && mkdir -p '$fp' && cd '$fp' && NODE_NAME='$NODE_NAME' SUITE='$SUITE' ARCHITECTURE='$ARCHITECTURE' JOB_NAME='$JOB_NAME' ~/jenkins-tools/$what"
				for i in "${sync_from_remote[@]}"; do
					echo "[$hostname] Syncing $i from $NODE_NAME"
					fp=$(realpath --relative-to=/home/jenkins ./$i)
					rsync -ravz --delete "$NODE_NAME:$fp/." "$i"
				done
				echo "[$hostname] Exiting successfully."
				exit 0
				;;
			*)
				echo >&2 "Node name mismatch: We are $hostname, but NODE_NAME is $NODE_NAME."
				exit 1
				;;
		esac
	fi
}
