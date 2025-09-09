import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sync Browsers',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SyncBrowsersPage(),
    );
  }
}

class SyncBrowsersPage extends StatefulWidget {
  const SyncBrowsersPage({super.key});

  @override
  State<SyncBrowsersPage> createState() => _SyncBrowsersPageState();
}

class _SyncBrowsersPageState extends State<SyncBrowsersPage> {
  final List<WebViewController?> _controllers =
      List<WebViewController?>.filled(6, null);

  bool _syncEnabled = false;

  final String _injectJs = '''
(function(){
  if (window._flutterSyncInjected) return;
  window._flutterSyncInjected = true;

  function sendEvent(type, detail){
    if (window.SyncChannel && window.SyncChannel.postMessage) {
      window.SyncChannel.postMessage(JSON.stringify({type:type, detail:detail}));
    }
  }

  document.addEventListener('click', function(e){
    var path = [];
    var el = e.target;
    while(el && el.tagName){
      var info = {tag: el.tagName.toLowerCase(), id: el.id || null};
      path.push(info);
      el = el.parentElement;
    }
    sendEvent('click', {x: e.clientX, y: e.clientY, path: path});
  }, true);

  function watchInputs(){
    var inputs = document.querySelectorAll('input, textarea');
    inputs.forEach(function(inp){
      if (inp._flutterSyncListening) return;
      inp._flutterSyncListening = true;
      inp.addEventListener('input', function(e){
        sendEvent('input', {value: e.target.value, id: e.target.id || null});
      });
    });
  }

  var mo = new MutationObserver(function(){ watchInputs(); });
  mo.observe(document.documentElement || document.body, {childList:true, subtree:true});
  watchInputs();
})();
''';

  void _handleMasterEvent(String msg) async {
    if (!_syncEnabled) return;
    final data = jsonDecode(msg);
    final type = data['type'];
    final detail = Map<String, dynamic>.from(data['detail']);

    String js = "";
    if (type == "input") {
      final value = jsonEncode(detail['value'] ?? '');
      final id = detail['id'] != null ? jsonEncode(detail['id']) : null;
      if (id != null) {
        js =
            "(function(){var el=document.getElementById($id); if(el){el.value=$value; el.dispatchEvent(new Event('input',{bubbles:true}));}})();";
      }
    } else if (type == "click") {
      final path = List.from(detail['path'] ?? []);
      String? targetId;
      for (var p in path) {
        if (p is Map && p['id'] != null) {
          targetId = p['id'];
          break;
        }
      }
      if (targetId != null) {
        final id = jsonEncode(targetId);
        js =
            "(function(){var el=document.getElementById($id); if(el){el.click();}})();";
      }
    }

    for (int i = 1; i < _controllers.length; i++) {
      final c = _controllers[i];
      if (c != null && js.isNotEmpty) {
        try {
          await c.runJavascript(js);
        } catch (_) {}
      }
    }
  }

  Widget _buildWebView(int index) {
    return Container(
      width: 400,
      height: 500,
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(6),
      ),
      child: WebView(
        initialUrl: "https://www.google.com",
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (controller) {
          _controllers[index] = controller;
        },
        javascriptChannels: {
          JavascriptChannel(
            name: 'SyncChannel',
            onMessageReceived: (msg) {
              if (index == 0) {
                _handleMasterEvent(msg.message);
              }
            },
          )
        },
        onPageFinished: (_) {
          _controllers[index]?.runJavascript(_injectJs);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("6 متصفحات - المزامنة"),
        actions: [
          Row(
            children: [
              const Text("مزامنة"),
              Switch(
                value: _syncEnabled,
                onChanged: (v) {
                  setState(() {
                    _syncEnabled = v;
                  });
                },
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Wrap(
            children: List.generate(6, (i) => _buildWebView(i)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          for (final c in _controllers) {
            c?.reload();
          }
        },
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
