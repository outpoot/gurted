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
COPY dns/Cargo.toml ./
COPY dns/src ./src
COPY dns/migrations ./migrations

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

COPY --from=builder /app/target/release/webx_dns /app/webx_dns
COPY --from=builder /app/migrations ./migrations
COPY dns/frontend ./frontend
COPY search-engine/frontend ./search-engine/frontend

RUN mkdir -p /app/config /app/data /home/matt/gurted/dns/certs && \
    chown -R appuser:appgroup /app && \
    chown -R appuser:appgroup /home/matt && \
    ls -la /home/matt/gurted/dns/ && \
    echo "Directory structure created successfully"

USER appuser

EXPOSE 4878 8876

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD nc -z localhost 4878 || exit 1

# Default command
CMD ["sh", "-c", "ls -la /home/matt/gurted/dns/certs/ && ./webx_dns --config /app/config/config.toml start"]
