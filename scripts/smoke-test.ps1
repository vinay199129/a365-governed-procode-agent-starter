$headers = @{
  "Authorization" = "Bearer test-token"
  "Content-Type"  = "application/json"
}
$body = @{
  type = "message"
  id = "test-$(Get-Random)"
  timestamp = (Get-Date).ToUniversalTime().ToString("o")
  localTimestamp = (Get-Date).ToString("o")
  channelId = "msteams"
  serviceUrl = "http://localhost:56150"
  from = @{
    id = "29:1test-user"
    name = "Test User"
    aadObjectId = "cfb40a8b-29bf-4b93-a129-89ab5a84d926"
  }
  conversation = @{
    id = "test-conv-1"
    conversationType = "personal"
    tenantId = "253bc031-a17c-4b57-b83c-1ee1d86b1331"
  }
  recipient = @{
    id = "28:bot-1"
    name = "procodeagent"
    tenantId = "253bc031-a17c-4b57-b83c-1ee1d86b1331"
    agenticAppId = "19bc459c-7807-4a41-a467-4adfb9f9704b"
  }
  text = "hello"
  textFormat = "plain"
  locale = "en-US"
  channelData = @{
    tenant = @{ id = "253bc031-a17c-4b57-b83c-1ee1d86b1331" }
  }
} | ConvertTo-Json -Depth 10
try {
  $resp = Invoke-WebRequest -Uri "http://localhost:3978/api/messages" -Method POST -Headers $headers -Body $body -TimeoutSec 20
  Write-Host "STATUS: $($resp.StatusCode)"
  Write-Host $resp.Content
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  try { Write-Host ($_.ErrorDetails.Message) } catch {}
}
