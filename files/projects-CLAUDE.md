# Project standards

<!-- Generated from devvm/files/projects-CLAUDE.md on every boot. Edit it there; changes made here are lost on restart. -->

## All projects

- Before reporting work as done, run the project's tests and `sonar-check`, and fix what fails.
- To list SonarQube issues beyond what `sonar-check` prints, query the API with no login: `curl -s "http://localhost:9000/api/issues/search?components=<project key>&resolved=false&ps=500"`. The key is `sonar.projectKey` in `sonar-project.properties`, otherwise the repo's directory name.
- If the repo has an executable `./run` at its root, use it for setup, serve, build and other project tasks.
- Formatting and linting are part of the build, so the normal test command does them with no separate step: it formats and auto-fixes first, then fails on what is left. In CI (`CI` is set) it only checks, never rewrites. See Java and JavaScript below.
- A format-on-commit hook stays as a backstop: Husky + lint-staged where there is a `package.json`, a native Git hook (`core.hooksPath`) in a JVM-only repo. CI runs the same checks as the build.
- Pin dependency versions (no floating ranges) and let Renovate bump them.
- Shell scripts pass `shellcheck`; Dockerfiles pass `hadolint`.
- Every repo's own GitHub secret scanning with push protection is on (Settings → Advanced Security). Remind the user if a repo you work on does not have it.

## Java

- Format with Spotless (google-java-format or palantir-java-format), and run PMD and SpotBugs (or Error Prone), failing the build on violations.
- Gradle: the plugins hook their checks into `check`; outside CI, also make `compileJava` depend on `spotlessApply`.
- Maven: bind `spotless:apply` to `process-sources` outside CI (a profile off when `env.CI` is set), and `spotless:check`, `pmd:check` and `spotbugs:check` to `verify`.
- Build with the wrapper (`./gradlew` or `./mvnw`), never a system Gradle or Maven.

## JavaScript and TypeScript

- Always use `pnpm` instead of `npm`: `pnpm install`, `pnpm run <script>`, `pnpm exec <command>`. Do not run `npm` or `npx`.
- The root `package.json` sets `"packageManager": "pnpm@<version>"` and `"devEngines": {"packageManager": {"name": "pnpm", "onFail": "error"}}`, so `npm install` fails in the repo on any machine.
- Lint with ESLint, or oxlint if the user prefers it, and format with Prettier; `tsconfig` has `"strict": true`.
- The `test` script fixes first, then tests, e.g. `eslint --fix . && prettier --write . && vitest run` (`oxlint --fix` in place of `eslint --fix` with oxlint), and a `lint` script (`eslint . && prettier --check .`) is what CI runs. Do not rely on a `pretest` script: pnpm may not run pre/post scripts.
- Run `pnpm audit` after adding a dependency, and do not leave high or critical findings.
