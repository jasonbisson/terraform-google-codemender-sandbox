FROM ubuntu:22.04

# Avoid prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies including C, C++, Java compilers, Python, Go, Node.js, plus unzip and curl
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    g++ \
    default-jdk \
    python3 \
    python3-pip \
    golang \
    nodejs \
    npm \
    unzip \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user (matching runAsUser: 1000 in Kubernetes)
RUN useradd -m -u 1000 codemender

# Create workspace directory and set permissions
RUN mkdir -p /workspace && chown codemender:codemender /workspace

# Download URL argument
ARG CLI_URL="https://artifactregistry.googleapis.com/download/v1/projects/cmoc-prod/locations/us/repositories/codemender-cli-production/files/cm%3Astable%3Acm-linux-amd64.zip:download?alt=media"

# Download, extract, make executable, and clean up in one layer
RUN curl --noproxy "*" -sSL -f -o /tmp/cm-linux-amd64.zip "$CLI_URL" && \
    unzip -o /tmp/cm-linux-amd64.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/cm* && \
    (test -f /usr/local/bin/cm || ln -s /usr/local/bin/cm-linux /usr/local/bin/cm) && \
    rm -f /tmp/cm-linux-amd64.zip

# Set working directory to the writable workspace
WORKDIR /workspace

# Switch to the non-root user
USER codemender

# Initialize the codemender workspace
RUN cm init

# Set the entrypoint to keep the container alive
CMD ["sleep", "infinity"]
