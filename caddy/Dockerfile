# Caddy with caddy-l4 built from a git repository and branch, so the same image
# can be built from upstream caddy-l4 or from a branch with a fix.
FROM golang:1.25-alpine AS build
RUN apk add --no-cache git
ARG XCADDY_VERSION=v0.4.7
ARG CADDY_VERSION=v2.11.4
ARG CADDY_L4_REPO=https://github.com/mholt/caddy-l4
ARG CADDY_L4_REF=master
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@${XCADDY_VERSION}
RUN git clone --depth 1 --branch "${CADDY_L4_REF}" "${CADDY_L4_REPO}" /src/caddy-l4 \
 && git -C /src/caddy-l4 log -1 --format="${CADDY_L4_REPO} ${CADDY_L4_REF} %h %s" > /caddy-l4-version
RUN xcaddy build "${CADDY_VERSION}" --output /caddy --with github.com/mholt/caddy-l4=/src/caddy-l4

FROM alpine:3.22
COPY --from=build /caddy /usr/bin/caddy
COPY --from=build /caddy-l4-version /caddy-l4-version
COPY caddy.json /etc/caddy/caddy.json
CMD ["sh", "-c", "echo \"caddy-l4: $(cat /caddy-l4-version)\"; exec caddy run --config /etc/caddy/caddy.json"]
