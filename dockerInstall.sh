#!/bin/bash

# Installing docker

curl -fsSL test.docker.com -o get-docker.sh && sh get-docker.sh

# Add User to docker group

sudo usermod -aG docker $USER

# Install docker-compose

curl -L https://github.com/linuxserver/docker-docker-compose/releases/download/1.28.5-ls32/docker-compose-armhf | sudo tee /usr/local/bin/docker-compose >/dev/null
