# syntax=docker/dockerfile:1
FROM debian:trixie-slim

# ---- System dependencies ----
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# ---- Install Julia ----
ARG JULIA_VERSION=1.12.7
ARG JULIA_SHA256=4e7e9e776634d24835250de67cde39b0d4af15bc432eb20697e6be6c28ea69e8

RUN curl -fL -o /tmp/julia.tar.gz \
    https://julialang-s3.julialang.org/bin/linux/x64/1.12/julia-${JULIA_VERSION}-linux-x86_64.tar.gz && \
    echo "${JULIA_SHA256} */tmp/julia.tar.gz" | sha256sum --check && \
    mkdir -p /usr/local/julia && \
    tar -xzf /tmp/julia.tar.gz -C /usr/local/julia --strip-components 1 && \
    ln -s /usr/local/julia/bin/julia /usr/local/bin/julia && \
    rm /tmp/julia.tar.gz

# ---- Julia depot lives inside the image, next to Julia itself ----
ENV JULIA_DEPOT_PATH=/opt/julia_depot
RUN mkdir -p /opt/julia_depot

# ---- Package install / precompile script ----
# No GPU is present during a Docker build, so CUDA.jl can't auto-detect a
# target version. We pin one explicitly. Check `nvidia-smi` / the driver
# version on the cluster and adjust v"12.9" below to match before building.
COPY <<'EOF' /tmp/install_packages.jl
using Pkg
Pkg.add(["Polyester", "ThreadPinning", "LoopVectorization", "CUDA", "JLD2", "Random", "Dates", "BenchmarkTools", "JET"])

using CUDA
CUDA.set_runtime_version!(v"12.8")

Pkg.precompile()
EOF

RUN julia /tmp/install_packages.jl && rm /tmp/install_packages.jl

# ---- Startup file: make the baked-in depot visible to every user/UID ----
RUN mkdir -p /usr/local/julia/etc/julia

COPY <<'EOF' /usr/local/julia/etc/julia/startup.jl
user_depot = expanduser("~/.julia")
if !(user_depot in DEPOT_PATH)
    pushfirst!(DEPOT_PATH, user_depot)
end
if !("/opt/julia_depot" in DEPOT_PATH)
    insert!(DEPOT_PATH, 2, "/opt/julia_depot")
end
EOF

# ---- Permissions: Apptainer runs you as your host UID, not root, so make
#      sure that UID can read/execute everything Julia needs ----
RUN chmod -R a+rX /opt/julia_depot /usr/local/julia

ENTRYPOINT ["julia"]
