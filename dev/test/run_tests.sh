#!/usr/bin/env bash
#
# Copyright 2026 Viascom Ltd liab. Co
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Runs the nanoid test suite (installation, unit tests, regression tests, upgrade-path test)
# against multiple PostgreSQL major versions using the official Docker images. Images are pulled
# before each run so the latest minor of every major is tested. A pull failure fails that version
# by default; set NANOID_TEST_OFFLINE=1 to allow the local image cache when deliberately offline.
# The upgrade-path test installs the previous release (origin/main), creates a table with a
# dependent DEFAULT nanoid() column, and applies the current nanoid.sql on top: the upgrade must
# either succeed outright or roll back atomically and succeed after the dependent default is
# dropped.
#
# Usage:
#   dev/test/run_tests.sh              # all supported versions (9.6 through 18 plus the 19 prerelease)
#   dev/test/run_tests.sh 16 17 18     # only the given versions
#
# Requirements: docker. Exits non-zero if any version fails.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Bump the 19 prerelease as new betas/RCs land; replace it with plain 19 at GA.
DEFAULT_VERSIONS="9.6 10 11 12 13 14 15 16 17 18 19beta1"
VERSIONS="${*:-$DEFAULT_VERSIONS}"

SUMMARY=""
FAILED=0

run_sql_file() {
    # $1 = container name, $2 = SQL file, $3 = database (default postgres).
    # NOTICE output is suppressed, errors stay visible.
    docker exec -i -e PGOPTIONS='-c client_min_messages=warning' "$1" \
        psql -U postgres -d "${3:-postgres}" -q -v ON_ERROR_STOP=1 -f - <"$2" >/dev/null
}

run_sql() {
    # $1 = container name, $2 = database, $3 = SQL. Prints the unaligned result.
    docker exec -e PGOPTIONS='-c client_min_messages=warning' "$1" \
        psql -U postgres -d "$2" -q -t -A -v ON_ERROR_STOP=1 -c "$3"
}

# The previous release used by the upgrade-path test. Skipped when the ref is unavailable
# (e.g. a shallow clone without origin/main).
OLD_NANOID_SQL="$(mktemp)"
if git -C "$REPO_ROOT" show origin/main:nanoid.sql >"$OLD_NANOID_SQL" 2>/dev/null; then
    UPGRADE_TEST_AVAILABLE=1
else
    UPGRADE_TEST_AVAILABLE=0
    echo "NOTE: upgrade-path test skipped (origin/main:nanoid.sql not available)"
fi

run_upgrade_test() {
    # $1 = container name. Installs origin/main's nanoid.sql into a fresh database, creates a
    # table whose column default depends on nanoid(), then applies the current nanoid.sql.
    # Contract: the upgrade either succeeds outright, or fails atomically (old install stays
    # fully intact) and succeeds after the dependent default is dropped.
    local NAME="$1" ERRLOG UPGRADED
    [ "$UPGRADE_TEST_AVAILABLE" -eq 1 ] || return 0
    ERRLOG="$(mktemp)"

    run_sql "$NAME" postgres "DROP DATABASE IF EXISTS upgrade_test;" >/dev/null &&
        run_sql "$NAME" postgres "CREATE DATABASE upgrade_test;" >/dev/null &&
        run_sql_file "$NAME" "$OLD_NANOID_SQL" upgrade_test &&
        run_sql "$NAME" upgrade_test \
            "CREATE TABLE upgrade_dep(id char(21) DEFAULT nanoid() PRIMARY KEY, n int); INSERT INTO upgrade_dep(n) VALUES (1);" >/dev/null ||
        { echo "    upgrade test: could not set up the previous release"; rm -f "$ERRLOG"; return 1; }

    if run_sql_file "$NAME" "$REPO_ROOT/nanoid.sql" upgrade_test 2>"$ERRLOG"; then
        UPGRADED=1
    else
        # The upgrade was blocked (e.g. dependent column default). It must have rolled back
        # atomically: still exactly one nanoid() and it must still work.
        UPGRADED=0
        if [ "$(run_sql "$NAME" upgrade_test "SELECT count(*) FROM pg_proc WHERE proname = 'nanoid';")" != "1" ] ||
            [ "$(run_sql "$NAME" upgrade_test "SELECT length(nanoid());")" != "21" ]; then
            echo "    upgrade test: blocked upgrade did not roll back atomically"
            cat "$ERRLOG"
            rm -f "$ERRLOG"
            return 1
        fi
        run_sql "$NAME" upgrade_test "ALTER TABLE upgrade_dep ALTER COLUMN id DROP DEFAULT;" >/dev/null
        if ! run_sql_file "$NAME" "$REPO_ROOT/nanoid.sql" upgrade_test; then
            echo "    upgrade test: upgrade still failed after dropping the dependent default"
            rm -f "$ERRLOG"
            return 1
        fi
    fi
    rm -f "$ERRLOG"

    # The upgraded database must expose exactly one nanoid() and positional calls must work.
    if [ "$(run_sql "$NAME" upgrade_test "SELECT count(*) FROM pg_proc WHERE proname = 'nanoid';")" != "1" ] ||
        [ "$(run_sql "$NAME" upgrade_test "SELECT count(*) FROM pg_proc WHERE proname = 'nanoid_optimized';")" != "1" ] ||
        [ "$(run_sql "$NAME" upgrade_test "SELECT length(nanoid());")" != "21" ]; then
        echo "    upgrade test: upgraded database is inconsistent"
        return 1
    fi

    # Re-running the script must be idempotent.
    if ! run_sql_file "$NAME" "$REPO_ROOT/nanoid.sql" upgrade_test; then
        echo "    upgrade test: re-running nanoid.sql on the upgraded database failed"
        return 1
    fi

    # The documented recovery path must complete: re-add the default and insert through it.
    if [ "$UPGRADED" -eq 0 ]; then
        if ! run_sql "$NAME" upgrade_test \
            "ALTER TABLE upgrade_dep ALTER COLUMN id SET DEFAULT nanoid(); INSERT INTO upgrade_dep(n) VALUES (2);" >/dev/null ||
            [ "$(run_sql "$NAME" upgrade_test "SELECT count(*) FROM upgrade_dep WHERE length(id) = 21;")" != "2" ]; then
            echo "    upgrade test: re-adding the column default failed"
            return 1
        fi
    fi
    return 0
}

