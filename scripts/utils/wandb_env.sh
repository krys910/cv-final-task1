#!/usr/bin/env bash
# 加载 WandB 凭据（不提交到 git）。服务器上: echo "KEY" > ~/.wandb_api_key && chmod 600 ~/.wandb_api_key
# shellcheck disable=SC1091
if [[ -f "${HOME}/.wandb_api_key" ]]; then
  export WANDB_API_KEY="$(tr -d '[:space:]' < "${HOME}/.wandb_api_key")"
fi
export WANDB_PROJECT="${WANDB_PROJECT:-cv-final-pj}"
export WANDB_DIR="${WANDB_DIR:-${HOME}/hw3/logs/wandb}"
mkdir -p "$WANDB_DIR"
