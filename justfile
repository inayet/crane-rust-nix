# Justfile - Enhanced with Multi-Level Interactive Commands
# This Justfile integrates ripgrep (rg), fzf, zoxide, and aspell (optional)
# to provide a deep, interactive command-line experience.
# Ensure the following tools are installed:
#   - ripgrep (rg)
#   - fzf
#   - bat
#   - zoxide
#   - aspell (optional, for spell-check hints)
#
# Usage examples:
#   just service [pattern]
#   just search <pattern>
#   just files
#   just jump [dir]
#   (plus other Nix and Git commands as defined below)

# ===== Settings ===== #

# Define aliases for frequent commands
alias b := rebuild
alias d := ezaD
alias a := ezaA
alias l := list-generations
alias gs := status
alias j := just
alias r := upfrefresh

# Set Justfile options
set positional-arguments
set shell := ["bash", "-c"]

just:
	@just --list --color=always

# ===== System & Utilities ===== #

# List directories (using eza as ls alternative)
[group("File Utilities")]
ezaD:
	@eza -D

# List all files (incl. hidden) with details (using eza)
[group("File Utilities")]
ezaA:
	@eza -ola

# --- Advanced Systemctl Management ---
#
# Interactive multi-level systemctl management command.
# This recipe does the following:
# 1. Lists all systemd service unit files (filtered by an optional pattern).
# 2. Uses fzf to let you select a service.
# 3. Optionally checks for typos using aspell.
# 4. Confirms the selected service.
# 5. Uses fzf to select a desired action (status, start, stop, restart, enable, disable, etc.).
# 6. Asks for final confirmation before executing sudo systemctl.
#
# Usage:
#   just service [optional-filter-pattern]
[doc("Multi-level interactive systemctl management (includes spell-check hints)")]
[group("System")]
service pattern="" action="":
	#!/usr/bin/env bash
	# 1. Get list of service unit files, optionally filtering with the pattern
	if [ -n "{{pattern}}" ]; then
		echo "Filtering services for pattern \"{{pattern}}\"..."
		services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}' | rg -i "{{pattern}}")
	else
		services=$(systemctl list-unit-files --type=service --no-pager --no-legend | awk '{print $1}')
	fi

	if [ -z "$services" ]; then
		echo "No services found matching pattern." >&2
		exit 0
	fi

	# 2. Use fzf to select a service
	service=$(echo "$services" | fzf --prompt "Select service: ")
	if [ -z "$service" ]; then
		echo "No service selected." >&2
		exit 0
	fi

	# 3. Optional: Spell-check the service name (if aspell is installed)
	if command -v aspell >/dev/null 2>&1; then
		suggestions=$(echo "$service" | aspell list)
		if [ -n "$suggestions" ]; then
			echo "Warning: The service name \"$service\" might be misspelled. Suggestions:" >&2
			echo "$suggestions" >&2
		fi
	fi

	# 4. Confirm the selected service
	read -p "Confirm selected service [$service] (Y/n)? " confirm
	if [ "$confirm" != "" ] && [ "$confirm" != "Y" ] && [ "$confirm" != "y" ]; then
		echo "Aborting."; exit 0
	fi

	# 5. Select an action via fzf if not provided
	if [ -z "{{action}}" ]; then
		action=$(printf "status\nstart\nstop\nrestart\nenable\ndisable\nenable-now\ndisable-now" | fzf --prompt "Select action: ")
		if [ -z "$action" ]; then
			echo "No action selected." >&2; exit 0
		fi
	else
		action="{{action}}"
	fi

	# 6. Final confirmation before execution
	read -p "Execute 'sudo systemctl $action $service'? (Y/n) " final
	if [ "$final" != "" ] && [ "$final" != "Y" ] && [ "$final" != "y" ]; then
		echo "Command aborted."; exit 0
	fi

	echo "Executing: sudo systemctl $action $service"
	sudo systemctl "$action" "$service"

# Open man pages in Firefox browser
[group("System")]
man subject:
	@man --html=firefox --all {{subject}}


# Fuzzy find and open a file from current directory (via fzf)
# Preview file content with bat; opens the selected file in $EDITOR
[group("Search & Navigate")]
files:
	#!/usr/bin/env bash
	if ! command -v rg &>/dev/null || ! command -v fzf &>/dev/null || ! command -v bat &>/dev/null; then
		echo "Error: Required tools (ripgrep, fzf, bat) are not installed." >&2
		exit 1
	fi
	file=$(rg --files --hidden --glob "!.git" --glob "!node_modules" 2>/dev/null | \
		fzf --prompt "Select file: " \
			--preview "bat --style=numbers --color=always {}" \
			--preview-window=right:60%:wrap)
	if [ -z "$file" ]; then
		echo "No file selected." >&2
		exit 0
	fi
	if [ ! -f "$file" ]; then
		echo "Error: Selected file does not exist." >&2
		exit 1
	fi
	exec ${EDITOR:-nano} "$file"
	
# Jump to a directory (using zoxide & fzf)
# Opens a subshell in the selected directory
[doc("Jump to a directory via zoxide; spawn shell in that directory")]
[group("Search & Navigate")]
jump dir="":
	#!/usr/bin/env bash
	PATTERN="{{dir}}"
	if [ -z "$PATTERN" ]; then
		DIR=$(zoxide query -i)
	else
		DIR=$(zoxide query -i "$PATTERN")
	fi
	if [ -z "$DIR" ]; then
		echo "No directory found for: $PATTERN" >&2
		exit 0
	fi
	cd "$DIR" && exec ${SHELL:-bash}

# ===== Nix Commands ===== #

[group("NixOS")]
list-generations:
	@nixos-rebuild list-generations

