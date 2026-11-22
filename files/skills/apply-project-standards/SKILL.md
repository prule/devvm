---
name: apply-project-standards
description: >
  Bring one repo in line with the standards in ~/projects/CLAUDE.md: lint and
  format inside the test/verify command, PMD/SpotBugs/Spotless, pinned deps,
  Renovate, hooks, shellcheck/hadolint, push protection. Use when asked to
  apply, check or align a project with the project standards.
---

# Apply project standards

The rules are in `~/projects/CLAUDE.md`, the single source of truth. This skill is the recipe for meeting them in the current repo. It does not restate them.

## Steps

1. **Check.** Run `standards-check` at the repo root. Each output line is one gap; exit 0 means none. Lines starting `note:` (stderr) are not gaps.
2. **Plan.** Read the repo's build files, `package.json`s, CI workflows and `CLAUDE.md`. Group the gaps by the sections below. Done when every gap line has a planned fix, or a reason it does not apply (say a workspace package already linted from the root).
3. **Fix**, one section at a time, with the recipes below. After each section, run the repo's normal test/verify command (`./run` if the repo has one) and get it green before the next section.
4. **Existing violations.** A newly added checker (PMD, SpotBugs, ESLint, strict TypeScript, shellcheck) usually fails on code that was already there. Fix them when there are a handful. When there are many, stop and tell the user the count per checker, and propose a choice: fix them now, or narrow the rule set and fix them later. Never silence a checker to get green.
5. **Verify.** `standards-check` exits 0 (or every remaining line is agreed with the user), the test/verify command passes, the same command with `CI=true` passes without changing any file (`git status` clean afterwards), and `sonar-check` passes.
6. **Report.** One line per gap: fixed, skipped (why), or left for the user. Do not commit unless asked.

Pin every version you add to the newest release, looked up now (Gradle plugin portal, Maven Central, `pnpm view <pkg> version`), never from memory. Renovate keeps them current after that.

## Gradle

In the module's `build.gradle.kts` (use the version catalog or `buildSrc` convention plugin if the repo has one):

```kotlin
plugins {
    pmd
    id("com.diffplug.spotless") version "<latest>"
    id("com.github.spotbugs") version "<latest>"
}

spotless { java { googleJavaFormat() } }  // keep palantirJavaFormat() if the repo already uses it

pmd {
    toolVersion = "<latest PMD 7>"
    isConsoleOutput = true
}

// Format before compiling, locally only: CI must fail on unformatted code, not fix it.
if (System.getenv("CI") == null) {
    tasks.named("compileJava") { dependsOn("spotlessApply") }
}
```

All three plugins hook their checks into `check`. Kotlin modules: `spotless { kotlin { ktlint() } }`, and Detekt in place of PMD.

## Maven

- `spotless-maven-plugin` with goal `check` in the main build (it binds to `verify`).
- `apply` bound to `process-sources` in a profile active only outside CI:

```xml
<profile>
  <id>format</id>
  <activation><property><name>!env.CI</name></property></activation>
  <build><plugins><plugin>
    <groupId>com.diffplug.spotless</groupId>
    <artifactId>spotless-maven-plugin</artifactId>
    <executions><execution>
      <id>apply</id><phase>process-sources</phase><goals><goal>apply</goal></goals>
    </execution></executions>
  </plugin></plugins></build>
</profile>
```

- `maven-pmd-plugin` and `spotbugs-maven-plugin`, each with goal `check` (binds to `verify`).
- No `./mvnw`: `mvn wrapper:wrapper` once, then commit `mvnw`, `mvnw.cmd` and `.mvn/`. No `./gradlew`: `gradle wrapper` once, then commit it.

## JavaScript and TypeScript

Work at the repo root; in a pnpm workspace, add the tools once at the root with `pnpm add -D -E -w`.

