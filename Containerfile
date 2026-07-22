FROM registry.redhat.io/rhel10/rhel-bootc:latest

# Build-time args (passed from CI)
ARG RHSM_ACTIVATION_KEY
ARG RHSM_ORG
ARG DEMO_PUB_KEY

# Register, enable repos, install packages, then unregister and clean entitlement files in one RUN
RUN set -ex; \
    arch=$(uname -m); \
    if [ "$arch" = "x86_64" ]; then \
      repo_arch="x86_64"; \
    elif [ "$arch" = "aarch64" ]; then \
      repo_arch="aarch64"; \
    else \
      repo_arch="x86_64"; \
    fi; \
    if [ -n "$RHSM_ACTIVATION_KEY" ] && [ -n "$RHSM_ORG" ]; then \
      subscription-manager register --activationkey="$RHSM_ACTIVATION_KEY" --org="$RHSM_ORG" || true; \
      subscription-manager repos --enable=rhel-10-for-${repo_arch}-baseos-rpms --enable=rhel-10-for-${repo_arch}-appstream-rpms || true; \
    else \
      echo "RHSM_ACTIVATION_KEY or RHSM_ORG not provided - continuing but dnf may fail"; \
    fi; \
    dnf -y install \
      httpd \
      firewalld \
      jq \
      curl \
      vim-enhanced \
      bash-completion \
      sudo \
      selinux-policy-targeted \ 
      qemu-guest-agent \
      policycoreutils; \
    # Unregister & remove entitlement files so credentials are not present in final image
    if subscription-manager identity >/dev/null 2>&1; then \
      subscription-manager unregister || true; \
      subscription-manager clean || true; \
      rm -rf /etc/pki/entitlement /etc/pki/consumer || true; \
    fi

COPY app/index.html /var/www/html/index.html
COPY files/motd /etc/motd
COPY scripts/vm-status.sh /usr/local/bin/vm-status
COPY scripts/vm-upgrade.sh /usr/local/bin/vm-upgrade
RUN chmod +x /usr/local/bin/vm-status /usr/local/bin/vm-upgrade

COPY <<EOF /usr/lib/sysusers.d/demo.conf
u demo 1000 "Demo User" /home/demo /bin/bash
EOF

RUN systemd-sysusers && mkdir -p /var/home/demo && chown demo:demo /var/home/demo

RUN echo 'demo:redhat' | chpasswd && \
    echo 'demo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/demo && \
    chmod 0440 /etc/sudoers.d/demo && \
    install -d -m 0755 /home/demo/.ssh && \
    printf '%s\n' "$DEMO_PUB_KEY" > /home/demo/.ssh/authorized_keys && \
    chown -R demo:demo /home/demo/.ssh && \
    chmod 0600 /home/demo/.ssh/authorized_keys

RUN systemctl enable httpd
RUN echo "KEYMAP=dk-mac_nodeadkeys" > /etc/vconsole.conf

RUN dnf clean all && \
    rm -rf /run/httpd /run/rhsm \
           /var/cache/dnf/* \
           /var/lib/dnf/history.sqlite* \
           /var/lib/rhsm/cache/* /var/lib/rhsm/productid.js \
           /var/log/dnf.librepo.log /var/log/dnf.log /var/log/dnf.rpm.log \
           /var/log/hawkey.log /var/log/rhsm/rhsm.log

RUN bootc container lint