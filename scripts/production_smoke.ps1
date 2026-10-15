param(
  [Parameter(Mandatory = $true)] [string] $ProjectRef,
  [Parameter(Mandatory = $true)] [string] $InputFile
)

$ErrorActionPreference = 'Stop'
if (-not $env:SUPABASE_ACCESS_TOKEN) {
  throw 'SUPABASE_ACCESS_TOKEN is required.'
}

$managementHeaders = @{ Authorization = "Bearer $env:SUPABASE_ACCESS_TOKEN" }
$keys = Invoke-RestMethod `
  -Uri "https://api.supabase.com/v1/projects/$ProjectRef/api-keys?reveal=true" `
  -Headers $managementHeaders
$publishableKey = ($keys | Where-Object {
    $_.type -eq 'publishable' -and $_.name -eq 'default'
  }).api_key
$serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' }).api_key
$baseUrl = "https://$ProjectRef.supabase.co"

$userId = $null
$accessToken = $null
$storagePath = $null
try {
  $signup = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/v1/signup" `
    -Headers @{ apikey = $publishableKey; 'Content-Type' = 'application/json' } `
    -Body '{"data":{"full_name":"Production Verification"}}'
  $userId = [string] $signup.user.id
  $accessToken = [string] $signup.access_token
  $headers = @{
    apikey = $publishableKey
    Authorization = "Bearer $accessToken"
    'Content-Type' = 'application/json'
  }
  $writeHeaders = $headers.Clone()
  $writeHeaders.Prefer = 'return=representation'

  $subject = (Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/rest/v1/subject" -Headers $writeHeaders `
    -Body (@{ user_id = $userId; name = 'ViaX production verification' } |
      ConvertTo-Json -Compress))[0]

  $hash = (Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash.ToLower()
  $storagePath = "$userId/$($subject.id)/$hash-verification.pptx"
  Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/storage/v1/object/documents/$storagePath" `
    -Headers @{ apikey = $publishableKey; Authorization = "Bearer $accessToken"; 'x-upsert' = 'true' } `
    -ContentType 'application/vnd.openxmlformats-officedocument.presentationml.presentation' `
    -InFile $InputFile -TimeoutSec 120 | Out-Null

  $document = (Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/rest/v1/document" -Headers $writeHeaders `
    -Body (@{
      subject_id = $subject.id; user_id = $userId; filename = 'verification.pptx'
      storage_path = $storagePath
      mime_type = 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
      byte_size = (Get-Item -LiteralPath $InputFile).Length
      content_hash = $hash; status = 'pending'
    } | ConvertTo-Json -Compress))[0]

  $ingestion = Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/functions/v1/ingest" -Headers $headers `
    -Body (@{ document_id = $document.id } | ConvertTo-Json -Compress) `
    -TimeoutSec 300
  $question = Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/functions/v1/examine" -Headers $headers `
    -Body (@{ action = 'question'; subject_id = $subject.id; mode = 'practice' } |
      ConvertTo-Json -Compress) -TimeoutSec 300
  $evaluation = Invoke-RestMethod -Method Post `
    -Uri "$baseUrl/functions/v1/examine" -Headers $headers `
    -Body (@{
      action = 'evaluate'; question_id = $question.question.id
      answer = 'The poster uses a clear academic sequence from title and abstract through objectives, methodology, results, applications, conclusion, references, and visuals, helping visitors scan the project and the team explain it consistently.'
    } | ConvertTo-Json -Compress) -TimeoutSec 300

  [pscustomobject]@{
    auth = 'ok'; private_upload = 'ok'; pages = $ingestion.pages
    chunks = $ingestion.chunks; concepts = $ingestion.concepts
    question = $(if ($question.ok) { 'ok' } else { 'failed' })
    evaluation = $(if ($evaluation.ok) { 'ok' } else { 'failed' })
    score = $evaluation.composite; verdict = $evaluation.verdict
  } | ConvertTo-Json -Compress
}
finally {
  if ($accessToken -and $storagePath) {
    try {
      Invoke-RestMethod -Method Delete -Uri "$baseUrl/storage/v1/object/documents" `
        -Headers @{ apikey = $publishableKey; Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' } `
        -Body (@{ prefixes = @($storagePath) } | ConvertTo-Json -Compress) | Out-Null
    } catch { }
  }
  if ($userId -and $serviceKey) {
    try {
      Invoke-RestMethod -Method Delete -Uri "$baseUrl/auth/v1/admin/users/$userId" `
        -Headers @{ apikey = $serviceKey; Authorization = "Bearer $serviceKey" } | Out-Null
    } catch { }
  }
}
