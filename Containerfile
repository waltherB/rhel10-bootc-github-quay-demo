FROM registry.redhat.io/rhel10/rhel-bootc:latest

ARG RHSM_ACTIVATION_KEY
ARG RHSM_ORG
ARG DEMO_PUB_KEY

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
      rhsm_config_file=$(find /usr/lib64 /usr/lib -name config.py | grep rhsm | head -n 1); \
      if [ -f "$rhsm_config_file" ]; then \
        cp "$rhsm_config_file" "${rhsm_config_file}.bak"; \
        sed -i 's/\(def in_container() -> bool:\)/\1\n    return False/g' "$rhsm_config_file"; \
      fi; \
      subscription-manager register --force --activationkey="$RHSM_ACTIVATION_KEY" --org="$RHSM_ORG"; \
      subscription-manager repos --enable=rhel-10-for-${repo_arch}-baseos-rpms --enable=rhel-10-for-${repo_arch}-appstream-rpms; \
    else \
      echo "RHSM_ACTIVATION_KEY or RHSM_ORG not provided - continuing but dnf may fail"; \
    fi; \
    dnf -y install \
      httpd \
      firewalld \
      jq \
      lynx \
      curl \
      vim-enhanced \
      bash-completion \
      sudo \
      selinux-policy-targeted \
      qemu-guest-agent \
      podman \
      python3-pip \
      python3-devel \
      git \
      libffi-devel \
      openssl-devel \
      systemd-resolved \
      policycoreutils --nogpgcheck; \
    dnf update -y; \
    if [ -n "$RHSM_ACTIVATION_KEY" ] && [ -n "$RHSM_ORG" ]; then \
      if subscription-manager identity >/dev/null 2>&1; then \
        subscription-manager unregister || true; \
        subscription-manager clean || true; \
      fi; \
      if [ -f "${rhsm_config_file}.bak" ]; then \
        mv "${rhsm_config_file}.bak" "$rhsm_config_file"; \
      fi; \
      rm -rf /etc/pki/entitlement /etc/pki/consumer || true; \
    fi 
RUN  systemctl enable systemd-resolved 
COPY app/index.html /var/www/html/index.html
COPY files/motd /etc/motd
COPY files/resolv.conf /etc/resolv.conf
COPY scripts/vm-status.sh /usr/local/bin/vm-status
COPY scripts/vm-upgrade.sh /usr/local/bin/vm-upgrade
RUN chmod +x /usr/local/bin/vm-status /usr/local/bin/vm-upgrade

RUN systemctl enable httpd serial-getty@tty1.service

RUN echo 'u demo 1000 "Demo User" /home/demo /bin/bash' > /usr/lib/sysusers.d/demo.conf

RUN systemd-sysusers && mkdir -p /var/home/demo && chown demo:demo /var/home/demo

RUN echo 'demo:redhat' | chpasswd && \
    echo 'demo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/demo && \
    chmod 0440 /etc/sudoers.d/demo && \
  test -n "$DEMO_PUB_KEY" && \
    install -d -m 0755 /home/demo/.ssh && \
    printf '%s\n' "$DEMO_PUB_KEY" > /home/demo/.ssh/authorized_keys && \
    chown -R demo:demo /home/demo/.ssh && \
    chmod 0600 /home/demo/.ssh/authorized_keys

RUN systemctl enable httpd

# Configure DNS to use Cloudflare (1.1.1.1) and Google (8.8.8.8)
# Both /etc/resolv.conf and NetworkManager configuration for persistence
RUN mkdir -p /etc/NetworkManager/conf.d && \
    mkdir -p /etc/systemd/resolved.conf.d && \
    printf '%s\n' \
      '[main]' \
      'dns=systemd-resolved' \
      'dhcp=dhclient' > /etc/NetworkManager/conf.d/99-dns.conf && \
    printf '%s\n' \
      '[Resolve]' \
      'DNS=1.1.1.1 8.8.8.8' \
      'FallbackDNS=1.1.1.1 8.8.8.8' \
      'DNSSECNegativeTrustAnchors=' > /etc/systemd/resolved.conf.d/99-dns.conf && \
    printf '%s\n' \
      'nameserver 1.1.1.1' \
      'nameserver 8.8.8.8' > /etc/resolv.conf && \
    chmod 0644 /etc/resolv.conf

RUN echo "KEYMAP=dk-mac_nodeadkeys" > /etc/vconsole.conf

RUN dnf remove -y \
    kernel-debug \
    kernel-debug-core \
    kernel-debug-modules \
    kernel-debug-modules-core || true

RUN dnf clean all && \
    rm -rf /run/httpd /run/rhsm \
           /var/cache/dnf/* \
           /var/lib/dnf/history.sqlite* \
           /var/lib/rhsm/cache/* /var/lib/rhsm/productid.js \
           /var/log/dnf.librepo.log /var/log/dnf.log /var/log/dnf.rpm.log \
           /var/log/hawkey.log /var/log/rhsm/rhsm.log

#RUN bootc container lint
