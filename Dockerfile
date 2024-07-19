FROM registry.fedoraproject.org/fedora-minimal:40 as builder

RUN microdnf -y --refresh upgrade

RUN microdnf -y install     \
    --setopt=tsflags=nodocs \
    --setopt=deltarpm=false \
    gcc-c++                 \
    libstdc++-static        \
    glibc-static            \
    make

COPY . .

ENV DEBUG=0
ENV ASAN=0
ENV ANALYZER=0
ENV LTO=1
ENV NATIVE=0
ENV STATIC=1

RUN make -j `nproc --ignore=1`

FROM scratch
LABEL maintainer="emneo <emneo@kreog.com>"

COPY --from=builder liskvork .

ENTRYPOINT ["/liskvork"]
