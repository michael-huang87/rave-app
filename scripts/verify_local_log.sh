#!/usr/bin/env bash
# Proves a festival seen tick updates sets, stats, and recap with no network, and that the
# pending seen-set drains once the API answers. No simulator and no backend: the sync leg
# uses a fake API compiled into the check.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN=$(mktemp -d)/local-log-check
swiftc -swift-version 5 -parse-as-library \
    ios/Rave/Models/RaveModels.swift \
    ios/Rave/Services/LastReadStore.swift \
    ios/Rave/Services/Outbox.swift \
    ios/Rave/Services/LocalLog.swift \
    ios/Rave/Services/APIClient.swift \
    ios/Rave/Services/ScheduleStore.swift \
    ios/LocalLogCheck.swift \
    -o "$BIN"
"$BIN"
