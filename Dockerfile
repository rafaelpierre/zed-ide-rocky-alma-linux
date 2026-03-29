# syntax=docker/dockerfile:1
# Build Zed from source on Rocky Linux 8 (RHEL 8-compatible, amd64)
# glibc 2.28 — matches RHEL 8, safe to deploy to any RHEL 8+ machine.
FROM --platform=linux/amd64 rockylinux:8

# ── Enable extra repos needed on el8 ──────────────────────────────────────────
# PowerTools (called crb on el9) has many -devel packages that aren't in BaseOS
RUN dnf install -y 'dnf-command(config-manager)' \
    && dnf config-manager --set-enabled powertools \
    && dnf install -y epel-release \
    && dnf clean all

# ── System deps ───────────────────────────────────────────────────────────────
# Note: vulkan-loader-devel is in epel on el8, not BaseOS
RUN dnf install -y --allowerasing \
      curl git cmake clang pkg-config \
      alsa-lib-devel wayland-devel libxkbcommon-devel \
      fontconfig-devel libzstd-devel openssl-devel \
      vulkan-loader-devel \
      # Needed by Zed's GPU / window system layer
      libX11-devel libXcursor-devel libXrandr-devel libXi-devel \
      # el8 needs these explicitly; el9 pulls them in transitively
      gcc gcc-c++ make \
      # Needed by some Zed crates
      perl \
    && dnf clean all

# ── Rust (installed for a non-root build user) ────────────────────────────────
# Running cargo as root works but is discouraged; a dedicated user avoids
# ownership headaches when copying artefacts out later.
RUN useradd -m builder
USER builder
WORKDIR /home/builder

ENV PATH="/home/builder/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable --profile minimal \
    && rustup component add rust-src

# ── Clone Zed ─────────────────────────────────────────────────────────────────
# Pin to a specific tag for reproducibility; change to `main` if you want HEAD.
ARG ZED_REF=main
RUN git clone --depth 1 --branch "${ZED_REF}" \
      https://github.com/zed-industries/zed.git

WORKDIR /home/builder/zed

# ── Build ─────────────────────────────────────────────────────────────────────
# -p zed        → only the editor binary (skips other workspace members)
# RELEASE=1 tells some build scripts to enable optimisations
RUN cargo build --release -p zed 2>&1 | tee /tmp/zed-build.log

# ── Collect artefacts into a single, easy-to-copy directory ──────────────────
RUN mkdir -p /home/builder/artefacts \
    && cp target/release/zed /home/builder/artefacts/ \
    # The CLI launcher lives in a separate crate
    && cp target/release/cli /home/builder/artefacts/ 2>/dev/null || true \
    # Desktop entry + icons (useful if you want to register Zed on the host)
    && cp -r crates/zed/resources /home/builder/artefacts/ 2>/dev/null || true

# Default command: just show what was built
CMD ["ls", "-lh", "/home/builder/artefacts/"]