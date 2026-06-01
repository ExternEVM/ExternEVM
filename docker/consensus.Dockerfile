FROM rust:1.93 AS builder

WORKDIR /build
COPY ./consensus ./consensus
WORKDIR /build/consensus

RUN cargo build --release

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y ca-certificates curl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/consensus/target/release/externevm-consensus /usr/local/bin/externevm-consensus

ENTRYPOINT ["externevm-consensus"]