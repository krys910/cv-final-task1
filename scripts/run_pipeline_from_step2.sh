#!/usr/bin/env bash
# 从 Step 2 严格续跑 B → C → 背景 → 融合（Step 5 需 B/C mesh 均存在）
exec env START_STEP=2 "$(dirname "$0")/run_full_pipeline.sh" "$@"
