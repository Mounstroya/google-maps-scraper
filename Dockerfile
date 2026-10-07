# Build stage for Playwright dependencies
# Uses the same Go module as the app (golang:1.26.1-trixie, matching the final
# debian:trixie-slim image) so the local `replace` for playwright-go in go.mod
# applies: upstream playwright-community/playwright-go stopped publishing new
# versions (merged back into github.com/mxschmitt/playwright-go), and every
# version we can pull as playwright-community still ships the driver via the
# old playwright.azureedge.net zip CDN, which returns 404 for linux-arm64 on
# all mirrors (verified for 1.52.0, 1.60.0, 1.61.1 — a live CDN issue, not a
# version problem). Newer driver versions (1.61.1+) fetch the driver from the
# npm registry + nodejs.org instead, which works. thirdparty/playwright-go is
# a vendored copy of playwright-community/playwright-go v0.6100.0 (source is
# identical to github.com/mxschmitt/playwright-go v0.6100.0, just with the
# module path renamed back) so we get that download path without needing a
# module the rest of the code can't import.
FROM golang:1.26.1-trixie AS playwright-deps
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
WORKDIR /app
COPY go.mod go.sum ./
COPY thirdparty ./thirdparty
RUN go mod download \
    && go run github.com/playwright-community/playwright-go/cmd/playwright install chromium --with-deps

# Build stage
FROM golang:1.26.1-trixie AS builder
WORKDIR /app
COPY go.mod go.sum ./
COPY thirdparty ./thirdparty
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /usr/bin/google-maps-scraper

# Final stage
FROM debian:trixie-slim
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
ENV PLAYWRIGHT_DRIVER_PATH=/opt/ms-playwright-go/1.61.1

# Install only the necessary dependencies in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=playwright-deps /opt/browsers /opt/browsers
COPY --from=playwright-deps /root/.cache/ms-playwright-go /opt/ms-playwright-go

RUN chmod -R 755 /opt/browsers \
    && chmod -R 755 /opt/ms-playwright-go

COPY --from=builder /usr/bin/google-maps-scraper /usr/bin/

ENTRYPOINT ["google-maps-scraper"]
