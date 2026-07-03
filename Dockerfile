# Production image for Novel (Novella on Olares).
# Build: docker build -t beclab/novella:v1.0.3 .
# Run:   docker run -p 3000:3000 -e OPENAI_API_KEY=... -e OPENAI_BASE_URL=... beclab/novella:v1.0.3

FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@9.5.0 --activate
WORKDIR /app

FROM base AS deps
ENV CI=true
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json ./apps/web/
COPY packages/headless/package.json ./packages/headless/
COPY packages/tsconfig/package.json ./packages/tsconfig/
RUN printf '%s\n' \
  'onlyBuiltDependencies[]=@biomejs/biome' \
  'onlyBuiltDependencies[]=esbuild' \
  'onlyBuiltDependencies[]=sharp' \
  >> .npmrc \
  && pnpm install --frozen-lockfile

FROM base AS builder
ENV CI=true
WORKDIR /app
# Copy the full pnpm workspace install (root + package-level node_modules symlinks).
COPY --from=deps /app/ ./
COPY . .
# Turbo "build" runs typecheck before ^build outputs exist in Docker; build
# workspace packages directly so novel dist + .d.ts exist before next build.
RUN pnpm --filter novel run build \
 && pnpm --filter novel-next-app run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs

COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/static ./apps/web/.next/static

USER nextjs
EXPOSE 3000
CMD ["node", "apps/web/server.js"]
