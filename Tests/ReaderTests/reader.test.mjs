// Adapter contract tests, not a browser/WKWebView rendering or performance test.
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import vm from 'node:vm'

const source = (await readFile(new URL('../../Sources/Leaf/Resources/Reader/reader.js', import.meta.url), 'utf8'))
    .replace(/^import '\.\/foliate\/view.js'\s*$/m, '')

async function reader(meta = { name: 'Help', format: 'chm', entries: [{ filename: 'index.html' }] }) {
    const messages = [], styles = [], selected = []
    let initialized = false, cleared = 0
    const view = {
        renderer: { setStyles: css => styles.push(css) },
        addEventListener() {},
        async open(book) { this.book = book },
        // Match pinned Foliate's destructured init argument: missing {} must fail.
        async init({ lastLocation, showTextStart }) { initialized = true },
        async select(value) { selected.push(value) },
        clearSearch() { ++cleared },
        async *search() {},
    }
    const window = { leafStyle: 'system|17|1.6|32|light', addEventListener() {},
        webkit: { messageHandlers: { leaf: { postMessage: message => messages.push(message) } } } }
    const context = vm.createContext({ window, URL, Blob,
        document: { createElement: () => view, body: { append() {} } },
        matchMedia: () => ({ matches: false, addEventListener() {} }),
        fetch: async () => ({ ok: true, json: async () => meta }),
    })
    await vm.runInContext(`(async () => { ${source}\n})()`, context)
    return { view, window, messages, styles, selected,
        get initialized() { return initialized }, get cleared() { return cleared } }
}

test('CHM initialization follows pinned Foliate API and emits ready', async () => {
    const app = await reader()
    assert.ok(app.initialized)
    assert.ok(app.messages.some(x => x.type === 'ready'))
    assert.ok(!app.messages.some(x => x.type === 'error'))
})

test('closing Find prevents delayed results from replacing the contents', async () => {
    const app = await reader()
    let release
    const gate = new Promise(resolve => { release = resolve })
    app.view.search = async function* () { await gate; yield { subitems: [{ cfi: 'hit', excerpt: {} }] } }
    const pending = app.window.leafCommand({ name: 'find', text: 'word' })
    await app.window.leafCommand({ name: 'toc' })
    release()
    await pending
    assert.ok(app.cleared > 0)
    assert.ok(!app.messages.some(x => x.type === 'results'))
    assert.equal(app.selected.length, 0)
})

test('theme and font changes preserve current CHM zoom', async () => {
    const app = await reader()
    await app.window.leafCommand({ name: 'zoom', number: 2 })
    assert.match(app.styles.at(-1), /font-size:34px/)
    await app.window.leafCommand({ name: 'style', text: 'serif|19|1.6|32|dark' })
    assert.match(app.styles.at(-1), /font-size:38px/)
    assert.match(app.styles.at(-1), /background:#111/)
})

test('CHM with no HTML reports a useful failure rather than ready', async () => {
    const app = await reader({ name: 'Empty', format: 'chm', entries: [] })
    assert.ok(app.messages.some(x => x.type === 'error' && /no HTML/.test(x.message)))
    assert.ok(!app.messages.some(x => x.type === 'ready'))
})
