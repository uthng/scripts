#!/bin/sh
set -x

IPT_FILTER_FLUSH="iptables -F"
IPT_FILTER_DELETE="iptables -X"

IPT_NAT_FLUSH="iptables -t nat -F"
IPT_NAT_DELETE="iptables -t nat -X"

IPT_INPUT_POLICY="iptables -P INPUT"
IPT_FORWARD_POLICY="iptables -P FORWARD"
IPT_OUTPUT_POLICY="iptables -P OUTPUT"

IPT_APPEND_PREROUTING="iptables -t nat -A PREROUTING"
IPT_DELETE_PREROUTING="iptables -t nat -D PREROUTING"

IPT_APPEND_POSTROUTING="iptables -t nat -A POSTROUTING"
IPT_DELETE_POSTROUTING="iptables -t nat -D POSTROUTING"

IPT_APPEND_FORWARD="iptables -A FORWARD"

IPT_APPEND_INPUT="iptables -t filter -A INPUT"
IPT_APPEND_OUTPUT="iptables -t filter -A OUTPUT"

IPT_SAVE="iptables-save"

IFACE="eth0"

help() {
    echo "$0: script configuring iptables to route packets"
    echo "    between high and low modules of L2003 board"
    echo "Usage: "
    echo "      $0 <operation_type> <iface> <port_list> <high_link_iface> <high_link_ip> <low_link_iface> <low_link_ip> <low_out_iface> <low_out_ip> <dest_ip>"
    echo "Params:" 
    echo "      operation_type: a | d (a: adding new rules without erasing existing rules; d: create rules by deleting all existing rules"
    echo "      iface: in interface"
    echo "      port_list: list of ports to forward"
    echo "      high_link_iface: interface in high module connecting high and low modules"
    echo "      high_link_ip: high link interface IP"
    echo "      low_link_iface: interface in low module connecting high and low modules"
    echo "      low_link_ip: low link interface IP"
    echo "      low_out_iface: out interface in low module connect to outside world"
    echo "      low_out_ip: low out interface IP"
    echo "      dest_ip: destination IP connected to low module"
}

upper() {
    echo "$1" | tr a-z A-Z
}

#ap_allow_mac_addresses() {
    #local IFACE=$1
    #local FILE=$2

    ## Read file filter for list of authorized mac addresses
    #cat ${FILE} | while read LINE
    #do
        ## Accept incoming 443 for these mac addresses
        #echo "--- Allow incoming mac address ${LINE} on port 443 on ${IFACE} --------------"
        #${IPT_APPEND_INPUT} -i ${IFACE} -p tcp --dport 443 -m mac --mac-source ${LINE} -j ACCEPT
    #done

    ## Accept outcoming 443 for these mac addresses
    #echo "---- Allow outcoming on port 443 on ${IFACE} -----------------"
    #${IPT_APPEND_OUTPUT} -o ${IFACE} -p tcp --sport 443 -j ACCEPT
#}

