FROM registry.jetbrains.team/p/junie-cli/containers/demo-base:2

ENV PATH="/root/.local/bin:${PATH}"

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv python install 3.13
