# Runtime image for voice-stack (JACK-based audio services)

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libjack-jackd2-0 \
    ca-certificates \
    jack-tools \
    bash \
    curl \
    procps \
 && rm -rf /var/lib/apt/lists/*

ARG UID=1000
ARG GID=1000

RUN groupadd -g ${GID} jackuser \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash jackuser \
 && usermod -aG audio jackuser

# ------------------------------------------------------------
# create app directory explicitly and fix ownership
# ------------------------------------------------------------
RUN mkdir -p /home/jackuser/app \
 && chown -R jackuser:jackuser /home/jackuser

WORKDIR /home/jackuser/app

COPY --chown=jackuser:jackuser \
    target/aarch64-unknown-linux-gnu/release/asrd \
    target/aarch64-unknown-linux-gnu/release/znoise \
    target/aarch64-unknown-linux-gnu/release/playctl \
    run.sh \
    ./

COPY --chown=jackuser:jackuser crates/vtn/vtn-sys/vendor/linaro7.5.0_x64_release/ ./lib/
COPY --chown=jackuser:jackuser res/ ./res/

RUN chmod 755 asrd znoise playctl run.sh \
 && chmod 644 lib/libvtn.so \
 && [ -d lib ] && find lib -type d -exec chmod 755 {} \; || true \
 && [ -d res ] && find res -type d -exec chmod 755 {} \; || true \
 && [ -d res ] && find res -type f -exec chmod 644 {} \; || true \
 && mkdir -p \
    bin \
    assets/audio \
    config/znoise \
    config/asrd \
    config/playctl \
 && chown -R jackuser:jackuser bin assets config 

ENV \
  LD_LIBRARY_PATH=/home/jackuser/app/lib \
  JACK_DEFAULT_SERVER=default

USER jackuser

ENTRYPOINT ["./run.sh"]
CMD ["start"]
