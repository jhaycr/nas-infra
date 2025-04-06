# Ansible Role: jhaycr-local.logrotate

This role manages logrotate configurations for specified log files.

## Requirements

- Ansible 2.9 or higher
- Debian/Ubuntu Linux

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Default logrotate settings
logrotate_defaults:
  rotate: 4
  frequency: weekly
  create: true
  create_mode: "640"
  create_owner: root
  create_group: root
  compress: true
  delaycompress: true
  missingok: true
  notifempty: true
  copytruncate: true

# List of logs to rotate
logrotate_logs: []
```

### Customizing Log Rotation

You can override the default settings for specific logs by adding the appropriate parameters to the log entry:

```yaml
logrotate_logs:
  - path: /var/log/example.log
    rotate: 14
    frequency: weekly
    create: true
    create_mode: "0640"
    create_owner: root
    create_group: adm
    compress: true
    delaycompress: true
    missingok: true
    notifempty: false
    dateext: true
    dateformat: "-%Y%m%d"
    size: "100M"
    maxsize: "200M"
    minsize: "10M"
    maxage: 365
    su: true
    su_user: www-data
    su_group: www-data
    sharedscripts: true
    prerotate: |
      echo "Pre-rotation script"
    postrotate: |
      echo "Post-rotation script"
    firstaction: |
      echo "First action script"
    lastaction: |
      echo "Last action script"
```

## Usage

### Host-Specific Configuration

The recommended approach is to define the logs to rotate in your host or group vars files:

```yaml
# In group_vars/your_group/vars.yml or host_vars/your_host/vars.yml
logrotate_logs:
  - path: /var/log/snapraid.log
  - path: /var/log/autorestic.log
  - path: /var/log/custom.log
    rotate: 14
    frequency: weekly
    size: "100M"
```

### Example Playbook

```yaml
- hosts: servers
  roles:
    - role: jhaycr-local.logrotate
```

You can also override the configuration directly in the playbook, though this is not the recommended approach:

```yaml
- hosts: servers
  roles:
    - role: jhaycr-local.logrotate
      vars:
        logrotate_logs:
          - path: /var/log/custom.log
            rotate: 14
            frequency: weekly
```

## License

MIT
