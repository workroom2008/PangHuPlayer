import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// TV 端配对服务器配置数据
class PairingServerConfig {
  final String name;
  final String url;
  final String username;
  final String password;
  final String? serverType;

  const PairingServerConfig({
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.serverType,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'serverType': serverType,
      };

  factory PairingServerConfig.fromJson(Map<String, dynamic> json) =>
      PairingServerConfig(
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        serverType: json['serverType']?.toString(),
      );
}

/// TV 端配对 HTTP 服务器
///
/// 在 TV 端启动一个轻量 HTTP 服务，监听局域网请求：
/// - GET /         返回 HTML 配置表单
/// - GET /ping     健康检查（手机端可探测是否在线）
/// - POST /api/server 接收手机提交的服务器配置
///
/// 手机扫码后用浏览器打开 http://<TV_IP>:8848/，
/// 在表单中填写服务器信息并提交，TV 端自动收到并保存。
class TvPairingServer {
  static const int defaultPort = 8848;

  HttpServer? _server;
  final StreamController<PairingServerConfig> _configController =
      StreamController<PairingServerConfig>.broadcast();

  /// 收到手机提交的配置时推送
  Stream<PairingServerConfig> get onConfigReceived => _configController.stream;

  /// 当前 TV 端在局域网中的 URL（http://<ip>:<port>/）
  String? _pairingUrl;
  String? get pairingUrl => _pairingUrl;

  /// 启动配对服务器
  /// 返回访问 URL（http://<ip>:<port>/），失败返回 null
  Future<String?> start({int port = defaultPort}) async {
    if (_server != null) return _pairingUrl;

    String? ip;
    try {
      ip = await NetworkInfo().getWifiIP();
    } catch (_) {
      ip = null;
    }

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      // 端口被占用等情况
      return null;
    }
    _server = server;

    _pairingUrl = ip != null ? 'http://$ip:$port/' : null;

    // 后台处理请求
    _handleRequest(server);

    return _pairingUrl;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _pairingUrl = null;
  }

  void dispose() {
    stop();
    _configController.close();
  }

  Future<void> _handleRequest(HttpServer server) async {
    await for (final request in server) {
      try {
        final path = request.uri.path;
        if (request.method == 'GET' && (path == '/' || path.isEmpty)) {
          await _serveForm(request);
        } else if (request.method == 'GET' && path == '/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write('{"ok":true}')
            ..close();
        } else if (request.method == 'POST' && path == '/api/server') {
          await _handleConfigSubmit(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found')
            ..close();
        }
      } catch (e) {
        try {
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..write('Error: $e')
            ..close();
        } catch (_) {}
      }
    }
  }

  /// 返回 HTML 配置表单
  Future<void> _serveForm(HttpRequest request) async {
    final html = _buildHtmlForm();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(html)
      ..close();
  }

  /// 处理手机提交的配置
  Future<void> _handleConfigSubmit(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final config = PairingServerConfig.fromJson(json);
      _configController.add(config);

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write('{"ok":true,"message":"配置已发送到 TV 端"}')
        ..close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write('{"ok":false,"message":"$e"}')
        ..close();
    }
  }

  String _buildHtmlForm() {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>LAN Player - 添加服务器</title>
<style>
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Microsoft YaHei', sans-serif;
    background: linear-gradient(135deg, #0a0a0a 0%, #1e1e3a 100%);
    color: #fff;
    margin: 0;
    padding: 24px 16px;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .container {
    width: 100%;
    max-width: 480px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 16px;
    padding: 32px 24px;
    backdrop-filter: blur(20px);
  }
  h1 {
    margin: 0 0 8px 0;
    font-size: 22px;
    font-weight: 700;
  }
  .subtitle {
    color: rgba(255, 255, 255, 0.6);
    font-size: 14px;
    margin-bottom: 24px;
  }
  .field {
    margin-bottom: 16px;
  }
  label {
    display: block;
    font-size: 13px;
    color: rgba(255, 255, 255, 0.7);
    margin-bottom: 6px;
    font-weight: 500;
  }
  input {
    width: 100%;
    padding: 12px 14px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 10px;
    color: #fff;
    font-size: 16px;
    transition: border-color 0.2s;
  }
  input:focus {
    outline: none;
    border-color: #6366f1;
  }
  input::placeholder { color: rgba(255, 255, 255, 0.3); }
  button {
    width: 100%;
    padding: 14px;
    background: #6366f1;
    color: #fff;
    border: none;
    border-radius: 10px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    margin-top: 8px;
    transition: background 0.2s;
  }
  button:hover { background: #5457e5; }
  button:disabled { background: #4a4d9c; cursor: not-allowed; }
  .status {
    margin-top: 16px;
    padding: 12px;
    border-radius: 8px;
    font-size: 14px;
    text-align: center;
    display: none;
  }
  .status.success { background: rgba(16, 185, 129, 0.15); color: #10b981; display: block; }
  .status.error { background: rgba(239, 68, 68, 0.15); color: #ef4444; display: block; }
  select {
    width: 100%;
    padding: 12px 14px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 10px;
    color: #fff;
    font-size: 16px;
    cursor: pointer;
    transition: border-color 0.2s;
  }
  select:focus {
    outline: none;
    border-color: #6366f1;
  }
  select option {
    background: #1e1e3a;
    color: #fff;
  }
</style>
</head>
<body>
  <div class="container">
    <h1>添加媒体服务器</h1>
    <div class="subtitle">填写服务器信息后点击提交，配置将自动发送到 TV 端</div>

    <div class="field">
      <label>服务器类型</label>
      <select id="serverType">
        <option value="emby">Emby</option>
        <option value="jellyfin">Jellyfin</option>
        <option value="fnos">飞牛影视</option>
      </select>
    </div>
    <div class="field">
      <label>服务器名称</label>
      <input id="name" type="text" placeholder="例如：我的媒体库">
    </div>
    <div class="field">
      <label>服务器地址</label>
      <input id="url" type="text" placeholder="http://192.168.1.1:8096">
    </div>
    <div class="field">
      <label>用户名</label>
      <input id="username" type="text" placeholder="用户名">
    </div>
    <div class="field">
      <label>密码</label>
      <input id="password" type="password" placeholder="密码">
    </div>

    <button id="submit" onclick="submitForm()">提交到 TV</button>
    <div id="status" class="status"></div>
  </div>

<script>
async function submitForm() {
  const data = {
    name: document.getElementById('name').value.trim(),
    url: document.getElementById('url').value.trim(),
    username: document.getElementById('username').value.trim(),
    password: document.getElementById('password').value,
    serverType: document.getElementById('serverType').value,
  };

  if (!data.url) {
    showStatus('请填写服务器地址', 'error');
    return;
  }

  const btn = document.getElementById('submit');
  btn.disabled = true;
  btn.textContent = '发送中...';

  try {
    const resp = await fetch('/api/server', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(data),
    });
    const result = await resp.json();
    if (result.ok) {
      showStatus(result.message || '配置已发送', 'success');
      setTimeout(() => { btn.textContent = '已提交'; }, 0);
    } else {
      showStatus(result.message || '提交失败', 'error');
      btn.disabled = false;
      btn.textContent = '提交到 TV';
    }
  } catch (e) {
    showStatus('网络错误：' + e.message, 'error');
    btn.disabled = false;
    btn.textContent = '提交到 TV';
  }
}

function showStatus(msg, type) {
  const s = document.getElementById('status');
  s.textContent = msg;
  s.className = 'status ' + type;
}
</script>
</body>
</html>''';
  }
}
