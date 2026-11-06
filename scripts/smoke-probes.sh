# Samba：sso=proxy（X-Wonton-Web-Key 密钥头；网页不认 Remote-User，用户名来自注入的 WONTON_OWNER_NAME）；SMB 账号按用户名建。清单没有 mcp。
SSO=proxy
MCP=0

web_assert() { grep -qi 'smb'; }   # 标准输入：连接信息页

identity_check() { # 页面以用户身份列出连接信息；再用容器里的 smbclient 以用户账号真登录一次
  local page out c
  page="$(dweb /)" || { echo "页面失败：$page"; return 1; }
  grep -qF "你好，$SMOKE_OWNER" <<<"$page" || grep -qF "$SMOKE_OWNER" <<<"$page" ||
    { echo "页面没显示用户 $SMOKE_OWNER"; return 1; }
  c="wonton-$SMOKE_INSTANCE--${SMOKE_PLUGIN_ID//./-}--samba"
  out="$(docker exec "$c" sh -c 'smbclient --configfile=/etc/samba/smb.conf -L //127.0.0.1 -U "'"$SMOKE_OWNER"'%$(cat /run/secrets/pass)" -m SMB3' 2>&1)" ||
    { echo "smbclient 登录失败：$out"; return 1; }
  grep -q 'transfers' <<<"$out" || { echo "共享列表没有 transfers：$out"; return 1; }
}
