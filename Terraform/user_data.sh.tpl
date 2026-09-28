#!/bin/bash
set -euxo pipefail

dnf install -y nginx

cat > /etc/nginx/nginx.conf <<'CONF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events { worker_connections 1024; }
http {
  access_log /var/log/nginx/access.log;
  include /etc/nginx/mime.types;
  default_type text/html;
  server {
    listen ${app_port};
    root /usr/share/nginx/html;
    location /health { return 200 'ok'; }
  }
}
CONF

# IMDSv2
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<EOF
<h1>Hello from $IID</h1>
<p>Availability Zone: $AZ</p>
EOF

systemctl enable --now nginx