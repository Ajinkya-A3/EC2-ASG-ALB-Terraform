#!/bin/bash
set -euxo pipefail

sudo dnf install -y nginx

# App code + nginx config, baked into the image
sudo cp /tmp/app/index.html.tpl /usr/share/nginx/html/index.html.tpl
sudo cp /tmp/nginx.conf /etc/nginx/nginx.conf

# Boot-time render script + its systemd unit
sudo mkdir -p /opt/app
sudo cp /tmp/render-index.sh /opt/app/render-index.sh
sudo chmod +x /opt/app/render-index.sh
sudo cp /tmp/render-index.service /etc/systemd/system/render-index.service

sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl enable render-index.service