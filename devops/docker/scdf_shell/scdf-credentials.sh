uaaUrl="http://localhost:8080/oauth/token"
clientID="dataflow"
clientSecret="d@t@fl0w"

# Obtain the Bearer token
response=$(curl -s -X POST -u "$clientID:$clientSecret" \
  -d "grant_type=client_credentials" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  $uaaUrl)

token=$(jq -r .access_token)

# Use the token
echo "Bearer $token"