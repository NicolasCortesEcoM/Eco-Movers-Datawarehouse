#!/usr/bin/env bash
# host_bootstrap.sh - deploy the SmartMoving extraction pipeline on the droplet
# HOST (same box as n8n + Postgres). Run ON the droplet as datawarehouse_user.
#
# Why the host and not the n8n container: n8n runs in Docker without python; the
# orchestration model is n8n Schedule/worker nodes -> SSH Execute into this host
# -> run.py. See IMPLEMENTATION_STATUS.md / the plan.
#
# Prereq: the repo's pipeline/, scripts/, and a host .env have already been copied
# to $APP_DIR (see deploy/README.md for the scp step). Idempotent: re-runnable.
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/datawarehouse}"

echo "==> Using APP_DIR=$APP_DIR"
cd "$APP_DIR"

if [ ! -f "$APP_DIR/.env" ]; then
  echo "!! $APP_DIR/.env missing. Create it first (see deploy/README.md)." >&2
  exit 1
fi

echo "==> Python venv"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
# same deps the pipeline declares (dlt[duckdb,postgres], requests)
./venv/bin/pip install 'dlt[duckdb,postgres]>=1.4' 'requests>=2.31'

echo "==> Smoke test: dims pull for one instance against local Postgres"
cd "$APP_DIR/pipeline"
../venv/bin/python run.py --job dims --instance ld --dest postgres --budget 30

echo "==> Done. Scheduled/worker invocation form (used by n8n SSH Execute):"
echo "    cd $APP_DIR/pipeline && ../venv/bin/python run.py --ids <ids> --instance <inst> --dest postgres --budget 200 --pace 0.6"
