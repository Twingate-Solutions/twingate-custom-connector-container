# Dockerfile
FROM debian:bookworm-slim@sha256:f06537653ac770703bc45b4b113475bd402f451e85223f0f2837acbf89ab020a

# Install runtime dependencies and Twingate connector at build time
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       ca-certificates \
       gnupg \
       bash \
       iproute2 \
       iptables \
       iputils-ping \
       procps \
       grep \
    && curl -fsSL "https://packages.twingate.com/apt/gpg.key" | gpg --dearmor -o /usr/share/keyrings/twingate-connector-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/twingate-connector-keyring.gpg] https://packages.twingate.com/apt/ /" | tee /etc/apt/sources.list.d/twingate.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends twingate-connector \
    && rm -rf /var/lib/apt/lists/*

ENV TERM=xterm-256color

HEALTHCHECK --interval=90s --timeout=45s \
  CMD /usr/local/bin/healthchecks.sh || exit 1

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY healthchecks.sh /usr/local/bin/healthchecks.sh
COPY healthchecks.d/ /healthchecks.d/
RUN sed -i 's/\r//' /usr/local/bin/entrypoint.sh /usr/local/bin/healthchecks.sh \
    && find /healthchecks.d -type f -name '*.sh' -exec sed -i 's/\r//' {} \; \
    && chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthchecks.sh \
    && find /healthchecks.d -type f -name '*.sh' -exec chmod +x {} \;

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
