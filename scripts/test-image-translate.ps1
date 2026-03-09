param(
    [string]$BaseUrl = "http://127.0.0.1:8080",
    [string]$ImagePath,
    [string]$ImageUrl,
    [string]$Text,
    [string]$SourceLangCode = "auto",
    [string]$TargetLangCode = "zh",
    [int]$MaxTokens = 500,
    [double]$Temperature = 0.2,
    [string]$Model,
    [switch]$RawResponse
)

function Get-ImageMimeType {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    switch ($extension) {
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".webp" { return "image/webp" }
        ".gif" { return "image/gif" }
        ".bmp" { return "image/bmp" }
        default {
            throw "Unsupported image extension: $extension. Supported: .png, .jpg, .jpeg, .webp, .gif, .bmp"
        }
    }
}

function Convert-ImageToDataUrl {
    param([string]$Path)

    $resolvedPath = (Resolve-Path $Path).Path
    $mimeType = Get-ImageMimeType -Path $resolvedPath
    $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
    $base64 = [System.Convert]::ToBase64String($bytes)

    return "data:$mimeType;base64,$base64"
}

if ([string]::IsNullOrWhiteSpace($ImagePath) -and [string]::IsNullOrWhiteSpace($ImageUrl)) {
    Write-Error "Please provide -ImagePath or -ImageUrl."
    exit 1
}

if (-not [string]::IsNullOrWhiteSpace($ImagePath) -and -not (Test-Path $ImagePath)) {
    Write-Error "Image file not found: $ImagePath"
    exit 1
}

$imageReference = if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
    Convert-ImageToDataUrl -Path $ImagePath
} else {
    $ImageUrl
}

$baseUrlTrimmed = $BaseUrl.TrimEnd('/')

$content = @()

if (-not [string]::IsNullOrWhiteSpace($Text)) {
    $content += [ordered]@{
        type = "text"
        text = $Text
    }
}

$content += [ordered]@{
    type = "image_url"
    image_url = [ordered]@{
        url = $imageReference
    }
}

$payload = [ordered]@{
    messages = @(
        [ordered]@{
            role = "user"
            content = $content
        }
    )
    chat_template_kwargs = [ordered]@{
        source_lang_code = $SourceLangCode
        target_lang_code = $TargetLangCode
    }
    max_tokens = $MaxTokens
    temperature = $Temperature
}

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $payload.model = $Model
}

$jsonBody = $payload | ConvertTo-Json -Depth 10

Write-Host "POST $baseUrlTrimmed/v1/chat/completions"
if (-not [string]::IsNullOrWhiteSpace($ImagePath)) {
    Write-Host "ImagePath: $((Resolve-Path $ImagePath).Path)"
} else {
    Write-Host "ImageUrl: $ImageUrl"
}
Write-Host "Translate: $SourceLangCode -> $TargetLangCode"
Write-Host "PayloadMode: openai-image_url"
if (-not [string]::IsNullOrWhiteSpace($Text)) {
    Write-Host "Text: $Text"
}

try {
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$baseUrlTrimmed/v1/chat/completions" `
        -ContentType "application/json; charset=utf-8" `
        -Body $jsonBody `
        -TimeoutSec 300
} catch {
    Write-Error "Request failed: $($_.Exception.Message)"

    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Host $_.ErrorDetails.Message
    }

    exit 1
}

if ($RawResponse) {
    $response | ConvertTo-Json -Depth 10
    exit 0
}

$translation = $response.choices[0].message.content

if ([string]::IsNullOrWhiteSpace($translation)) {
    Write-Warning "Response does not contain choices[0].message.content."
    $response | ConvertTo-Json -Depth 10
    exit 0
}

Write-Host ""
Write-Host "Translation Result:" -ForegroundColor Green
Write-Output $translation
