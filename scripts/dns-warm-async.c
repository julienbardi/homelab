/* dns-warm-async.c */
#include <ares.h>
#include <arpa/nameser.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <unistd.h>
#include <time.h>

#define MAX_INFLIGHT 768   /* tuning knob - 768 has no packet loss and same runtime as 2048  netstat -su > /tmp/udp.before;netstat -su > /tmp/udp.after;diff -u /tmp/udp.before /tmp/udp.after*/

static int pending = 0;
/* forward declaration */
static void drive_ares(ares_channel channel);

/* helpers */
static double now_sec(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void query_cb(void *arg, int status, int timeouts,
    unsigned char *abuf, int alen)
{
    (void)arg;
    (void)status;
    (void)timeouts;
    (void)abuf;
    (void)alen;

    /* We don't care about the answer, only that it was attempted */
    pending--;
}

static void drive_ares(ares_channel channel)
{
    fd_set rfds, wfds;
    FD_ZERO(&rfds);
    FD_ZERO(&wfds);

    int nfds = ares_fds(channel, &rfds, &wfds);
    if (nfds == 0)
        return;

    struct timeval tv, *tvp;
    tvp = ares_timeout(channel, NULL, &tv);

    poll(NULL, 0,
         tvp->tv_sec * 1000 + tvp->tv_usec / 1000);
    ares_process(channel, &rfds, &wfds);
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

    ares_channel channel;
    struct ares_options opts = {
        .timeout = 2000,
        .tries = 1,
    };
    int optmask = ARES_OPT_TIMEOUTMS | ARES_OPT_TRIES;

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

        /* Throttle submission */
        while (pending >= MAX_INFLIGHT)
            drive_ares(channel);

        domains++;
        pending++;
        ares_query(channel, line, ns_c_in, ns_t_a, query_cb, NULL);
    }

    fclose(f);

    while (pending > 0) {
        fd_set rfds, wfds;
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);

        int nfds = ares_fds(channel, &rfds, &wfds);
        if (nfds == 0)
            break;

        struct timeval tv, *tvp;
        tvp = ares_timeout(channel, NULL, &tv);

        poll(NULL, 0,
             tvp->tv_sec * 1000 + tvp->tv_usec / 1000);
        ares_process(channel, &rfds, &wfds);
    }

    double end = now_sec();

    printf("dns-warm-async: resolver=127.0.0.1 domains=%d duration=%.1fs\n",
           domains, end - start);

    ares_destroy(channel);
    ares_library_cleanup();
    return 0;
}