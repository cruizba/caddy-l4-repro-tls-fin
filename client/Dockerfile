FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -o /client .

FROM alpine:3.22
COPY --from=build /client /usr/bin/client
ENTRYPOINT ["client"]
