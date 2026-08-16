#!/bin/sh
set -eu

# ponytail: one process per request is enough for this lab; use a real server for load testing.
if [ "${1:-}" = "serve" ]; then
  exec nc -lk -p 8080 -e "$0"
fi

IFS=' ' read -r method path _ || exit 1
while IFS= read -r header; do
  [ "$header" = "$(printf '\r')" ] && break
done

status="200 OK"
case "$method $path" in
  "GET /")
    body="region=$REGION"
    ;;
  "GET /healthz")
    body="ok"
    ;;
  "GET /readyz")
    writable=$(PGCONNECT_TIMEOUT=2 psql -XAtqw -h "$DB_WRITER_ENDPOINT" \
      -v ON_ERROR_STOP=1 -c "SELECT current_setting('transaction_read_only') = 'off';" 2>/dev/null || true)
    if [ "$writable" = "t" ]; then
      body="ready"
    else
      status="503 Service Unavailable"
      body="database unavailable"
    fi
    ;;
  *)
    status="404 Not Found"
    body="not found"
    ;;
esac

printf 'HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' \
  "$status" "${#body}" "$body"
