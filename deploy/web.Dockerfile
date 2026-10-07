# SkincareSync frontend: Vite build, served by nginx.
#
# Build context is the REPOSITORY ROOT, not frontend/, so the image can pick up
# deploy/nginx.conf alongside the app source:
#
#     docker build -f deploy/web.Dockerfile -t skincaresync-web .

FROM node:22-alpine AS build

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./

# Baked into the bundle at build time, not read at run time -- changing it
# later means rebuilding the image. Empty means "same origin", which is what
# the nginx config serves: the SPA and /api/ come from one host, so the session
# cookie is first-party and CORS never applies. Override only when the API is
# deployed to a different origin.
ARG VITE_API_URL=""
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build


FROM nginx:1.27-alpine AS runtime

COPY --from=build /app/dist /usr/share/nginx/html
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
