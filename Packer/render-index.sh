#!/bin/bash
set -euo pipefail

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

sed -e "s/{{INSTANCE_ID}}/$IID/" -e "s/{{AZ}}/$AZ/" \
  /usr/share/nginx/html/index.html.tpl > /usr/share/nginx/html/index.html