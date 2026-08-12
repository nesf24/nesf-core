# NESF Core API — serves the JSON API and the Flutter web build from one origin.
#
# The web build is NOT compiled here: the Flutter SDK would add ~1 GB to the
# image. Run `npm run build:web` first so ./public exists, and it is copied in
# below. Deploying without it yields an API-only service, which still works.
FROM node:22-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
# Cloud Run supplies PORT; this is the documented default it uses.
EXPOSE 8080

CMD ["node", "src/server.js"]
