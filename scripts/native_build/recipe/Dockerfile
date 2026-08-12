# syntax=docker/dockerfile:1.7
FROM --platform=linux/arm64 debian:bookworm-slim@sha256:817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0

ARG DEBIAN_SNAPSHOT=20260801T000000Z
ENV DEBIAN_FRONTEND=noninteractive

# bookworm-slim does not include a CA bundle. Bootstrap ca-certificates over
# HTTP from the dated snapshot; apt authenticates the signed InRelease file.
RUN printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} bookworm main" \
      > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/* \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install --yes --no-install-recommends \
      ca-certificates \
      llvm \
      minisign \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

ADD --checksum=sha256:f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b \
  https://ziglang.org/download/0.14.1/zig-aarch64-linux-0.14.1.tar.xz \
  /tmp/zig-aarch64-linux-0.14.1.tar.xz
ADD https://ziglang.org/download/0.14.1/zig-aarch64-linux-0.14.1.tar.xz.minisig \
  /tmp/zig-aarch64-linux-0.14.1.tar.xz.minisig
ADD https://codeberg.org/atman/zg/archive/v0.14.1.tar.gz \
  /tmp/zg-v0.14.1.tar.gz

RUN printf '%s  %s\n' \
      'f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b' \
      '/tmp/zig-aarch64-linux-0.14.1.tar.xz' \
      | sha256sum --check --strict - \
    && minisign -Vm /tmp/zig-aarch64-linux-0.14.1.tar.xz \
      -x /tmp/zig-aarch64-linux-0.14.1.tar.xz.minisig \
      -P 'RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U' \
    && mkdir -p /opt/zig \
    && tar --extract --xz --file /tmp/zig-aarch64-linux-0.14.1.tar.xz \
      --strip-components=1 --directory /opt/zig \
    && test "$(/opt/zig/zig version)" = '0.14.1'

COPY seed_zig_cache.sh /usr/local/bin/seed_zig_cache.sh
RUN /bin/sh /usr/local/bin/seed_zig_cache.sh \
    && mkdir -p /opt/noir-runner \
    && dpkg-query --show --showformat='${Package}=${Version}\n' \
      | sort > /opt/noir-runner/debian-packages.txt \
    && { \
      /opt/zig/zig version; \
      llvm-readobj --version | head -n 1; \
      llvm-strip --version | head -n 1; \
      minisign -v 2>&1 | head -n 1; \
    } > /opt/noir-runner/tool-versions.txt \
    && rm -f \
      /tmp/zig-aarch64-linux-0.14.1.tar.xz \
      /tmp/zig-aarch64-linux-0.14.1.tar.xz.minisig \
      /tmp/zg-v0.14.1.tar.gz

ENV PATH=/opt/zig:/usr/lib/llvm-14/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV TZ=UTC LANG=C.UTF-8 LC_ALL=C.UTF-8

WORKDIR /work
