# neo parity3 — post-RMA replacement checklist

**Status:** `/dev/sdi` (parity3, Seagate Exos 16TB, serial `ZL2GYE21`) SMART-FAILED
July 2026 and was **physically pulled for RMA**. Replacement 16TB disk expected
~2026-07-21/22.

While the disk is out, snapraid runs **zero parity3 protection** (data is still
single-parity protected via parity1), and the **nightly snapraid cron is
disabled** on neo (`#DISABLED#` prefix in root's crontab). Leftovers still
referencing the absent disk: `/etc/fstab` keeps the `crypt-parity3 /mnt/parity3`
line (`nofail`, so boot is fine) and `/etc/snapraid.conf` still lists parity3.

## Do this when the replacement disk arrives

- [ ] **1. Physical swap.** Install the new 16TB disk. Identify its device +
      serial with `lsblk -o NAME,SIZE,SERIAL,MODEL` and confirm it is the new
      blank drive (the removed one was serial `ZL2GYE21`).
- [ ] **2. LUKS format + mount** as `crypt-parity3` → `/mnt/parity3` via the
      disks role / crypttab procedure. **DESTRUCTIVE — triple-check the target
      device is the new blank disk.** The fstab line already exists; verify
      crypttab has the mapping + keyfile.
- [ ] **3. Sanity check.** `/mnt/parity3` mounted and empty; `snapraid.conf`
      still lists parity3 (it does today).
- [ ] **4. Rebuild parity.** Run `snapraid sync` (hours-long). Optional
      `snapraid scrub` afterward. Drive this manually — it is not one of the
      read-only diagnostics scripts.
- [ ] **5. Re-enable the nightly run.** Prefer `make neo-disks` — it re-enables
      the cron **and** reconciles two IaC-drift items at once: the manual
      `#DISABLED#` prefix (not in code) and the stale bare cron command →
      `/opt/snapraid-arr-sync.sh` (from `snapraid_runner_cron_jobs` in
      `group_vars/neo/vars.yml`). For just the toggle:
      `.claude/skills/neo-disk-diagnostics/scripts/remediate/snapraid-cron.sh enable --confirm`.
- [ ] **6. Verify green.** `snapraid status` clean; watch the next nightly run
      log `Run finished successfully` in Loki (`{job="snapraid"}`); confirm the
      Grafana SnapRAID alert stays quiet.
- [ ] **7. Close out.** Delete this file (or mark resolved). Warranty note:
      Exos = 5yr, SMART FAILED = auto-RMA (serial `ZL2GYE21`).

## Not related to the disk — do NOT re-diagnose

The daily **"SnapRAID Run Failed"** Discord alert was a *separate* bug: the
Grafana alert rule errored on a Loki datasource-UID mismatch (`datasourceUid:
loki` vs. the auto-assigned UID). Fixed 2026-07-21 in commit `6ba452a`
(`deleteDatasources` added to the metrics compose provisioning heredoc), so the
Loki datasource now pins `uid: loki`. It was never an actual snapraid failure.
