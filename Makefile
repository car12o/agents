.PHONY: install uninstall

CONFIG_FILE := $(shell pwd)/AGENTS.md
SKILLS_DIR := $(shell pwd)/skills

###############
### ALL
###############

install: install-claude install-codex install-opencode install-tools

uninstall: uninstall-claude uninstall-codex uninstall-opencode uninstall-tools

###############
### CLAUDE
###############

install-claude:
	@if [ ! -d "$(HOME)/.claude" ]; then \
		echo "WARNING: $(HOME)/.claude does not exist. Skipping."; \
	else \
		echo "=== Installing Claude configuration ==="; \
		rm -f "$(HOME)/.claude/CLAUDE.md"; \
		ln -s "$(CONFIG_FILE)" "$(HOME)/.claude/CLAUDE.md"; \
		echo "  + CLAUDE.md -> $(HOME)/.claude/CLAUDE.md"; \
		mkdir -p "$(HOME)/.claude/skills"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.claude/skills/$$skill_name"; \
			ln -s "$$skill" "$(HOME)/.claude/skills/$$skill_name"; \
			echo "  + $(HOME)/.claude/skills/$$skill_name -> $$skill"; \
		done; \
		echo "Claude installed."; \
	fi

uninstall-claude:
	@if [ ! -d "$(HOME)/.claude" ]; then \
		echo "WARNING: $(HOME)/.claude does not exist. Skipping."; \
	else \
		echo "=== Uninstalling Claude configuration ==="; \
		rm -f "$(HOME)/.claude/CLAUDE.md"; \
		echo "  - $(HOME)/.claude/CLAUDE.md"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.claude/skills/$$skill_name"; \
			echo "  - $(HOME)/.claude/skills/$$skill_name"; \
		done; \
		echo "Claude uninstalled."; \
	fi

###############
### CODEX
###############

install-codex:
	@if [ ! -d "$(HOME)/.codex" ]; then \
		echo "WARNING: $(HOME)/.codex does not exist. Skipping."; \
	else \
		echo "=== Installing Codex configuration ==="; \
		rm -f "$(HOME)/.codex/AGENTS.md"; \
		ln -s "$(CONFIG_FILE)" "$(HOME)/.codex/AGENTS.md"; \
		echo "  + AGENTS.md -> $(HOME)/.codex/AGENTS.md"; \
		mkdir -p "$(HOME)/.codex/skills"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.codex/skills/$$skill_name"; \
			ln -s "$$skill" "$(HOME)/.codex/skills/$$skill_name"; \
			echo "  + $(HOME)/.codex/skills/$$skill_name -> $$skill"; \
		done; \
		echo "Codex installed."; \
	fi

uninstall-codex:
	@if [ ! -d "$(HOME)/.codex" ]; then \
		echo "WARNING: $(HOME)/.codex does not exist. Skipping."; \
	else \
		echo "=== Uninstalling Codex configuration ==="; \
		rm -f "$(HOME)/.codex/AGENTS.md"; \
		echo "  - $(HOME)/.codex/AGENTS.md"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.codex/skills/$$skill_name"; \
			echo "  - $(HOME)/.codex/skills/$$skill_name"; \
		done; \
		echo "Codex uninstalled."; \
	fi

###############
### OPENCODE
###############

install-opencode:
	@if [ ! -d "$(HOME)/.config/opencode" ]; then \
		echo "WARNING: $(HOME)/.config/opencode does not exist. Skipping."; \
	else \
		echo "=== Installing OpenCode configuration ==="; \
		rm -f "$(HOME)/.config/opencode/AGENTS.md"; \
		ln -s "$(CONFIG_FILE)" "$(HOME)/.config/opencode/AGENTS.md"; \
		echo "  + AGENTS.md -> $(HOME)/.config/opencode/AGENTS.md"; \
		mkdir -p "$(HOME)/.config/opencode/skills"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.config/opencode/skills/$$skill_name"; \
			ln -s "$$skill" "$(HOME)/.config/opencode/skills/$$skill_name"; \
			echo "  + $(HOME)/.config/opencode/skills/$$skill_name -> $$skill"; \
		done; \
		echo "OpenCode installed."; \
	fi

uninstall-opencode:
	@if [ ! -d "$(HOME)/.config/opencode" ]; then \
		echo "WARNING: $(HOME)/.config/opencode does not exist. Skipping."; \
	else \
		echo "=== Uninstalling OpenCode configuration ==="; \
		rm -f "$(HOME)/.config/opencode/AGENTS.md"; \
		echo "  - $(HOME)/.config/opencode/AGENTS.md"; \
		for skill in $(SKILLS_DIR)/*/; do \
			skill_name=$$(basename "$$skill"); \
			rm -rf "$(HOME)/.config/opencode/skills/$$skill_name"; \
			echo "  - $(HOME)/.config/opencode/skills/$$skill_name"; \
		done; \
		echo "OpenCode uninstalled."; \
	fi

###############
### TOOLS
###############

TOOLS_DIR := $(shell pwd)/tools
LOCAL_BIN := $(HOME)/.local/bin

install-tools:
	@mkdir -p "$(LOCAL_BIN)"; \
	echo "=== Installing tools ==="; \
	for tool in $(TOOLS_DIR)/*.sh; do \
		tool_name=$$(basename "$$tool" .sh); \
		rm -f "$(LOCAL_BIN)/$$tool_name"; \
		ln -s "$$tool" "$(LOCAL_BIN)/$$tool_name"; \
		echo "  + $(LOCAL_BIN)/$$tool_name -> $$tool"; \
	done; \
	echo "Tools installed."

uninstall-tools:
	@echo "=== Uninstalling tools ==="; \
	for tool in $(TOOLS_DIR)/*.sh; do \
		tool_name=$$(basename "$$tool" .sh); \
		rm -f "$(LOCAL_BIN)/$$tool_name"; \
		echo "  - $(LOCAL_BIN)/$$tool_name"; \
	done; \
	echo "Tools uninstalled."
