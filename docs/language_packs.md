# Language files

HearthNG's menus are in English. Other languages come from users; a few were translated by machine and are marked *(machine translated)* until a native speaker checks them. There are two ways to use one.

## Choose a language that comes with HearthNG (every TV, no root)

Languages that users shared and we accepted are inside the app and arrive with HearthNG updates (Homebrew Channel). Open **Settings → System** and use the left and right arrows on **HearthNG language**. The first time you pick a language it is read from the app (about a second); after that it is instant. Texts a language does not have yet stay in English. The list of languages that come with HearthNG is at the end of this page.

## Load your own language file (rooted TVs)

1. Put the file on the TV in `/media/developer/languages`, or on a USB drive (the file name must end in `.json`).
2. In HearthNG open **Settings → System** and press OK on **HearthNG language**.
3. Pick the folder or drive, then the file. A wrong file changes nothing and the pop-up says why.
4. Your file joins the arrows list, after the languages that come with HearthNG. **Remove the language file** takes it out again.

Loading your own file needs a rooted TV; choosing a language that comes with HearthNG does not. Your own file and the bundled languages do not replace each other.

## Make a language file

Start from the English base file: [`languages/en.json`](languages/en.json). Copy it, then change:

- `"language"`: the name shown in Settings (up to 30 characters), for example `"Deutsch"`.
- `"code"`: the language code, for example `"de"` or `"pt-BR"` (optional for your own file; required for a file you share, and the file is named `<code>.json`).
- the texts under `"strings"`: translate the part after the colon, never the key on the left.

A file looks like this:

```json
{
  "format": 1,
  "language": "Deutsch",
  "code": "de",
  "strings": {
    "pref.theme.label": "Thema",
    "pref.quietSec.label": "Ruhemodus"
  }
}
```

Rules, checked when the file is loaded:

- The file is UTF-8 JSON, at most 400 KB, and `"format"` is `1`.
- Keep every `{placeholder}` exactly as in English (for example `{name}` or `{n}`): the same ones, no more, no fewer. The text around them may move.
- A text is not empty, has no more than 1000 characters and no control characters (a line break is allowed).
- Keys that HearthNG does not know are ignored; keys you leave out stay English. You do not have to translate everything.

## Limits

- HearthNG shows the letters the TV's fonts have. Languages with Latin, Cyrillic or Greek letters are the supported scope. Chinese, Japanese, Korean, Arabic, Hebrew and other scripts, and right-to-left writing, are **not supported in 2.0.0** (menus would show missing-letter boxes or the wrong direction). We reopen this only after a TV report from a tester.
- The menu changes at once; a few texts (such as lists that were already open) change after HearthNG restarts.
- When a new HearthNG version adds texts, they show in English until your file is updated.

## Share your translation

1. Name the file after the code, for example `de.json` or `pt-BR.json`, and load it on your TV first to see that the letters show.
2. Send the file to the HearthNG author (HearthNG has no public issue tracker yet). Hearth's **Translation** issue form is for Hearth.
3. The file goes into the folder `docs/languages/packs` of the HearthNG source (the file name must be `<code>.json` and the `"code"` inside must match) and into the list below, with your name if you want it. Your wording is not changed.
4. The next HearthNG release carries it inside the app (the build copies every file of that folder; a wrong file stops the build). From then on everybody, rooted or not, picks it with the arrows.

Languages that come with HearthNG: Bahasa Indonesia (`id`), Español (`es`), Deutsch (`de`), العربية (`ar`), Français (`fr`), Polski (`pl`), Português (Brasil) (`pt-BR`), Русский (`ru`). Français was written and checked by Foxinou35 (issue #33), Polski by sir_RAFIK (issue #35) and Português (Brasil) by assanches (issue #38), all native speakers. The first four languages of the list and Русский were translated from the English base file by Claude (Anthropic), not by a native speaker; the texts added after the native versions of Français, Polski and Português (Brasil) were written (2.1.0) were also translated by Claude; wording corrections are welcome through the *Translation* form or a pull request. Arabic is shown with the bundled Noto Sans Arabic font; the screens stay laid out left to right (no mirrored layout).

## Keep a language file up to date

Each release lists the texts that are new or changed: maintainers run `node scripts/lang-check.mjs` and post the list with the release. Add the new keys to your file; for changed ones re-read the English text. A pack needs no update to keep working, because texts it lacks stay English. When a language that comes with HearthNG is improved, the new HearthNG version replaces the copy on the TV by itself (once, after the update).
