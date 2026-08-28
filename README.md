# ansible-labs

Hands-on labs for learning Ansible step-by-step. `ansible/` is the reference solution — this README walks you through each concept in order.

## 0. Prerequisites

- Python 3.10+
- Azure VM (Windows Server 2022) provisioned via `terraform/` or a local Docker container for early labs

## 1. Create isolated environment and install Ansible

We use `.venv` so labs don't pollute system Python.

```bash
python -m venv ansible/.venv
source ansible/.venv/bin/activate
pip install ansible pywinrm
ansible --version
```

What this does:
- `python -m venv` — creates `.venv/` with its own `python`/`pip`
- `source .../activate` — switches your shell to use that env
- `ansible` — the CLI (`ansible`, `ansible-playbook`, `ansible-galaxy`)
- `pywinrm` — Python library for WinRM/PSRP (required to talk to Windows; without it you get `No module named 'winrm'`)

Optional for Windows modules:

```bash
ansible-galaxy collection install ansible.windows community.windows
```

> `.venv/` is gitignored (`ansible/.venv/.gitignore`) — each student creates their own.

## 2. Ad-hoc ping via Docker (no inventory yet)

Fastest way to verify Ansible works — no SSH/WinRM.

```bash
docker run -d --name ansible-test --rm alpine sleep 3600
ansible all -i "ansible-test," -c docker -m ping
```

Breakdown:
- `ansible all` — run against host pattern `all`
- `-i "ansible-test,"` — inline inventory; trailing `,` tells Ansible it's a host list, not a file
- `-c docker` — connection plugin `docker` (exec into container, like `docker exec`)
- `-m ping` — the `ping` module (not ICMP, just verifies Ansible can connect and run Python)

Expected: `ansible-test | SUCCESS => {"ping": "pong"}`. Then `docker rm -f ansible-test`.

## 3. Inventory file

File: `ansible/inventory/windows.ini`

```ini
[windows]
student01 ansible_host=40.81.225.81

[windows:vars]
ansible_connection=psrp
ansible_port=5986
ansible_user=wakizu
ansible_password=!BRr39E,BAPUWq
ansible_psrp_auth=basic
ansible_psrp_cert_validation=ignore
```

Line by line:
- `[windows]` — group named `windows`. Groups let you target `hosts: windows` in playbooks.
- `student01` — inventory hostname (logical name, used as `inventory_hostname`).
- `ansible_host=40.81.225.81` — real IP/host Ansible connects to (overrides hostname).
- `[windows:vars]` — variables applied to every host in `[windows]`.
- `ansible_connection=psrp` — use PSRP (PowerShell Remoting Protocol) over WinRM. Alternative: `winrm`. PSRP is newer and recommended.
- `ansible_port=5986` — WinRM HTTPS port (5985 = HTTP, 5986 = HTTPS).
- `ansible_user` / `ansible_password` — Windows credentials.
- `ansible_psrp_auth=basic` — auth method (`basic` needs HTTPS; `ntlm` also common).
- `ansible_psrp_cert_validation=ignore` — skip cert check. Our VM uses self-signed cert from `ConfigureRemotingForAnsible.ps1` (`terraform/main.tf:136`). Use `ignore` for labs; `validate` only with CA-signed cert.

## 4. Ad-hoc ping via inventory

```bash
ansible windows -i ansible/inventory/windows.ini -m ansible.windows.win_ping
```

- `windows` — host pattern (all hosts in `[windows]` group)
- `-i ansible/inventory/windows.ini` — inventory file
- `-m ansible.windows.win_ping` — Windows-specific ping (runs PowerShell, returns `pong`)

Playbook equivalent (`ansible/ping.yml`):

```yaml
---
- name: Test Windows connectivity
  hosts: windows
  tasks:
    - name: Ping Windows host
      ansible.windows.win_ping:
```

```bash
ansible-playbook -i ansible/inventory/windows.ini ansible/ping.yml
```

`hosts: windows` must match a group/host in inventory. Ad-hoc = one-off command; playbook = versioned, repeatable.

## 5. First playbook — write a file

File: `ansible/hello.yml` (no variables yet)

```yaml
---
- name: Write hello world to desktop
  hosts: windows
  tasks:
    - name: Write hello world text file to desktop
      ansible.windows.win_copy:
        content: "hello world"
        dest: "{{ ansible_facts['env'].USERPROFILE }}\\Desktop\\hello.txt"

    - name: Create application directory
      ansible.windows.win_file:
        path: C:\apps\training
        state: directory
```

Concepts:
- `hosts: windows` — which inventory group to run on
- `tasks` — ordered list
- `ansible.windows.win_copy` / `win_file` — Windows modules (use `ansible.windows.*` for Windows, not `ansible.builtin.copy`)
- `{{ ansible_facts['env'].USERPROFILE }}` — fact gathered at start (`C:\Users\wakizu`). Always use `ansible_facts['...']`, not bare `ansible_env` (deprecated `INJECT_FACTS_AS_VARS`).

Run:

```bash
ansible-playbook -i ansible/inventory/windows.ini ansible/hello.yml
```

Verify on VM: `Desktop\hello.txt` and `C:\apps\training\` exist.

## 6. Variables — inline host vars

Inline in `inventory/windows.ini`:

```ini
[windows]
student01 ansible_host=40.81.225.81 training_path=C:\apps\training
```

Use in `hello.yml`:

```yaml
    - name: Create application directory
      ansible.windows.win_file:
        path: "{{ training_path }}"
        state: directory
```

Works but gets messy with many vars/passwords.

## 7. Variables — host_vars directory (recommended)

Ansible auto-loads `host_vars/<hostname>.yml` and `group_vars/<group>.yml` relative to playbook/inventory.

```
ansible/
├── inventory/windows.ini
├── host_vars/
│   └── student01.yml
├── hello.yml
└── iis.yml
```

`ansible/host_vars/student01.yml`:

```yaml
training_path: C:\apps\training
```

Remove `training_path=` from `inventory/windows.ini`:

```ini
[windows]
student01 ansible_host=40.81.225.81
```

`hello.yml` stays `path: "{{ training_path }}"` — no change. Same for `group_vars/windows.yml` (applies to whole group) or `host_vars/student02.yml` with a different path — same playbook, different per-host values.

Debug host var:

```yaml
    - name: Show host variable value
      ansible.builtin.debug:
        msg: "training_path for {{ inventory_hostname }} is {{ training_path }}"
```

## 8. Next: IIS lab

`ansible/iis.yml` installs IIS and writes `C:\inetpub\wwwroot\index.html`. Exposed via NSG rule `HTTP` (port 80, `terraform/main.tf:62`). Windows Firewall rule is auto-created by `Web-Server` feature — no manual `win_firewall_rule` needed.

```bash
ansible-playbook -i ansible/inventory/windows.ini ansible/iis.yml
curl http://40.81.225.81/
```
