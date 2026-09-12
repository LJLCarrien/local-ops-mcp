@{
    # Copy this file to local-ops.psd1 and replace the example values.
    # local-ops.psd1 is ignored by Git.
    WorkspaceRoot = 'D:\Projects\MyProject'
    TunnelId     = 'tunnel_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
    ProxyUrl     = 'http://127.0.0.1:<PROXY_PORT>'
    Profile      = 'local-ops'
    # Local health/admin listener. Use port 0 to let Windows allocate a free port.
    HealthListenAddr = '127.0.0.1:0'
    # Optional. Leave empty to auto-detect Node.js from PATH or Codex.
    NodePath     = ''
    # Git capability switches. Remote child switches only apply when GitRemote is $true.
    GitRead      = $true
    GitWrite     = $true
    GitRemote    = $false
    GitFetch     = $true
    GitPull      = $false
    GitPush      = $false
}
