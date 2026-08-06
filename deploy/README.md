# Deploying the pipeline on the droplet host

The pipeline runs on the droplet **host** (same box as n8n + Postgres). n8n
(Docker, no python) orchestrates it via **SSH Execute** nodes that call `run.py`.
This is a one-time setup; after it, the n8n schedules + enrichment worker drive it.

Layout on the host (the pipeline reads `REPO_ROOT/.env` and appends to
`REPO_ROOT/scripts/api_call_log.jsonl`, so **both** `pipeline/` and `scripts/`
plus `.env` must sit under `$APP_DIR`):

```
/opt/datawarehouse/
 - - - - - - .env            # host secrets (see host.env.example)
 - - - - - - pipeline/       # run.py + sm_pipeline/
 - - - - - - scripts/        # api_call_log.jsonl lives here
 - " - - - - venv/           # created by host_bootstrap.sh
```

## Steps (run from your Windows laptop, git-bash/PowerShell; you'll type the SSH password)

All host/user/URL values below are placeholders — the real values live in your
laptop `.env` as `droplet_ssh_host`, `droplet_ssh_user`, and `n8n_docker_gateway`.
Substitute them in, don't hardcode them here.

1. **Create the app dir on the host** (needs sudo once; grant ownership to your user):
   ```bash
   ssh <droplet_ssh_user>@<droplet_ssh_host> \
     'sudo mkdir -p /opt/datawarehouse && sudo chown -R $USER /opt/datawarehouse'
   ```

2. **Copy the code + deploy script** (from the repo root):
   ```bash
   scp -r pipeline scripts deploy/host_bootstrap.sh \
     <droplet_ssh_user>@<droplet_ssh_host>:/opt/datawarehouse/
   ```

3. **Create the host `.env`.** Fill `deploy/host.env.example` with the real values
   from your laptop `.env`, then copy it up as `/opt/datawarehouse/.env`:
   ```bash
   scp deploy/host.env.filled <droplet_ssh_user>@<droplet_ssh_host>:/opt/datawarehouse/.env
   ```
   (Keep `postgres_host=localhost`, `postgres_port=5432`, `postgres_user=platform_rw`.)

4. **Run the bootstrap on the host** (venv + deps + smoke test):
   ```bash
   ssh <droplet_ssh_user>@<droplet_ssh_host> \
     'cd /opt/datawarehouse && bash host_bootstrap.sh'
   ```
   Success = dims rows land + a new line in `scripts/api_call_log.jsonl`.

5. **Create the n8n SSH credential** (n8n UI -' Credentials -' SSH):
   - Host `<n8n_docker_gateway>` (the Docker-'host gateway; from laptop `.env`), Port `22`
   - User `<droplet_ssh_user>`, Password (or better, a key you add to the host)
   - Name it `Droplet host SSH`. The schedule + worker workflows reference it.

After this, the n8n workflows (`Enrichment_worker`, `leads_poll`, `opps_sweep`,
`weekly_dims`, `nightly_reconciliation`) can SSH-Execute:
```
cd /opt/datawarehouse/pipeline && ../venv/bin/python run.py --ids <ids> --instance <inst> --dest postgres --budget 200 --pace 0.6
```
