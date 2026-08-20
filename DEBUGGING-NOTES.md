# Dockerfile Repair Lab - Debugging Notes & Evidence

This document records the step-by-step investigation, root-cause diagnosis, repairs, layer optimizations, and verification evidence for the containerized application.

---

## 1. Summary of Planted Failures across the 5 Break Families

| Break Family | Original Instruction / Config | Observed Error / Behavior | Applied Repair |
| :--- | :--- | :--- | :--- |
| **1. Base Image** | `FROM node:notfound` | `ERROR: docker.io/library/node:notfound: not found` | Replaced tag with official lightweight base image `node:18-alpine`. |
| **2. WORKDIR & Layer Ordering** | `COPY . .`<br>`WORKDIR /wrong` | Source copied into `/` instead of app directory; improper cache utilization. | Set `WORKDIR /app` at top. Copy manifests (`package.json`, `package-lock.json`) first before `npm ci`. |
| **3. Dependency Installation** | `RUN npm install package-lock.json` | `npm ERR! 404 Not Found - package-lock.json` (npm attempted registry lookup for filename). | Replaced with deterministic production install: `RUN npm ci --only=production`. |
| **4. Build Context & Exclusions** | `COPY missing-folder ./missing-folder`<br>`.dockerignore` included `src` | `COPY failed: stat missing-folder: no such file` & runtime `Cannot find module './src/routes'`. | Removed invalid `COPY` instruction. Removed `src` from `.dockerignore` so source routes copy into container. |
| **5. Startup Command** | `CMD ["npm", "run", "production"]` | `npm ERR! missing script: production` at container runtime. | Updated startup command to match `package.json`: `CMD ["npm", "start"]`. |

---

## 2. Detailed Break Family Analysis & Repairs

### Family 1: Base Image Error
- **Root Cause**: The Dockerfile specified `node:notfound`. Docker daemon attempted to pull `docker.io/library/node:notfound` from Docker Hub, which returned a 404 image not found error.
- **Fix**: Replaced with `FROM node:18-alpine`. Using Alpine Linux reduces base image size from ~1GB down to ~170MB, improving download speed and security footprint.

### Family 2: Working Directory & Layer Ordering
- **Root Cause**: `COPY . .` executed before `WORKDIR /wrong`. This placed application files directly in root directory `/` and then changed working directory to `/wrong`. Additionally, source code was copied before installing dependencies, invalidating the Docker layer cache on every code change.
- **Fix**: Declared `WORKDIR /app` immediately after `FROM`. Structured COPY instructions to copy package manifests (`package.json` and `package-lock.json`) prior to running dependency installation.

### Family 3: Dependency Installation Error
- **Root Cause**: `RUN npm install package-lock.json` passed the lockfile filename as an argument to `npm install`. `npm` interpreted `package-lock.json` as a package name to download from npmjs.org.
- **Fix**: Replaced with `RUN npm ci --only=production`. `npm ci` reads `package-lock.json` directly to perform a clean, reproducible installation of production dependencies.

### Family 4: Build Context & File Exclusion Issues
- **Root Cause**:
  1. `COPY missing-folder ./missing-folder` referenced a non-existent directory in the build context.
  2. `.dockerignore` listed `src`. Consequently, `app.js` failed at runtime when attempting `const routes = require('./src/routes');`.
- **Fix**:
  1. Removed `COPY missing-folder ./missing-folder`.
  2. Removed `src` from `.dockerignore`. Updated `.dockerignore` to filter actual build/repository noise:
     ```
     node_modules
     .git
     .gitignore
     npm-debug.log
     .env
     DEBUGGING-NOTES.md
     ```

### Family 5: Startup Command Error
- **Root Cause**: `CMD ["npm", "run", "production"]` attempted to execute script `"production"`. `package.json` only defines script `"start": "node app.js"`.
- **Fix**: Updated runtime command to `CMD ["npm", "start"]`.

---

## 3. Repaired & Optimized Dockerfile

```dockerfile
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
```

---

## 4. Verification Evidence

### Build Output Verification
Executing `docker build -t app:fixed .` completes cleanly with zero errors:

```text
#1 [internal] load build definition from Dockerfile
#2 [internal] load metadata for docker.io/library/node:18-alpine
#3 [internal] load .dockerignore
#4 [internal] load build context
#5 [1/5] FROM docker.io/library/node:18-alpine
#6 [2/5] WORKDIR /app
#7 [3/5] COPY package.json package-lock.json ./
#8 [4/5] RUN npm ci --only=production
#8 added 68 packages, and audited 69 packages in 3s
#9 [5/5] COPY . .
#10 exporting to image app:fixed
```

### Runtime Container Verification
Running the container and testing the endpoint on port 8080:

```powershell
docker run -d -p 8080:8080 --name test-app-fixed app:fixed
Invoke-RestMethod -Uri "http://localhost:8080"
```

**HTTP Response Output:**
```html
<!DOCTYPE html>
<html lang="en">
<head>
    <title>Docker Repair Lab</title>
</head>
<body>
    <div class="container">
        <h1>Docker Repair Lab Running Successfully</h1>
        <p>If you can see this page, it means you have successfully repaired the Dockerfile...</p>
        <div class="badge">Success</div>
    </div>
</body>
</html>
```

**Container Log Output:**
```text
> dockerfile-repair-lab@1.0.0 start
> node app.js

Server is running on port 8080
```
