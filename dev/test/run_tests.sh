#!/usr/bin/env bash
#
# Runs the nanoid test suite (installation, unit tests, regression tests) against multiple
# PostgreSQL major versions using the official Docker images (latest minor of each major).
#
# Usage:
#   dev/test/run_tests.sh              # all supported versions (9.6 through 18)
#   dev/test/run_tests.sh 16 17 18     # only the given versions
#
# Requirements: docker. Exits non-zero if any version fails.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEFAULT_VERSIONS="9.6 10 11 12 13 14 15 16 17 18"
VERSIONS="${*:-$DEFAULT_VERSIONS}"

SUMMARY=""
FAILED=0

run_sql_file() {
    # $1 = container name, $2 = SQL file. NOTICE output is suppressed, errors stay visible.
    docker exec -i -e PGOPTIONS='-c client_min_messages=warning' "$1" \
        psql -U postgres -q -v ON_ERROR_STOP=1 -f - <"$2" >/dev/null
}

for VERSION in $VERSIONS; do
    IMAGE="postgres:${VERSION}-alpine"
    NAME="nanoid-test-pg$(echo "$VERSION" | tr -d .)"
    echo "==> PostgreSQL ${VERSION} (${IMAGE})"

    docker rm -f "$NAME" >/dev/null 2>&1

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
    fi

    SERVER_VERSION="$(docker exec "$NAME" psql -U postgres -t -A -c 'SHOW server_version;' 2>/dev/null)"
    docker stop "$NAME" >/dev/null 2>&1

    [ "$RESULT" = "PASS" ] || FAILED=1
    echo "    ${RESULT} (server ${SERVER_VERSION})"
    SUMMARY="${SUMMARY}${VERSION} (${SERVER_VERSION}): ${RESULT}\n"
done

echo ""
echo "================ SUMMARY ================"
printf "%b" "$SUMMARY"
exit "$FAILED"
