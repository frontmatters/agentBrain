---
date: 2026-03-17
type: deploy
tags: [project, example, deploy]
project: example
id: 41f44739-c50a-596d-b096-e87d7c903f97
---

# Example Project -- Deploy

## Environment

- Production: Docker container on VPS
- Staging: Local Docker Compose
- Node.js 20 LTS

## Build

```bash
npm ci
npm run build
docker build -t example-app .
```

## Deploy Steps

1. Build Docker image
2. Push to container registry
3. SSH into server, pull new image
4. `docker compose up -d`

## Rollback

1. `docker compose down`
2. `docker compose up -d` with previous image tag
