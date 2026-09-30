// Foliate supplies CHM pagination, links, selection and search; Leaf supplies CHMLib bytes.
import './foliate/view.js'
const post = (type, data = {}) => window.webkit.messageHandlers.leaf.postMessage({ type, ...data })
const base = 'leaf://book'
const entryURL = name => `${base}/entry/${name.split('/').map(encodeURIComponent).join('/')}`
const fetchOK = async url => { const response = await fetch(url); if (!response.ok) throw Error(`Cannot read ${url}`); return response }
const parse = html => new DOMParser().parseFromString(html, 'text/html')
const flatten = (items = [], depth = 0) => items.flatMap(item => [
    { title: item.label || 'Untitled', target: String(item.href), depth }, ...flatten(item.subitems, depth + 1),
])
const htmlBook = async meta => {
    const paths = meta.entries.map(x => x.filename).filter(x => /\.x?html?$/i.test(x))
    const index = paths.findIndex(x => /(^|\/)(index|default|welcome)\.html?$/i.test(x))
    if (index > 0) paths.unshift(...paths.splice(index, 1))
    if (!paths.length) throw Error('This CHM contains no HTML pages')
    const contents = async path => (await fetchOK(entryURL(path))).text()
    const localHref = href => href.replace(/^(?:mk:@MSITStore:|ms-its:|its:).*?::\/?/i, '').replace(/\\/g, '/')
    const resolve = href => {
        const url = new URL(localHref(href), entryURL(paths[0]))
        const path = decodeURIComponent(url.pathname.replace(/^\/entry\//, ''))
        const index = paths.findIndex(p => p.toLowerCase() === path.toLowerCase())
        if (index < 0) return null
        const hash = decodeURIComponent(url.hash.slice(1))
        return { index, anchor: doc => hash ? doc.getElementById(hash) : 0 }
    }
    const sections = paths.map(path => {
        let blob
        const createDocument = async () => {
            const doc = parse(await contents(path)), tag = doc.createElement('base')
            tag.href = entryURL(path); doc.head.prepend(tag); return doc
        }
        return { id:path,size:1,createDocument,resolveHref:href=>new URL(localHref(href),entryURL(path)).href,
            load:async()=>{if(!blob)blob=URL.createObjectURL(new Blob([(await createDocument()).documentElement.outerHTML],{type:'text/html'}));return blob},
            unload:()=>{if(blob)URL.revokeObjectURL(blob);blob=null} }
    })
    let toc = paths.map(path => ({ label:path,href:entryURL(path) }))
    const hhc = meta.entries.find(x => /\.hhc$/i.test(x.filename))
    if (hhc) {
        const doc=parse(await (await fetchOK(entryURL(hhc.filename))).text())
        const links=[...doc.querySelectorAll('object')].map(object=>{const values=Object.fromEntries([...object.querySelectorAll('param')].map(p=>[p.getAttribute('name')?.toLowerCase(),p.getAttribute('value')]));return {label:values.name,href:values.local&&new URL(localHref(values.local),entryURL(hhc.filename)).href}}).filter(x=>x.href)
        if(links.length)toc=links
    }
    return {sections,toc,metadata:{title:meta.name},resolveHref:resolve,isExternal:href=>/^(https?:|mailto:)/i.test(href),
        splitTOCHref:href=>{const u=new URL(href,entryURL(paths[0]));return [decodeURIComponent(u.pathname.replace(/^\/entry\//,'')),u.hash.slice(1)]},
        getTOCFragment:(doc,id)=>doc.getElementById(id)}
}

const view = document.createElement('foliate-view')
document.body.append(view)
let searchID = 0, query = '', hits = [], selected = -1, zoom = 1
const scheme=matchMedia('(prefers-color-scheme:dark)')
const style = value => {
    const [family='system', size='17', line='1.6', margin='32', theme='system'] = String(value || '').split('|')
    const font = family === 'system' ? '-apple-system,BlinkMacSystemFont,sans-serif' : family
    const dark = theme === 'dark' || (theme === 'system' && scheme.matches)
    view.renderer?.setStyles?.(`:root{color-scheme:${dark?'dark':'light'}}body{font-family:${font}!important;font-size:${Number(size) * zoom}px!important;line-height:${line}!important;padding-inline:${margin}px!important;background:${dark?'#111':'#fff'}!important;color:${dark?'#ddd':'#111'}!important}a{color:${dark?'#8ab4f8':'#06c'}!important}img,svg{max-width:100%;height:auto}`)
}
scheme.addEventListener('change',()=>{if(String(window.leafStyle||'').split('|')[4]==='system')style(window.leafStyle)})
window.leafCommand = async command => {
    try {
        switch (command.name) {
        case 'next': await view.next(); break
        case 'prev': await view.prev(); break
        case 'href': await view.goTo(command.text); break
        case 'zoom': zoom = command.number; style(window.leafStyle); break
        case 'style': window.leafStyle = command.text; style(command.text); break
        case 'toc': ++searchID; query = ''; hits = []; selected = -1; view.clearSearch(); post('toc', { items: flatten(view.book.toc) }); break
        case 'find': {
            if (!command.text) break
            if (query === command.text && hits.length) { selected = (selected + 1) % hits.length; await view.select(hits[selected].cfi); break }
            const id = ++searchID; query = command.text; hits = []; selected = -1
            post('status', { message: 'Searching…' })
            for await (const result of view.search({ query })) {
                if (id !== searchID) { if (!query) view.clearSearch(); return }
                if (result.subitems) hits.push(...result.subitems)
                if (hits.length >= 200) { hits = hits.slice(0, 200); break }
            }
            if (id !== searchID) return
            post('status', { message: `${hits.length}${hits.length >= 200 ? '+' : ''} matches` })
            post('results', { items: hits.map(hit => ({ title: `${hit.excerpt?.pre ?? ''}${hit.excerpt?.match ?? ''}${hit.excerpt?.post ?? ''}`, target: hit.cfi, depth: 0 })) })
            if (hits.length) { selected = 0; await view.select(hits[0].cfi) }
            break
        }
        }
    } catch (error) { post('error', { message: error.message }) }
}
view.addEventListener('external-link', event => { event.preventDefault(); post('external', { href: event.detail.href_ }) })
view.addEventListener('load', ({ detail: { doc } }) => doc.addEventListener('keydown', event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.target.closest('input,textarea,[contenteditable]')) return
    if (event.key === 'ArrowLeft') { event.preventDefault(); view.goLeft() }
    if (event.key === 'ArrowRight') { event.preventDefault(); view.goRight() }
}))
try {
    const meta = await (await fetchOK(`${base}/meta`)).json()
    if (meta.format !== 'chm') throw Error('WebKit reader only supports CHM')
    const book = await htmlBook(meta)
    await view.open(book)
    style(window.leafStyle)
    post('toc', { items: flatten(book.toc) })
    await view.init({})
    post('ready')
} catch (error) { post('error', { message: error.message }) }
window.addEventListener('pagehide', () => { ++searchID; view.close() })
