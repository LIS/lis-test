#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

LOG_FILE=/tmp/summary.log
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1} >> ${LOG_FILE}
}

if [ $# -lt 3 ]; then
    echo -e "\nUsage:\n$0 server user test_type"
    exit 1
fi

SERVER="$1"
USER="$2"
TEST_TYPE="$3"

if [ -e /tmp/summary.log ]; then
    rm -rf /tmp/summary.log
fi

distro="$(head -1 /etc/issue)"
if [[ ${distro} == *"Ubuntu"* ]]
then
    sudo apt update
    # solving gce ubuntu kernel package upgrades and dependencies
    sudo apt install -y aptitude
    printf '.\n.\n.\n.\nY\nY\n' |sudo aptitude install build-essential >> ${LOG_FILE}
    sudo apt -y install build-essential >> ${LOG_FILE}
    sudo apt -y install sysstat zip bc cmake>> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt update"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt install -y aptitude"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "printf '.\n.\n.\n.\nY\nY\n' |sudo aptitude install build-essential"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install sysstat zip bc build-essential cmake" >> ${LOG_FILE}
elif [[ ${distro} == *"Amazon"* ]]
then
    sudo yum clean dbcache >> ${LOG_FILE}
    sudo yum -y install sysstat zip bc git gcc automake autoconf rpm cmake>> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum clean dbcache" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo yum -y install sysstat zip bc git gcc automake autoconf rpm cmake" >> ${LOG_FILE}
else
    LogMsg "Unsupported distribution: ${distro}."
fi
sudo iptables -F >> ${LOG_FILE}
ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo iptables -F" >> ${LOG_FILE}
mkdir -p /tmp/network${TEST_TYPE}
cd /tmp
if [[ ${TEST_TYPE} == "TCP" ]]
then
    TEST_THREADS=(1 2 4 8 16 32 64 128 256 512 1024 2048 4096 6144 8192 10240)
    cd /tmp; git clone https://github.com/Microsoft/ntttcp-for-linux
    cd /tmp/ntttcp-for-linux/src; sudo make && sudo make install
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/ntttcp-for-linux" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/ntttcp-for-linux/src; sudo make && sudo make install" >> ${LOG_FILE}
    cd /tmp; git clone https://github.com/Microsoft/lagscope >> ${LOG_FILE}
    cd /tmp/lagscope; sudo ./do-cmake.sh build && sudo ./do-cmake.sh install >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/lagscope" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/lagscope; sudo ./do-cmake.sh build && sudo ./do-cmake.sh install" >> ${LOG_FILE}
elif [[ ${TEST_TYPE} == "latency" ]]
then
    cd /tmp; git clone https://github.com/Microsoft/lagscope
    cd /tmp/lagscope; sudo ./do-cmake.sh build && sudo ./do-cmake.sh install >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; git clone https://github.com/Microsoft/lagscope" >> ${LOG_FILE}
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp/lagscope; sudo ./do-cmake.sh build && sudo ./do-cmake.sh install" >> ${LOG_FILE}
elif [[ ${TEST_TYPE} == "UDP" ]]
then
    TEST_THREADS=(1 2 4 8 16 32 64 128 256 512 1024)
    MAX_STREAMS=128
    TEST_BUFFERS=('1k' '8k')
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        sudo apt -y install iperf3 >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install iperf3" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm" >> ${LOG_FILE}
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
elif [[ ${TEST_TYPE} == "single_tcp" ]]
then
    TEST_BUFFERS=(32 64 128 256 512 1024 2048 4096 8192 16384 32768 65536)
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        sudo apt -y install iperf3 >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install iperf3" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm" >> ${LOG_FILE}
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
elif [[ ${TEST_TYPE} == "custom" ]]
then
    TEST_BUFFERS=('64k' '128k')
    if [[ ${distro} == *"Ubuntu"* ]]
    then
        sudo apt -y install iperf3 >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo apt -y install iperf3" >> ${LOG_FILE}
    elif [[ ${distro} == *"Amazon"* ]]
    then
        cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm >> ${LOG_FILE}
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "cd /tmp; wget https://iperf.fr/download/fedora/iperf3-3.1.3-1.fc24.x86_64.rpm; sudo rpm -ivh iperf3-3.1.3-1.fc24.x86_64.rpm" >> ${LOG_FILE}
    else
        LogMsg "Unsupported distribution: ${distro}."
    fi
else
    LogMsg "Unsupported test type: ${TEST_TYPE}."
fi

function get_tx_bytes(){
    local eth=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'`
    # RX bytes:66132495566 (66.1 GB)  TX bytes:3067606320236 (3.0 TB)
    local Tx_bytes=`ifconfig ${eth} | grep "TX bytes"   | awk -F':' '{print $3}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_bytes" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_bytes=`ifconfig ${eth}| grep "TX packets"| awk '{print $5}'`
    fi
    echo ${Tx_bytes}
}

function get_tx_pkts(){
    local eth=`ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}'`
    # TX packets:543924452 errors:0 dropped:0 overruns:0 carrier:0
    local Tx_pkts=`ifconfig ${eth} | grep "TX packets" | awk -F':' '{print $2}' | awk -F' ' ' {print $1}'`

    if [ "x$Tx_pkts" == "x" ]
    then
        #TX packets 223558709  bytes 15463202847 (14.4 GiB)
        Tx_pkts=`ifconfig ${eth}| grep "TX packets"| awk '{print $3}'`
    fi
    echo ${Tx_pkts}
}

ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "mkdir /tmp/network${TEST_TYPE}"