- Tools: `pnpm add -D -E eslint @eslint/js typescript-eslint eslint-config-prettier prettier`, plus the framework's plugin if one is used (`eslint-plugin-react-hooks`). Write a flat `eslint.config.js` from `@eslint/js` recommended, `typescript-eslint` recommended and `eslint-config-prettier` last. Add a `.prettierignore` for build output.
- oxlint instead of ESLint, only when the user asks for it or the repo already uses it: `pnpm add -D -E oxlint prettier`, `pnpm exec oxlint --init` for `.oxlintrc.json`, and `oxlint` for `eslint` in the scripts and lint-staged below. Drop ESLint and its config rather than run both.
- Scripts (keep the repo's own test runner in place of `vitest run`):

```json
"lint": "eslint . && prettier --check .",
"format": "eslint --fix . && prettier --write .",
"fix": "if [ -n \"$CI\" ]; then pnpm lint; else pnpm format; fi",
"test": "pnpm fix && vitest run"
```

- `tsconfig`: `"strict": true` in the config the compiler uses (`tsconfig.app.json` in a Vite project with references).
- Floating ranges: add `save-exact=true` to `.npmrc`, then set each range to the version the lockfile resolved (`pnpm ls --depth 0 --json`), and run `pnpm install`.
- An npm or yarn lockfile: delete it, `pnpm import` first if `pnpm-lock.yaml` is missing, then `pnpm install`.
- Package manager guard, root `package.json` only: set `"packageManager": "pnpm@<pnpm -v>"` and `"devEngines": {"packageManager": {"name": "pnpm", "onFail": "error"}}`. Node 25+ has no Corepack, so `packageManager` alone does not stop npm; `devEngines` makes npm fail with `EBADDEVENGINES`.

## Hooks

The hook is a backstop for edits made outside the build; the build and CI are what enforce. A repo with a `package.json` uses Husky + lint-staged. A JVM-only repo uses a native hook: adding a `package.json` just for Husky would make Node a requirement for a hook git runs on its own.

**Husky + lint-staged:**

```bash
pnpm add -D -E -w husky lint-staged   # drop -w outside a pnpm workspace
pnpm exec husky init                  # adds the "prepare": "husky" script and .husky/pre-commit
echo "pnpm exec lint-staged" > .husky/pre-commit
```

`lint-staged.config.mjs` at the root. Each file matches one glob only, because lint-staged runs globs in parallel and two tools rewriting one file race:

```js
const code = '*.{js,jsx,ts,tsx,mjs,cjs}';
export default {
  [code]: ['eslint --fix', 'prettier --write'],
  [`!(${code})`]: 'prettier --write --ignore-unknown',
  // With a JVM backend in the same repo. A function, so lint-staged does not
  // append file names, which Gradle would read as task names:
  // '*.{java,kt,kts}': () => './gradlew spotlessApply',
};
```

lint-staged re-stages only what it formatted and keeps unstaged changes out of the commit. `pnpm install` runs `prepare`, so every clone gets the hook. Husky sets `core.hooksPath`, and the VM still scans for secrets there, from `~/.config/husky/init.sh`.

**Native hook (JVM-only):** `.githooks/pre-commit`, executable (`chmod +x`):

```bash
#!/bin/bash
# Formats staged code before a commit. A backstop: the build formats too.
set -euo pipefail
# core.hooksPath makes git skip .git/hooks, where the VM's secret scan lives.
if command -v devvm-secret-scan > /dev/null; then devvm-secret-scan || exit 1; fi
staged=$(git diff --cached --name-only --diff-filter=ACMR -- '*.java' '*.kt' '*.kts')
[ -z "$staged" ] && exit 0
./gradlew spotlessApply --quiet   # Maven: ./mvnw --quiet spotless:apply
# Re-stage only the files that were staged; shortcut: a partly staged file gets its unstaged hunks too.
echo "$staged" | xargs git add --
```

`core.hooksPath` is local config, which a clone does not carry, so set it from the build. Gradle:

```kotlin
val installGitHooks by tasks.registering(Exec::class) {
    commandLine("git", "config", "core.hooksPath", ".githooks")
}
tasks.named("compileJava") { dependsOn(installGitHooks) }
```

Maven, or a repo with `./run`: add `git config core.hooksPath .githooks` to `./run setup`. With neither, add it as a once-per-clone step to the repo's `CLAUDE.md` and README.

**CI:** the workflow runs the same check-only command as the build (`./gradlew check`, `./mvnw verify`, `pnpm lint` and `pnpm test`), with `CI` set, which GitHub Actions does by default. Add the step if the workflow lacks it.

## Renovate

`renovate.json` at the root:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", ":pinAllExceptPeerDependencies"]
}
```

## Shell and Dockerfiles

Fix each `shellcheck` and `hadolint` finding in the code. Add a `# shellcheck disable=SCxxxx` or `# hadolint ignore=DLxxxx` comment only on a line that is deliberate (a demo of a defect, say), with the reason on the same line.

## Push protection

Changing a repo's settings on GitHub is outward-facing: ask the user first. On their yes:

```bash
gh api -X PATCH repos/<owner>/<repo> \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
```

A private repo on a free plan cannot have it (`standards-check` prints a `note:`); report that, nothing to fix.
