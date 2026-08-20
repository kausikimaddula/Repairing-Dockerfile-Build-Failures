
# Use lightweight, production-ready Node.js Alpine base image
FROM node:18-alpine

# Set working directory inside container
WORKDIR /app

# Copy dependency manifests first for layer caching
COPY package.json package-lock.json ./

# Install production dependencies cleanly using npm ci
RUN npm ci --only=production

# Copy application source code
COPY . .

# Expose container port
EXPOSE 8080

# Configure runtime startup command
CMD ["npm", "start"]

