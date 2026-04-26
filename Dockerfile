# syntax=docker/dockerfile:1
# Production-ready multi-stage build for Phoenix 1.8 + Elixir 1.18 + OTP 27.
# Based on `mix phx.gen.release --docker` template, hardened for tini /
# healthcheck / debian-slim runtime (avoids Alpine musl/DNS pitfalls).

ARG BUILDER_IMAGE="elixir:1.18.4-otp-27-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

# ============================================================================
# Stage 1: Builder
# ============================================================================
FROM ${BUILDER_IMAGE} AS builder

# Switch apt source to Tencent Cloud mirror (CN: deb.debian.org is unreachable/slow)
RUN sed -i 's|http://deb.debian.org/debian|http://mirrors.cloud.tencent.com/debian|g' \
      /etc/apt/sources.list.d/debian.sources && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential git ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Cache deps layer separately
COPY mix.exs mix.lock ./
# Pre-place heroicons (CN servers cannot reach github.com from inside docker).
# mix deps.get sees deps/heroicons already exists + matches lock → skips git clone.
COPY deps/heroicons deps/heroicons
RUN mix deps.get --only $MIX_ENV

# Copy compile-time config (NOT runtime.exs — that goes after compile)
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Compile release first, THEN assets — order matches phx.gen.release template
RUN mix compile

# Build assets (esbuild + tailwind are pure Elixir, no Node needed)
RUN mix assets.deploy

# Runtime config + release scripts
COPY config/runtime.exs config/
COPY rel rel

RUN mix release

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM ${RUNNER_IMAGE} AS final

# Same Tencent Cloud apt mirror swap for runtime stage
RUN sed -i 's|http://deb.debian.org/debian|http://mirrors.cloud.tencent.com/debian|g' \
      /etc/apt/sources.list.d/debian.sources && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates \
      tini wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    HOME=/app

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/prod/rel/evenglass ./

USER nobody

# tini handles PID 1 + forwards SIGTERM to BEAM for graceful shutdown
ENTRYPOINT ["/usr/bin/tini", "--"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget --spider -q http://localhost:4000/ || exit 1

CMD ["/app/bin/server"]
