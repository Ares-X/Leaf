// Foliate supplies parsing, pagination, CFI, links, selection and search; Leaf supplies local bytes.
import './foliate/view.js'
const post = (type, data = {}) => window.webkit.messageHandlers.leaf.postMessage({ type, ...data })
const base = 'leaf://book'
const entryURL = name => `${base}/entry/${name.split('/').map(encodeURIComponent).join('/')}`
const fetchOK = async url => { const response = await fetch(url); if (!response.ok) throw Error(`Cannot read ${url}`); return response }
const flatten = (items = [], depth = 0) => items.flatMap(item => [
    { title: item.label || 'Untitled', target: String(item.href), depth }, ...flatten(item.subitems, depth + 1),
])
// A Blob-like slice backed by native seek/read. No whole-book fetch or base64 copy for MOBI/KF8.
class LocalSlice {
    constructor(name, size, start = 0, end = size) { Object.assign(this, { name, size: end - start, start, end }) }
    slice(start = 0, end = this.size) {
        const at = n => Math.max(0, Math.min(this.size, n < 0 ? this.size + n : n))
        const first = at(start), last = Math.max(first, at(end))
        return new LocalSlice(this.name, this.size, this.start + first, this.start + last)
    }
    async arrayBuffer() { return (await fetchOK(`${base}/raw?start=${this.start}&end=${this.end}`)).arrayBuffer() }
    async text() { return new TextDecoder().decode(await this.arrayBuffer()) }
}
const parse = html => new DOMParser().parseFromString(html, 'text/html')
const htmlBook = async (meta, markdown = false) => {
    let paths, contents
    if (meta.format === 'chm') {
        paths = meta.entries.map(x => x.filename).filter(x => /\.x?html?$/i.test(x))
        const index = paths.findIndex(x => /(^|\/)(index|default|welcome)\.html?$/i.test(x))
        if (index > 0) paths.unshift(...paths.splice(index, 1))
        contents = async path => (await fetchOK(entryURL(path))).text()
    } else {
        paths = [meta.name]
        let html = await (await fetchOK(`${base}/raw`)).text()
        if (markdown) { const { marked } = await import('./marked.js'); html = marked.parse(html, { gfm: true }) }
        contents = async () => html
    }
    if (!paths.length) throw Error('This document contains no HTML pages')
    const localHref = href => href.replace(/^(?:mk:@MSITStore:|ms-its:|its:).*?::\/?/i, '').replace(/\\/g, '/')
    const resolve = href => {
        const url = new URL(localHref(href), entryURL(paths[0]))
        const path = decodeURIComponent(url.pathname.replace(/^\/entry\//, ''))
        return { index: Math.max(0, paths.findIndex(p => meta.format === 'chm' ? p.toLowerCase() === path.toLowerCase() : p === path)), anchor: doc => doc.getElementById(decodeURIComponent(url.hash.slice(1))) }
    }
    const sections = paths.map(path => {
        let blob
        const createDocument = async () => {
            const doc = parse(await contents(path)), tag = doc.createElement('base')
            tag.href = meta.format === 'chm' ? entryURL(path) : `${base}/files/`
            doc.head.prepend(tag)
            // All scripts are disabled by the reader's CSP. No generic HTML sanitizer or parser framework.
            return doc
        }
        return { id: path, size: 1, createDocument,
            resolveHref: href => new URL(localHref(href), entryURL(path)).href,
            load: async () => {
                if (!blob) blob = URL.createObjectURL(new Blob([(await createDocument()).documentElement.outerHTML], { type: 'text/html' }))
                return blob
            }, unload: () => { if (blob) URL.revokeObjectURL(blob); blob = null },
        }
    })
    let toc = paths.map(path => ({ label: path, href: entryURL(path) }))
    if (meta.format === 'chm') {
        const hhc = meta.entries.find(x => /\.hhc$/i.test(x.filename))
        if (hhc) {
            const doc = parse(await (await fetchOK(entryURL(hhc.filename))).text())
            const links = [...doc.querySelectorAll('object')].map(object => {
                const values = Object.fromEntries([...object.querySelectorAll('param')].map(p => [p.getAttribute('name')?.toLowerCase(), p.getAttribute('value')]))
                return { label: values.name, href: values.local && new URL(localHref(values.local), entryURL(hhc.filename)).href }
            }).filter(x => x.href)
            if (links.length) toc = links
        }
    }
    return { sections, toc, metadata: { title: meta.name }, resolveHref: resolve,
        isExternal: href => /^(https?:|mailto:)/i.test(href),
        splitTOCHref: href => { const u = new URL(href, entryURL(paths[0])); return [decodeURIComponent(u.pathname.replace(/^\/entry\//, '')), u.hash.slice(1)] },
        getTOCFragment: (doc, id) => doc.getElementById(id),
    }
}

const view = document.createElement('foliate-view')
document.body.append(view)
let searchID = 0, query = '', hits = [], selected = -1
window.leafCommand = async command => {
    try {
        switch (command.name) {
        case 'next': await view.next(); break
        case 'prev': await view.prev(); break
        case 'href': await view.goTo(command.text); break
        case 'fraction': await view.goToFraction(command.number); break
        case 'zoom': view.renderer.setStyles?.(`body{font-size:${17 * command.number}px!important;line-height:1.6}img,svg{max-width:100%}`); break
        case 'spread': view.renderer.setAttribute('max-column-count', String(command.number)); break
        case 'flow': view.renderer.setAttribute('flow', command.text); break
        case 'fit': view.renderer.setStyles?.('body{font-size:17px;line-height:1.6}img,svg{max-width:100%}'); break
        case 'find': {
            if (!command.text) break
            if (query === command.text && hits.length) { selected = (selected + 1) % hits.length; await view.select(hits[selected].cfi); break }
            const id = ++searchID; query = command.text; hits = []; selected = -1
            post('status', { message: 'Searching…' })
            for await (const result of view.search({ query })) {
                if (id !== searchID) return
                if (result.subitems) hits.push(...result.subitems)
                if (hits.length >= 200) { hits = hits.slice(0, 200); break }
            }
            post('status', { message: `${hits.length}${hits.length >= 200 ? '+' : ''} matches` })
            post('results', { items: hits.map(hit => ({ title: `${hit.excerpt?.pre ?? ''}${hit.excerpt?.match ?? ''}${hit.excerpt?.post ?? ''}`, target: hit.cfi, depth: 0 })) })
            if (hits.length) { selected = 0; await view.select(hits[0].cfi) }
            break
        }
        }
    } catch (error) { post('error', { message: error.message }) }
}
view.addEventListener('relocate', ({ detail }) => post('location', { cfi: detail.cfi, fraction: detail.fraction ?? 0 }))
view.addEventListener('external-link', event => { event.preventDefault(); post('external', { href: event.detail.href_ }) })
view.addEventListener('load', ({ detail: { doc } }) => doc.addEventListener('keydown', event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.target.closest('input,textarea,[contenteditable]')) return
    if (event.key === 'ArrowLeft') { event.preventDefault(); view.goLeft() }
    if (event.key === 'ArrowRight') { event.preventDefault(); view.goRight() }
}))
try {
    const meta = await (await fetchOK(`${base}/meta`)).json()
    let book
    if (meta.format === 'chm' || meta.format === 'html' || meta.format === 'markdown') book = await htmlBook(meta, meta.format === 'markdown')
    else if (meta.name.toLowerCase().endsWith('.epub')) {
        const { EPUB } = await import('./foliate/epub.js'), sizes = new Map(meta.entries.map(x => [x.filename, x.size]))
        book = await new EPUB({
            entries: meta.entries,
            loadText: async name => sizes.has(name) ? (await fetchOK(entryURL(name))).text() : null,
            loadBlob: async (name, type) => sizes.has(name) ? new Blob([await (await fetchOK(entryURL(name))).arrayBuffer()], { type }) : null,
            getSize: name => sizes.get(name) ?? 0,
            sha1: async text => new Uint8Array(await (await fetchOK(`${base}/sha1?text=${encodeURIComponent(text)}`)).arrayBuffer()),
        }).init()
    } else if (/\.(fb2|fb2z|fbz|zfb2|fb2\.zip)$/i.test(meta.name)) {
        const { makeFB2 } = await import('./foliate/fb2.js')
        const fb2 = meta.entries.find(x => /\.fb2$/i.test(x.filename))
        const file = await (await fetchOK(fb2 ? entryURL(fb2.filename) : `${base}/raw`)).blob()
        book = await makeFB2(file)
    } else {
        const { MOBI } = await import('./foliate/mobi.js'), { unzlibSync } = await import('./foliate/vendor/fflate.js')
        book = await new MOBI({ unzlib: unzlibSync }).open(new LocalSlice(meta.name, meta.size))
    }
    await view.open(book)
    view.renderer.setAttribute('max-column-count', String(window.leafSpread ?? 1))
    view.renderer.setAttribute('flow', window.leafFlow ?? 'paginated')
    view.renderer.setStyles?.('body{font-size:17px;line-height:1.6}img,svg{max-width:100%}')
    post('toc', { items: flatten(book.toc) })
    await view.init({ lastLocation: window.leafLocation || undefined })
} catch (error) { post('error', { message: error.message }) }
window.addEventListener('pagehide', () => { ++searchID; view.close() })
