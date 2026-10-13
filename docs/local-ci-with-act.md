# Testing CI locally with act

[act](https://github.com/nektos/act) runs the GitHub Actions workflow in
`.github/workflows/ci.yml` inside Docker containers, so you can check it
before pushing.

## Tools and libraries

| Tool | Used for |
| --- | --- |
| [act](https://github.com/nektos/act) | Runs workflows locally |
| Docker | Container runtime act needs |
| [GitHub CLI (`gh`)](https://cli.github.com) | Optional: installs act as an extension |

### What the workflow itself uses

| Library / action | Purpose |
| --- | --- |
| `actions/checkout@v4` | Checks out the repo |
| `actions/setup-node@v4` | Node 20 + npm cache for the frontend |
| `actions/setup-python@v5` | Python 3.12 + pip cache for the Django services |
| `docker/setup-buildx-action@v3` | Sets up Buildx for the `docker` job |
| `docker/login-action@v3` | Logs in to Docker Hub (push events only) |
| `docker/metadata-action@v5` | Generates image tags and labels |
| `docker/build-push-action@v6` | Builds and pushes the service images |
| `slackapi/slack-github-action@v1.26.0` | Slack notification (`notify-slack` job) |
| `flake8` | Python lint (syntax errors and undefined names only) |
| Django test runner (`manage.py test`) | Auth and game service tests |
| `vite build` (`npm run build`) | Frontend build check |

## Install

```bash
# GitHub CLI extension
gh extension install https://github.com/nektos/gh-act

# or the standalone script (-b sets the install dir; the default is ./bin
# in the current directory, which is not on PATH)
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin

act --version
```

On first run act asks which runner image to use. Choose **Medium**.

## Run

Run from the repo root.

```bash
act -l                                              # list jobs, confirms the workflow parses
act push -j frontend                                # frontend job only
act push -j django                                  # both Django services (matrix)
act push -j django --matrix service:auth_service    # a single service
act pull_request -j docker                          # build images without pushing
act pull_request                                    # simulate a PR event
act push --secret-file .env                         # pass secrets from .env
act push --reuse                                    # keep containers between runs
act push --container-architecture linux/amd64       # Apple Silicon
```

## Notes

- The workflow triggers on pushes and PRs to `develop`. `act push` checks the
  current branch, so run it from `develop` or no workflow will match.
- `act push` runs the `docker` job with `push` enabled, so it logs in and
  pushes to Docker Hub if `--secret-file .env` supplies `DOCKER_USERNAME` and
  `DOCKERHUB_TOKEN`. To only test the build, use `act pull_request -j docker`.
  The `gha` build cache is not available under act and is ignored.
- `notify-slack` posts to the real Slack webhook if `SLACK_WEBHOOK_URL` is
  provided. Run it with `-j frontend` and `-j django` to avoid sending messages.
- `cache: npm` / `cache: pip` may warn or do nothing locally, because act has
  no GitHub cache service. This is harmless.
- `concurrency` and `permissions` are ignored by act.
- A green act run is a sanity check, not proof. GitHub's runner image and `if:`
  expressions can still behave differently.
- Keep `.env` out of git. It is listed in `.gitignore`.
