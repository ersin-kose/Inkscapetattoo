import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PinterestBrowserPage extends StatefulWidget {
  final String initialUrl;

  const PinterestBrowserPage({
    super.key,
    this.initialUrl = 'https://www.pinterest.com/search/pins/?q=tattoo%20isolated%20background',
  });

  @override
  State<PinterestBrowserPage> createState() => _PinterestBrowserPageState();
}

class _PinterestBrowserPageState extends State<PinterestBrowserPage> {
  late final WebViewController _controller;
  String _currentUrl = '';
  bool _loading = true;

  bool get _isPinUrl {
    final u = _currentUrl.toLowerCase();
    return u.contains('/pin/') && !u.contains('/create');
  }

  Future<String?> _extractBestImageUrlViaJs() async {
    try {
      final js = r"""
        (function(){
          function abs(u){ try { return u ? new URL(u, location.href).toString() : ''; } catch(e){ return u||''; } }
          function getMeta(){
            const sels=['meta[property="og:image"]','meta[name="og:image"]','meta[property="twitter:image"]','meta[name="twitter:image"]'];
            for (const s of sels){ const m=document.querySelector(s); if (m){ const c=m.getAttribute('content')||''; if (c) return abs(c);} }
            return '';
          }
          function fromSrcSet(ss){
            if (!ss) return '';
            try {
              const parts = ss.split(',').map(s=>s.trim()).filter(Boolean);
              const last = parts[parts.length-1]||'';
              const url = last.split(' ')[0];
              return abs(url);
            } catch(e){ return ''; }
          }
          function collectImgs(){
            const out=[];
            const imgs = Array.from(document.images||[]);
            for (const i of imgs){
              const srcs=[];
              if (i.currentSrc) srcs.push(i.currentSrc);
              if (i.src) srcs.push(i.src);
              if (i.srcset) srcs.push(fromSrcSet(i.srcset));
              const u = srcs.find(Boolean);
              if (!u) continue;
              const w = i.naturalWidth || i.width || 0;
              const h = i.naturalHeight || i.height || 0;
              out.push({u: abs(u), w, h});
            }
            const nodes = Array.from(document.querySelectorAll('[style*="background-image"], [data-test-id*="image"]'));
            for (const n of nodes){
              const style = getComputedStyle(n);
              const bg = (style && style.backgroundImage) || (n.style && n.style.backgroundImage) || '';
              const m = bg.match(/url\((['\"]?)(.*?)\1\)/i);
              if (m && m[2]){
                const w = n.clientWidth||0, h = n.clientHeight||0;
                out.push({u: abs(m[2]), w, h});
              }
            }
            return out;
          }
          function score(c){
            const u = (c.u||'').toLowerCase();
            let s = 0;
            if (u.includes('i.pinimg.com')) s += 5;
            if (u.includes('/originals/')) s += 6;
            if (u.includes('/736x/')) s += 5;
            if (u.includes('/474x/')) s += 4;
            if (u.includes('/236x/')) s += 3;
            if (u.match(/\.(png|jpe?g)(\?|$)/)) s += 2;
            if (u.includes('s.pinimg.com') || u.includes('/rs/')) s -= 4;
            const area = (c.w||0)*(c.h||0);
            if (area > 0) s += Math.min(10, Math.floor(area/50000));
            if ((c.w||0) < 100 || (c.h||0) < 100) s -= 3;
            return s;
          }
          function pick(){
            const set = new Map();
            const m = getMeta();
            if (m) set.set(m, {u:m,w:0,h:0});
            for (const c of collectImgs()){
              if (!set.has(c.u)) set.set(c.u, c);
            }
            const arr = Array.from(set.values());
            arr.sort((a,b)=>score(b)-score(a));
            return arr.length ? arr[0].u : '';
          }
          return pick();
        })();
      """;
      final raw = await _controller.runJavaScriptReturningResult(js);
      var s = raw?.toString() ?? '';
      // webview_flutter returns quoted JSON string sometimes
      if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
        s = s.substring(1, s.length - 1);
      }
      s = s.replaceAll('\\n', '').trim();
      if (s.isEmpty) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onPickPressed() async {
    // First, try to get direct image URL via JS from the page
    final imgUrl = await _extractBestImageUrlViaJs();
    if (imgUrl != null && imgUrl.isNotEmpty) {
      if (!mounted) return;
      Navigator.of(context).pop(imgUrl);
      return;
    }

    // Fallback to current URL if it looks like a pin page
    if (_isPinUrl && _currentUrl.isNotEmpty) {
      if (!mounted) return;
      Navigator.of(context).pop(_currentUrl);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu sayfadan görsel alınamadı. Pin detayına girip tekrar deneyin.')),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _loading = true;
              _currentUrl = url;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _loading = false;
              _currentUrl = url;
            });
          },
          onNavigationRequest: (request) {
            // Allow https/http inside webview; block custom schemes to avoid crashes
            final scheme = Uri.tryParse(request.url)?.scheme.toLowerCase();
            if (scheme == 'http' || scheme == 'https') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web’den içe aktar'),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 12,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _onPickPressed,
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 20, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                'try tattoo',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
