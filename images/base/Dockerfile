# syntax=docker/dockerfile:1
# devbox base — the container's own shell environment and nothing else.
#
# Toolchain layer, harness-free (D2, criterion 7): this file names no agent and
# no harness script. The harness slot is filled by exactly one script selected
# through ARG HARNESS (D3), so adding a harness is adding one file under
# harnesses/ and no edit here. It mounts nothing host-side and copies no host
# file (I1, I4, I6).
#
# Builds with BuildKit: the COPY heredocs below are the canary, since the legacy
# builder parses them but writes empty files — so it fails loudly here.
FROM ubuntu:24.04

# What a harness may reasonably expect to find; zsh is the interactive shell.
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl findutils git gnupg less procps ripgrep \
      tmux unzip vim-tiny wget zsh \
 && rm -rf /var/lib/apt/lists/*

# D9 / criterion 11 — the shell config is written here, at image build, and is
# never mounted or copied from the host. `~/.zshenv` is the non-login rc (zsh
# sources it for every shell), `~/.zshrc` the interactive one. No plugins, no
# network fetch at shell start, no host content.
COPY <<'ZSHENV' /root/.zshenv
export LANG=C.UTF-8
export EDITOR=vim
export PAGER=less
typeset -U path PATH
path=(/root/.local/bin $path)
ZSHENV

COPY <<'ZSHRC' /root/.zshrc
HISTFILE=/root/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS SHARE_HISTORY INTERACTIVE_COMMENTS

autoload -Uz colors && colors
PROMPT='%F{cyan}%m%f:%F{blue}%~%f%# '

alias ll='ls -alF'
alias la='ls -A'
ZSHRC

RUN chsh -s /usr/bin/zsh root

WORKDIR /root
CMD ["/bin/zsh", "-l"]

# The harness seam (D3). HARNESS has no default on purpose: an image with no
# harness chosen is a build error, not a silent no-op.
ARG HARNESS
COPY harnesses/${HARNESS}.sh /opt/devbox/harness.sh
RUN sh /opt/devbox/harness.sh
