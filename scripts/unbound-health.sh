#!/bin/bash
set -euo pipefail
SCRIPT_NAME="unbound-health"
source /usr/local/bin/common.sh

require_bin unbound-control
require_bin awk

unbound-control -c /etc/unbound/unbound-control.conf stats_noreset | \
awk -F= '
/thread[0-9]+\.num\.queries=/        { q += $2 }
/thread[0-9]+\.num\.cachehits=/      { h += $2 }
/thread[0-9]+\.num\.cachemiss=/      { m += $2 }
/thread[0-9]+\.recursion\.time\.avg=/ { t += $2; n++ }
END {
    if (!q) exit;
    hp = (h/q)*100;
    mp = (m/q)*100;
    rt = (n ? (t/n)*1000 : 0);
    printf "Metric                    Value        Ratio\n";
    printf "————————————————————————————————————————————\n";
    printf "%-22s %10d %9.1f%%\n", "Total queries", q, 100;
    printf "%-22s %10d %9.1f%%\n", "Cache hits", h, hp;
    printf "%-22s %10d %9.1f%%\n", "Cache misses", m, mp;
    printf "%-22s %10.2f ms\n", "Avg recursion time", rt;
    printf "\n";
    if (hp < 10)
        print "Verdict: ℹ️ Expected after restart";
    else if (rt > 20)
        print "Verdict: ⚠️ high recursion latency";
    else
        print "Verdict: ✅ healthy resolver";
}'
