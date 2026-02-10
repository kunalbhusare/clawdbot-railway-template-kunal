// ClawLifeOS pm2 ecosystem config
// Deployed to /data/clawlifeos/ecosystem.config.js on Railway
// Started by entrypoint.sh on container boot

module.exports = {
  apps: [{
    name: 'claw-linear-webhook',
    script: '/app/clawlifeos/linear-webhook.js',
    env: {
      LINEAR_WEBHOOK_PORT: 3100,
    },
    restart_delay: 5000,
    max_restarts: 50,
    autorestart: true,
  }]
};