function run_lagscope()
{
    LogMsg "======================================"
    LogMsg "Running lagscope "
    LogMsg "======================================"
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f lagscope"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo lagscope -r${SERVER}"
    sleep 5
    sudo lagscope -s${SERVER} -n1000000 -i0 -H > "/tmp/network${TEST_TYPE}/lagscope.log"
    sleep 5
    sudo pkill -f lagscope
}

function run_ntttcp ()
{
    current_test_threads=$1
    LogMsg "======================================"
    LogMsg "Running NTTTCP thread= ${current_test_threads}"
    LogMsg "======================================"
    if [ ${current_test_threads} -lt 64 ]
    then
        num_threads_P=${current_test_threads}
        num_threads_n=1
    else
        num_threads_P=64
        num_threads_n=$(($current_test_threads / $num_threads_P))
    fi
    sudo pkill -f ntttcp
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f ntttcp"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo ntttcp -r${SERVER} -P $num_threads_P -e -W 1 -C 1 > /tmp/network${TEST_TYPE}/${current_test_threads}_ntttcp-receiver.log"
    sudo pkill -f lagscope
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f lagscope"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo lagscope -r${SERVER}"
    sleep 5
    previous_tx_bytes=$(get_tx_bytes)
    previous_tx_pkts=$(get_tx_pkts)
    sudo lagscope -s${SERVER} -t60 > "/tmp/network${TEST_TYPE}/${current_test_threads}_lagscope.log" &
    sudo ntttcp -s${SERVER} -P ${num_threads_P} -n ${num_threads_n} -t 60 -W 1 -C 1 > "/tmp/network${TEST_TYPE}/${current_test_threads}_ntttcp-sender.log"
    current_tx_bytes=$(get_tx_bytes)
    current_tx_pkts=$(get_tx_pkts)
    bytes_new=`(expr ${current_tx_bytes} - ${previous_tx_bytes})`
    pkts_new=`(expr ${current_tx_pkts} - ${previous_tx_pkts})`
    avg_pkt_size=$(echo "scale=2;${bytes_new}/${pkts_new}/1024" | bc)
    echo "Average Package Size: ${avg_pkt_size}" >> /tmp/network${TEST_TYPE}/${current_test_threads}_ntttcp-sender.log
    sleep 10
    sudo pkill -f ntttcp
    sudo pkill -f lagscope
    previous_tx_bytes=${current_tx_bytes}
    previous_tx_pkts=${current_tx_pkts}
}

function run_iperf_parallel(){
    current_test_threads=$1
    buffer=$2
    port=8001
    number_of_connections=${current_test_threads}
    while [ ${number_of_connections} -gt ${MAX_STREAMS} ]; do
        number_of_connections=$(($number_of_connections - $MAX_STREAMS))
        logfile="/tmp/network${TEST_TYPE}/${current_test_threads}-p${port}-l${buffer}-iperf3.log"
        iperf3 -u -c ${SERVER} -p ${port} -4 -b 0 -l ${buffer} -P ${MAX_STREAMS} -t 60 --get-server-output -i 60 > ${logfile} 2>&1 & pid=$!
        port=$(($port + 1))
        PID_LIST+=" $pid"
    done
    if [ ${number_of_connections} -gt 0 ]
    then
        logfile="/tmp/network${TEST_TYPE}/${current_test_threads}-p${port}-l${buffer}-iperf3.log"
        iperf3 -u -c ${SERVER} -p ${port} -4 -b 0 -l ${buffer} -P ${number_of_connections} -t 60 --get-server-output -i 60 > ${logfile} 2>&1 & pid=$!
        PID_LIST+=" $pid"
    fi

    trap "sudo kill ${PID_LIST}" SIGINT
    wait ${PID_LIST}
}

