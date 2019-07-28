#!/bin/bash -x

DOCKER_VERSION="18.09.7"

if [ -n "$1" ]; then
    DOCKER_VERSION="$1"
fi

systemctl stop firewalld 
systemctl disable firewalld


yum install -y yum-utils device-mapper-persistent-data lvm

yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

DOCKER_INSTALL_VERSION=$(repoquery --show-duplicates docker-ce | grep $DOCKER_VERSION)

yum install -y $DOCKER_INSTALL_VERSION

systemctl enable docker.service
systemctl start docker

DOCKER_CLI_VERSION=$(repoquery --show-duplicates docker-ce-cli* | grep $DOCKER_VERSION)

yum downgrade -y $DOCKER_CLI_VERSION