[group("Nix Flake")]
upfrefresh:
	# Update all flake inputs
	nix flake update

[group("Nix Flake")]
upflock:
	@nix flake lock

[group("Nix Flake")]
upflock-dir:
	# Update nix-ld-dir flake.lock
	cd nix-ld-dir && nix flake lock

[group("Nix Flake")]
upuinput:
	@nix flake metadata --json | nix run nixpkgs#jq '.locks.nodes.root.inputs[]' | \
	  sed 's/"//g' | nix run nixpkgs#fzf | xargs nix flake update --repair

[group("Nix Flake")]
show:
	@nix flake show

[group("Nix Flake")]
check:
	@nix flake check

[group("NixOS")]
rebuild-container:
	# Rebuild container
	sudo nixos-rebuild switch --flake .#nixos --target-host hadicloud@192.168.0.10

[group("NixOS")]
rebuild:
	# Rebuild the system
	sudo nixos-rebuild switch --flake .#nixos

[group("NixOS")]
rebuild-fast:
	# Fast rebuild without updating inputs
	sudo nixos-rebuild switch --flake .#nixos --fast

[doc("View latest rebuild log")]
[group("NixOS")]
view-log:
	#!/usr/bin/env bash
	# Find the most recent log file
	LATEST_LOG=$(ls -t logs/rebuild*.log 2>/dev/null | head -n1)
	if [ -z "$LATEST_LOG" ]; then
		echo "No log files found in logs directory"
		exit 1
	fi
	# Display the log file
	cat "$LATEST_LOG"

[doc("Refresh flake inputs, commit changes, and rebuild system")]
[group("NixOS")]
gr message="":
	#!/usr/bin/env bash
	# Format and commit any pending changes
	if ! just gact "{{message}}"; then
		echo "Failed to format and commit changes" >&2
		exit 1
	fi
	# Update flake locks
	if ! just upflock-dir; then
		echo "Failed to update nix-ld-dir flake lock" >&2
		exit 1
	fi
	if ! just upfrefresh; then
		echo "Failed to update flake inputs" >&2
		exit 1
	fi
	# Rebuild the system
	just rebuild

[group("Nix Packages")]
locate pkg:
	@nix-search --flake flake:nixpkgs --verbose=0 -e '{{ pkg }}'

[group("Nix Packages")]
locatb pkg:
	@nix-search --flake flake:nixpkgs --verbose=true '{{ pkg }}'

[group("Nix Packages")]
buildpkgs pkg:
	@nix build nixpkgs#"{{ pkg }}"

[group("Nix Packages")]
run pkg:
	@nix shell nixpkgs#"{{ pkg }}"

[group("Nix Packages")]
repl:
	@nix repl -f flake:nixpkgs

[group("Nix GC")]
gc days:
	#!/usr/bin/env bash
	if [ -f /.dockerenv ]; then
		echo "Running in container environment. Using nix commands without sudo..."
		nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than {{ days }}d
		nix-collect-garbage --delete-older-than {{ days }}d
	else
		sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than {{ days }}d
		sudo nix-collect-garbage --delete-older-than {{ days }}d
	fi

[group("Nix GC")]
gc-all:
	#!/usr/bin/env bash
	if [ -f /.dockerenv ]; then
		echo "Running in container environment. Using nix commands without sudo..."
		# Without sudo
		nix store gc --debug
		nix-collect-garbage -d
		nix-collect-garbage
		nix store optimise
	else
		# With sudo
		sudo nix store gc --debug
		sudo nix-collect-garbage -d
		sudo nix-collect-garbage
		sudo nix store optimise
	fi

# ===== Git Commands ===== #

[group("git")]
gitdiff:
	@git diff -- ':^flake.lock' ':^pkgs/_sources/*'

[group("git")]
gitdiffcached:
	@git diff --cached -- ':^flake.lock' ':^pkgs/_sources/*'

[doc("Commit changes (if no message is provided, editor opens)")]
[group("git")]
commit message="":
	#!/usr/bin/env bash
	if [ -z "{{message}}" ]; then
		git commit
	else
		git commit -m "{{message}}"
	fi

[group("git")]
status:
	@git status

[group("git")]
i:
	@git status --ignored

[group("git")]
add:
	@git add .

[group("git")]
lint:
	@treefmt

[doc("Format code, stage changes, commit with optional message, and show status")]
[group("git")]
gact message="":
	#!/usr/bin/env bash
	# Run formatting first
	if ! just lint; then
		echo "Formatting failed" >&2
		exit 1
	fi
	# If formatting succeeded, proceed with git operations
	just gac "{{message}}"

[doc("Stage changes, commit with optional message, and show status")]
[group("git")]
gac message="":
	#!/usr/bin/env bash
	# Stage changes
	git add .
	# Commit with message or open editor
	if [ -z "{{message}}" ]; then
		git commit
	else
		git commit -m "{{message}}"
	fi
	# Show status
	git status

[group("git")]
pull:
	@git pull --rebase

# Knowledge system commands
[group("Knowledge")]
learn TYPE DESC SOLUTION:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh learn "{{TYPE}}" "{{DESC}}" "{{SOLUTION}}"

[group("Knowledge")]
analyze:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh analyze

[group("Knowledge")]
suggest TYPE CONTEXT:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh suggest "{{TYPE}}" "{{CONTEXT}}"

[group("Knowledge")]
kreport:
    @chmod +x nixos/tools/knowledge-system.sh
    @./nixos/tools/knowledge-system.sh report

[group("Knowledge")]
kinit:
    @find nixos/tools -name "*.sh" -exec chmod +x {} +
    @./nixos/tools/knowledge-system.sh init
    @./nixos/tools/knowledge-system.sh hook

# Alias for quick access
k := "kinit"
