# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.24

# set version label
ARG BUILD_DATE
ARG VERSION
ARG SEALSKIN_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"
ENV HOME=/config

# install software
RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache --upgrade --virtual=build-dependencies \
    python3-dev \
    py3-pip && \
  echo "**** install packages ****" && \
  apk add --no-cache \
    caddy \
    openssl \
    python3 && \
  echo "**** install sealskin ****" && \
  if [ -z ${SEALSKIN_VERSION+x} ]; then \
    SEALSKIN_VERSION=$(curl -sX GET "https://api.github.com/repos/selkies-project/sealskin/releases/latest" \
    | jq -r '.tag_name'); \
  fi && \
  curl -o \
    "/tmp/sealskin_server-${SEALSKIN_VERSION}-py3-none-any.whl" -L \
    "https://github.com/selkies-project/sealskin/releases/download/${SEALSKIN_VERSION}/sealskin_server-${SEALSKIN_VERSION}-py3-none-any.whl" && \
  pip3 install \
    "/tmp/sealskin_server-${SEALSKIN_VERSION}-py3-none-any.whl" --break-system-packages && \
  echo "**** cleanup ****" && \
  printf "Linuxserver.io version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    $HOME/.cache \
    /tmp/*

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8000 8443
VOLUME /config /storage
