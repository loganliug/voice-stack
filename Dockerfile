# ------------------------------------------------------------
# Runtime image for voice-stack (JACK-based audio services)
# ------------------------------------------------------------
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------------------------
# Install dependencies
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        libjack-jackd2-0 \
        jack-tools \
        bash \
        curl \
        procps \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Set workdir and copy binaries
# ------------------------------------------------------------
WORKDIR /app

# Copy compiled binaries
COPY target/aarch64-unknown-linux-gnu/release/asrd \
     target/aarch64-unknown-linux-gnu/release/znoise \
     target/aarch64-unknown-linux-gnu/release/playctl \
     target/aarch64-unknown-linux-gnu/release/

# Copy entrypoint script
COPY run.sh ./

# Copy resources
COPY res/ res/

# Copy libraries 
COPY crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release/ crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release


# ------------------------------------------------------------
# Fix permissions for root user
# ------------------------------------------------------------
RUN chmod +x run.sh \
    target/aarch64-unknown-linux-gnu/release/asrd \
    target/aarch64-unknown-linux-gnu/release/znoise \
    target/aarch64-unknown-linux-gnu/release/playctl \
    && [ -d lib ] && find lib -type d -exec chmod 755 {} \; || true \
    && [ -d lib ] && find lib -type f -exec chmod 644 {} \; || true \
    && [ -d res ] && find res -type d -exec chmod 755 {} \; || true \
    && [ -d res ] && find res -type f -exec chmod 644 {} \; || true \
    && mkdir -p bin assets/audio config \
    && chmod 755 bin assets config

# ------------------------------------------------------------
# Environment for system JACK (root/systemd)
# ------------------------------------------------------------
ENV LD_LIBRARY_PATH=/app/crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release \
    JACK_DEFAULT_SERVER=system \
    JACK_NO_AUDIO_RESERVATION=1 \
    JACK_START_SERVER=0

# ------------------------------------------------------------
# Run as root (default)
# ------------------------------------------------------------
USER root

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------
ENTRYPOINT ["./run.sh"]
CMD ["start"]
