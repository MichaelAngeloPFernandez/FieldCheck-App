# Build Flutter web and serve with nginx

FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.22.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Flutter SDK
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

WORKDIR /app

# Copy only what we need for dependency resolution first
COPY pubspec.yaml pubspec.lock ./
RUN flutter config --no-analytics
RUN flutter pub get

# Copy the rest of the app and build
COPY . .
RUN flutter build web --release


FROM nginx:1.27-alpine

# Provide SPA-friendly routing
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy built site
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
