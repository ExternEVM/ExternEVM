# =============================================================================
# ExternEVM — Modified Reth with API_CALL precompile
# Multi-stage build: Rust builder → Debian runtime (same glibc version)
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Builder
# ---------------------------------------------------------------------------
FROM rust:1.93 AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    libclang-dev \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy the entire reth source tree
COPY ./reth ./reth

WORKDIR /build/reth

# Build only the reth binary in release mode
RUN cargo build --release -p reth --bin reth

# ---------------------------------------------------------------------------
# Stage 2: Runtime — MUST match builder's Debian version for glibc compat
# ---------------------------------------------------------------------------
# rust:1.93 is based on Debian Trixie (13), so runtime must also be Trixie
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled binary
COPY --from=builder /build/reth/target/release/reth /usr/local/bin/reth

# Copy entrypoint
COPY ./docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create data directory
RUN mkdir -p /data /config

# Expose ports
EXPOSE 8545 8546 30303 30303/udp

ENTRYPOINT ["/entrypoint.sh"]