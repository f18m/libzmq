#pragma once

//#define ZMQ_BUILD_DRAFT_API 1
#include "../include/zmq.h"

// tune TCP kernel socket buffers to achieve comparable results across different HW:
// NOTE: this setting will have no impact to sockets that have transport != TCP (e.g. inproc or ipc sockets)
static inline int set_fixed_tcp_kernel_buff (void *s)
{
    unsigned int rxBuff = 1 * 1024 * 1024;
    unsigned int txBuff = 1 * 1024 * 1024;

    int rc = zmq_setsockopt (s, ZMQ_RCVBUF, &rxBuff, sizeof (rxBuff));
    if (rc != 0) {
        printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
        return -1;
    }

    rc = zmq_setsockopt (s, ZMQ_SNDBUF, &txBuff, sizeof (txBuff));
    if (rc != 0) {
        printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
        return -1;
    }

    return 0;
}

#if 1 //def ZMQ_BUILD_DRAFT_API

static inline int set_batching (void *s)
{
    unsigned int rxBuff = 1 * 1024 * 1024;
    unsigned int txBuff = 1 * 1024 * 1024;

    printf ("setting batching size to %u/%u bytes\n", rxBuff, txBuff);

    int rc = zmq_setsockopt (s, ZMQ_IN_BATCH_SIZE, &rxBuff, sizeof (rxBuff));
    if (rc != 0) {
        printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
        return -1;
    }

    rc = zmq_setsockopt (s, ZMQ_OUT_BATCH_SIZE, &txBuff, sizeof (txBuff));
    if (rc != 0) {
        printf ("error in zmq_setsockoopt: %s\n", zmq_strerror (errno));
        return -1;
    }

    return 0;
}

#else

static inline int set_batching (void *s)
{
    return 0;
}

#endif // ZMQ_BUILD_DRAFT_API
