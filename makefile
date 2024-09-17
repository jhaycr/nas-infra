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
	find ./group_vars -type f -name "vault.yml" -print0 | xargs -0 ansible-vault encrypt

vault-unlock:
	find ./group_vars -type f -name "vault.yml" -print0 | xargs -0 ansible-vault decrypt

neo:
	ansible-playbook -v site.yml --limit neo

neo-compose:
	ansible-playbook -vv site.yml --limit neo --tags compose