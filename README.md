# WHOX Assistant

<p align="center">
  <a href="https://github.com/overviewlabs/WHOX"><img src="https://img.shields.io/badge/PROJECT-WHOX-FFD700?style=for-the-badge" alt="Project WHOX"></a>
  <a href="https://github.com/NousResearch/hermes-agent"><img src="https://img.shields.io/badge/POWERED%20BY-HERMES%20AGENT-6EA8FE?style=for-the-badge" alt="Powered by Hermes Agent"></a>
  <a href="https://nousresearch.com"><img src="https://img.shields.io/badge/CORE%20FRAMEWORK-NOUS%20RESEARCH-9333EA?style=for-the-badge" alt="Core Framework Nous Research"></a>
</p>

WHOX is Where Humans Optimize...

Credit: The core agent framework is Hermes Agent, built and open-sourced by Nous Research. WHOX builds on top of that foundation.

## Why WHOX

- One-line install and minimal setup inputs
- Optimized for persistent VPS operation
- Built for long-running autonomous tasks with progress updates
- Multi-tool execution for coding, browsing, scheduling, automation, and publishing
- Tuned for efficient operation with free-tier model constraints

## WHOX vs OpenClaw

- Faster setup path: WHOX is opinionated and trimmed for immediate deployment
- Lower ops overhead: WHOX focuses on stable defaults, fewer moving parts, and practical automation
- Better cost profile: WHOX is pre-tuned for low-cost and free-tier operation patterns
- Production intent: WHOX is built for real unattended work, not just local experimentation

## Install WHOX

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/overviewlabs/WHOX/main/install-whox.sh)
```

Setup prompts are intentionally short and ask for:

1. Qwen 3.5 397B API key
2. Telegram bot token
3. VPS base domain (optional)
4. Timezone
5. Feature profile (recommended or custom per capability)

If no base domain is configured, isolated app/site workspace creation is disabled by design.

After install:

```bash
source ~/.bashrc
whox gateway status
whox
```

## 100% Free Personal Assistant Build

This stack can run fully free if your accounts remain within free-tier limits.

### Step 1: Provision a free VPS on Oracle

1. Create an Oracle Cloud account: `https://www.oracle.com/cloud/free/`
2. Upgrade the account to **Pay As You Go** in Oracle Cloud billing settings.
3. Create a compute instance under Always Free resources.
3. Target this footprint where available:
   - 4 OCPU (Ampere A1)
   - 24 GB RAM
   - 200 GB storage
   - Ubuntu OS
4. Open required firewall ports for SSH and web access.
5. Point your domain/subdomain records to the VPS public IP.

Important: Use the Ampere A1 shape with `4 OCPU / 24 GB RAM / 200 GB storage` to stay in the Always Free allocation while getting a high-performance VPS.

### Step 2: Get the free Qwen model key from NVIDIA

NVIDIA model page:

`https://build.nvidia.com/qwen/qwen3.5-397b-a17b`

NVIDIA API key portal:

`https://build.nvidia.com/`

Create your API key and keep it ready for WHOX setup.

### Step 3: Install WHOX on the VPS

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/overviewlabs/WHOX/main/install-whox.sh)
```

Enter:

- NVIDIA Qwen key
- Telegram bot token
- Base domain
- Timezone

### Step 4: Verify

```bash
whox gateway status
whox
```

Send a message to your bot in Telegram and confirm responses stream correctly.

## Qwen Free-Tier Optimization

WHOX is tuned to work within NVIDIA-hosted Qwen rate constraints and avoid burst failures:

- Request pacing to respect per-minute throughput limits
- Retry and cooldown behavior for temporary provider throttling
- Long-task progress signaling for better reliability over chat

## Core Capabilities

- Autonomous coding and app/site generation
- Web research and extraction workflows
- Browser automation (navigate, click, fill, scrape)
- Scheduled reminders and recurring tasks
- Multi-platform messaging gateway support
- Persistent memory and context continuity
- Background execution with progress updates
- Isolated app workspaces and publish helpers

## Notes

- Free-tier availability can vary by region, account eligibility, and provider policy changes.
- WHOX is designed to stay useful under strict budget constraints while still supporting advanced autonomous behavior.

## License

MIT. See [LICENSE](LICENSE).
