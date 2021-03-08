ARG BASE_IMAGE=ubuntu:18.04

FROM ${BASE_IMAGE} AS compile-image
ARG BASE_IMAGE=ubuntu:18.04
ENV PYTHONUNBUFFERED TRUE

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    ca-certificates \
    g++ \
    python3-dev \
    python3-distutils \
    python3-venv \
    openjdk-11-jre-headless \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && cd /tmp \
    && curl -O https://bootstrap.pypa.io/get-pip.py \
    && python3 get-pip.py

RUN python3 -m venv /home/venv

ENV PATH="/home/venv/bin:$PATH"

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
    && update-alternatives --install /usr/local/bin/pip pip /usr/local/bin/pip3 1

# This is only useful for cuda env
RUN export USE_CUDA=1

ARG CUDA_VERSION=""

RUN TORCH_VER=$(curl --silent --location https://pypi.org/pypi/torch/json | python -c "import sys, json, pkg_resources; releases = json.load(sys.stdin)['releases']; print(sorted(releases, key=pkg_resources.parse_version)[-1])") && \
    TORCH_VISION_VER=$(curl --silent --location https://pypi.org/pypi/torchvision/json | python -c "import sys, json, pkg_resources; releases = json.load(sys.stdin)['releases']; print(sorted(releases, key=pkg_resources.parse_version)[-1])") && \
    if echo "$BASE_IMAGE" | grep -q "cuda:"; then \
    # Install CUDA version specific binary when CUDA version is specified as a build arg
    if [ "$CUDA_VERSION" ]; then \
    pip install --no-cache-dir torch==$TORCH_VER+$CUDA_VERSION torchvision==$TORCH_VISION_VER+$CUDA_VERSION -f https://download.pytorch.org/whl/torch_stable.html; \
    # Install the binary with the latest CUDA version support
    else \
    pip install --no-cache-dir torch torchvision; \
    fi \
    # Install the CPU binary
    else \
    pip install --no-cache-dir torch==$TORCH_VER+cpu torchvision==$TORCH_VISION_VER+cpu -f https://download.pytorch.org/whl/torch_stable.html; \
    fi
RUN pip install --no-cache-dir captum torchtext torchserve torch-model-archiver

# Final image for production
FROM ${BASE_IMAGE} AS runtime-image

ENV PYTHONUNBUFFERED TRUE

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    python3 \
    python3-distutils \
    python3-dev \
    openjdk-11-jre-headless \
    build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && cd /tmp

RUN useradd -m model-server \
    && mkdir -p /home/model-server/tmp

COPY --chown=model-server --from=compile-image /home/venv /home/venv

ENV PATH="/home/venv/bin:$PATH"

COPY dockerd-entrypoint.sh /usr/local/bin/dockerd-entrypoint.sh

RUN chmod +x /usr/local/bin/dockerd-entrypoint.sh \
    && chown -R model-server /home/model-server

COPY config.properties /home/model-server/config.properties
RUN mkdir /home/model-server/model-store && chown -R model-server /home/model-server/model-store
COPY styletransfer.mar /home/model-server/model-store/styletransfer.mar

# EXPOSE 8080 8081 8082 7070 7071

USER model-server
WORKDIR /home/model-server
ENV TEMP=/home/model-server/tmp

ENV TS_INFERENCE_ADDRESS "http://0.0.0.0:"

ENTRYPOINT ["/usr/local/bin/dockerd-entrypoint.sh"]