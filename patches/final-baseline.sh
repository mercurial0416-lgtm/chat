#!/usr/bin/env bash
set -euo pipefail

echo "=== v49 insert VAPID public key ==="

cat > app/src/pushConfig.js <<'EOF'
export const VAPID_PUBLIC_KEY = "BAwkeaVBFeJg2VWKfcbiRktUUxlr_XJn-WG4hH9FknOeB9XqQdM8kRdazzhlv2AWOgl5EAmmHtODgVEJl2b48Hk";
EOF

echo "=== v49 VAPID public key inserted ==="
git status --short