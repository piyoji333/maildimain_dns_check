#!/bin/bash

# メールドメインを入力
read -p "チェックするメールドメインを入力してください: " domain

if [ -z "$domain" ]; then
  echo "ドメインが入力されていません。終了します。"
  exit 1
fi

# 一時ファイルを作成
spf_temp_file=$(mktemp)
trap "rm -f $spf_temp_file" EXIT

# SPFレコードのlookup数を再帰的に計算する関数
calculate_spf_lookups() {
  local record=$1
  local count=0
  local includes=$(echo "$record" | grep -oE "include:[^ ]+")

  for include in $includes; do
    local included_domain=$(echo $include | cut -d: -f2)
    local included_record=$(dig +short TXT $included_domain | grep -i "v=spf1")
    if [ -n "$included_record" ]; then
      local sub_count=$(calculate_spf_lookups "$included_record")
      count=$((count + sub_count))
    fi
    count=$((count + 1))
  done

  echo $count
}

# SPFチェック
echo "\n=== SPF レコード ==="
dig +short TXT $domain | grep -i "v=spf1" > $spf_temp_file
spf_record=$(cat $spf_temp_file)
if [ -n "$spf_record" ]; then
  echo "SPFレコードが見つかりました: $spf_record"
  # SPFレコードの有効性チェック
  if echo "$spf_record" | grep "all" > /dev/null; then
    if echo "$spf_record" | grep -- "-all" > /dev/null; then
      echo "SPFポリシーは 'fail (-all)' で設定されています。有効です。"
    elif echo "$spf_record" | grep -- "~all" > /dev/null; then
      echo "SPFポリシーは 'softfail (~all)' で設定されています。注意が必要です。"
    elif echo "$spf_record" | grep -- "?all" > /dev/null; then
      echo "SPFポリシーは 'neutral (?all)' で設定されています。推奨されません。"
    else
      echo "SPFポリシーに未知の設定があります。"
    fi
  else
    echo "SPFポリシーが明確に定義されていません。"
  fi

  # SPFレコードのlookup数を計算
  lookup_count=$(calculate_spf_lookups "$spf_record")
  if [ "$lookup_count" -ge 10 ]; then
    echo "エラー: SPFレコードのlookup数が10を超えています ($lookup_count)。設定を見直してください。"
  else
    echo "SPFレコードのlookup数は適切です ($lookup_count)。"
  fi
else
  echo "SPFレコードが見つかりません。"
fi

# DKIMチェック
echo "\n=== DKIM レコード ==="
default_selector="default._domainkey"
dkim_record=$(dig +short TXT $default_selector.$domain)
if [ -n "$dkim_record" ]; then
  echo "デフォルトセレクターのDKIMレコードが見つかりました: $dkim_record"
else
  echo "デフォルトセレクターのDKIMレコードが見つかりません。"
  echo "必要に応じてカスタムセレクターを指定してください。"
fi

# DMARCチェック
echo "\n=== DMARC レコード ==="
dmarc_record=$(dig +short TXT _dmarc.$domain)
if [ -n "$dmarc_record" ]; then
  echo "DMARCレコードが見つかりました: $dmarc_record"
else
  echo "DMARCレコードが見つかりません。"
fi

# 終了
echo "\n=== チェック完了 ==="

