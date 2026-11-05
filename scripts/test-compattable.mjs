// The Tested TVs table (.github/scripts/compat-table.mjs) reads HearthNG's issue form and still reads reports filed
// on the Hearth form (headings "Does Hearth work…", "Hearth version").
import {rowOf, tableOf} from '../.github/scripts/compat-table.mjs';
let fail = 0;
const eq = (got, want, name) => { const ok = JSON.stringify(got) === JSON.stringify(want); console.log((ok ? 'ok   ' : 'FAIL ') + name + (ok ? '' : `\n   got  ${JSON.stringify(got)}\n   want ${JSON.stringify(want)}`)); if (!ok) fail++; };
const body = (works, version, way) => ['### TV type', '', 'OLED', '### Exact TV model (optional)', '', 'OLED00X0XXA',
	'### webOS version', '', '4.x', '### Firmware version', '', '05.30.00', '### Is the TV rooted?', '', 'Yes',
	works[0], '', works[1], version[0], '', version[1], '### Remote control (optional)', '', 'Magic Remote', way[0], '', way[1]].join('\n');
const ng = {number: 7, html_url: 'https://github.com/emoorpheus/hearthng/issues/7',
	body: body(['### Does HearthNG work on your TV?', 'Yes, it works'], ['### HearthNG version (optional)', '1.0.0'], ['### How do you open HearthNG? (optional)', 'The helper that replaces LG Home'])};
const old = {number: 3, html_url: 'https://github.com/rudra-avatar/Hearth/issues/3',
	body: body(['### Does Hearth work on your TV?', 'No'], ['### Hearth version (optional)', '2.0.1'], ['### How do you open Hearth? (optional)', 'Power-on app (when the TV starts)'])};
const r = rowOf(ng);
eq(r && [r[4], r[5], r[7]], ['Works', '1.0.0', 'The helper that replaces LG Home'], 'a HearthNG form gives result, version and how it opens');
const o = rowOf(old);
eq(o && [o[4], o[5], o[7]], ['Does not work', '2.0.1', 'Power-on app (when the TV starts)'], 'a Hearth form still gives its row');
eq(rowOf({number: 9, html_url: 'x', body: '### Something else\n\ntext'}), null, 'a body that is not a compatibility form gives no row');
eq(tableOf([ng]).split('\n')[0].indexOf('| Version |') !== -1, true, 'the table names the column Version (HearthNG and Hearth reports share it)');
console.log(fail ? `\n${fail} FAILED` : '\nall ok');
process.exit(fail ? 1 : 0);
