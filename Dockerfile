# Stage 1: Build
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=26.2.5.18
ARG DEBIAN_VERSION=bookworm-20260223-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV="prod"

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency files first for caching
COPY mix.exs mix.lock ./
COPY local_deps local_deps

RUN mix deps.get --only $MIX_ENV

# Copy application code
COPY config config
COPY lib lib
COPY priv priv

RUN mix compile

# Build release
RUN mix release

# Stage 2: Runtime
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8
ENV MIX_ENV="prod"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/trpg_master ./

# Create data directories (local dev fallback + Fly volume mount point)
RUN mkdir -p /app/data && chown nobody:root /app/data
RUN mkdir -p /data && chown nobody:root /data

USER nobody

CMD ["/app/bin/trpg_master", "start"]
