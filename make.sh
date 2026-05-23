#!/bin/bash
cat > /root/goose/server_config.json <<'EOF'
{
  "server_host": "0.0.0.0",
  "server_port": 8443,
  "tunnel_key": "d9840514c1d12a8b12cf6df9c84796c1b3a99d7b642c38a40f3b33ec6d99430d"
}
EOF
