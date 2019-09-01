#!/usr/bin/python3

#
# This script assumes that the set of CSV files produced by "generate_csv.sh" is provided as input.
#
# Usage example:
#   export RESULT_DIRECTORY="./results"
#   export TCP_LINK_SPEED_GBPS="10"     # or 1 or 100 as you like
#   ./generate_graphs.py
#

# dependencies
#
# pip3 install matplotlib
#

import matplotlib.pyplot as plt
import numpy as np
import os


# functions

def get_theoretical_Mpps(message_size_bytes, tcp_link_speed_gbps):
        
    # see https://kb.juniper.net/InfoCenter/index?page=content&id=KB14737
    
    # convert Gbps -> bytes per second
    link_speed_in_bytes_per_sec = tcp_link_speed_gbps * 1000000000 / 8
    
    # computation of all overheads over a PHY ethernet link:
    #         14 = ethernet header
    #         4 = ethernet FCS
    #         8 = PHY preamble
    #         12 = PHY inter-frame gap (IFG)
    #         20 = minimal IPv4 header
    #         20 = minimal TCP header
    ethernet_ipv4_tcp_overhead = 14+4+8+12+20+20
     
    pps_theoretical_on_ethernet = [(link_speed_in_bytes_per_sec/(x+ethernet_ipv4_tcp_overhead)) for x in message_size_bytes]
    return np.asarray(pps_theoretical_on_ethernet) / 1e6


def plot_throughput(csv_filename, title, is_tcp=False, tcp_link_speed_gbps=10):
    message_size_bytes, message_count, pps, mbps = np.loadtxt(csv_filename, delimiter=',', unpack=True)

    print("Generating PNG image file [%s] from CSV results '%s'" % (title, csv_filename))
    fig, ax1 = plt.subplots()

    # PPS axis
    color = 'tab:red'
    ax1.set_xlabel('Message size [B]')
    ax1.set_ylabel('PPS [Mmsg/s]', color=color)
    ax1.semilogx(message_size_bytes, pps / 1e6, label='PPS measured [Mmsg/s]', marker='x', color=color)
    ax1.semilogx(message_size_bytes, get_theoretical_Mpps(message_size_bytes, tcp_link_speed_gbps), label='PPS upper bound [Mmsg/s]', marker='v', color=color)
    ax1.tick_params(axis='y', labelcolor=color)
    ax1.legend()

    # GBPS axis
    color = 'tab:blue'
    ax2 = ax1.twinx()  # instantiate a second axes that shares the same x-axis
    ax2.set_ylabel('Throughput [Gb/s]', color=color)
    ax2.semilogx(message_size_bytes, mbps / 1e3, label='Throughput [Gb/s]', marker='o')
    if is_tcp:
        ax2.set_yticks(np.arange(0, tcp_link_speed_gbps + 1, tcp_link_speed_gbps/10)) 
    ax2.tick_params(axis='y', labelcolor=color)
    ax2.grid(True)
    
    plt.title(title)
    fig.tight_layout()  # otherwise the right y-label is slightly clippe
    plt.savefig(csv_filename.replace('.csv', '.png'))
    plt.show()

def plot_latency(csv_filename, title):
    message_size_bytes, message_count, lat = np.loadtxt(csv_filename, delimiter=',', unpack=True)

    print("Generating PNG image file [%s] from CSV results '%s'" % (title, csv_filename))
    plt.semilogx(message_size_bytes, lat, label='Latency [us]', marker='o')
    
    plt.xlabel('Message size [B]')
    plt.ylabel('Latency [us]')
    plt.grid(True)
    plt.title(title)
    plt.savefig(csv_filename.replace('.csv', '.png'))
    plt.show()


# main

try:
    result_dir = os.environ['RESULT_DIRECTORY']
except:
    result_dir = "results" # default value

try:
    tcp_link_speed_gbps = int(os.environ['TCP_LINK_SPEED_GBPS'])
except:
    tcp_link_speed_gbps = 10 # default value
    
    

# result files for TCP:
INPUT_FILE_PUSHPULL_TCP_THROUGHPUT = result_dir + "/pushpull_tcp_thr_results.csv"
INPUT_FILE_REQREP_TCP_LATENCY = result_dir + "/reqrep_tcp_lat_results.csv"

# results for INPROC:
INPUT_FILE_PUSHPULL_INPROC_THROUGHPUT = result_dir + "/pushpull_inproc_thr_results.csv"
INPUT_FILE_PUBSUBPROXY_INPROC_THROUGHPUT = result_dir + "/pubsubproxy_inproc_thr_results.csv"

# generate plots
plot_throughput(INPUT_FILE_PUSHPULL_TCP_THROUGHPUT, 'ZeroMQ PUSH/PULL socket throughput, TCP transport', is_tcp=True, tcp_link_speed_gbps=tcp_link_speed_gbps)

# plot_throughput(INPUT_FILE_PUSHPULL_INPROC_THROUGHPUT, 'ZeroMQ PUSH/PULL socket throughput, INPROC transport')
# plot_throughput(INPUT_FILE_PUBSUBPROXY_INPROC_THROUGHPUT, 'ZeroMQ PUB/SUB PROXY socket throughput, INPROC transport')
# plot_latency(INPUT_FILE_REQREP_TCP_LATENCY, 'ZeroMQ REQ/REP socket latency, TCP transport')
