# PocketBase for Railway (persistent volume at /pb_data)
FROM debian:bookworm-slim

ARG PB_VERSION=0.40.6

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates unzip curl \
    && rm -rf /var/lib/apt/lists/*

ADD https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip /tmp/pb.zip
RUN unzip /tmp/pb.zip -d /pb/ \
    && chmod +x /pb/pocketbase \
    && rm /tmp/pb.zip

COPY pb_migrations /pb/pb_migrations
COPY pb_hooks /pb/pb_hooks

EXPOSE 8080

# Railway volume must be mounted at /pb/pb_data
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8080", "--dir=/pb/pb_data", "--migrationsDir=/pb/pb_migrations", "--hooksDir=/pb/pb_hooks"]
