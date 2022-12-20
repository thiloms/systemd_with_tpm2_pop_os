#!/bin/bash

mode="${1:-in_docker}"

#Usage:
# mode = [ on_this_host | in_docker* ]
# 		defaults to 'in_docker'.


# Prepare apt environment
function configure_apt_environment()
{
# Only if running inside a Docker container
        if [ -f /.dockerenv ]; then
          echo "I'm inside a docker container"
          # remove content from /etc/apt
          rm -rf /etc/apt/*
          # copy recursive /etc/apt from Docker host mounted at /etc/apt-pop
          cp -R /etc/apt-pop/* /etc/apt/
          # Remove hook (may only be required in my setup)
          # The original script will create a snapshot before an apt command make any changes
          # As this script will be executed inside a Docker Container the snapshot is not required
          rm -rf /etc/apt/apt.conf.d/80-timeshift-autosnap-apt
          # Update
          apt update
          # Install ca-certificates as some updates repos will cause an error due to missing certificates
          apt -y install ca-certificates
          # Update again with installed certificates (this time it will work)
          apt update
          # Update ubuntu:22.04 container with the latest updates from Pop!_OS 22.04 incl. downgrade if required
          apt -y upgrade --allow-downgrades
        fi
}

function enable_source_packages()
{
	sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list
}

function update_apt()
{
	apt-get update
}

function install_dependencies()
{
	apt-get install -y build-essential fakeroot dpkg-dev libtss2-dev
}

function get_systemd_build_dependencies()
{
	# Build dependencies based on installed systemd version on Docker host
	apt-get build-dep -y systemd=${SYSTEMD_VERSION}
}
function get_systemd_src()
{
	# Get systemd sources based on installed systemd version on Docker host
	apt-get source systemd=${SYSTEMD_VERSION}
}

function build_systemd_with_tpm2_support()
{
	cd systemd-249.11
	sed -i 's/tpm2=false/tpm2=true/g' debian/rules
	dpkg-buildpackage -rfakeroot -uc -b
}


case "$mode" in
	"on_this_host")
		#These could be done in a Dockerfile.
		#will need a timezone setting!
                configure_apt_environment
		enable_source_packages
		update_apt
		install_dependencies
		get_systemd_build_dependencies

		#this needs to be done inside the image:
		get_systemd_src
		build_systemd_with_tpm2_support
		;;
	"in_docker")
		# Run Docker container based on ubuntu:22.04 including:
		#   - host volume mount of current folder to /build
		#   - host volume mount of /etc/apt folder to /etc/apt-pop
		#   - set environment variable SYSTEMD_VERSION with systemd version of Docker host
		docker run --rm -it -v $(pwd):/build --env SYSTEMD_VERSION=$(systemd --version | head -1 | awk '{ print substr($3, 2, length($3)-2)}') -v /etc/apt:/etc/apt-pop:ro -w /build ubuntu:22.04 ./build_systemd_with_tpm2_support.sh "on_this_host"
		;;
esac