function run_iperf_udp()
{
    current_test_threads=$1
    buffer=$2
    LogMsg "======================================"
    LogMsg "Running iPerf3 thread= ${current_test_threads}"
    LogMsg "======================================"
    port=8001
    server_iperf_instances=$((current_test_threads/${MAX_STREAMS}+port))
    for ((i=port; i<=server_iperf_instances; i++))
    do
        ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "iperf3 -s -4 -p $i -i 60 -D"
        sleep 1
    done

    run_iperf_parallel ${current_test_threads} ${buffer}

    sleep 5
    sudo pkill -f iperf3
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iperf3" >> ${LOG_FILE}
    sleep 5
}

function run_single_tcp()
{
    current_test_buffer=$1
    LogMsg "======================================"
    LogMsg "Running iPerf3 variable packet size = ${current_test_buffer}"
    LogMsg "======================================"
    port=8001
    sudo pkill -f iperf3
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iperf3" >> ${LOG_FILE}
    sleep 10
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo iperf3 -s -4 -p ${port} -i 60 -D" >> ${LOG_FILE}
    sleep 3
    sudo iperf3 -c ${SERVER} -p ${port} -4 -b 0 -l ${current_test_buffer} -P 1 -t 60 --get-server-output -i 60 > /tmp/network${TEST_TYPE}/${current_test_buffer}-iperf3.log
}

function run_custom()
{
    current_test_buffer=$1
    LogMsg "======================================"
    LogMsg "Running iPerf3 check behaviour = ${current_test_buffer}"
    LogMsg "======================================"
    port=8001
    sudo pkill -f iperf3
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iperf3" >> ${LOG_FILE}
    sleep 10
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo iperf3 -s -4 -p ${port} -i 60 -D" >> ${LOG_FILE}
    sleep 3
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -n DEV 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.sar.netio.receiver.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "sar -P ALL 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.sar.cpu.receiver.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "iostat -x -d 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.iostat.diskio.receiver.log"
    ssh -f -o StrictHostKeyChecking=no ${USER}@${SERVER} "vmstat 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.vmstat.memory.cpu.receiver.log"
    sar -n DEV 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.sar.netio.sender.log &
    sar -P ALL 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.sar.cpu.sender.log &
    iostat -x -d 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.iostat.netio.sender.log &
    vmstat 1 2>&1 > /tmp/network${TEST_TYPE}/${current_test_buffer}.vmstat.netio.sender.log &

    sudo iperf3 -c ${SERVER} -p ${port} -4 -b 0 -l ${current_test_buffer} -P 64 -t 60 --get-server-output -i 60 > /tmp/network${TEST_TYPE}/${current_test_buffer}-iperf3.log

    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f sar"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f iostat"
    ssh -T -o StrictHostKeyChecking=no ${USER}@${SERVER} "sudo pkill -f vmstat"
    sudo pkill -f sar
    sudo pkill -f iostat
    sudo pkill -f vmstat
}

if [[ ${TEST_TYPE} == "TCP" ]]
then
    ulimit -n 204800
    ssh -o StrictHostKeyChecking=no ${USER}@${SERVER} "ulimit -n 204800"
    for thread in "${TEST_THREADS[@]}"
    do
        run_ntttcp ${thread}
    done
elif [[ ${TEST_TYPE} == "latency" ]]
then
    run_lagscope
elif [[ ${TEST_TYPE} == "UDP" ]]
then
    for buffer in "${TEST_BUFFERS[@]}"
    do
        for thread in "${TEST_THREADS[@]}"
        do
            run_iperf_udp ${thread} ${buffer}
        done
        # Wait a while before running next buffer size
        sleep 300
    done
elif [[ ${TEST_TYPE} == "single_tcp" ]]
then
    for packet in "${TEST_BUFFERS[@]}"
    do
        run_single_tcp ${packet}
    done
elif [[ ${TEST_TYPE} == "custom" ]]
then
    for buffer in "${TEST_BUFFERS[@]}"
    do
        run_custom ${buffer}
    done
    scp -o StrictHostKeyChecking=no ${USER}@${SERVER}:/tmp/network${TEST_TYPE}/* /tmp/network${TEST_TYPE}/ >> ${LOG_FILE}
else
    LogMsg "Unsupported test type: ${TEST_TYPE}."
fi

LogMsg "Kernel Version : `uname -r`"
LogMsg "Guest OS : ${distro}"

cd /tmp
zip -r network.zip . -i network${TEST_TYPE}/* >> ${LOG_FILE}
zip -r network.zip . -i summary.log >> ${LOG_FILE}