# Function main
# Params :
# $1 : in interface (from which all packets will be forwarded)
# $2 : port list with ; as separator
main() {
    local iface=$IFACE
    local in_tcp_ports=""
    local out_tcp_ports=""
    local in_udp_ports=""
    local out_udp_ports=""
    local flush_filter=0
    local flush_nat=0
    local disable_ssh=0
    local input_policy="DROP"
    local forward_policy="DROP"
    local output_policy="DROP"

    # read the options
    TEMP=`getopt -o h --long help,flush-filter,flush-nat,disable_ssh,iface:,in-tcp-ports:,in-udp-ports:,out-tcp-ports:,out-udp-ports:,input-policy:,forward-policy:,output-policy: -n 'iptables_ports.sh' -- "$@"`
    eval set -- "$TEMP"

    while true ; do
        case "$1" in
            --flush-filter) flush_filter=1 ; shift ;;
            --flush-nat) flush_nat=1 ; shift ;;
            --disable-ssh) disable_ssh=1 ; shift ;;
            --iface) iface="$2" ; shift 2 ;;
            --in-tcp-ports) in_tcp_ports="$2" ; shift 2 ;;
            --in-udp-ports) in_udp_ports="$2" ; shift 2 ;;
            --out-tcp-ports) out_tcp_ports="$2" ; shift 2 ;;
            --out-udp-ports) out_udp_ports="$2" ; shift 2 ;;
            --input-policy) input_policy=$(upper "$2") ; shift 2 ;;
            --forward-policy) forward_policy=$(upper "$2") ; shift 2 ;;
            --output-policy) output_policy=$(upper "$2") ; shift 2 ;;
            -h | --help) help ; shift ;;
            \?) echo "Invalid argument !" ; exit 1 ;;
            --) shift ; break ;;
            *) echo "Error argument !" ; exit 1 ;;
        esac
    done

    echo "--- Configure IPTABLES with the following parameters : ------"
    echo " Flush FILTER: ${flush_filter}"
    echo " Flush NAT: ${flush_nat}"
    echo " Input interface: ${iface}"
    echo " Incomming TCP ports: ${in_tcp_ports}"
    echo " Incomming UDP ports: ${in_udp_ports}"
    echo " Disable SSH: ${disable_ssh}"
    echo " Input policy: ${input_policy}"
    echo " Forward policy: ${forward_policy}"
    echo " Output policy: ${output_policy}"
    echo "------------------------------------------------------------"
    echo ""

    # (Re)initialize iptables filter and nat tables
    if [ "${flush_filter}" -eq 1 ]
    then
        echo "\nFlushing all rules in FILTER table...\n"
        ${IPT_FILTER_FLUSH}
        ${IPT_FILTER_DELETE}
    fi

    if [ "${flush_nat}" -eq 1 ]
    then
        echo "\nFlushing all rules in NAT table...\n"
        ${IPT_NAT_FLUSH}
        ${IPT_NAT_DELETE}
    fi


    if [ "${disable_ssh}" -eq 0 ]
    then
        echo "--- Allow only SSH connection on all interfaces ----------------"
        # Incoming SSH connection
        ${IPT_APPEND_INPUT} -i ${iface} -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        if [ "${output_policy}" != "ACCEPT" ]; then
            ${IPT_APPEND_OUTPUT} -o ${iface} -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
        fi

        # Outcoming SSH connection
        if [ "${output_policy}" != "ACCEPT" ]; then
            ${IPT_APPEND_OUTPUT} -o ${iface} -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
            ${IPT_APPEND_INPUT} -i ${iface} -p tcp --sport 22 -m conntrack --ctstate ESTABLISHED -j ACCEPT
        fi
    fi

    echo "--- Allow trafic on local on loopback interface ----------"
    ${IPT_APPEND_INPUT} -i lo -j ACCEPT
    ${IPT_APPEND_OUTPUT} -o lo -j ACCEPT

    echo "--- Allow Established and Related Incoming Connections ----------"
    ${IPT_APPEND_INPUT} -i ${iface} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    echo "--- Allow Established Outgoing Connections ----------"
    ${IPT_APPEND_OUTPUT} -o ${iface} -m conntrack --ctstate ESTABLISHED -j ACCEPT
    echo "--- Drop Invalid Packets --------------"
    ${IPT_APPEND_INPUT} -i ${iface} -m conntrack --ctstate INVALID -j DROP

    echo "--- Set policies for INPUT, FORWARD & OUTPUT ------------------------"
    ${IPT_INPUT_POLICY} ${input_policy}
    ${IPT_FORWARD_POLICY} ${forward_policy}
    ${IPT_OUTPUT_POLICY} ${output_policy}

    # Allow all TCP incomming connections if specified
    if [ "${in_tcp_ports}" != "" ]
    then
        echo "--- Allow all TCP incoming connections on the following ports: ${in_tcp_ports} ----------"
        # Add rule for accepting new connection
        ${IPT_APPEND_INPUT} -i ${iface} -p tcp -m multiport --dports ${in_tcp_ports} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

        if [ "${output_policy}" != "ACCEPT" ]; then
            ${IPT_APPEND_OUTPUT} -o ${iface} -p tcp -m multiport --sports ${in_tcp_ports} -m conntrack --ctstate ESTABLISHED -j ACCEPT
        fi
    fi

    # Allow all TCP outcomming connections if specified
    if [ "${out_tcp_ports}" != "" ] && [ "${output_policy}" != "ACCEPT" ]
    then
        echo "--- Allow all UDP outcoming connections on the following ports: ${out_tcp_ports} ----------"
        ${IPT_APPEND_OUTPUT} -o ${iface} -p tcp -m multiport --dports ${out_tcp_ports} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        ${IPT_APPEND_INPUT} -i ${iface} -p tcp -m multiport --sports ${out_tcp_ports} -m conntrack --ctstate ESTABLISHED -j ACCEPT
    fi

    # Allow all UDP incomming connections if specified
    if [ "${in_udp_ports}" != "" ]
    then
        echo "--- Allow all UDP incoming connections on the following ports: ${in_udp_ports} ----------"
        # Add rule for accepting new connection
        ${IPT_APPEND_INPUT} -i ${iface} -p udp -m multiport --dports ${in_udp_ports} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

        if [ "${output_policy}" != "ACCEPT" ]; then
            ${IPT_APPEND_OUTPUT} -o ${iface} -p udp -m multiport --sports ${in_udp_ports} -m conntrack --ctstate ESTABLISHED -j ACCEPT
        fi
    fi

    # Allow all UDP outcomming connections if specified
    if [ "${out_udp_ports}" != "" ] && [ "${output_policy}" != "ACCEPT" ]
    then
        echo "--- Allow all UDP outcoming connections on the following ports: ${out_udp_ports} ----------"
        ${IPT_APPEND_OUTPUT} -o ${iface} -p udp -m multiport --dports ${out_udp_ports} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        ${IPT_APPEND_INPUT} -i ${iface} -p udp -m multiport --sports ${out_udp_ports} -m conntrack --ctstate ESTABLISHED -j ACCEPT
    fi

    # Save iptables rules
    ${IPT_SAVE}
}

main $@
