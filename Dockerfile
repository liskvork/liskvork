FROM registry.fedoraproject.org/fedora-minimal:38
LABEL maintainer="Alexandre Flion <huntears@kreog.com>"

RUN microdnf -y upgrade

RUN microdnf -y --refresh install   \
        --setopt=tsflags=nodocs     \
        --setopt=deltarpm=false     \
        clang                       \
        make                        \
        cmake                       \
        git                         \
        gtest-devel                 \
        rpm-build                   \
        dpkg

RUN microdnf clean all

RUN rm -rf /tmp/liskvork_build && mkdir -pv /tmp/liskvork_build

WORKDIR /tmp/build

COPY . .

RUN mkdir -pv build \
    && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release .. \
    && make -j4

RUN mkdir -pv /usr/app && cp build/bin/liskvork /usr/app/liskvork

RUN cd /tmp \
    && rm -rf /tmp/* \
    && chmod 1777 /tmp

WORKDIR /usr/app

ENTRYPOINT ["/usr/app/liskvork"]
