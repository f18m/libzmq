#!/bin/bash

#
# This script assumes that 2 machines are used to generate performance results.
# First machine is assumed to be the one where this script runs.
# Second machine is the "REMOTE_IP_SSH" machine; we assume to have passwordless SSH access.
#
# Usage example:
#    export REMOTE_IP_SSH=10.0.0.1
#    export LOCAL_TEST_ENDPOINT="tcp://192.168.1.1:1234"
#    export REMOTE_TEST_ENDPOINT="tcp://192.168.1.2:1234"
#    export REMOTE_LIBZMQ_PATH="/home/fmontorsi/libzmq/perf"
#    export MESSAGE_SIZE_LIST="8 16 32 64 128 210"
#    export BENCHMARKS="tcp"  # e.g. to run only TCP tests
#    ./generate_csv.sh
#

set -u

# configurable values (via environment variables):
REMOTE_IP_SSH=${REMOTE_IP_SSH:-127.0.0.1}
REMOTE_LIBZMQ_PATH=${REMOTE_LIBZMQ_PATH:-/root/libzmq/perf}
LOCAL_TEST_ENDPOINT=${LOCAL_TEST_ENDPOINT:-tcp://192.168.1.1:1234}
REMOTE_TEST_ENDPOINT=${REMOTE_TEST_ENDPOINT:-tcp://192.168.1.2:1234}
MESSAGE_SIZE_LIST="${MESSAGE_SIZE_LIST:-8 16 32 64 128 256 512 1024 2048 4096 8192 16384 32768 65536 131072}"
BENCHMARKS="${BENCHMARKS:-tcp inproc}"
REPETITIONS="${REPETITIONS:-3}"
NUM_MSGS="${NUM_MSGS:-10000000}"

# constant values:
OUTPUT_DIR="results"
OUTPUT_FILE_PREFIX="results.txt"
OUTPUT_FILE_CSV_PREFIX="results.csv"


# utility functions:

function print_config()
{
    echo "*** Benchmarking configuration: ***"
    echo "REMOTE_IP_SSH=$REMOTE_IP_SSH"
    echo "REMOTE_LIBZMQ_PATH=$REMOTE_LIBZMQ_PATH"
    echo "LOCAL_TEST_ENDPOINT=$LOCAL_TEST_ENDPOINT"
    echo "REMOTE_TEST_ENDPOINT=$REMOTE_TEST_ENDPOINT"
    echo "MESSAGE_SIZE_LIST=$MESSAGE_SIZE_LIST"
    echo "BENCHMARKS=$BENCHMARKS"
    echo "REPETITIONS=$REPETITIONS"
    echo "NUM_MSGS=$NUM_MSGS"
    echo "*** End of benchmarking configuration ***"
}

function verify_ssh()
{
    ssh $REMOTE_IP_SSH "ls /" >/dev/null
    if [ $? -ne 0 ]; then
        echo "Cannot connect via SSH passwordless to the REMOTE_IP_SSH $REMOTE_IP_SSH. Please fix the problem and retry."
        exit 2
    fi

    ssh $REMOTE_IP_SSH "ls $REMOTE_LIBZMQ_PATH" >/dev/null
    if [ $? -ne 0 ]; then
        echo "The folder $REMOTE_LIBZMQ_PATH is not valid. Please fix the problem and retry."
        exit 2
    fi

    echo "SSH connection to the remote $REMOTE_IP_SSH is working fine."
}

function set_reproducible_tcp_kernel_buff_size()
{
    sysctl -w net.core.rmem_max=8388608 && \
        sysctl -w net.core.wmem_max=8388608 && \
        sysctl -w net.core.rmem_default=65536 && \
        sysctl -w net.core.wmem_default=65536 && \
        sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' && \
        sysctl -w net.ipv4.tcp_wmem='4096 65536 8388608' && \
        sysctl -w net.ipv4.tcp_mem='8388608 8388608 8388608' && \
        sysctl -w net.ipv4.route.flush=1
    if [ $? -ne 0 ]; then
        echo "Failed setting kernel socket buffer sizes LOCALLY"
        exit 2
    fi

    ssh $REMOTE_IP_SSH "sysctl -w net.core.rmem_max=8388608 && \
        sysctl -w net.core.wmem_max=8388608 && \
        sysctl -w net.core.rmem_default=65536 && \
        sysctl -w net.core.wmem_default=65536 && \
        sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' && \
        sysctl -w net.ipv4.tcp_wmem='4096 65536 8388608' && \
        sysctl -w net.ipv4.tcp_mem='8388608 8388608 8388608' && \
        sysctl -w net.ipv4.route.flush=1"
    if [ $? -ne 0 ]; then
        echo "Failed setting kernel socket buffer sizes on the REMOTE system $REMOTE_IP_SSH"
        exit 2
    fi
}

function run_remote_perf_util()
{
    local MESSAGE_SIZE_BYTES="$1"
    local REMOTE_PERF_UTIL="$2"
    local NUM_MESSAGES="$3"

    echo "Launching on $REMOTE_IP_SSH the utility [$REMOTE_PERF_UTIL] for messages ${MESSAGE_SIZE_BYTES}B long"
    ssh $REMOTE_IP_SSH "$REMOTE_LIBZMQ_PATH/$REMOTE_PERF_UTIL $TEST_ENDPOINT $MESSAGE_SIZE_BYTES $NUM_MESSAGES" &
    if [ $? -ne 0 ]; then
        echo "Failed to launch remote perf util."
        exit 2
    fi
}

function generate_output_file()
{
    local LOCAL_PERF_UTIL="$1"     # must be the utility generating the TXT output
    local REMOTE_PERF_UTIL="$2"
    local OUTPUT_FILE_PREFIX="$3"
    local NUM_MESSAGES="$4"
    local NUM_REPETITIONS="$5"
    local CSV_HEADER_LINE="$6"

    # derived values:
    local OUTPUT_FILE_TXT="${OUTPUT_DIR}/${OUTPUT_FILE_PREFIX}.txt"         # useful just for human-friendly debugging
    local OUTPUT_FILE_CSV="${OUTPUT_DIR}/${OUTPUT_FILE_PREFIX}.csv"     # actually used to later produce graphs
    local MESSAGE_SIZE_ARRAY=($MESSAGE_SIZE_LIST)

    echo "Killing still-running ZMQ performance utils, if any"
    pkill $LOCAL_PERF_UTIL                       # in case it's running from a previous test
    if [ ! -z "$REMOTE_PERF_UTIL" ]; then
        ssh $REMOTE_IP_SSH "pkill $REMOTE_PERF_UTIL"     # in case it's running from a previous test
    fi

    echo "Resetting output file $OUTPUT_FILE_TXT and $OUTPUT_FILE_CSV"
    mkdir -p ${OUTPUT_DIR}
    > $OUTPUT_FILE_TXT
    echo "$CSV_HEADER_LINE" > $OUTPUT_FILE_CSV

    for RUN_IDX in $(seq 1 $NUM_REPETITIONS); do
        echo "Running repetition $RUN_IDX/$NUM_REPETITIONS"
        for MESSAGE_SIZE in ${MESSAGE_SIZE_ARRAY[@]}; do
            echo "Launching locally the utility [$LOCAL_PERF_UTIL] for messages ${MESSAGE_SIZE}B long"
            ./$LOCAL_PERF_UTIL $TEST_ENDPOINT $MESSAGE_SIZE $NUM_MESSAGES >${OUTPUT_FILE_TXT}-${MESSAGE_SIZE} &

            if [ ! -z "$REMOTE_PERF_UTIL" ]; then
                run_remote_perf_util $MESSAGE_SIZE $REMOTE_PERF_UTIL $NUM_MESSAGES
            fi
            wait

            # produce the complete human-readable output file:
            cat ${OUTPUT_FILE_TXT}-${MESSAGE_SIZE} >>${OUTPUT_FILE_TXT}

            # produce a machine-friendly file for later plotting:
            local DATALINE="$(cat ${OUTPUT_FILE_TXT}-${MESSAGE_SIZE} | grep -o '[0-9.]*' | tr '\n' ',')"
            echo ${DATALINE::-1} >>$OUTPUT_FILE_CSV
            rm -f ${OUTPUT_FILE_TXT}-${MESSAGE_SIZE}
        done

        sleep 3
    done
    echo "All measurements completed and saved into $OUTPUT_FILE_TXT and $OUTPUT_FILE_CSV"
}



# main:

print_config
verify_ssh
set_reproducible_tcp_kernel_buff_size

THROUGHPUT_CSV_HEADER_LINE="# message_size,message_count,PPS[msg/s],throughput[Mb/s]"

if [[ $BENCHMARKS =~ .*"tcp".* ]]; then
    # PUSH/PULL TCP throughput CSV file:
    TEST_ENDPOINT="$LOCAL_TEST_ENDPOINT"
    generate_output_file "local_thr" "remote_thr" \
        "pushpull_tcp_thr_results" \
        "$NUM_MSGS" \
        "$REPETITIONS" \
        "$THROUGHPUT_CSV_HEADER_LINE"

    # REQ/REP TCP latency CSV file:
    # NOTE: in this case it's the remote_lat utility that prints out the data, so we swap the local/remote arguments to the bash func:
    TEST_ENDPOINT="$REMOTE_TEST_ENDPOINT"
    generate_output_file "remote_lat" "local_lat" \
        "reqrep_tcp_lat_results" \
        "$NUM_MSGS" \
        "$REPETITIONS" \
        "# message_size,message_count,latency[us]"
fi

if [[ $BENCHMARKS =~ .*"inproc".* ]]; then
    # PUSH/PULL INPROC throughput CSV file:
    # NOTE: in this case there is no remote utility to run and no ENDPOINT to provide:
    TEST_ENDPOINT=""  # inproc does not require any endpoint
    generate_output_file "inproc_thr" "" \
        "pushpull_inproc_thr_results" \
        "$NUM_MSGS" \
        "$REPETITIONS" \
        "$THROUGHPUT_CSV_HEADER_LINE"

    # PUB/SUB proxy INPROC throughput CSV file:
    # NOTE: in this case there is no remote utility to run and no ENDPOINT to provide:
    TEST_ENDPOINT="" # inproc does	not require any	endpoint
    generate_output_file "proxy_thr" "" \
        "pubsubproxy_inproc_thr_results" \
        "$NUM_MSGS" \
        "$REPETITIONS" \
        "$THROUGHPUT_CSV_HEADER_LINE"
fi

