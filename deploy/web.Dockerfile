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

# deploy/nginx.conf is a template: the image's entrypoint renders everything in
# /etc/nginx/templates into conf.d at start. nginx-env.envsh runs first (the
# entrypoint sources *.envsh in name order) and fills in the defaults.
COPY deploy/nginx.conf /etc/nginx/templates/default.conf.template
COPY deploy/nginx-env.envsh /docker-entrypoint.d/05-skincaresync-env.envsh
RUN rm -f /etc/nginx/conf.d/default.conf

# Ask the image to export the container's DNS servers as NGINX_LOCAL_RESOLVERS
# for the `resolver` directive. Substitute only our placeholders, so nginx's own
# lowercase $variables -- and any env var that happens to share a name -- are
# never touched.
ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1 \
    NGINX_ENVSUBST_FILTER="^(PORT|API_UPSTREAM|FORWARDED_FOR|NGINX_LOCAL_RESOLVERS)$"

EXPOSE 80
