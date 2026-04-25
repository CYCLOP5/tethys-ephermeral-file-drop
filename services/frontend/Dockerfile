# syntax=docker/dockerfile:1.6
FROM node:20-bookworm-slim AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm install --no-audit --no-fund

FROM node:20-bookworm-slim AS build
WORKDIR /app
ENV NODE_ENV=production
ARG VITE_UPLOAD_BEARER=""
ENV VITE_UPLOAD_BEARER=${VITE_UPLOAD_BEARER}
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
WORKDIR /usr/share/nginx/html
COPY --from=build /app/dist ./
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Non-root by default in the unprivileged image.
EXPOSE 8080
