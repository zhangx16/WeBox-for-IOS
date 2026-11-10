(function () {
  'use strict';
  const DEFAULT_SITE = 'https://www.cilixiong.cc';
  const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  const clean = (v, max) => String(v || '').replace(/\s+/g, ' ').trim().slice(0, max || 1024);
  const origin = ctx => ctx.url.origin(ctx.settings.site || DEFAULT_SITE);

  function local(ctx, relative, base) {
    try {
      const u = ctx.url.resolve(String(relative || '').trim(), base || origin(ctx) + '/');
      return ctx.url.origin(u) === origin(ctx) ? u.split('#')[0] : '';
    } catch (_) { return ''; }
  }
  function remote(ctx, relative, base) {
    try {
      if (!relative || /^(?:data|javascript|magnet|thunder):/i.test(relative)) return '';
      const u = ctx.url.resolve(String(relative).trim(), base);
      return /^https?:\/\//i.test(u) ? u : '';
    } catch (_) { return ''; }
  }
  function headers(ctx) {
    const h = { 'User-Agent': UA, Accept: 'text/html,application/xhtml+xml,*/*;q=0.8', Referer: origin(ctx) + '/' };
    const cookie = String(ctx.settings.cookie || '').trim();
    if (/[\r\n]/.test(cookie)) ctx.fail('CONFIG_REQUIRED', '网站 Cookie 不能包含换行', { fields: ['cookie'] });
    if (cookie) h.Cookie = cookie;
    return h;
  }
  async function html(ctx, address, text) {
    ctx.signal.throwIfAborted();
    const u = local(ctx, address);
    if (!u) ctx.fail('INVALID_RESPONSE', '站点链接不在配置的域名内');
    const opts = { responseType: 'text', timeoutMs: 18000, headers: headers(ctx) };
    if (text !== undefined) { opts.text = text; opts.headers['Content-Type'] = 'application/x-www-form-urlencoded'; }
    let r;
    try { r = text === undefined ? await ctx.http.get(u, opts) : await ctx.http.post(u, opts); }
    catch (e) {
      ctx.signal.throwIfAborted();
      if (/WBX_ERROR:/.test(String(e && e.message))) throw e;
      ctx.fail('NETWORK', '磁力熊请求失败，请检查网络后重试');
    }
    ctx.signal.throwIfAborted();
    if (r.status === 429) ctx.fail('RATE_LIMITED', '网站请求过于频繁，请稍后重试');
    if (r.status === 401 || r.status === 403) ctx.fail('AUTH_REQUIRED', '网站要求验证或当前会话无访问权限');
    if (r.status === 404 || r.status === 410) ctx.fail('NOT_FOUND', '页面不存在或已下架');
    if (r.status < 200 || r.status >= 300) ctx.fail('NETWORK', '网站返回错误状态，请稍后重试');
    const finalUrl = local(ctx, r.url || u);
    if (!finalUrl) ctx.fail('INVALID_RESPONSE', '网站跳转到了其他域名，请核对服务地址');
    if (typeof r.data !== 'string' || !r.data.trim()) ctx.fail('INVALID_RESPONSE', '网站返回了空页面');
    if (/<title[^>]*>\s*(?:Just a moment|Attention Required)/i.test(r.data)) ctx.fail('AUTH_REQUIRED', '网站要求浏览器验证');
    return { url: finalUrl, body: r.data };
  }
  // HTML 只加载一次，避免对每个选择器重复解析。
  async function document(ctx, address, text) {
    const r = await html(ctx, address, text);
    return { $: ctx.html.load(r.body), url: r.url, body: r.body };
  }
  function content(ctx, id) {
    const m = /^(movie|drama):([1-9]\d{0,11})$/.exec(String(id || ''));
    if (!m) ctx.fail('NOT_FOUND', '内容标识无效，请重新打开目录');
    return { type: m[1], number: m[2], path: '/' + m[1] + '/' + m[2] + '.html' };
  }
  function itemIdentity(ctx, href, base) {
    const u = local(ctx, href, base);
    if (!u) return null;
    const m = /^\/(movie|drama)\/([1-9]\d{0,11})\.html$/.exec(u.slice(origin(ctx).length).split('?')[0]);
    return m ? { id: m[1] + ':' + m[2], kind: m[1] === 'movie' ? 'movie' : 'series' } : null;
  }
  function image(ctx, node, base, $) {
    const img = node.find('img').first();
    let src = img.attr('data-src') || img.attr('data-original') || img.attr('src') || '';
    if (!src || /^data:/i.test(src)) {
      const styled = node.find('[style]').addBack('[style]').filter((i, e) => /background-image/i.test(String($(e).attr('style') || ''))).first();
      const style = styled.attr('style') || '';
      const m = /background-image\s*:\s*url\(\s*(['"]?)(.*?)\1\s*\)/i.exec(style);
      src = m ? m[2] : '';
    }
    return remote(ctx, src, base);
  }
  function items(ctx, d) {
    const out = [], seen = new Set(), $ = d.$;
    $('a[href]').each((i, e) => {
      ctx.signal.throwIfAborted();
      const a = $(e), identity = itemIdentity(ctx, a.attr('href'), d.url);
      if (!identity || seen.has(identity.id)) return;
      const title = clean(a.find('h2,h3').first().text() || a.attr('title') || a.text(), 240);
      if (!title) return;
      const item = Object.assign({ title }, identity);
      const poster = image(ctx, a, d.url, $);
      if (poster) item.poster = poster;
      const subtitle = clean(a.find('li.small,.card-subtitle').text());
      if (subtitle) item.subtitle = subtitle;
      const score = Number(clean(a.find('.rank').first().text()));
      if (score > 0 && score <= 10) item.rating = { value: score, scale: 10, label: '评分' };
      seen.add(identity.id); out.push(item);
    });
    if (out.length > 1000) ctx.fail('INVALID_RESPONSE', '网站单页条目过多');
    return out;
  }
  function allowedPath(path, category, search) {
    if (search) return /^\/e\/search\/(?:result\/(?:index\.php)?|result\.php)(?:\?[^#]*)?$/.test(path);
    if (category === 'home') return path === '/';
    return new RegExp('^/' + category + '/(?:index(?:_[1-9]\\d*)?\\.html)?$').test(path);
  }
  function scope(category, query) { return category + '\n' + (query || ''); }
  function firstOrCursor(ctx, req, category, query) {
    if (req.cursor == null) return { url: origin(ctx) + (category === 'home' ? '/' : '/' + category + '/'), step: 1 };
    let c;
    try { c = JSON.parse(req.cursor); } catch (_) { ctx.fail('INVALID_RESPONSE', '分页状态无效，请刷新列表'); }
    if (!c || c.v !== 1 || c.site !== origin(ctx) || c.scope !== scope(category, query) || !Number.isInteger(c.step) || c.step < 2 || c.step > 100000 || typeof c.path !== 'string' || !allowedPath(c.path, category, !!query)) ctx.fail('INVALID_RESPONSE', '分页状态与当前栏目不符，请刷新列表');
    const url = local(ctx, c.path);
    if (!url) ctx.fail('INVALID_RESPONSE', '分页链接无效');
    return { url, step: c.step };
  }
  function nextCursor(ctx, d, category, query, step) {
    let next = '';
    d.$('a[href]').each((i, e) => {
      if (next) return;
      const a = d.$(e), label = clean(a.attr('title') || a.text(), 80);
      if (a.attr('rel') !== 'next' && !/^(?:下一页|下一頁|下页|下頁|next)$/i.test(label)) return;
      const u = local(ctx, a.attr('href'), d.url);
      if (!u || u === d.url) return;
      const path = u.slice(origin(ctx).length);
      if (allowedPath(path, category, !!query)) next = path;
    });
    if (!next) return null;
    const c = JSON.stringify({ v: 1, site: origin(ctx), scope: scope(category, query), path: next, step: step + 1 });
    if (c.length > 2048) ctx.fail('INVALID_RESPONSE', '分页链接过长，请缩短搜索词');
    return c;
  }
  function page(ctx, d, category, query, step) {
    const result = items(ctx, d);
    if (!result.length && !/没有搜索到相关的内容|沒有搜尋到相關|暂无数据|暂无内容|暫無內容/.test(d.$('body').text())) ctx.fail('INVALID_RESPONSE', '未找到目录节点，网站结构可能已变化');
    return { items: result, nextCursor: nextCursor(ctx, d, category, query, step) };
  }
  function media(ctx, value, base) {
    const u = remote(ctx, value, base);
    if (!u) return null;
    const path = u.split(/[?#]/)[0];
    if (/\.m3u8$/i.test(path)) return { url: u, mime: 'application/vnd.apple.mpegurl' };
    if (/\.mp4$/i.test(path)) return { url: u, mime: 'video/mp4' };
    if (/\.mpd$/i.test(path)) return { url: u, mime: 'application/dash+xml' };
    return null;
  }
  function quoted(raw) {
    // 只读取字符串字面量，不 eval 站点代码。
    const q = raw[0], v = raw.slice(1, -1);
    if (q === '"') { try { return JSON.parse(raw); } catch (_) { return ''; } }
    return v.replace(/\\u([\da-f]{4})|\\x([\da-f]{2})|\\([\\/'"])/gi, (m, u, x, c) => u || x ? String.fromCharCode(parseInt(u || x, 16)) : c);
  }
  function parseMedia(ctx, d) {
    const out = [], seen = new Set();
    function add(value) { const m = media(ctx, value, d.url); if (m && !seen.has(m.url)) { seen.add(m.url); out.push(m); } }
    d.$('video[src],video source[src]').each((i, e) => add(d.$(e).attr('src')));
    d.$('script:not([src])').each((i, e) => {
      const code = d.$(e).html() || '';
      const re = /\b(?:var|let|const)\s+vurl\s*=\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g;
      let m; while ((m = re.exec(code))) { ctx.signal.throwIfAborted(); add(quoted(m[1])); }
    });
    return out;
  }
  async function entries(ctx, d) {
    const out = [], frames = [], seen = new Set();
    const direct = parseMedia(ctx, d);
    if (direct.length) { out.push({ id: 'inline', name: '网页线路', url: d.url, resources: direct }); seen.add('inline'); }
    d.$('iframe[src]').each((i, e) => {
      const u = local(ctx, d.$(e).attr('src'), d.url);
      if (!u) return;
      const m = /^\/e\/extend\/jx\.php\?id=([1-9]\d{0,11})$/.exec(u.slice(origin(ctx).length));
      if (m && !seen.has('web-' + m[1])) { seen.add('web-' + m[1]); frames.push({ id: 'web-' + m[1], name: '网页线路', url: u }); }
    });
    if (frames.length > 8) ctx.fail('INVALID_RESPONSE', '网页播放入口过多');
    for (const f of frames) {
      ctx.signal.throwIfAborted();
      const fd = await document(ctx, f.url), resources = parseMedia(ctx, fd);
      if (!resources.length) ctx.fail('UNSUPPORTED', '网页播放入口未提供可直接解析的标准媒体');
      out.push(Object.assign(f, { resources }));
    }
    return out;
  }
  function preview(d) {
    return /剧集\s*仅提供\s*第(?:一|1)集\s*在线播放预览|劇集\s*僅提供\s*第(?:一|1)集\s*在線播放預覽/.test(d.$('body').text());
  }
  function groups(kind, rows, isPreview) {
    return rows.map((row, index) => ({ id: row.id, name: rows.length > 1 ? '网页线路 ' + (index + 1) : row.name, episodes: [{ id: 'web', name: isPreview ? '第1集（预览）' : kind === 'movie' ? '正片' : '网页播放' }] }));
  }
  WeBox.define({
    api: '1.1', id: 'dev.webox.native.cilixiong', name: '磁力熊', version: '1.0.1', requires: ['html'],
    settings: { fields: [
      { key: 'site', label: '网站地址', type: 'url', default: DEFAULT_SITE, required: true },
      { key: 'cookie', label: '网站 Cookie（可选）', type: 'secret', maxLength: 8192, help: '只用于当前网站，不发送给媒体 CDN；没有验证要求时留空。' }
    ] },
    cache: { list: 120, detail: 60, filters: 3600 },
    async filters() { return [{ key: 'category', label: '栏目', type: 'select', default: 'home', options: [{ label: '首页', value: 'home' }, { label: '电影', value: 'movie' }, { label: '剧集', value: 'drama' }] }]; },
    async list(ctx, req) {
      const category = req.filters && req.filters.category || 'home';
      if (!['home', 'movie', 'drama'].includes(category)) ctx.fail('INVALID_RESPONSE', '栏目无效');
      const c = firstOrCursor(ctx, req, category, '');
      return page(ctx, await document(ctx, c.url), category, '', c.step);
    },
    async search(ctx, req) {
      const query = String(req.query || '').trim();
      if (!query) return { items: [], nextCursor: null };
      if (query.length > 200) ctx.fail('INVALID_RESPONSE', '搜索词过长');
      const c = firstOrCursor(ctx, req, 'search', query);
      let d;
      if (req.cursor == null) {
        const text = 'classid=1%2C2&show=title&tempid=1&keyboard=' + encodeURIComponent(query);
        d = await document(ctx, origin(ctx) + '/e/search/index.php', text);
      } else d = await document(ctx, c.url);
      return page(ctx, d, 'search', query, c.step);
    },
    async detail(ctx, req) {
      const id = content(ctx, req.id), d = await document(ctx, origin(ctx) + id.path);
      const kind = id.type === 'movie' ? 'movie' : 'series';
      const result = { id: req.id, kind, groups: groups(kind, await entries(ctx, d), preview(d)) };
      const title = clean(d.$('h1').first().text() || d.$('meta[property="og:title"]').attr('content'), 240);
      if (title) result.title = title;
      const poster = remote(ctx, d.$('meta[property="og:image"]').attr('content'), d.url);
      if (poster) result.poster = poster;
      const summary = clean(d.$('meta[property="og:description"]').attr('content') || d.$('meta[name="description"]').attr('content'), 65536);
      const note = preview(d) ? '网站明确说明剧集仅提供第一集在线播放预览。完整剧集为磁力资源，本脚本不把磁力链接转换成视频，也不补造后续选集。' : !result.groups.length ? '本站当前页面未提供可解析的在线播放入口；磁力和网盘链接不作为媒体线路。' : kind === 'series' ? '仅列出网页实际提供的播放入口，不根据剧集简介补造选集。' : '';
      if (summary || note) result.summary = (summary + (summary && note ? '\n\n' : '') + note).slice(0, 65536);
      return result;
    },
    async play(ctx, req) {
      const id = content(ctx, req.contentId);
      if (req.episodeId !== 'web') ctx.fail('NOT_FOUND', '选集标识无效');
      // 每次重新取详情与播放器，refresh/download 均不复用旧媒体地址。
      const d = await document(ctx, origin(ctx) + id.path);
      const isPreview = preview(d);
      if (isPreview && req.purpose === 'download') ctx.fail('UNSUPPORTED', '本站剧集仅提供第一集预览，不支持完整剧集下载');
      const rows = await entries(ctx, d);
      const row = rows.find(x => x.id === req.groupId);
      if (!row) ctx.fail('NOT_FOUND', '播放入口已变化，请重新打开详情');
      return { sources: row.resources.map((r, i) => ({ id: row.id + '-' + (i + 1), name: isPreview ? '第1集（预览）' : row.resources.length > 1 ? '网页线路 ' + (i + 1) : '网页线路', url: r.url, mime: r.mime, headers: { 'User-Agent': UA, Referer: row.url }, downloadable: !isPreview })) };
    }
  });
})();
