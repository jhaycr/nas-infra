# Stage 1: Build stage with minimal dependencies
FROM node:20-alpine AS builder

# Install essential build tools
RUN apk add --no-cache python3 make g++ gcc zstd-dev

# Create app directory
WORKDIR /app

# Install igir
RUN npm install igir@latest

# Stage 2: Minimal runtime
FROM alpine:3.22

# Install runtime dependencies
RUN apk add --no-cache \
    nodejs \
    zstd-libs

# Copy application from builder
COPY --from=builder /app/node_modules /app/node_modules

# Set default UID/GID to 1000
ARG USER_ID=1000
ARG GROUP_ID=1000

# Create symlink for execution
RUN addgroup -g $GROUP_ID -S appuser && \
    adduser -u $USER_ID -G appuser -S -H -D appuser && \
    mkdir /data && \
    chmod 755 /data && \
    chown appuser:appuser /data && \
    ln -s /app/node_modules/.bin/igir /usr/local/bin/igir

# Set working directory
WORKDIR /data
USER appuser

# Set entrypoint
ENTRYPOINT ["igir"]