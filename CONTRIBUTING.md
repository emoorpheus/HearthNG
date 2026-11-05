# Contributing to HearthNG

Thank you for helping. HearthNG is a fork of [Hearth for WebOS](https://github.com/rudra-avatar/Hearth); fixes that
also apply to Hearth are welcome there too.

## Reports

- **Bugs:** open an issue with the *Bug report* form. Say which TV (model, webOS and firmware version from Settings,
  Support, TV Information), whether it is rooted, and what you did. The Debug tab (Settings, System, *Show the Debug
  tab*) or `/tmp/hearth-debug.txt` on a rooted TV helps a lot.
- **Tested a TV?** The *Compatibility report* form fills the Tested TVs table once a maintainer marks it `verified`.
- **Security problems:** not in an issue; see [SECURITY.md](SECURITY.md).

## Translations

Start from `docs/languages/en.json` and follow `docs/language_packs.md`. Translations are written by people; machine
translations are not accepted. Send them with the *Translation* form or as a pull request.

## Code

Read [AGENTS.md](AGENTS.md) first: it lists where things are and the rules. In short:

```sh
npm install
npm i --prefix /tmp/ast typescript@5   # once; the language scan test needs the TypeScript 5 API
npm test                               # must pass before and after your change
npm run build && npm run package       # build/com.hearthng.launcher_<version>_all.ipk
```

- Write the test first and see it fail; then make it pass; then run the whole suite.
- Keep each pull request to one change, with a message that says why, what, and how you checked it.
- Say plainly whether you tried it on a TV (which model and webOS version) or only with the tests.
- Code must run on Chrome 53 and Chromium 38 (webOS 3); every visible text goes into `src/i18n/en.ts`.
- Shell scripts are POSIX `sh` and pass `shellcheck -s sh`.
- Do not commit IP addresses, host names, tokens or other personal data; use `TV_IP` in examples.

By sending a contribution you agree that it is published under the MIT licence of this project.
