################################################################################
# variables
################################################################################

REPOSITORY     := takumi/debian-ignition-builder
APT_MIRROR_URL := http://proxy.apt.internal:3142/debian
SUITE          ?= stable
VARIANT        ?= apt
ARCHITECTURES  ?= amd64
COMPONENTS     ?= main,contrib,non-free

# packages
INCLUDE_PACKAGES ?=
# web
INCLUDE_PACKAGES += ca-certificates
INCLUDE_PACKAGES += curl
INCLUDE_PACKAGES += wget
# security
INCLUDE_PACKAGES += sudo
INCLUDE_PACKAGES += policykit-1
INCLUDE_PACKAGES += openssh-server
# systemd
INCLUDE_PACKAGES += init
INCLUDE_PACKAGES += dbus
INCLUDE_PACKAGES += dbus-user-session
INCLUDE_PACKAGES += systemd
INCLUDE_PACKAGES += systemd-sysv
INCLUDE_PACKAGES += systemd-timesyncd
INCLUDE_PACKAGES += libpam-systemd
INCLUDE_PACKAGES += libnss-systemd
INCLUDE_PACKAGES += libnss-resolve
INCLUDE_PACKAGES += libnss-myhostname
# timezone
INCLUDE_PACKAGES += tzdata
# networking
INCLUDE_PACKAGES += ethtool
INCLUDE_PACKAGES += iproute2
INCLUDE_PACKAGES += iputils-ping
INCLUDE_PACKAGES += netbase
INCLUDE_PACKAGES += netcat-openbsd
# tuning
INCLUDE_PACKAGES += irqbalance
# utils
INCLUDE_PACKAGES += bash-completion
INCLUDE_PACKAGES += htop
INCLUDE_PACKAGES += less
INCLUDE_PACKAGES += lsof
INCLUDE_PACKAGES += patch
INCLUDE_PACKAGES += vim-tiny

IGNITION_REPOSITORY := github.com/coreos/ignition
IGNITION_VERSION    := $(shell git -C ignition describe --dirty --always)
IGNITION_LDFLAGS    := -X $(IGNITION_REPOSITORY)/v2/internal/version.Raw=$(IGNITION_VERSION) -s -w

################################################################################
# default
################################################################################

.PHONY: default
default: clean ignition rootfs

################################################################################
# builder
################################################################################

.PHONY: builder
builder:
	@docker build -t $(REPOSITORY):latest .

################################################################################
# ignition
################################################################################

.PHONY: ignition
ignition:
	@mkdir -p ignition/bin
	@cd ignition && \
		CGO_ENABLED=1 \
		GO111MODULE=on \
		go build -v \
		-trimpath \
		-mod=vendor \
		-buildmode=pie \
		-ldflags "${IGNITION_LDFLAGS}" \
		-o bin/ignition \
		$(IGNITION_REPOSITORY)/v2/internal
	@cd ignition && \
		CGO_ENABLED=0 \
		GO111MODULE=on \
		go build -v \
		-trimpath \
		-mod=vendor \
		-ldflags "${IGNITION_LDFLAGS}" \
		-o bin/ignition-validate \
		$(IGNITION_REPOSITORY)/v2/validate

################################################################################
# rootfs
################################################################################

.PHONY: rootfs
rootfs:
	@docker run \
		--rm -i -t \
		--privileged \
		-v $(CURDIR)/ignition:/ignition:ro \
		-v /tmp:/tmp $(REPOSITORY):latest \
		mmdebstrap \
		--variant='$(VARIANT)' \
		--components='$(COMPONENTS)' \
		--architectures='$(ARCHITECTURES)' \
		--include='$(INCLUDE_PACKAGES)' \
		--dpkgopt='path-exclude=/usr/share/gnome/help/*' \
		--dpkgopt='path-exclude=/usr/share/help/*' \
		--dpkgopt='path-exclude=/usr/share/info/*' \
		--dpkgopt='path-exclude=/usr/share/locale/*' \
		--dpkgopt='path-exclude=/usr/share/man/*' \
		--dpkgopt='path-exclude=/usr/share/omf/*' \
		--dpkgopt='path-exclude=/usr/share/doc/*' \
		--dpkgopt='path-include=/usr/share/doc/*/copyright' \
		--dpkgopt='path-include=/usr/share/doc/*/changelog.Debian.*' \
		--customize-hook='ln -sf "../run/systemd/resolve/stub-resolv.conf" "$$1/etc/resolv.conf"' \
		--customize-hook='echo "127.0.0.1 localhost.localdomain localhost" > "$$1/etc/hosts"' \
		--customize-hook='echo "localhost" > "$$1/etc/hostname"' \
		--customize-hook='rm -f "$$1/var/lib/dbus/machine-id"' \
		--customize-hook='rm -f "$$1/etc/machine-id"' \
		--customize-hook='touch "$$1/var/lib/dbus/machine-id"' \
		--customize-hook='touch "$$1/etc/machine-id"' \
		--customize-hook='install -m 0755 /ignition/bin/ignition $$1/bin/ignition' \
		--customize-hook='install -m 0755 /ignition/bin/ignition-validate $$1/bin/ignition-validate' \
		--customize-hook='install -m 0755 /ignition/dracut/30ignition/ignition-kargs-helper.sh $$1/sbin/ignition-kargs-helper' \
		--customize-hook='install -m 0755 /ignition/dracut/30ignition/ignition-generator $$1/lib/systemd/system-generators/' \
		--customize-hook='install -m 0644 /ignition/dracut/30ignition/*.service $$1/lib/systemd/system/' \
		--customize-hook='install -m 0644 /ignition/dracut/30ignition/*.target $$1/lib/systemd/system/' \
		--customize-hook='install -m 0644 /ignition/dracut/30ignition/*.rules $$1/lib/udev/rules.d/' \
		--customize-hook='chroot $$1 dpkg -l | sed -E "1,5d" | awk "{print \$$2 \"\t\" \$$3}" > /tmp/rootfs.manifests' \
		--hook-directory='/usr/share/mmdebstrap/hooks' \
		'$(SUITE)' '/tmp/rootfs' '$(APT_MIRROR_URL)'
	@cd /tmp/rootfs && sudo find . -type f -print | sudo cpio -ov | pixz > /tmp/rootfs.cpio.xz

################################################################################
# clean
################################################################################

.PHONY: clean
clean:
	@docker system prune -f
	@docker volume prune -f
	@git -C ignition clean -xdf
	@sudo rm -fr /tmp/rootfs*
