FROM telegraf

# Update and install smartmontools
RUN apt-get update && apt-get install -y sudo smartmontools nvme-cli

# Modify the sudoers file to allow the telegraf user to run smartctl and nvme without a password
RUN echo 'Cmnd_Alias SMARTCTL = /usr/sbin/smartctl' >> /etc/sudoers && \
  echo 'Cmnd_Alias NVME = /usr/sbin/nvme' >> /etc/sudoers && \
  echo 'telegraf  ALL=(ALL) NOPASSWD: SMARTCTL, NVME' >> /etc/sudoers && \
  echo 'Defaults!SMARTCTL !logfile, !syslog, !pam_session' >> /etc/sudoers && \
  echo 'Defaults!NVME !logfile, !syslog, !pam_session' >> /etc/sudoers
