FROM mcr.microsoft.com/devcontainers/universal:2-linux

ARG USER=codespace

# Install additional development tools
RUN apt-get update && apt-get install -y \
    tmux \
    vim \
    neovim \
    htop \
    jq \
    curl \
    wget \
    build-essential \
    software-properties-common \
    git \
    unzip \
    zip \
    postgresql-client \
    mysql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list \
    && apt-get update \
    && apt-get install -y kubectl \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN TERRAFORM_VERSION="1.9.8" \
    && wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Install code-server
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Python packages
RUN pip3 install --upgrade pip \
    && pip3 install \
    black \
    flake8 \
    mypy \
    pytest \
    ipython \
    jupyter \
    pandas \
    numpy \
    requests \
    fastapi \
    uvicorn

# Install Node.js global packages
RUN npm install -g \
    typescript \
    ts-node \
    nodemon \
    pm2 \
    prettier \
    eslint \
    @angular/cli \
    @vue/cli \
    create-react-app \
    yarn

# Install Go tools
RUN go install golang.org/x/tools/gopls@latest \
    && go install github.com/go-delve/delve/cmd/dlv@latest \
    && go install golang.org/x/lint/golint@latest

# Setup directories for codespace user
RUN echo "$USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USER \
    && chmod 0440 /etc/sudoers.d/$USER \
    && mkdir -p /home/$USER/workspace /home/$USER/.claude/agents /home/$USER/.config/claude-code \
    && chown -R $USER:$USER /home/$USER

# Switch to codespace user
USER $USER
WORKDIR /home/$USER

# Configure code-server
RUN mkdir -p /home/$USER/.config/code-server
RUN echo "bind-addr: 0.0.0.0:13337\nauth: none\ncert: false" > /home/$USER/.config/code-server/config.yaml

# Set up shell configuration
RUN echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /home/$USER/.bashrc \
    && echo 'export PATH=$PATH:/home/'$USER'/.local/bin' >> /home/$USER/.bashrc

EXPOSE 13337

CMD ["code-server", "--bind-addr", "0.0.0.0:13337", "--auth", "none"]