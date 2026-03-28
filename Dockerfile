# Use official pre-built OpenClaw image instead of building from source.
# This avoids dependency issues (e.g. "Multiple matrix-js-sdk entrypoints detected!")
# and follows the recommended approach from docs.openclaw.ai/install/docker.
FROM ghcr.io/openclaw/openclaw:latest AS openclaw-image

# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

# Install system dependencies + CLI tools for OpenClaw skills
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

WORKDIR /app

# Wrapper deps
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Install pm2 for ClawLifeOS notification daemon
RUN npm install -g pm2

# Copy pre-built OpenClaw from official image.
# The official image packages openclaw as a global npm install.
COPY --from=openclaw-image /usr/local/lib/node_modules/openclaw /openclaw
COPY --from=openclaw-image /usr/local/bin/openclaw /usr/local/bin/openclaw

# Fallback: provide an openclaw executable pointing to the dist entry if the
# binary copy above turns out to be a symlink that doesn't resolve.
RUN if [ ! -x /usr/local/bin/openclaw ]; then \
      printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
      && chmod +x /usr/local/bin/openclaw; \
    fi

COPY src ./src

# ClawLifeOS: bake in skills and startup script
COPY clawlifeos ./clawlifeos
COPY entrypoint.sh ./entrypoint.sh

# The wrapper listens on this port.
ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
EXPOSE 8080
CMD ["bash", "entrypoint.sh"]
