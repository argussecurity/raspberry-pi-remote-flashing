FROM ubuntu:22.04

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# add required tools
RUN apt update \
 && apt install -y \
	    sudo \
		wget \
		patch \
		parted \
		dosfstools \
		bzip2 \
		make \
		bison\
		flex \
		kpartx \
		u-boot-tools \
		gcc-arm-linux-gnueabi \
		coreutils

# add required develop tools
RUN apt update \
&& apt install -y \
		git

# Create 'user' account
RUN groupadd -g $GID -o user

# Add 'user' to sudo group (password-free)
RUN useradd -u $UID -m -g user user \
	&& echo 'user ALL = NOPASSWD: ALL' > /etc/sudoers.d/user \
	&& chmod 0440 /etc/sudoers.d/user

USER root
