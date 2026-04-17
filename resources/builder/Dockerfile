FROM alpine:edge

RUN adduser -D user
RUN apk add --no-cache \
    libsodium-static \
    curl \
    nim \
    nimble \
    git \
    musl-dev \
    gcc \
    g++ \
    binutils \
    make

WORKDIR /src
COPY libs/* /src/
RUN nimble install -y
RUN mv /src/chronicles.nim /root/.nimble/pkgs2/chronicles-0.10.3-79f09526d4d9b9196dd2f6a75310d71a890c4f88/chronicles.nim
RUN mv /src/sodium.nim /root/.nimble/pkgs2/libsodium-0.7.1-8c7717a7883faa6a0b0a00b7eccbae972e536fc4/libsodium/sodium.nim
RUN mv /src/sodium_sizes.nim /root/.nimble/pkgs2/libsodium-0.7.1-8c7717a7883faa6a0b0a00b7eccbae972e536fc4/libsodium/sodium_sizes.nim
