   # Dockerfile for Base Container with Amazon Q CLI and OpenaI Codex pre-installed
   FROM ghcr.io/guttmacher/research-stack/full:latest

   # Switch to the me user for installation
   USER me
   WORKDIR /home/me

   # Install Amazon Q CLI during image build
   RUN curl --proto '=https' --tlsv1.2 -sSf \
       'https://desktop-release.q.us-east-1.amazonaws.com/latest/q-aarch64-linux.zip' \
       -o 'q.zip' && \
       unzip q.zip && \
       chmod +x ./q/install.sh && \
       ./q/install.sh --no-confirm && \
       rm -rf q.zip q

   # Install CAO (CLI Agent Orchestrator) and built-in agents
   RUN uv tool install git+https://github.com/awslabs/cli-agent-orchestrator.git@main --upgrade && \
       cao install code_supervisor && \
       cao install developer && \
       cao install reviewer

   # Ensure Q CLI is in PATH for all users
   ENV PATH="/home/me/.local/bin:$PATH"

   # Install Codex CLI via npm without global (-g)
   # Install into a user-local prefix and symlink into ~/.local/bin (already on PATH)
   RUN mkdir -p /home/me/.local/codex /home/me/.local/bin && \
       npm install @openai/codex --prefix /home/me/.local/codex && \
       ln -sf /home/me/.local/codex/node_modules/.bin/codex /home/me/.local/bin/codex
