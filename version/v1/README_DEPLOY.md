# ToolPilot Production Deploy

This deployment does not require Node.js on the CentOS 7 host. The frontend is built inside the `node:20-alpine` Docker build stage and served by Nginx.

## Server Steps

```bash
cd /opt
git clone <your-repo-url> toolpilot
cd /opt/toolpilot

cp .env.production.example .env.production
vi .env.production
```

Update `DATABASE_URL` in `.env.production` to the production PostgreSQL connection string.

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

Check the API through the frontend container:

```bash
curl http://127.0.0.1:8021/api/health
```

Open the frontend in a browser:

```text
http://10.7.121.13:8021
```

## Service Layout

- `toolpilot-backend`: FastAPI service, internal port `8000`, not published to the host.
- `toolpilot-frontend`: Nginx service, publishes `8021:80`.
- `toolpilot-net`: shared bridge network for frontend-to-backend proxying.

## API Routing

The frontend calls relative `/api/...` paths only. Nginx proxies `/api/` to `http://backend:8000/api/`.

Main endpoints:

- `GET /api/health`
- `GET /api/market/prices`
- `GET /api/market/forecasts`
- `GET /api/tools/specs`
- `GET /api/procurement/advice`

Do not deploy this project into `/var/www/vue3-app`, and do not bind port `8080`.
