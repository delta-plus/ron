# Alpine for static MUSL compilation
FROM alpine:edge

# Create user
RUN adduser -D user

# Install Alpine packages
RUN apk add --no-cache \
    libsodium-static \
    curl \
    git \
    musl-dev \
    gcc \
    g++ \
    binutils \
    make

# Build Nim from source
WORKDIR /src
COPY nim.tar.xz /src
RUN tar -xJf nim.tar.xz
RUN rm nim.tar.xz
RUN mv nim* nim
WORKDIR /src/nim
RUN ./build.sh
RUN bin/nim c koch
RUN ./koch boot -d:release
RUN ./koch tools

# Add Nim to $PATH
RUN cp -r /src/nim /root/nim
RUN mkdir -p /root/.nimble/bin
ENV PATH="$PATH:/root/nim/bin:/root/.nimble/bin"

# Install Nim libraries
RUN nimble install -y chronos libsodium websock

# Patch Chronicles
WORKDIR /src
COPY libs/chronicles.nim /src
RUN mv chronicles.nim /root/.nimble/pkgs2/chronicles-*/chronicles.nim
