FROM alpine:edge AS builder

ARG BUILD_VERSION=0.0.0

RUN apk add --no-cache "zig=~0.14"

WORKDIR /work

COPY . .

RUN zig build -Doptimize=ReleaseSafe -Dversion=${BUILD_VERSION} --summary all

FROM scratch
LABEL maintainer="Emily Flion <emneo@kreog.com>"

WORKDIR /

COPY --from=builder /work/zig-out/bin/liskvork .

WORKDIR /data

ENTRYPOINT ["/liskvork"]
