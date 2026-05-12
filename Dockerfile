# =============================================================================
# Dockerfile for "Linux Kernel Programming" 2E
# (c) Author: Kaiwan N Billimoria | Publisher: Packt
# https://github.com/PacktPublishing/Linux-Kernel-Programming_2E
#
# Build:
#   docker build -t lkp2e .
#
# Run (privileged is required for many kernel/perf/BPF tools):
#   docker run -it --privileged lkp2e bash
#
# Notes:
#   - linux-headers and linux-tools are pinned to a fixed kernel version
#     because $(uname -r) resolves at build time to the builder host's kernel,
#     which may differ from the container's runtime kernel. Pass
#     --build-arg KERNEL_VER=$(uname -r) at build time if you want them
#     matched to your host.
#   - GUI packages (gnome-system-monitor, yad) are included but need an X11
#     display or VNC to be useful.
#   - openjdk-22-jdk is requested; falls back gracefully if unavailable for
#     the chosen Ubuntu release (adjust UBUNTU_VERSION as needed).
# =============================================================================

ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION}

# Kernel version to install headers/tools for.
# Override at build time: --build-arg KERNEL_VER=5.15.0-91-generic
ARG KERNEL_VER=generic

LABEL maintainer="ishdeshpa"
LABEL description="Linux Kernel Programming 2E – full build and study environment"

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# ── 1. Basic build essentials ────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        make \
        perl \
    && rm -rf /var/lib/apt/lists/*
 
# ── 2. Kernel build dependencies ─────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        asciidoc \
        binutils-dev \
        bison \
        build-essential \
        flex \
        gawk \
        libncurses5-dev \
        ncurses-dev \
        libelf-dev \
        libssl-dev \
        openssl \
        pahole \
        tar \
        util-linux \
        xz-utils \
        zstd \
    && rm -rf /var/lib/apt/lists/*
 
# ── 3. Additional study / tracing / analysis tools ───────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bc \
        bsdextrautils \
        clang \
        coccinelle \
        coreutils \
        cppcheck \
        cscope \
        curl \
        exuberant-ctags \
        fakeroot \
        flawfinder \
        git \
        gnome-system-monitor \
        gnuplot \
        hwloc \
        indent \
        kmod \
        libnuma-dev \
        man-db \
        net-tools \
        numactl \
        openjdk-21-jdk \
        perf-tools-unstable \
        procps \
        psmisc \
        python3-distutils \
        rt-tests \
        smem \
        sparse \
        stress \
        stress-ng \
        sysfsutils \
        trace-cmd \
        tree \
        openssh-server \
        tmux \
        tuna \
        virt-what \
        yad \
    && rm -rf /var/lib/apt/lists/*
 
# ── 4. Linux headers & tools (host-kernel-matched or generic) ────────────────
#    Pass --build-arg KERNEL_VER=$(uname -r) to match your host kernel.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        linux-headers-${KERNEL_VER} \
        linux-tools-${KERNEL_VER} \
    && rm -rf /var/lib/apt/lists/*
 
# ── 5. tldr (Python version, not in standard apt repos) ──────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-pip \
    && pip3 install --no-cache-dir tldr \
    && rm -rf /var/lib/apt/lists/*
 
# ── 6. Neovim – latest stable binary from GitHub releases ──────────────────────
#    apt ships a very stale nvim; pull the official prebuilt tarball instead.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL \
       "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" \
       -o /tmp/nvim.tar.gz \
    && tar -C /opt -xzf /tmp/nvim.tar.gz \
    && ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
    && rm /tmp/nvim.tar.gz
 
# ── 7. LTTng (Linux Trace Toolkit Next Generation) ────────────────────────────
#    Provides userspace + kernel tracing via the LTTng framework.
#    lttng-modules-dkms builds the kernel modules at install time; it requires
#    linux-headers to already be present (installed in step 4).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        lttng-tools \
        lttng-modules-dkms \
        liblttng-ust-dev \
        liblttng-ust1 \
        python3-lttngust \
        babeltrace2 \
    && rm -rf /var/lib/apt/lists/*
 
# ── 8. BCC / eBPF – full stack ────────────────────────────────────────────────
#    bpfcc-tools was added in step 3; this layer adds the dev headers,
#    Python bindings, bpftrace, and libbpf so you can write BPF programs
#    from C, Python, or bpftrace's high-level language.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bpfcc-tools \
        libbpf-dev \
        libbpfcc \
        libbpfcc-dev \
        python3-bpfcc \
        bpftrace \
        linux-tools-common \
    && rm -rf /var/lib/apt/lists/*
 
# ── 9. procmap – build from source (Kaiwan N Billimoria) ────────────────────
#    https://github.com/kaiwan/procmap
#    Visualises the complete virtual address space of any process.
#    Depends on: bc, awk, gawk, bash, (all already installed).
RUN git clone --depth=1 https://github.com/kaiwan/procmap.git /opt/procmap \
    && cd /opt/procmap \
    && ln -sf /opt/procmap/procmap /usr/local/bin/procmap \
    && ln -sf /opt/procmap/procmap_kernel /usr/local/bin/procmap_kernel
 
# ── 10. Clean up ──────────────────────────────────────────────────────────────
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
 
WORKDIR /workspace
 
# ── SSH server configuration ──────────────────────────────────────────────────
#    - Root login is allowed because this is a dedicated dev sandbox.
#    - PasswordAuthentication is off; key injection via SSH_PUBKEY env var.
#    - Generate static host keys now so sshd starts instantly at runtime.
RUN mkdir -p /run/sshd && \
    ssh-keygen -A && \
    sed -i \
        -e 's/#PermitRootLogin.*/PermitRootLogin yes/' \
        -e 's/#PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        /etc/ssh/sshd_config
 
# ── Entrypoint: inject SSH public key, then launch sshd ──────────────────────
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
 
EXPOSE 22
 
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
