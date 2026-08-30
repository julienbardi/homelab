/* dns-warm-async.c */
#include <ares.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

/* tuning knob - 768 has no packet loss and same runtime as 2048  netstat -su > /tmp/udp.before;netstat -su > /tmp/udp.after;diff -u /tmp/udp.before /tmp/udp.after*/
#define MAX_INFLIGHT 768

static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void query_cb(void *arg, ares_status_t status, size_t timeouts, const ares_dns_record_t *dnsrec)
{
    (void)arg;
    (void)status;
    (void)timeouts;
    (void)dnsrec;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <domain-file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "r");
    if (!f) {
        perror("fopen");
        return 1;
    }

    if (ares_library_init(ARES_LIB_INIT_ALL) != ARES_SUCCESS) {
        fprintf(stderr, "ares_library_init failed\n");
        return 1;
    }

    ares_channel_t *channel;
    struct ares_options opts = {
        .timeout = 2000,
        .tries = 1,
    };
    int optmask = ARES_OPT_TIMEOUTMS | ARES_OPT_TRIES | ARES_OPT_EVENT_THREAD;

    if (ares_init_options(&channel, &opts, optmask) != ARES_SUCCESS) {
        fprintf(stderr, "ares_init_options failed\n");
        return 1;
    }

    /* Force resolver to dnsmasq */
    ares_set_servers_ports_csv(channel, "127.0.0.1:53");

    int domains = 0;
    double start = now_sec();

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n');
        if (nl)
            *nl = '\0';

        if (*line == '\0')
            continue;

        /* Throttle submission using modern queue tracking */
        while (ares_queue_active_queries(channel) >= MAX_INFLIGHT)
            usleep(1000);

        domains++;
        ares_query_dnsrec(channel, line, ARES_CLASS_IN, ARES_REC_TYPE_A, query_cb, NULL, NULL);
    }

    fclose(f);

    /* Wait for all pending queries to finish using the background event thread */
    ares_queue_wait_empty(channel, -1);

    double end = now_sec();

    printf("dns-warm-async: resolver=127.0.0.1 domains=%d duration=%.1fs\n",
           domains, end - start);

    ares_destroy(channel);
    ares_library_cleanup();
    return 0;
}