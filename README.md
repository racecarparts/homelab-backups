# homelab-backups

Docker volume backup management using [Backrest](https://github.com/garethgeorge/backrest) (a web UI built on [restic](https://restic.net/)) with Google Drive as the storage backend.

Designed for homelabs running multiple Docker hosts managed by Portainer. One Portainer stack per host, all pointing at this repo. Same compose file, zero per-host variables. Each host's Backrest instance manages its own volumes and pushes to Google Drive under `backups/{hostname}/`.

## Features

- **Web UI** for browsing snapshots and triggering restores — no CLI required for day-to-day use
- **Scheduled backups** via cron expressions, configured per volume in the Backrest UI
- **Restore picker** — browse by date, select files or whole volumes, restore in place
- **Google Drive backend** via rclone service account — no OAuth tokens, no token expiry
- **Identical deploy** on every host — one compose file, no per-host variables
- **Portainer-native** — deploy and update directly from this Git repository
- **Multihost ready** — when Backrest's unified multihost UI stabilizes, one instance becomes the hub and others connect as daemons with no stack changes needed

## Prerequisites

- One or more Docker hosts running Portainer with Git repository stack support
- A Google Cloud project with the Drive API enabled
- A Google Drive folder to store backups

---

## First-time setup on a new host

### 1. Create a Google Cloud service account key

This uses a service account key instead of OAuth — no browser required, no token expiry, and the same key file works on every host. If you already have a Google Cloud project, use that.

1. Go to [Google Cloud Console](https://console.cloud.google.com) → your project
2. **APIs & Services → Enable APIs** → enable the **Google Drive API** if not already on
3. **IAM & Admin → Service Accounts → Create Service Account**
   - Name: `homelab-backups`
   - No roles needed at the project level
4. Click the service account → **Keys → Add Key → Create new key → JSON**
   - Download the `.json` key file
5. In Google Drive, create a folder called `backups` and **share it** with the service account's
   email address (looks like `homelab-backups@your-project.iam.gserviceaccount.com`) with
   **Editor** access — this is how the service account gets permission to write to your Drive

Store the JSON key file somewhere safe (Vaultwarden). You'll use it in the next step.

---

### 2. Run the setup script

Clone this repo on the host and run `setup.sh`. It installs rclone, places the service account key, writes the rclone config, and verifies the Google Drive connection.

```bash
git clone https://github.com/YOUR_USERNAME/homelab-backups.git
cd homelab-backups
./setup.sh
```

The script will prompt you to paste the contents of your service account JSON key directly in the terminal — no `scp` required. Alternatively, if you've already copied the key file to the host, you can pass it as an argument:

```bash
./setup.sh ~/sa-key.json
```

At the end of the script, it will confirm the Google Drive connection and print the next steps.

---

### 3. Deploy the Backrest stack via Portainer

1. In Portainer, switch to the target host environment
2. Go to **Stacks → Add stack**
3. Choose **Repository** as the build method
4. Set:
   - Repository URL: `https://github.com/YOUR_USERNAME/homelab-backups`
   - Compose path: `docker-compose.yml`
   - Enable **automatic updates** if you want redeployments on push
5. Click **Deploy the stack**

Backrest will be available at `http://{host-ip}:9898`.

---

### 4. Configure Backrest (in the UI)

Once deployed, open the Backrest UI and complete the configuration.

#### Add a repository (where backups are stored)

- Backend: `rclone`
- Path: `gdrive:backups/{hostname}` — use the actual hostname so each host has its own isolated folder in Drive, e.g. `gdrive:backups/myhost`
- Set a strong encryption password and **store it in Vaultwarden immediately**
- This password is required for any future restore — it cannot be recovered if lost

#### Find your Docker volume names

Before adding plans, check what volumes exist on the host. Run this in a terminal on the host (or via Portainer's console):

```bash
docker volume ls
```

All Docker volumes are mounted at `/docker-volumes` inside the Backrest container. A volume named `portainer_data` maps to `/docker-volumes/portainer_data/_data` in Backrest.

#### Add a plan (what to back up, when)

Add one plan per volume you want to back up:

- Path: `/docker-volumes/{volume-name}/_data`
- Repository: select the one you just created
- Schedule: cron expression, e.g. `0 2 * * *` for 2am daily (UTC)
- Retention: e.g. keep last 7 daily, 4 weekly, 3 monthly

---

## Restoring from a backup

1. Open Backrest UI on the relevant host
2. Go to **Snapshots** → select the repo
3. Browse to the snapshot date you want
4. Select files or directories and click **Restore** (or **Download** for individual files without a full restore)
5. Restore target: `/docker-volumes/{volume-name}/_data`
   - Stop the relevant container(s) first via Portainer before restoring

---

## Adding a new host

1. Clone this repo on the new host and run `./setup.sh`
2. Deploy the Portainer stack pointing at this repo
3. In the Backrest UI, add a repository with the GDrive path set to `gdrive:backups/{newhostname}` to keep it isolated from other hosts
4. No changes needed to this repo

---

## Hosts

Update this table with your own hosts once deployed.

| Host    | IP          | Backrest UI                 |
|---------|-------------|-----------------------------|
| host-1  | 192.168.x.x | http://192.168.x.x:9898     |
| host-2  | 192.168.x.x | http://192.168.x.x:9898     |

---

## Notes

- Backrest downloads and manages its own restic binary — no need to install restic separately
- Backup schedules use UTC — factor that in when choosing cron times
- The encryption password per repo is **not stored in this repo** — keep it in Vaultwarden
- For databases (Postgres, MySQL), add a pre-backup hook in Backrest to run a dump before the volume backup
- If you prefer to configure rclone manually rather than using `setup.sh`, see `rclone/rclone.conf.example` for the expected config shape
- Multihost unified UI is on the Backrest roadmap — when it lands, one instance becomes the hub and others connect as daemons with no stack changes needed
