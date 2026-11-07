# SmartStock Pro — Architecture (initial baseline)

## Product scope
Android-first investment research assistant for Vietnamese equities. The product provides decision support and research tools; it does not place trades or guarantee investment returns.

## Planned system
- **Mobile:** Flutter Android application.
- **API:** Python FastAPI, versioned under `/api/v1`.
- **Database:** PostgreSQL for users, watchlists, market observations, financial statements, analysis runs, and strategy results.
- **AI layer:** LLM orchestration with retrieval-augmented generation (RAG); provider keys remain on the server.
- **Market data:** prioritize licensed/official data access. FireAnt is the preferred initial provider; evaluate WiGroup/WiFeed as fallback subject to contract, coverage, and permitted use.

## Main bounded modules
1. Identity and access: registration, login, access/refresh tokens, role-based authorization.
2. Market data: symbols, OHLCV, corporate actions, financial statements, data provenance and freshness.
3. Technical analysis: Elliott Wave, Fibonacci, RSI, MACD, Volume Profile, OBV, A/D, CMF, CVD/Delta.
4. Fundamental analysis: financial statement normalization, ratios, quality checks, valuation.
5. Scanner and scoring: configurable filters and explainable ranking.
6. AI research room: RAG over approved documents and the user's saved research.
7. Backtesting: historical strategy simulation with fees, slippage, and out-of-sample evaluation.

## Security baseline
- HTTPS in every deployed environment.
- Passwords hashed with Argon2id (or bcrypt where Argon2id is unavailable).
- Short-lived access tokens and rotating/revocable refresh tokens.
- Secrets and AI provider credentials stored only in server-side environment/secret storage.
- Validate and authorize every user-owned resource on the server.
- Audit sensitive authentication and account events without logging passwords or tokens.

## Delivery sequence
1. Repository foundation and API health check.
2. Authentication and user profile.
3. Market data abstraction and mock provider for deterministic development.
4. Watchlists and quote/history endpoints.
5. Technical-analysis services and explainable scanner.
6. Financial statements and fundamental analysis.
7. AI RAG research room.
8. Backtesting, monitoring, hardening, and Android release pipeline.

## Current implementation status
This repository started with a README only. The first implementation slice adds a minimal FastAPI service and health tests. Database persistence, authentication, market-data integrations, Flutter screens, and AI workflows are not implemented yet.
