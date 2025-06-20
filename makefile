reqs:
	ansible-galaxy install -r requirements.yml

bootstrap-ssh:
	@if [ -z "$(LIMIT)" ]; then \
		echo "Error: LIMIT variable is not set"; \
		exit 1; \
	fi
	@echo "Running Ansible playbook with --limit=$(LIMIT)"
	ansible-playbook -v ./playbooks/bootstrap-ssh.yml --limit=$(LIMIT) -k -K

bootstrap-ssh-rollback:
	@if [ -z "$(LIMIT)" ]; then \
		echo "Error: LIMIT variable is not set"; \
		exit 1; \
	fi
	@echo "Running Ansible playbook with --limit=$(LIMIT)"
	ansible-playbook -v ./playbooks/bootstrap-ssh-rollback.yml --limit=$(LIMIT)

vault-lock:
	find -L ./group_vars -type f -name "vault.yml" -print0 | xargs -0 ansible-vault encrypt

vault-unlock:
	find -L ./group_vars -type f -name "vault.yml" -print0 | xargs -0 ansible-vault decrypt

neo:
	ansible-playbook site.yml --limit neo $(EXTRA_VARS:%=-e '%')

neo-docker:
	ansible-playbook site.yml --limit neo --tags compose $(EXTRA_VARS:%=-e '%')

neo-disks:
	ansible-playbook site.yml --limit neo --tags disks $(EXTRA_VARS:%=-e '%')

neo-vm:
	ansible-playbook site.yml --limit neo --tags vm $(EXTRA_VARS:%=-e '%')

morpheus:
	ansible-playbook site.yml --limit morpheus $(EXTRA_VARS:%=-e '%')

trinity:
	ansible-playbook site.yml --limit trinity -K $(EXTRA_VARS:%=-e '%')

trinity-docker:
	ansible-playbook site.yml --limit trinity --tags compose -K $(EXTRA_VARS:%=-e '%')

compose:
	ansible-playbook site.yml --tags compose $(EXTRA_VARS:%=-e '%')