# Use official pre-built OpenClaw image as base.
# This avoids dependency issues (e.g. "Multiple matrix-js-sdk entrypoints detected!")
# and follows the recommended approach from docs.openclaw.ai/install/docker.
FROM ghcr.io/openclaw/openclaw:latest

USER root

# Install additional system dependencies for OpenClaw skills
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    # video-frames skill
    ffmpeg \
    # session-logs skill
    jq \
    ripgrep \
    # tmux skill
    tmux \
    # python for various skills
    python3 \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI for github skill
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update \
  && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /wrapper

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Install pm2 for ClawLifeOS notification daemon
RUN npm install -g pm2

COPY src ./src

# ClawLifeOS: bake in skills and startup script
COPY clawlifeos ./clawlifeos
COPY entrypoint.sh ./entrypoint.sh

# The wrapper listens on this port.
# Use the openclaw binary already in PATH from the base image.
ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
EXPOSE 8080
CMD ["bash", "entrypoint.sh"]
