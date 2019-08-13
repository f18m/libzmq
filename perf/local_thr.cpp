/*
    Copyright (c) 2007-2016 Contributors as noted in the AUTHORS file

    This file is part of libzmq, the ZeroMQ core engine in C++.

    libzmq is free software; you can redistribute it and/or modify it under
    the terms of the GNU Lesser General Public License (LGPL) as published
    by the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    As a special exception, the Contributors give you permission to link
    this library with independent modules to produce an executable,
    regardless of the license terms of these independent modules, and to
    copy and distribute the resulting executable under terms of your choice,
    provided that you also meet, for each linked independent module, the
    terms and conditions of the license of that module. An independent
    module is a module which is not derived from or based on this library.
    If you modify this library, you must extend this exception to your
    version of the library.

    libzmq is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
    FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public
    License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "../include/zmq.h"
#include <stdio.h>
#include <stdlib.h>
#include "shared_perf_utils.h"

// keys are arbitrary but must match remote_lat.cpp
const char server_prvkey[] = "{X}#>t#jRGaQ}gMhv=30r(Mw+87YGs+5%kh=i@f8";


int main (int argc, char *argv[])
{
    const char *bind_to;
    int duration_sec = 10;
    size_t message_size;
    size_t message_count;
    void *ctx;
    void *s;
    int rc;
    zmq_msg_t msg;
    void *watch;
    unsigned long elapsed_us;
    double throughput;
    double megabits;
    int curve = 0;
    int zmq_bg_threads = 1;

    if (argc != 3 && argc != 4 && argc != 5 && argc != 6) {
        printf (
          "usage: local_thr <bind-to> <message-size> [<duration-of-test-sec>] "
          "[<enable_curve>] [<num_bg_threads>]\n");
        return 1;
    }
    bind_to = argv[1];
    message_size = atoi (argv[2]);
    if (argc >= 4) {
        duration_sec = atoi (argv[3]);
    }
    if (argc >= 5) {
        curve = atoi (argv[4]);
    }
    if (argc >= 6) {
        zmq_bg_threads = atoi (argv[5]);
    }

    ctx = zmq_init (zmq_bg_threads);
    if (!ctx) {
        printf ("error in zmq_init: %s\n", zmq_strerror (errno));
        return -1;
    }

    s = zmq_socket (ctx, ZMQ_PULL);
    if (!s) {
        printf ("error in zmq_socket: %s\n", zmq_strerror (errno));
        return -1;
    }

    //  Add your socket options here.
    //  For example ZMQ_RATE, ZMQ_RECOVERY_IVL and ZMQ_MCAST_LOOP for PGM.
    if (curve) {
        rc = zmq_setsockopt (s, ZMQ_CURVE_SECRETKEY, server_prvkey,
                             sizeof (server_prvkey));
        if (rc != 0) {
            printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
            return -1;
        }
        int server = 1;
        rc = zmq_setsockopt (s, ZMQ_CURVE_SERVER, &server, sizeof (int));
        if (rc != 0) {
            printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
            return -1;
        }
    }

    if (set_fixed_tcp_kernel_buff (s) != 0)
        return -1;
    if (set_batching (s) != 0)
        return -1;

    rc = zmq_bind (s, bind_to);
    if (rc != 0) {
        printf ("error in zmq_bind: %s\n", zmq_strerror (errno));
        return -1;
    }

    rc = zmq_msg_init (&msg);
    if (rc != 0) {
        printf ("error in zmq_msg_init: %s\n", zmq_strerror (errno));
        return -1;
    }

    rc = zmq_recvmsg (s, &msg, 0);
    if (rc < 0) {
        printf ("error in zmq_recvmsg: %s\n", zmq_strerror (errno));
        return -1;
    }
    if (zmq_msg_size (&msg) != message_size) {
        printf ("message of incorrect size received\n");
        return -1;
    }

    watch = zmq_stopwatch_start ();

    for (message_count = 0;; message_count++) {
        rc = zmq_recvmsg (s, &msg, 0);
        if (rc < 0) {
            printf ("error in zmq_recvmsg: %s\n", zmq_strerror (errno));
            return -1;
        }
        if (zmq_msg_size (&msg) != message_size) {
            printf ("message of incorrect size received\n");
            return -1;
        }

        if ((message_count % 1000) == 0) {
            elapsed_us = zmq_stopwatch_intermediate (watch);
            if (elapsed_us >= duration_sec * 1E6)
                break;
        }
    }

    elapsed_us = zmq_stopwatch_stop (watch);
    if (elapsed_us == 0)
        elapsed_us = 1;

    rc = zmq_msg_close (&msg);
    if (rc != 0) {
        printf ("error in zmq_msg_close: %s\n", zmq_strerror (errno));
        return -1;
    }

    throughput = ((double) message_count / (double) elapsed_us * 1E6);
    megabits = ((double) throughput * message_size * 8) / 1E6;

    printf ("elapsed: %.6f [s]\n", (double) elapsed_us / 1E6);
    printf ("message size: %d [B]\n", (int) message_size);
    printf ("message count: %d\n", (int) message_count);
    printf ("mean throughput: %d [msg/s]\n", (int) throughput);
    printf ("mean throughput: %.3f [Mb/s]\n", (double) megabits);

    rc = zmq_close (s);
    if (rc != 0) {
        printf ("error in zmq_close: %s\n", zmq_strerror (errno));
        return -1;
    }

    rc = zmq_ctx_term (ctx);
    if (rc != 0) {
        printf ("error in zmq_ctx_term: %s\n", zmq_strerror (errno));
        return -1;
    }

    return 0;
}
