FROM rustlang/rust:nightly-alpine AS builder

RUN apk add --no-cache \
    musl-dev \
    openssl-dev \
    openssl-libs-static \
    pkgconfig \
    postgresql-dev

ENV OPENSSL_STATIC=1
ENV OPENSSL_DIR=/usr
ENV PKG_CONFIG_ALLOW_CROSS=1

WORKDIR /app

COPY protocol/library ../protocol/library
COPY search-engine/Cargo.toml ./
COPY search-engine/src ./src

RUN cargo build --release

FROM alpine:3.19

RUN apk add --no-cache \
    ca-certificates \
    postgresql-client \
    wget \
    netcat-openbsd

RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

COPY --from=builder /app/target/release/gurted-search-engine /app/gurted-search-engine
COPY search-engine/frontend ./frontend

RUN mkdir -p /app/config /app/data /app/search_indexes /app/certs && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 4880

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD nc -z localhost 4880 || exit 1

# Default command - runs the server subcommand
CMD ["./gurted-search-engine", "--config", "/app/config/config.toml", "server"]