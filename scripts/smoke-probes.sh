# shellcheck shell=bash
# Samba：sso=proxy（X-Wonton-Web-Key 密钥头；网页不认 Remote-User，用户名来自注入的 WONTON_OWNER_NAME）；SMB 账号按用户名建。清单没有 mcp。

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

marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
  if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/samba-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

# 数据：共享文件夹就是用户数据。走应用自己的 SMB 通道：容器里的 smbclient 以用户账号往 documents
# 共享放一个内容是标记的文件，重装/升级后同一通道读回核对。
_samba_c() { printf 'wonton-%s--%s--samba' "$SMOKE_INSTANCE" "${SMOKE_PLUGIN_ID//./-}"; }

data_write() {
  local c marker out
  c="$(_samba_c)"
  marker="wonton-smoke-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')"
  out="$(docker exec "$c" sh -c 'printf %s "$1" > /tmp/.smoke-up && smbclient --configfile=/etc/samba/smb.conf //127.0.0.1/documents -U "$2%$(cat /run/secrets/pass)" -m SMB3 -c "put /tmp/.smoke-up $3"; rm -f /tmp/.smoke-up' sh "$marker" "$SMOKE_OWNER" "$marker")" ||
    { echo "放不进 documents 共享：$out"; return 1; }
  printf '%s' "$marker" >"$(marker_file)"
}

data_check() {
  local c marker out
  marker="$(cat "$(marker_file)" 2>/dev/null)" || { echo "没有 data_write 留下的标记"; return 1; }
  [[ -n "$marker" ]] || { echo "标记是空的"; return 1; }
  c="$(_samba_c)"
  out="$(docker exec "$c" sh -c 'smbclient --configfile=/etc/samba/smb.conf //127.0.0.1/documents -U "$1%$(cat /run/secrets/pass)" -m SMB3 -c "get $2 /tmp/.smoke-down" && cat /tmp/.smoke-down; rm -f /tmp/.smoke-down' sh "$SMOKE_OWNER" "$marker")" ||
    { echo "共享里读不回 $marker（数据丢了？）：$out"; return 1; }
  [[ "$out" == "$marker" ]] || { echo "标记对不上：期待 $marker，看到 $out"; return 1; }
}
