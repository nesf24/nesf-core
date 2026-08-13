# Production API server
FROM node:20-alpine

WORKDIR /app

# Install production dependencies only
COPY api/package*.json ./
RUN npm ci --only=production

# Copy pre-built web app (built locally via 'npm run build:web')
COPY api/public ./public

# Copy API source code
COPY api/src ./src
COPY api/scripts ./scripts

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:' + (process.env.PORT || 8080) + '/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

EXPOSE 8080
CMD ["node", "src/server.js"]