for VERSION in $VERSIONS; do
    IMAGE="postgres:${VERSION}-alpine"
    NAME="nanoid-test-pg$(echo "$VERSION" | tr -d .)"
    echo "==> PostgreSQL ${VERSION} (${IMAGE})"

    docker rm -f "$NAME" >/dev/null 2>&1

    # Pull the latest minor so a stale local cache is never what gets tested. A pull failure is
    # fatal by default so a bad tag, auth error, or rate limit cannot silently fall back to a
    # possibly stale cached image. Set NANOID_TEST_OFFLINE=1 to allow the cache when deliberately offline.
    if ! PULL_ERR="$(docker pull -q "$IMAGE" 2>&1)" &&
        ! PULL_ERR="$(docker pull -q --platform linux/amd64 "$IMAGE" 2>&1)"; then
        if [ "${NANOID_TEST_OFFLINE:-0}" = "1" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
            echo "    (offline: pull failed, using cached ${IMAGE})"
        else
            echo "    FAIL (image pull failed: ${PULL_ERR})"
            SUMMARY="${SUMMARY}${VERSION}: FAIL (image pull failed)\n"
            FAILED=1
            continue
        fi
    fi

    # Older images may not provide a native image for the host architecture; fall back to amd64.
    if ! docker run -d --rm --name "$NAME" -e POSTGRES_PASSWORD=postgres "$IMAGE" >/dev/null 2>&1 &&
        ! docker run -d --rm --name "$NAME" --platform linux/amd64 -e POSTGRES_PASSWORD=postgres "$IMAGE" >/dev/null; then
        echo "    FAIL (could not start container)"
        SUMMARY="${SUMMARY}${VERSION}: FAIL (could not start container)\n"
        FAILED=1
        continue
    fi

    # Wait for the server. Require two consecutive successful probes because the official image
    # starts a temporary server during initialization before the final one comes up.
    READY=0
    STREAK=0
    TRIES=0
    while [ "$TRIES" -lt 90 ]; do
        if docker exec "$NAME" psql -U postgres -q -c 'SELECT 1;' >/dev/null 2>&1; then
            STREAK=$((STREAK + 1))
            if [ "$STREAK" -ge 2 ]; then
                READY=1
                break
            fi
        else
            STREAK=0
        fi
        sleep 1
        TRIES=$((TRIES + 1))
    done

    if [ "$READY" -ne 1 ]; then
        echo "    FAIL (server did not become ready)"
        SUMMARY="${SUMMARY}${VERSION}: FAIL (server did not become ready)\n"
        FAILED=1
        docker stop "$NAME" >/dev/null 2>&1
        continue
    fi

    RESULT="PASS"
    if ! run_sql_file "$NAME" "$REPO_ROOT/nanoid.sql"; then
        RESULT="FAIL (install nanoid.sql)"
    elif ! run_sql_file "$NAME" "$REPO_ROOT/dev/test/unit_tests.sql"; then
        RESULT="FAIL (unit_tests.sql)"
    elif ! run_sql_file "$NAME" "$REPO_ROOT/dev/test/regression_tests.sql"; then
        RESULT="FAIL (regression_tests.sql)"
    elif ! run_upgrade_test "$NAME"; then
        RESULT="FAIL (upgrade test)"
    fi

    SERVER_VERSION="$(docker exec "$NAME" psql -U postgres -t -A -c 'SHOW server_version;' 2>/dev/null)"
    docker stop "$NAME" >/dev/null 2>&1

    [ "$RESULT" = "PASS" ] || FAILED=1
    echo "    ${RESULT} (server ${SERVER_VERSION})"
    SUMMARY="${SUMMARY}${VERSION} (${SERVER_VERSION}): ${RESULT}\n"
done

rm -f "$OLD_NANOID_SQL"

echo ""
echo "================ SUMMARY ================"
printf "%b" "$SUMMARY"
exit "$FAILED"
