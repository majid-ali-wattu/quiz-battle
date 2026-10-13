# Quiz Battle

A small two-player trivia game built as two independent Django microservices.

## Architecture

- **auth_service** (port 8001) — owns accounts. Register/login, issues JWTs
  (signed with a secret shared with game_service), tracks per-user win/loss
  stats. Its own SQLite database.
- **game_service** (port 8002) — owns everything about a match: question
  bank, rooms, scoring. Verifies JWTs itself (no network call back to
  auth_service on every request) and only calls auth_service once, after a
  match ends, to report the result via an internal endpoint. Its own SQLite
  database — it stores `user_id`/`username` from the token, not a foreign
  key into auth_service's users.

This is the standard microservice pattern: each service owns its data, and
they only talk to each other over HTTP for the one thing they can't know on
their own (auth_service needs to know who won; game_service needs to know
who's making the request).

There's no websockets/queue here on purpose — answers are submitted via
plain HTTP POSTs and you poll room state with GET. Good enough for a
2-player async match, and keeps the stack simple.

## Running it

```bash
docker compose up --build
```

- auth_service: http://localhost:8001
- game_service: http://localhost:8002 (auto-seeds 10 trivia questions on
  startup)

## Playing a full match (curl)

```bash
# 1. Register two players
curl -X POST localhost:8001/api/register/ -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "hunter22"}'
curl -X POST localhost:8001/api/register/ -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "hunter22"}'

# 2. Log in, grab each token
ALICE_TOKEN=$(curl -s -X POST localhost:8001/api/login/ -H "Content-Type: application/json" \
  -d '{"username": "alice", "password": "hunter22"}' | jq -r .token)
BOB_TOKEN=$(curl -s -X POST localhost:8001/api/login/ -H "Content-Type: application/json" \
  -d '{"username": "bob", "password": "hunter22"}' | jq -r .token)

# 3. Alice creates a room
CODE=$(curl -s -X POST localhost:8002/api/rooms/ -H "Authorization: Bearer $ALICE_TOKEN" | jq -r .code)

# 4. Bob joins it
curl -X POST localhost:8002/api/rooms/$CODE/join/ -H "Authorization: Bearer $BOB_TOKEN"

# 5. Both fetch the questions (no correct_choice field is sent to clients)
curl localhost:8002/api/rooms/$CODE/questions/ -H "Authorization: Bearer $ALICE_TOKEN"

# 6. Each player answers every question
curl -X POST localhost:8002/api/rooms/$CODE/answer/ -H "Authorization: Bearer $ALICE_TOKEN" \
  -H "Content-Type: application/json" -d '{"question_id": 1, "choice": "b"}'
# ... repeat for each question, for both players

# 7. Check the room — once both players have answered everything, status
#    flips to "finished" and auth_service stats get updated automatically
curl localhost:8002/api/rooms/$CODE/ -H "Authorization: Bearer $ALICE_TOKEN"

# 8. Check a player's win/loss record
curl localhost:8001/api/profile/1/
```

## Local dev without Docker

Each service is a normal Django project:

```bash
cd auth_service
python -m venv .venv && .venv\Scripts\activate   # or source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 8001
```

```bash
cd game_service
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate
python manage.py seed_questions
python manage.py runserver 8002
```

Set `JWT_SECRET`/`INTERNAL_API_KEY` env vars identically in both shells if
you change them from the defaults — they must match for the two services to
trust each other.

## CI/CD

`.github/workflows/ci.yml` runs on pushes and pull requests to `develop`:

| Job | What it does |
| --- | --- |
| `frontend` | `npm ci` and `npm run build` |
| `django` | For `auth_service` and `game_service`: flake8, `makemigrations --check`, `manage.py test` |
| `docker` | Builds an image per service; on a push (not a PR) also pushes it to Docker Hub |
| `notify-slack` | Posts the result to Slack, with the Docker Hub image links after a push |

Images are pushed as `<DOCKER_USERNAME>/quiz-battle-<service>` for
`auth_service`, `game_service` and `frontend`, tagged `latest`, `develop` and
`sha-<short sha>`.

Required GitHub repo secrets (Settings → Secrets and variables → Actions):
`DOCKER_USERNAME`, `DOCKERHUB_TOKEN`, `SLACK_WEBHOOK_URL`. Keep them in a local
`.env` (git-ignored) if you need them for local runs.

To test the workflow locally, see [docs/local-ci-with-act.md](docs/local-ci-with-act.md).

## Extending it later

- Swap SQLite for Postgres per service (just change `DATABASES` — nothing
  else needs to know).
- Add a `matchmaking` service that pairs waiting players instead of manual
  room codes.
- Add a leaderboard service that reads aggregated stats from auth_service.
